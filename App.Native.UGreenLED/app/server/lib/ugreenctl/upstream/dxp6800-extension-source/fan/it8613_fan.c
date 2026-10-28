#include "fan/it8613_fan.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "fan/it8613_direct.h"
#include "fan/it8613_hwmon.h"

/* Linux it87 maps control/duty registers 0x16/0x6b to pwm2 and
 * 0x17/0x73 to pwm3. The tachometer wiring is model-specific. */
static const struct it8613_hwmon_channel channels[] = {
    {"cpu", 2, 2},
    {"sys", 3, 3}
};

/* Direct mappings are model-specific fan wiring on the common IT8613 HWM.
 * They are used only when the generic it87 hwmon driver is not present. */
static const struct it8613_direct_channel direct_channels[] = {
    {"cpu", 0x16, 0x6b, 0x0e, 0x19, true},
    {"sys", 0x17, 0x73, 0x0f, 0x1a, true}
};

int it8613_read_fans(bool force, struct ugreenctl_fan_status *fans, size_t *fan_count,
                     char *error, size_t error_size)
{
    int result;

    (void)force;
    result = it8613_hwmon_read_fans(channels, 2, fans, fan_count,
                                    error, error_size);
    if (result != -ENODEV) {
        return result;
    }
    return it8613_direct_read_fans(direct_channels, 2, fans, fan_count,
                                   error, error_size);
}

int it8613_set_fan_pwm(bool force, const char *fan_id, uint8_t pwm,
                       char *error, size_t error_size)
{
    const struct it8613_hwmon_channel *channel;
    const struct it8613_direct_channel *direct_channel;
    int result;

    if (strcmp(fan_id, "cpu") == 0) {
        channel = &channels[0];
        direct_channel = &direct_channels[0];
    } else if (strcmp(fan_id, "sys") == 0) {
        channel = &channels[1];
        direct_channel = &direct_channels[1];
    } else {
        (void)snprintf(error, error_size, "unknown fan '%s' (expected cpu or sys)", fan_id);
        return -EINVAL;
    }
    result = it8613_hwmon_set_manual_pwm(channel, 1, pwm, error, error_size);
    if (result != -ENODEV) {
        return result;
    }
    if (!force) {
        (void)snprintf(error, error_size,
                       "direct Super I/O fan writes require --force together with --apply");
        return -EPERM;
    }
    return it8613_direct_set_manual_pwm(direct_channel, 1, pwm,
                                        error, error_size);
}
