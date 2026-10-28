#define _GNU_SOURCE

#include "fan/it8613_hwmon.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define IT8613_HWMON_NAME "it8613"
#define IT8613_MIN_MANUAL_PWM 40U
#define IT8613_HWMON_READBACK_RETRY_MS 2000L

struct it8613_hwmon_device {
    char path[PATH_MAX];
    int lock_fd;
};

static void set_error(char *error, size_t error_size, const char *format,
                      const char *detail)
{
    if (error != NULL && error_size > 0) {
        (void)snprintf(error, error_size, format, detail);
    }
}

static const char *hwmon_root(void)
{
    const char *override = getenv("UGREENCTL_HWMON_ROOT");
    return override != NULL && override[0] != '\0' ? override : "/sys/class/hwmon";
}

static const char *lock_path(void)
{
    const char *override = getenv("UGREENCTL_IT8613_LOCK");
    return override != NULL && override[0] != '\0'
               ? override
               : "/run/ugreenctl-it8613.lock";
}

static const char *incompatible_controller_owner(void)
{
    static const char * const paths[] = {
        "/proc/it86",
        "/sys/module/ug_it86x_sio",
        "/sys/module/ug_it86x_cpufan",
        NULL
    };
    const char * const *path;

    for (path = paths; *path != NULL; ++path) {
        if (access(*path, F_OK) == 0) {
            return *path;
        }
    }
    return NULL;
}

static bool is_hwmon_directory_name(const char *name)
{
    const unsigned char *cursor;

    if (strncmp(name, "hwmon", 5) != 0 || name[5] == '\0') {
        return false;
    }
    for (cursor = (const unsigned char *)name + 5; *cursor != '\0'; ++cursor) {
        if (!isdigit(*cursor)) {
            return false;
        }
    }
    return true;
}

static int build_path(char *path, size_t path_size, const char *directory,
                      const char *name, char *error, size_t error_size)
{
    if (snprintf(path, path_size, "%s/%s", directory, name) >= (int)path_size) {
        set_error(error, error_size, "hwmon path is too long: %s", name);
        return -ENAMETOOLONG;
    }
    return 0;
}

static int read_text_file(const char *path, char *buffer, size_t buffer_size,
                          char *error, size_t error_size)
{
    int fd;
    ssize_t length;
    size_t end;

    if (buffer_size < 2) {
        set_error(error, error_size, "read buffer is too small for: %s", path);
        return -EINVAL;
    }
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        set_error(error, error_size, "cannot open hwmon node: %s", path);
        return -errno;
    }
    length = read(fd, buffer, buffer_size - 1);
    if (length < 0) {
        int saved_errno = errno;
        (void)close(fd);
        set_error(error, error_size, "cannot read hwmon node: %s", path);
        return -saved_errno;
    }
    (void)close(fd);
    buffer[length] = '\0';
    end = (size_t)length;
    while (end > 0 && isspace((unsigned char)buffer[end - 1])) {
        buffer[--end] = '\0';
    }
    return 0;
}

static int read_unsigned_file(const char *path, unsigned long *value,
                              char *error, size_t error_size)
{
    char buffer[64];
    char *end;
    int result = read_text_file(path, buffer, sizeof(buffer), error, error_size);

    if (result != 0) {
        return result;
    }
    errno = 0;
    *value = strtoul(buffer, &end, 10);
    if (errno != 0 || buffer[0] == '\0' || *end != '\0') {
        set_error(error, error_size, "invalid numeric value in hwmon node: %s", path);
        return -EINVAL;
    }
    return 0;
}

static int find_it8613_hwmon(char *path, size_t path_size,
                             char *error, size_t error_size)
{
    const char *root = hwmon_root();
    DIR *directory = opendir(root);
    struct dirent *entry;
    bool found = false;

    if (directory == NULL) {
        set_error(error, error_size, "cannot open hwmon root: %s", root);
        return -errno;
    }
    while ((entry = readdir(directory)) != NULL) {
        char candidate[PATH_MAX];
        char name_path[PATH_MAX];
        char name[64];
        int result;

        if (!is_hwmon_directory_name(entry->d_name)) {
            continue;
        }
        result = build_path(candidate, sizeof(candidate), root, entry->d_name,
                            error, error_size);
        if (result != 0 ||
            build_path(name_path, sizeof(name_path), candidate, "name",
                       error, error_size) != 0) {
            (void)closedir(directory);
            return result != 0 ? result : -ENAMETOOLONG;
        }
        if (read_text_file(name_path, name, sizeof(name), NULL, 0) != 0 ||
            strcmp(name, IT8613_HWMON_NAME) != 0) {
            continue;
        }
        if (found) {
            (void)closedir(directory);
            set_error(error, error_size,
                      "multiple hwmon nodes report name=it8613: %s", root);
            return -EEXIST;
        }
        if (snprintf(path, path_size, "%s", candidate) >= (int)path_size) {
            (void)closedir(directory);
            set_error(error, error_size, "hwmon path is too long: %s", candidate);
            return -ENAMETOOLONG;
        }
        found = true;
    }
    (void)closedir(directory);
    if (!found) {
        set_error(error, error_size,
                  "no dynamic hwmon node with name=it8613 under: %s", root);
        return -ENODEV;
    }
    return 0;
}

static int it8613_hwmon_open(struct it8613_hwmon_device *device,
                             char *error, size_t error_size)
{
    const char *owner = incompatible_controller_owner();
    int result;

    memset(device, 0, sizeof(*device));
    device->lock_fd = -1;
    if (owner != NULL) {
        set_error(error, error_size,
                  "incompatible vendor controller owner is active: %s", owner);
        return -EBUSY;
    }
    device->lock_fd = open(lock_path(), O_CREAT | O_CLOEXEC | O_RDWR, 0600);
    if (device->lock_fd < 0) {
        set_error(error, error_size, "cannot create IT8613 process lock: %s",
                  lock_path());
        return -errno;
    }
    if (flock(device->lock_fd, LOCK_EX) != 0) {
        int saved_errno = errno;
        (void)close(device->lock_fd);
        device->lock_fd = -1;
        set_error(error, error_size, "cannot lock IT8613 hwmon access: %s",
                  lock_path());
        return -saved_errno;
    }
    result = find_it8613_hwmon(device->path, sizeof(device->path), error, error_size);
    if (result != 0) {
        (void)close(device->lock_fd);
        device->lock_fd = -1;
    }
    return result;
}

static void it8613_hwmon_close(struct it8613_hwmon_device *device)
{
    if (device->lock_fd >= 0) {
        (void)close(device->lock_fd);
    }
    memset(device, 0, sizeof(*device));
    device->lock_fd = -1;
}

static int channel_node_path(const struct it8613_hwmon_device *device,
                             const char *format, unsigned int index,
                             char *path, size_t path_size,
                             char *error, size_t error_size)
{
    char name[32];

    if (snprintf(name, sizeof(name), format, index) >= (int)sizeof(name)) {
        set_error(error, error_size, "invalid hwmon channel format: %s", format);
        return -EINVAL;
    }
    return build_path(path, path_size, device->path, name, error, error_size);
}

static int read_channel(const struct it8613_hwmon_device *device,
                        const struct it8613_hwmon_channel *channel,
                        struct ugreenctl_fan_status *fan,
                        char *error, size_t error_size)
{
    char path[PATH_MAX];
    unsigned long pwm;
    unsigned long enable;
    unsigned long rpm;
    int result;

    result = channel_node_path(device, "pwm%u", channel->pwm_index,
                               path, sizeof(path), error, error_size);
    if (result != 0 ||
        (result = read_unsigned_file(path, &pwm, error, error_size)) != 0) {
        return result;
    }
    if (pwm > 255) {
        set_error(error, error_size, "PWM value is outside 0-255: %s", path);
        return -ERANGE;
    }
    result = channel_node_path(device, "pwm%u_enable", channel->pwm_index,
                               path, sizeof(path), error, error_size);
    if (result != 0 ||
        (result = read_unsigned_file(path, &enable, error, error_size)) != 0) {
        return result;
    }
    result = channel_node_path(device, "fan%u_input", channel->fan_index,
                               path, sizeof(path), error, error_size);
    if (result != 0 ||
        (result = read_unsigned_file(path, &rpm, error, error_size)) != 0) {
        return result;
    }

    memset(fan, 0, sizeof(*fan));
    (void)snprintf(fan->id, sizeof(fan->id), "%s", channel->id);
    fan->pwm = (uint8_t)pwm;
    fan->pwm_known = true;
    /* Only value 1 is exposed as a supported/manual state. Value 2 is the
     * kernel driver's hardware auto mode, not the vendor hwmonitor curve. */
    fan->manual = enable == 1;
    fan->mode_known = enable == 1;
    fan->rpm = rpm;
    if (rpm == 0) {
        fan->tachometer = 0;
    } else {
        unsigned long tachometer = 675000UL / rpm;
        fan->tachometer = (uint16_t)(tachometer > UINT16_MAX ? UINT16_MAX : tachometer);
    }
    return 0;
}

static int write_unsigned_file(const char *path, unsigned int value,
                               char *error, size_t error_size)
{
    char buffer[32];
    int fd;
    int length = snprintf(buffer, sizeof(buffer), "%u\n", value);
    ssize_t written;

    if (length <= 0 || length >= (int)sizeof(buffer)) {
        set_error(error, error_size, "cannot format hwmon value for: %s", path);
        return -EINVAL;
    }
    fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        set_error(error, error_size, "cannot open writable hwmon node: %s", path);
        return -errno;
    }
    written = write(fd, buffer, (size_t)length);
    if (written != length) {
        int saved_errno = written < 0 ? errno : EIO;
        (void)close(fd);
        set_error(error, error_size, "cannot write hwmon node: %s", path);
        return -saved_errno;
    }
    (void)close(fd);
    return 0;
}

static void wait_for_hwmon_readback(void)
{
    struct timespec delay = {
        .tv_sec = IT8613_HWMON_READBACK_RETRY_MS / 1000L,
        .tv_nsec = (IT8613_HWMON_READBACK_RETRY_MS % 1000L) * 1000000L
    };

    while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {
    }
}

static int write_and_verify(const char *path, unsigned int expected,
                            char *error, size_t error_size)
{
    unsigned long actual;
    int result = write_unsigned_file(path, expected, error, error_size);

    if (result != 0) {
        return result;
    }
    result = read_unsigned_file(path, &actual, error, error_size);
    if (result != 0) {
        return result;
    }
    if (actual != expected) {
        /* The it87 driver may return a cached register value for up to 1.5
         * seconds. A mismatched immediate read must therefore be confirmed
         * before treating an accepted sysfs write as a hardware failure. */
        wait_for_hwmon_readback();
        result = read_unsigned_file(path, &actual, error, error_size);
        if (result != 0) {
            return result;
        }
        if (actual != expected) {
            char detail[PATH_MAX + 64];
            (void)snprintf(detail, sizeof(detail),
                           "%s wrote %u but read back %lu after %ld ms",
                           path, expected, actual,
                           IT8613_HWMON_READBACK_RETRY_MS);
            set_error(error, error_size, "hwmon write verification failed: %s", detail);
            return -EIO;
        }
    }
    return 0;
}

static int set_channel_manual_pwm(const struct it8613_hwmon_device *device,
                                  const struct it8613_hwmon_channel *channel,
                                  uint8_t pwm,
                                  char *error, size_t error_size)
{
    char path[PATH_MAX];
    int result = channel_node_path(device, "pwm%u_enable", channel->pwm_index,
                                   path, sizeof(path), error, error_size);

    if (result != 0 ||
        (result = write_and_verify(path, 1, error, error_size)) != 0) {
        return result;
    }
    result = channel_node_path(device, "pwm%u", channel->pwm_index,
                               path, sizeof(path), error, error_size);
    if (result != 0) {
        return result;
    }
    return write_and_verify(path, pwm, error, error_size);
}

int it8613_hwmon_read_fans(const struct it8613_hwmon_channel *channels,
                           size_t channel_count,
                           struct ugreenctl_fan_status *fans,
                           size_t *fan_count,
                           char *error, size_t error_size)
{
    struct it8613_hwmon_device device;
    size_t index;
    int result;

    if (channels == NULL || fans == NULL || fan_count == NULL ||
        channel_count == 0 || channel_count > UGREENCTL_MAX_FANS) {
        set_error(error, error_size, "invalid IT8613 hwmon fan mapping: %s", "count");
        return -EINVAL;
    }
    result = it8613_hwmon_open(&device, error, error_size);
    if (result != 0) {
        return result;
    }
    for (index = 0; index < channel_count; ++index) {
        result = read_channel(&device, &channels[index], &fans[index],
                              error, error_size);
        if (result != 0) {
            it8613_hwmon_close(&device);
            return result;
        }
    }
    *fan_count = channel_count;
    it8613_hwmon_close(&device);
    return 0;
}

int it8613_hwmon_set_manual_pwm(const struct it8613_hwmon_channel *channels,
                                size_t channel_count, uint8_t pwm,
                                char *error, size_t error_size)
{
    struct it8613_hwmon_device device;
    size_t index;
    int result;

    if (channels == NULL || channel_count == 0 ||
        channel_count > UGREENCTL_MAX_FANS) {
        set_error(error, error_size, "invalid IT8613 hwmon write mapping: %s", "count");
        return -EINVAL;
    }
    if (pwm < IT8613_MIN_MANUAL_PWM) {
        if (error != NULL && error_size > 0) {
            (void)snprintf(error, error_size,
                           "refusing unsafe PWM %u; choose a value of 40-255", pwm);
        }
        return -EPERM;
    }
    result = it8613_hwmon_open(&device, error, error_size);
    if (result != 0) {
        return result;
    }
    for (index = 0; index < channel_count; ++index) {
        result = set_channel_manual_pwm(&device, &channels[index], pwm,
                                        error, error_size);
        if (result != 0) {
            it8613_hwmon_close(&device);
            return result;
        }
    }
    it8613_hwmon_close(&device);
    return 0;
}
