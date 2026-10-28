#define _GNU_SOURCE

#include "fan/thermal_curve.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <limits.h>
#include <scsi/sg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define THERMAL_MAX_CELSIUS 125U
#define ATA_SMART_DATA_SIZE 512U
#define ATA_SMART_ATTRIBUTE_OFFSET 2U
#define ATA_SMART_ATTRIBUTE_SIZE 12U
#define ATA_SMART_ATTRIBUTE_COUNT 30U
#define ATA_SMART_AIRFLOW_TEMPERATURE_ATTRIBUTE 190U
#define ATA_SMART_TEMPERATURE_ATTRIBUTE 194U
#define ATA_PASS_THROUGH_16 0x85U
#define ATA_PROTOCOL_NON_DATA 0x06U
#define ATA_PROTOCOL_PIO_DATA_IN 0x08U
#define ATA_CHECK_CONDITION 0x02U
#define ATA_CHECK_POWER_MODE 0xe5U
#define ATA_SMART_COMMAND 0xb0U
#define ATA_SMART_READ_DATA 0xd0U
#define ATA_SMART_LBA_MID 0x4fU
#define ATA_SMART_LBA_HIGH 0xc2U
#define ATA_RETURN_DESCRIPTOR 0x09U

static void set_error(char *error, size_t error_size, const char *message)
{
    if (error != NULL && error_size > 0) {
        (void)snprintf(error, error_size, "%s", message);
    }
}

static const char *thermal_hwmon_root(void)
{
    const char *override = getenv("UGREENCTL_THERMAL_HWMON_ROOT");
    return override != NULL && override[0] != '\0' ? override : "/sys/class/hwmon";
}

static const char *thermal_block_root(void)
{
    const char *override = getenv("UGREENCTL_THERMAL_BLOCK_ROOT");
    return override != NULL && override[0] != '\0' ? override : "/sys/block";
}

static const char *thermal_device_root(void)
{
    const char *override = getenv("UGREENCTL_THERMAL_DEVICE_ROOT");
    return override != NULL && override[0] != '\0' ? override : "/dev";
}

static bool is_hwmon_directory(const char *name)
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

static int build_path(char *path, size_t path_size, const char *directory, const char *name)
{
    if (snprintf(path, path_size, "%s/%s", directory, name) >= (int)path_size) {
        return -ENAMETOOLONG;
    }
    return 0;
}

static int read_text(const char *path, char *buffer, size_t buffer_size)
{
    FILE *stream;
    size_t length;

    if (buffer_size < 2) {
        return -EINVAL;
    }
    stream = fopen(path, "r");
    if (stream == NULL) {
        return -errno;
    }
    if (fgets(buffer, (int)buffer_size, stream) == NULL) {
        int saved = ferror(stream) ? errno : EIO;
        (void)fclose(stream);
        return -saved;
    }
    (void)fclose(stream);
    length = strlen(buffer);
    while (length > 0 && isspace((unsigned char)buffer[length - 1])) {
        buffer[--length] = '\0';
    }
    return 0;
}

static int read_temperature_celsius(const char *path, int *temperature)
{
    char text[64];
    char *end;
    long value;
    int result = read_text(path, text, sizeof(text));

    if (result != 0) {
        return result;
    }
    errno = 0;
    value = strtol(text, &end, 10);
    if (errno != 0 || text[0] == '\0' || *end != '\0' || value < 0 || value > 200000) {
        return -EINVAL;
    }
    /* hwmon temperatures are normally millidegrees C.  Permit an integer C
     * test fixture as well, but reject implausible values either way. */
    if (value > 1000) {
        value /= 1000;
    }
    if (value > (long)THERMAL_MAX_CELSIUS) {
        return -ERANGE;
    }
    *temperature = (int)value;
    return 0;
}

static bool is_cpu_hwmon(const char *name)
{
    /* fnOS Resource Monitor looks for these generic x86 CPU hwmon drivers.
     * ACPI zones describe board sensors, not the CPU reading it presents. */
    return strcmp(name, "coretemp") == 0 || strcmp(name, "k8temp") == 0 ||
           strcmp(name, "k10temp") == 0 || strcmp(name, "zenpower") == 0;
}

static bool is_hdd_hwmon(const char *name)
{
    return strcmp(name, "drivetemp") == 0;
}

static bool is_ssd_hwmon(const char *name)
{
    return strcmp(name, "nvme") == 0 || strcmp(name, "nvme-pci") == 0;
}

static bool collect_first_hwmon_temperature(const char *directory, int *temperature)
{
    char pattern[PATH_MAX];
    glob_t matches;
    size_t index;
    bool found = false;

    if (snprintf(pattern, sizeof(pattern), "%s/temp*_input", directory) >=
        (int)sizeof(pattern)) {
        return false;
    }
    memset(&matches, 0, sizeof(matches));
    /* Use the same glob primitive as fnOS Resource Monitor.  Its first
     * result is the CPU value shown by fnOS, including platforms where the
     * labels are not ordered by numeric sensor index. */
    if (glob(pattern, 0, NULL, &matches) != 0) {
        globfree(&matches);
        return false;
    }
    for (index = 0; index < matches.gl_pathc; ++index) {
        if (read_temperature_celsius(matches.gl_pathv[index], temperature) == 0) {
            found = true;
            break;
        }
    }
    globfree(&matches);
    return found;
}

static void collect_hottest_hwmon_temperature(const char *directory, int *maximum)
{
    DIR *dir = opendir(directory);
    struct dirent *entry;

    if (dir == NULL) {
        return;
    }
    while ((entry = readdir(dir)) != NULL) {
        char path[PATH_MAX];
        int temperature;

        if (strncmp(entry->d_name, "temp", 4) != 0 ||
            strstr(entry->d_name, "_input") == NULL) {
            continue;
        }
        if (build_path(path, sizeof(path), directory, entry->d_name) != 0 ||
            read_temperature_celsius(path, &temperature) != 0) {
            continue;
        }
        if (temperature > *maximum) {
            *maximum = temperature;
        }
    }
    (void)closedir(dir);
}

int ugreenctl_parse_ata_smart_temperature(const unsigned char *data, size_t size,
                                          int *temperature)
{
    size_t index;
    int airflow_temperature = -1;

    if (data == NULL || temperature == NULL || size < ATA_SMART_DATA_SIZE) {
        return -EINVAL;
    }
    for (index = 0; index < ATA_SMART_ATTRIBUTE_COUNT; ++index) {
        size_t offset = ATA_SMART_ATTRIBUTE_OFFSET + index * ATA_SMART_ATTRIBUTE_SIZE;
        unsigned int attribute = data[offset];
        unsigned int value = data[offset + 5];

        if (value == 0 || value > THERMAL_MAX_CELSIUS) {
            continue;
        }
        if (attribute == ATA_SMART_TEMPERATURE_ATTRIBUTE) {
            *temperature = (int)value;
            return 0;
        }
        if (attribute == ATA_SMART_AIRFLOW_TEMPERATURE_ATTRIBUTE) {
            airflow_temperature = (int)value;
        }
    }
    if (airflow_temperature >= 0) {
        *temperature = airflow_temperature;
        return 0;
    }
    return -ENODATA;
}

static bool ata_return_sector_count(const unsigned char *sense, size_t sense_size,
                                    unsigned char *sector_count)
{
    size_t offset;

    if (sense == NULL || sector_count == NULL || sense_size < 8 ||
        (sense[0] & 0x7fU) != 0x72U) {
        return false;
    }
    for (offset = 8; offset + 1 < sense_size; offset += (size_t)sense[offset + 1] + 2U) {
        size_t descriptor_size = (size_t)sense[offset + 1] + 2U;

        if (descriptor_size > sense_size - offset) {
            return false;
        }
        if (sense[offset] == ATA_RETURN_DESCRIPTOR && descriptor_size >= 14U) {
            /* SAT ATA Return Descriptor: byte 4 is the expanded high byte;
             * byte 5 is the current ATA Sector Count register.  Check Power
             * Mode returns 0x00 for standby and a non-zero low byte for a
             * running disk (normally 0xff). */
            *sector_count = sense[offset + 5];
            return true;
        }
    }
    return false;
}

static int ata_check_power_mode(int file_descriptor, bool *running)
{
    unsigned char cdb[16] = {0};
    unsigned char sense[32] = {0};
    unsigned char sector_count;
    sg_io_hdr_t request;

    if (running == NULL) {
        return -EINVAL;
    }
    cdb[0] = ATA_PASS_THROUGH_16;
    cdb[1] = ATA_PROTOCOL_NON_DATA;
    cdb[2] = 0x20U; /* CK_COND: return the ATA taskfile in descriptor sense. */
    cdb[14] = ATA_CHECK_POWER_MODE;
    memset(&request, 0, sizeof(request));
    request.interface_id = 'S';
    request.dxfer_direction = SG_DXFER_NONE;
    request.cmd_len = (unsigned char)sizeof(cdb);
    request.mx_sb_len = (unsigned char)sizeof(sense);
    request.cmdp = cdb;
    request.sbp = sense;
    request.timeout = 2000U;
    if (ioctl(file_descriptor, SG_IO, &request) < 0) {
        return -errno;
    }
    if (request.host_status != 0 || request.status != ATA_CHECK_CONDITION ||
        !ata_return_sector_count(sense, request.sb_len_wr, &sector_count)) {
        return -EIO;
    }
    *running = sector_count != 0;
    return 0;
}

static int ata_read_smart_data(int file_descriptor, unsigned char data[ATA_SMART_DATA_SIZE])
{
    unsigned char cdb[16] = {0};
    unsigned char sense[32] = {0};
    sg_io_hdr_t request;

    cdb[0] = ATA_PASS_THROUGH_16;
    cdb[1] = ATA_PROTOCOL_PIO_DATA_IN;
    cdb[2] = 0x0eU; /* T_DIR + BYT_BLOK + sector-count transfer. */
    /* ATA PASS THROUGH (16) carries the normal taskfile registers in the
     * low-byte slots.  The adjacent odd offsets are the EXTEND high bytes. */
    cdb[4] = ATA_SMART_READ_DATA;
    cdb[6] = 1U;
    cdb[10] = ATA_SMART_LBA_MID;
    cdb[12] = ATA_SMART_LBA_HIGH;
    cdb[14] = ATA_SMART_COMMAND;
    memset(&request, 0, sizeof(request));
    request.interface_id = 'S';
    request.dxfer_direction = SG_DXFER_FROM_DEV;
    request.cmd_len = (unsigned char)sizeof(cdb);
    request.mx_sb_len = (unsigned char)sizeof(sense);
    request.dxfer_len = ATA_SMART_DATA_SIZE;
    request.dxferp = data;
    request.cmdp = cdb;
    request.sbp = sense;
    request.timeout = 5000U;
    if (ioctl(file_descriptor, SG_IO, &request) < 0) {
        return -errno;
    }
    if (request.status != 0 || request.host_status != 0 || request.driver_status != 0 ||
        request.resid != 0) {
        return -EIO;
    }
    return 0;
}

static bool is_sata_rotational_block_device(const char *block_root, const char *name)
{
    char path[PATH_MAX];
    char value[64];
    const unsigned char *cursor;

    if (strncmp(name, "sd", 2) != 0 || name[2] == '\0') {
        return false;
    }
    for (cursor = (const unsigned char *)name + 2; *cursor != '\0'; ++cursor) {
        if (!islower(*cursor)) {
            return false;
        }
    }
    if (snprintf(path, sizeof(path), "%s/%s/device/vendor", block_root, name) >=
            (int)sizeof(path) ||
        read_text(path, value, sizeof(value)) != 0 || strcmp(value, "ATA") != 0) {
        return false;
    }
    if (snprintf(path, sizeof(path), "%s/%s/queue/rotational", block_root, name) >=
            (int)sizeof(path) ||
        read_text(path, value, sizeof(value)) != 0 || strcmp(value, "1") != 0) {
        return false;
    }
    return true;
}

static void collect_smart_hdd_temperatures(int *maximum)
{
    const char *block_root = thermal_block_root();
    const char *device_root = thermal_device_root();
    DIR *directory;
    struct dirent *entry;

    if (maximum == NULL) {
        return;
    }
    directory = opendir(block_root);
    if (directory == NULL) {
        return;
    }
    while ((entry = readdir(directory)) != NULL) {
        char device_path[PATH_MAX];
        unsigned char data[ATA_SMART_DATA_SIZE] = {0};
        bool running = false;
        int file_descriptor;
        int temperature;

        if (!is_sata_rotational_block_device(block_root, entry->d_name) ||
            snprintf(device_path, sizeof(device_path), "%s/%s", device_root, entry->d_name) >=
                (int)sizeof(device_path)) {
            continue;
        }
        file_descriptor = open(device_path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (file_descriptor < 0) {
            continue;
        }
        /* Never issue SMART READ DATA to a standby drive: fan telemetry must
         * not wake a disk merely to obtain a temperature. */
        if (ata_check_power_mode(file_descriptor, &running) == 0 && running &&
            ata_read_smart_data(file_descriptor, data) == 0 &&
            ugreenctl_parse_ata_smart_temperature(data, sizeof(data), &temperature) == 0 &&
            temperature > *maximum) {
            *maximum = temperature;
        }
        (void)close(file_descriptor);
    }
    (void)closedir(directory);
}

void ugreenctl_fan_curve_config_defaults(struct ugreenctl_fan_curve_config *config)
{
    if (config == NULL) {
        return;
    }
    memset(config, 0, sizeof(*config));
    (void)snprintf(config->profile, sizeof(config->profile), "%s", "custom");
    config->interval_seconds = 10;
    config->downshift_delay_seconds = 60;
    config->minimum_pwm = 64;
    config->failsafe_pwm = 255;
    config->require_storage_sensor = false;
    config->allow_unvalidated_writes = false;
    config->hdd_curve_enabled = true;
    config->ssd_curve_enabled = true;
    config->cpu = (struct ugreenctl_curve_thresholds){50, 55, 75, 80, 90};
    config->hdd = (struct ugreenctl_curve_thresholds){40, 45, 50, 55, 70};
    config->ssd = (struct ugreenctl_curve_thresholds){45, 50, 60, 65, 70};
    config->pwm = (struct ugreenctl_curve_pwm_points){64, 128, 204, 255};
    config->system_pwm = config->pwm;
    config->cpu_pwm = config->pwm;
}

static int parse_unsigned(const char *text, unsigned int *value)
{
    char *end;
    unsigned long parsed;

    errno = 0;
    parsed = strtoul(text, &end, 10);
    if (errno != 0 || text[0] == '\0' || *end != '\0' || parsed > UINT_MAX) {
        return -EINVAL;
    }
    *value = (unsigned int)parsed;
    return 0;
}

static int parse_boolean(const char *text, bool *value)
{
    if (strcmp(text, "true") == 0 || strcmp(text, "1") == 0) {
        *value = true;
        return 0;
    }
    if (strcmp(text, "false") == 0 || strcmp(text, "0") == 0) {
        *value = false;
        return 0;
    }
    return -EINVAL;
}

static int parse_thresholds(const char *text, struct ugreenctl_curve_thresholds *thresholds)
{
    char copy[96];
    char *cursor;
    char *part;
    unsigned int values[5];
    size_t index = 0;

    if (snprintf(copy, sizeof(copy), "%s", text) >= (int)sizeof(copy)) {
        return -EINVAL;
    }
    cursor = copy;
    while ((part = strsep(&cursor, ",")) != NULL) {
        if (index >= 5 || parse_unsigned(part, &values[index]) != 0) {
            return -EINVAL;
        }
        ++index;
    }
    if (index != 5) {
        return -EINVAL;
    }
    *thresholds = (struct ugreenctl_curve_thresholds){
        values[0], values[1], values[2], values[3], values[4]
    };
    return 0;
}

static int parse_pwm_points(const char *text, struct ugreenctl_curve_pwm_points *pwm)
{
    char copy[96];
    char *cursor;
    char *part;
    unsigned int values[4];
    size_t index = 0;

    if (snprintf(copy, sizeof(copy), "%s", text) >= (int)sizeof(copy)) {
        return -EINVAL;
    }
    cursor = copy;
    while ((part = strsep(&cursor, ",")) != NULL) {
        if (index >= 4 || parse_unsigned(part, &values[index]) != 0) {
            return -EINVAL;
        }
        ++index;
    }
    if (index != 4) {
        return -EINVAL;
    }
    *pwm = (struct ugreenctl_curve_pwm_points){values[0], values[1], values[2], values[3]};
    return 0;
}

static char *trim(char *text)
{
    char *end;

    while (isspace((unsigned char)*text)) {
        ++text;
    }
    end = text + strlen(text);
    while (end > text && isspace((unsigned char)end[-1])) {
        *--end = '\0';
    }
    return text;
}

static bool profile_is_valid(const char *profile)
{
    return strcmp(profile, "custom") == 0 || strcmp(profile, "stock-4600") == 0 ||
           strcmp(profile, "stock-4800") == 0 ||
           strcmp(profile, "stock-4800s") == 0 ||
           strcmp(profile, "stock-4800plus") == 0 ||
           strcmp(profile, "stock-480tplus") == 0 ||
           strcmp(profile, "stock-6800pro") == 0 ||
           strcmp(profile, "stock-6800plus") == 0 ||
           strcmp(profile, "stock-6800") == 0;
}

/* Stock points were recovered from /etc/default configuration files in
 * the vendor universal image. The DXP6800 and Plus presets deliberately adopt Pro points
 * at the user's request; it is not evidence of their recovered factory curves.
 * This only restores the thermal policy; model
 * plugins remain the single owner of hardware detection and writes. */
static void apply_stock_profile(struct ugreenctl_fan_curve_config *config)
{
    config->minimum_pwm = 40;
    config->hdd_curve_enabled = true;
    config->ssd_curve_enabled = true;
    config->system_cpu_floor_enabled = false;

    if (strcmp(config->profile, "stock-4600") == 0) {
        /* DX4600 ships with fan.conf mode 2.  The vendor daemon applies that
         * mode by lowering every stop/start point 5 C and raising the mid/full
         * PWM points by 24 before evaluating the curve. */
        config->cpu = (struct ugreenctl_curve_thresholds){40, 45, 70, 80, 90};
        config->hdd = (struct ugreenctl_curve_thresholds){30, 35, 50, 55, 70};
        config->ssd = (struct ugreenctl_curve_thresholds){35, 40, 55, 65, 70};
        config->system_pwm = (struct ugreenctl_curve_pwm_points){64, 152, 228, 255};
        config->cpu_pwm = config->system_pwm;
    } else if (strcmp(config->profile, "stock-4800") == 0) {
        config->cpu = (struct ugreenctl_curve_thresholds){45, 50, 70, 75, 85};
        config->hdd = (struct ugreenctl_curve_thresholds){35, 40, 45, 50, 65};
        config->ssd = (struct ugreenctl_curve_thresholds){40, 45, 55, 60, 65};
        config->system_pwm = (struct ugreenctl_curve_pwm_points){64, 128, 204, 255};
        config->cpu_pwm = config->system_pwm;
    } else if (strcmp(config->profile, "stock-4800s") == 0) {
        config->cpu = (struct ugreenctl_curve_thresholds){50, 55, 75, 80, 90};
        config->hdd = (struct ugreenctl_curve_thresholds){40, 45, 50, 55, 70};
        config->ssd = (struct ugreenctl_curve_thresholds){45, 50, 60, 65, 70};
        config->system_pwm = (struct ugreenctl_curve_pwm_points){64, 128, 204, 255};
        config->cpu_pwm = config->system_pwm;
    } else if (strcmp(config->profile, "stock-4800plus") == 0) {
        config->cpu = (struct ugreenctl_curve_thresholds){42, 50, 70, 78, 90};
        config->hdd = (struct ugreenctl_curve_thresholds){30, 40, 46, 52, 55};
        config->ssd = (struct ugreenctl_curve_thresholds){50, 55, 60, 65, 70};
        config->system_pwm = (struct ugreenctl_curve_pwm_points){65, 125, 200, 235};
        config->cpu_pwm = (struct ugreenctl_curve_pwm_points){60, 125, 205, 230};
        config->system_cpu_floor_enabled = true;
        config->system_cpu_floor_start_celsius = 65;
        config->system_cpu_floor_end_celsius = 90;
        config->system_cpu_floor_start_pwm = 100;
        config->system_cpu_floor_end_pwm = 205;
    } else if (strcmp(config->profile, "stock-480tplus") == 0) {
        config->cpu = (struct ugreenctl_curve_thresholds){25, 55, 75, 85, 95};
        /* The vendor configuration deliberately disables HDD influence with
         * five zero points.  Retain those points and do not evaluate them. */
        config->hdd = (struct ugreenctl_curve_thresholds){0, 0, 0, 0, 0};
        config->hdd_curve_enabled = false;
        config->ssd = (struct ugreenctl_curve_thresholds){40, 50, 60, 70, 80};
        config->system_pwm = (struct ugreenctl_curve_pwm_points){55, 90, 110, 128};
        config->cpu_pwm = (struct ugreenctl_curve_pwm_points){70, 130, 150, 200};
    } else if (strcmp(config->profile, "stock-6800pro") == 0 ||
               strcmp(config->profile, "stock-6800plus") == 0 ||
               strcmp(config->profile, "stock-6800") == 0) {
        config->cpu = (struct ugreenctl_curve_thresholds){25, 38, 55, 75, 90};
        config->hdd = (struct ugreenctl_curve_thresholds){30, 35, 43, 48, 55};
        config->ssd = (struct ugreenctl_curve_thresholds){45, 50, 60, 65, 70};
        config->system_pwm = (struct ugreenctl_curve_pwm_points){64, 130, 210, 230};
        config->cpu_pwm = (struct ugreenctl_curve_pwm_points){80, 130, 210, 230};
        config->system_cpu_floor_enabled = true;
        config->system_cpu_floor_start_celsius = 65;
        config->system_cpu_floor_end_celsius = 90;
        config->system_cpu_floor_start_pwm = 125;
        config->system_cpu_floor_end_pwm = 220;
    }
    config->pwm = config->system_pwm;
}

int ugreenctl_fan_curve_load_config(const char *path,
                                    struct ugreenctl_fan_curve_config *config,
                                    char *error, size_t error_size)
{
    FILE *stream;
    char line[256];

    if (path == NULL || config == NULL) {
        set_error(error, error_size, "fan curve configuration path is required");
        return -EINVAL;
    }
    ugreenctl_fan_curve_config_defaults(config);
    stream = fopen(path, "r");
    if (stream == NULL) {
        set_error(error, error_size, "cannot open fan curve configuration");
        return -errno;
    }
    while (fgets(line, sizeof(line), stream) != NULL) {
        char *key = trim(line);
        char *value_text;
        char *equals;

        if (key[0] == '\0' || key[0] == '#' || key[0] == ';') {
            continue;
        }
        equals = strchr(key, '=');
        if (equals == NULL) {
            (void)fclose(stream);
            set_error(error, error_size, "invalid fan curve configuration line");
            return -EINVAL;
        }
        *equals = '\0';
        key = trim(key);
        value_text = trim(equals + 1);
        if (strcmp(key, "profile") == 0) {
            if (snprintf(config->profile, sizeof(config->profile), "%s", value_text) >=
                (int)sizeof(config->profile)) {
                (void)fclose(stream);
                set_error(error, error_size, "fan curve profile is too long");
                return -EINVAL;
            }
        } else if (strcmp(key, "interval_seconds") == 0) {
            if (parse_unsigned(value_text, &config->interval_seconds) != 0) goto invalid_value;
        } else if (strcmp(key, "downshift_delay_seconds") == 0) {
            if (parse_unsigned(value_text, &config->downshift_delay_seconds) != 0) goto invalid_value;
        } else if (strcmp(key, "minimum_pwm") == 0) {
            if (parse_unsigned(value_text, &config->minimum_pwm) != 0) goto invalid_value;
        } else if (strcmp(key, "failsafe_pwm") == 0) {
            if (parse_unsigned(value_text, &config->failsafe_pwm) != 0) goto invalid_value;
        } else if (strcmp(key, "require_storage_sensor") == 0) {
            if (parse_boolean(value_text, &config->require_storage_sensor) != 0) goto invalid_value;
        } else if (strcmp(key, "allow_unvalidated_writes") == 0) {
            if (parse_boolean(value_text, &config->allow_unvalidated_writes) != 0) goto invalid_value;
        } else if (strcmp(key, "hdd_curve_enabled") == 0) {
            if (parse_boolean(value_text, &config->hdd_curve_enabled) != 0) goto invalid_value;
        } else if (strcmp(key, "ssd_curve_enabled") == 0) {
            if (parse_boolean(value_text, &config->ssd_curve_enabled) != 0) goto invalid_value;
        } else if (strcmp(key, "cpu") == 0) {
            if (parse_thresholds(value_text, &config->cpu) != 0) goto invalid_value;
        } else if (strcmp(key, "hdd") == 0) {
            if (parse_thresholds(value_text, &config->hdd) != 0) goto invalid_value;
        } else if (strcmp(key, "ssd") == 0) {
            if (parse_thresholds(value_text, &config->ssd) != 0) goto invalid_value;
        } else if (strcmp(key, "pwm") == 0) {
            if (parse_pwm_points(value_text, &config->pwm) != 0) goto invalid_value;
        }
        continue;
invalid_value:
        (void)fclose(stream);
        set_error(error, error_size, "invalid fan curve configuration value");
        return -EINVAL;
    }
    (void)fclose(stream);
    if (!profile_is_valid(config->profile)) {
        set_error(error, error_size, "unsupported fan curve profile");
        return -EINVAL;
    }
    if (strcmp(config->profile, "custom") == 0) {
        config->system_pwm = config->pwm;
        config->cpu_pwm = config->pwm;
    } else {
        apply_stock_profile(config);
    }
    return ugreenctl_fan_curve_validate_config(config, error, error_size);
}

static bool valid_thresholds(const struct ugreenctl_curve_thresholds *thresholds)
{
    return thresholds->stop <= THERMAL_MAX_CELSIUS &&
           thresholds->stop < thresholds->start && thresholds->start < thresholds->mid &&
           thresholds->mid < thresholds->full && thresholds->full < thresholds->maximum &&
           thresholds->maximum <= THERMAL_MAX_CELSIUS;
}

static bool valid_pwm_points(const struct ugreenctl_curve_pwm_points *points,
                             unsigned int minimum_pwm)
{
    return points->idle >= minimum_pwm && points->maximum <= 255 &&
           points->idle <= points->mid && points->mid <= points->full &&
           points->full <= points->maximum;
}

int ugreenctl_fan_curve_validate_config(const struct ugreenctl_fan_curve_config *config,
                                        char *error, size_t error_size)
{
    if (config == NULL || !profile_is_valid(config->profile)) {
        set_error(error, error_size, "fan curve profile is unsupported");
        return -EINVAL;
    }
    if (config->interval_seconds < 2 || config->interval_seconds > 300 ||
        config->downshift_delay_seconds > 3600) {
        set_error(error, error_size, "fan curve timing is outside the safe range");
        return -ERANGE;
    }
    if (config->minimum_pwm < 40 || config->minimum_pwm > 255 ||
        config->failsafe_pwm < config->minimum_pwm || config->failsafe_pwm > 255 ||
        !valid_pwm_points(&config->pwm, config->minimum_pwm) ||
        !valid_pwm_points(&config->system_pwm, config->minimum_pwm) ||
        !valid_pwm_points(&config->cpu_pwm, config->minimum_pwm) ||
        !valid_thresholds(&config->cpu) ||
        (config->hdd_curve_enabled && !valid_thresholds(&config->hdd)) ||
        (config->ssd_curve_enabled && !valid_thresholds(&config->ssd)) ||
        (config->system_cpu_floor_enabled &&
         (config->system_cpu_floor_start_celsius >= config->system_cpu_floor_end_celsius ||
          config->system_cpu_floor_end_celsius > THERMAL_MAX_CELSIUS ||
          config->system_cpu_floor_start_pwm < config->minimum_pwm ||
          config->system_cpu_floor_end_pwm > 255 ||
          config->system_cpu_floor_start_pwm > config->system_cpu_floor_end_pwm))) {
        set_error(error, error_size, "fan curve thresholds or PWM points are outside the safe range");
        return -ERANGE;
    }
    return 0;
}

int ugreenctl_read_thermal_snapshot(struct ugreenctl_thermal_snapshot *snapshot,
                                    char *error, size_t error_size)
{
    const char *root = thermal_hwmon_root();
    DIR *directory;
    struct dirent *entry;

    if (snapshot == NULL) {
        set_error(error, error_size, "thermal snapshot is required");
        return -EINVAL;
    }
    snapshot->cpu_celsius = -1;
    snapshot->hdd_celsius = -1;
    snapshot->ssd_celsius = -1;
    snapshot->cpu_peak_celsius = -1;
    directory = opendir(root);
    if (directory == NULL) {
        set_error(error, error_size, "cannot open thermal hwmon root");
        return -errno;
    }
    while ((entry = readdir(directory)) != NULL) {
        char device[PATH_MAX];
        char name_path[PATH_MAX];
        char name[64];

        if (!is_hwmon_directory(entry->d_name) ||
            build_path(device, sizeof(device), root, entry->d_name) != 0 ||
            build_path(name_path, sizeof(name_path), device, "name") != 0 ||
            read_text(name_path, name, sizeof(name)) != 0) {
            continue;
        }
        if (is_cpu_hwmon(name)) {
            if (snapshot->cpu_celsius < 0) {
                (void)collect_first_hwmon_temperature(device, &snapshot->cpu_celsius);
            }
            collect_hottest_hwmon_temperature(device, &snapshot->cpu_peak_celsius);
        } else if (is_hdd_hwmon(name)) {
            collect_hottest_hwmon_temperature(device, &snapshot->hdd_celsius);
        } else if (is_ssd_hwmon(name)) {
            collect_hottest_hwmon_temperature(device, &snapshot->ssd_celsius);
        }
    }
    (void)closedir(directory);
    /* Kernel drivetemp remains the preferred source.  Some fnOS kernels omit
     * that module; on those systems, use guarded ATA SMART reads instead. */
    if (snapshot->hdd_celsius < 0) {
        collect_smart_hdd_temperatures(&snapshot->hdd_celsius);
    }
    return 0;
}

static unsigned int interpolate(unsigned int left_temperature, unsigned int right_temperature,
                                unsigned int left_pwm, unsigned int right_pwm,
                                unsigned int temperature)
{
    unsigned long numerator;
    unsigned long denominator = right_temperature - left_temperature;

    if (denominator == 0) {
        return right_pwm;
    }
    numerator = (unsigned long)(temperature - left_temperature) * (right_pwm - left_pwm);
    return left_pwm + (unsigned int)(numerator / denominator);
}

static unsigned int evaluate_source(const struct ugreenctl_curve_thresholds *thresholds,
                                    const struct ugreenctl_curve_pwm_points *points,
                                    int temperature)
{
    unsigned int value = (unsigned int)temperature;

    if (value <= thresholds->start) {
        return points->idle;
    }
    if (value < thresholds->mid) {
        return interpolate(thresholds->start, thresholds->mid, points->idle, points->mid, value);
    }
    if (value < thresholds->full) {
        return interpolate(thresholds->mid, thresholds->full, points->mid, points->full, value);
    }
    if (value < thresholds->maximum) {
        return interpolate(thresholds->full, thresholds->maximum, points->full,
                           points->maximum, value);
    }
    return points->maximum;
}

static unsigned int maximum_of(unsigned int left, unsigned int right)
{
    return left > right ? left : right;
}

static unsigned int cpu_system_floor(const struct ugreenctl_fan_curve_config *config,
                                     int cpu_celsius)
{
    unsigned int cpu = (unsigned int)cpu_celsius;

    if (!config->system_cpu_floor_enabled || cpu < config->system_cpu_floor_start_celsius) {
        return 0;
    }
    if (cpu >= config->system_cpu_floor_end_celsius) {
        return config->system_cpu_floor_end_pwm;
    }
    return interpolate(config->system_cpu_floor_start_celsius,
                       config->system_cpu_floor_end_celsius,
                       config->system_cpu_floor_start_pwm,
                       config->system_cpu_floor_end_pwm, cpu);
}

static int fan_curve_cpu_celsius(const struct ugreenctl_thermal_snapshot *snapshot)
{
    return snapshot->cpu_peak_celsius >= 0 ? snapshot->cpu_peak_celsius :
                                              snapshot->cpu_celsius;
}

int ugreenctl_fan_curve_evaluate_plan(const struct ugreenctl_fan_curve_config *config,
                                      const struct ugreenctl_thermal_snapshot *snapshot,
                                      struct ugreenctl_fan_curve_plan *plan,
                                      char *error, size_t error_size)
{
    unsigned int system_target;
    unsigned int cpu_target;
    int cpu_celsius;

    if (config == NULL || snapshot == NULL || plan == NULL) {
        set_error(error, error_size, "fan curve evaluation requires configuration and temperatures");
        return -EINVAL;
    }
    cpu_celsius = fan_curve_cpu_celsius(snapshot);
    if (cpu_celsius < 0) {
        plan->cpu_pwm = config->failsafe_pwm;
        plan->system_pwm = config->failsafe_pwm;
        set_error(error, error_size, "CPU temperature is unavailable; using failsafe PWM");
        return -ENODATA;
    }
    if (config->require_storage_sensor && snapshot->hdd_celsius < 0 && snapshot->ssd_celsius < 0) {
        plan->cpu_pwm = config->failsafe_pwm;
        plan->system_pwm = config->failsafe_pwm;
        set_error(error, error_size, "storage temperature is unavailable; using failsafe PWM");
        return -ENODATA;
    }
    system_target = evaluate_source(&config->cpu, &config->system_pwm, cpu_celsius);
    if (config->hdd_curve_enabled && snapshot->hdd_celsius >= 0) {
        system_target = maximum_of(system_target,
                                   evaluate_source(&config->hdd, &config->system_pwm,
                                                   snapshot->hdd_celsius));
    }
    if (config->ssd_curve_enabled && snapshot->ssd_celsius >= 0) {
        system_target = maximum_of(system_target,
                                   evaluate_source(&config->ssd, &config->system_pwm,
                                                   snapshot->ssd_celsius));
    }
    system_target = maximum_of(system_target, cpu_system_floor(config, cpu_celsius));
    if (strcmp(config->profile, "custom") == 0) {
        cpu_target = system_target;
    } else {
        cpu_target = evaluate_source(&config->cpu, &config->cpu_pwm, cpu_celsius);
    }
    plan->system_pwm = maximum_of(system_target, config->minimum_pwm);
    plan->cpu_pwm = maximum_of(cpu_target, config->minimum_pwm);
    return 0;
}

int ugreenctl_fan_curve_evaluate(const struct ugreenctl_fan_curve_config *config,
                                 const struct ugreenctl_thermal_snapshot *snapshot,
                                 unsigned int *pwm, char *error, size_t error_size)
{
    struct ugreenctl_fan_curve_plan plan;
    int result;

    if (pwm == NULL) {
        set_error(error, error_size, "fan curve evaluation requires a PWM output");
        return -EINVAL;
    }
    result = ugreenctl_fan_curve_evaluate_plan(config, snapshot, &plan, error, error_size);
    if (result != 0) {
        *pwm = config != NULL ? config->failsafe_pwm : 255;
        return result;
    }
    *pwm = maximum_of(plan.cpu_pwm, plan.system_pwm);
    return 0;
}
