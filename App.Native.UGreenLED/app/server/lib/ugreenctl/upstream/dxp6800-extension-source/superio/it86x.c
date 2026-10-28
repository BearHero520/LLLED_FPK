#define _GNU_SOURCE

#include "superio/it86x.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/io.h>
#include <unistd.h>

#define SIO_INDEX 0x2e
#define SIO_DATA 0x2f
#define HWM_INDEX 0xa35
#define HWM_DATA 0xa36
#define IT8613_ID 0x8613

static void set_error(char *error, size_t error_size, const char *format, const char *detail)
{
    if (error != NULL && error_size > 0) {
        (void)snprintf(error, error_size, format, detail);
    }
}

static const char *active_controller_owner(void)
{
    static const char * const paths[] = {
        "/proc/it86",
        "/sys/module/ug_it86x_sio",
        "/sys/module/ug_it86x_cpufan",
        "/sys/module/it87",
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

static void sio_enter(void)
{
    outb(0x87, SIO_INDEX);
    outb(0x01, SIO_INDEX);
    outb(0x55, SIO_INDEX);
    outb(0x55, SIO_INDEX);
}

static void sio_exit(void)
{
    outb(0x02, SIO_INDEX);
    outb(0x02, SIO_DATA);
}

uint8_t it86x_sio_read(uint8_t reg)
{
    outb(reg, SIO_INDEX);
    return inb(SIO_DATA);
}

void it86x_sio_write(uint8_t reg, uint8_t value)
{
    outb(reg, SIO_INDEX);
    outb(value, SIO_DATA);
}

uint8_t it86x_hwm_read(uint8_t reg)
{
    outb(reg, HWM_INDEX);
    return inb(HWM_DATA);
}

void it86x_hwm_write(uint8_t reg, uint8_t value)
{
    outb(reg, HWM_INDEX);
    outb(value, HWM_DATA);
}

int it86x_open(struct it86x_device *device, char *error, size_t error_size)
{
    const char *owner;
    uint8_t active;

    memset(device, 0, sizeof(*device));
    device->lock_fd = -1;
    owner = active_controller_owner();
    if (owner != NULL) {
        set_error(error, error_size,
                  "controller owner is active; unload it before direct access: %s", owner);
        return -EBUSY;
    }

    device->lock_fd = open("/run/ugreenctl-it8613.lock",
                           O_CREAT | O_CLOEXEC | O_RDWR, 0600);
    if (device->lock_fd < 0) {
        set_error(error, error_size, "cannot create controller lock: %s", strerror(errno));
        return -errno;
    }
    if (flock(device->lock_fd, LOCK_EX) != 0) {
        int saved_errno = errno;
        it86x_close(device);
        set_error(error, error_size, "cannot lock controller: %s", strerror(saved_errno));
        return -saved_errno;
    }

    if (ioperm(SIO_INDEX, 2, 1) != 0) {
        int saved_errno = errno;
        it86x_close(device);
        set_error(error, error_size,
                  "direct I/O permission denied (run as root or grant CAP_SYS_RAWIO): %s",
                  strerror(saved_errno));
        return -saved_errno;
    }
    if (ioperm(HWM_INDEX, 2, 1) != 0) {
        int saved_errno = errno;
        (void)ioperm(SIO_INDEX, 2, 0);
        it86x_close(device);
        set_error(error, error_size,
                  "direct I/O permission denied (run as root or grant CAP_SYS_RAWIO): %s",
                  strerror(saved_errno));
        return -saved_errno;
    }
    device->ports_enabled = true;
    sio_enter();
    device->config_open = true;
    device->chip_id = ((uint16_t)it86x_sio_read(0x20) << 8) | it86x_sio_read(0x21);
    device->revision = it86x_sio_read(0x22) & 0x0f;
    it86x_sio_write(0x07, 0x04);
    active = it86x_sio_read(0x30);
    if ((active & 0x01) == 0) {
        it86x_close(device);
        set_error(error, error_size, "IT86x hardware-monitor logical device is disabled: %s", "");
        return -ENODEV;
    }
    if (device->chip_id != IT8613_ID) {
        char found[32];
        (void)snprintf(found, sizeof(found), "found IT%04x, expected IT8613", device->chip_id);
        it86x_close(device);
        set_error(error, error_size, "controller identity mismatch: %s", found);
        return -ENODEV;
    }
    return 0;
}

void it86x_close(struct it86x_device *device)
{
    if (device->config_open) {
        sio_exit();
    }
    if (device->ports_enabled) {
        (void)ioperm(HWM_INDEX, 2, 0);
        (void)ioperm(SIO_INDEX, 2, 0);
    }
    if (device->lock_fd >= 0) {
        (void)close(device->lock_fd);
    }
    memset(device, 0, sizeof(*device));
    device->lock_fd = -1;
}
