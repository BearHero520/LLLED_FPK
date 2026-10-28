#include "fan/it8613_dx4600.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "fan/it8613_direct.h"
#include "fan/it8613_hwmon.h"

/* DX4600-family map recovered from the official UGOS Pro 1.17.0.0095
 * ug_it86x-sio.ko route.  Keep this map independent from other single-fan
 * models so later physical corrections cannot affect a different DMI. */
static const struct it8613_hwmon_channel channel = {"sys", 3, 3};
static const struct it8613_direct_channel direct_channel = {
    "sys", 0x17, 0x73, 0x0f, 0x1a, true
};

int it8613_dx4600_read_fan(struct ugreenctl_fan_status *fans, size_t *fan_count,
                           char *error, size_t error_size)
{
    int result = it8613_hwmon_read_fans(&channel, 1, fans, fan_count,
                                        error, error_size);

    if (result != -ENODEV) {
        return result;
    }
    return it8613_direct_read_fans(&direct_channel, 1, fans, fan_count,
                                   error, error_size);
}

int it8613_dx4600_set_fan_pwm(const char *fan_id, uint8_t pwm,
                              char *error, size_t error_size)
{
    int result;

    if (strcmp(fan_id, "sys") != 0) {
        (void)snprintf(error, error_size,
                       "unknown DX4600 fan target '%s' (expected sys)", fan_id);
        return -EINVAL;
    }
    result = it8613_hwmon_set_manual_pwm(&channel, 1, pwm, error, error_size);
    if (result != -ENODEV) {
        return result;
    }
    return it8613_direct_set_manual_pwm(&direct_channel, 1, pwm,
                                        error, error_size);
}
