#include "power/it8613_power.h"

#include <errno.h>
#include <stdio.h>

#include "superio/it86x.h"

static enum ugreenctl_startup_policy decode_policy(uint8_t f2, uint8_t f4)
{
    unsigned int state = ((f2 >> 3) & 0x4U) | ((f4 >> 5) & 0x3U);
    switch (state) {
    case 1:
        return UGREENCTL_STARTUP_ON;
    case 3:
        return UGREENCTL_STARTUP_OFF;
    case 7:
        return UGREENCTL_STARTUP_RESTORE;
    default:
        return UGREENCTL_STARTUP_UNKNOWN;
    }
}

int it8613_read_startup_policy(bool force, enum ugreenctl_startup_policy *policy,
                               char *error, size_t error_size)
{
    struct it86x_device device;
    int result;

    (void)force;
    result = it86x_open(&device, error, error_size);

    if (result != 0) {
        return result;
    }
    *policy = decode_policy(it86x_sio_read(0xf2), it86x_sio_read(0xf4));
    it86x_close(&device);
    return 0;
}

int it8613_set_startup_policy(bool force, enum ugreenctl_startup_policy policy,
                              char *error, size_t error_size)
{
    struct it86x_device device;
    uint8_t f2;
    uint8_t f4;
    int result;

    (void)force;
    result = it86x_open(&device, error, error_size);
    if (result != 0) {
        return result;
    }
    f2 = it86x_sio_read(0xf2);
    f4 = it86x_sio_read(0xf4);
    switch (policy) {
    case UGREENCTL_STARTUP_ON:
        f2 &= (uint8_t)~0x20U;
        f4 = (f4 | 0x20U) & (uint8_t)~0x40U;
        break;
    case UGREENCTL_STARTUP_OFF:
        f2 &= (uint8_t)~0x20U;
        f4 |= 0x60U;
        break;
    case UGREENCTL_STARTUP_RESTORE:
        f2 |= 0x20U;
        f4 |= 0x60U;
        break;
    default:
        it86x_close(&device);
        (void)snprintf(error, error_size, "invalid startup policy");
        return -EINVAL;
    }
    it86x_sio_write(0xf2, f2);
    it86x_sio_write(0xf4, f4);
    if (it86x_sio_read(0xf2) != f2 || it86x_sio_read(0xf4) != f4 ||
        decode_policy(f2, f4) != policy) {
        it86x_close(&device);
        (void)snprintf(error, error_size,
                       "IT8613 AC-recovery register readback did not match %s policy",
                       policy == UGREENCTL_STARTUP_ON ? "on" :
                       policy == UGREENCTL_STARTUP_OFF ? "off" : "restore");
        return -EIO;
    }
    it86x_close(&device);
    return 0;
}
