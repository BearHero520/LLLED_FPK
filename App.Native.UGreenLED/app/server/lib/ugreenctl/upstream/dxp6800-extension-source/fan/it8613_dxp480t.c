#include "fan/it8613_dxp480t.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "fan/it8613_direct.h"
#include "fan/it8613_hwmon.h"

static const struct it8613_hwmon_channel status_channels[] = {
    /* ug_it86x-cpufan's exact DXP480T Plus route wires its `cpu` command
     * to 0x17/0x73 (it87 pwm3). Its `set` command drives the two system
     * fans through 0x16/0x6b (pwm2) and 0x1e/0x7b (pwm4). */
    {"cpu", 3, 3},
    {"sys1", 2, 2},
    {"sys2", 4, 4}
};

/* Preserve the vendor DXP480T Plus `set <PWM>` transaction order exactly.
 * Despite the legacy public target name `all`, this is the system-fan pair;
 * the stock controller applies CPU duty with a separate `cpu <PWM>` command. */
static const struct it8613_hwmon_channel system_write_channels[] = {
    {"sys1", 2, 2},
    {"sys2", 4, 4}
};

static const struct it8613_direct_channel direct_status_channels[] = {
    {"cpu", 0x17, 0x73, 0x0f, 0x1a, true},
    {"sys1", 0x16, 0x6b, 0x0e, 0x19, true},
    {"sys2", 0x1e, 0x7b, 0x80, 0x81, true}
};

/* `set <PWM>` is the vendor system-fan transaction. It writes sys1 before
 * sys2, while `cpu <PWM>` independently writes direct_status_channels[0]. */
static const struct it8613_direct_channel direct_system_write_channels[] = {
    {"sys1", 0x16, 0x6b, 0x0e, 0x19, true},
    {"sys2", 0x1e, 0x7b, 0x80, 0x81, true}
};

int it8613_dxp480t_read_fans(struct ugreenctl_fan_status *fans, size_t *fan_count,
                              char *error, size_t error_size)
{
    int result = it8613_hwmon_read_fans(status_channels, 3, fans, fan_count,
                                        error, error_size);

    if (result != -ENODEV) {
        return result;
    }
    return it8613_direct_read_fans(direct_status_channels, 3, fans, fan_count,
                                   error, error_size);
}

int it8613_dxp480t_set_fan_pwm(bool force, const char *fan_id, uint8_t pwm,
                                char *error, size_t error_size)
{
    int result;

    if (strcmp(fan_id, "cpu") != 0 && strcmp(fan_id, "all") != 0) {
        (void)snprintf(error, error_size,
                       "unknown DXP480T fan target '%s' (expected cpu or all)", fan_id);
        return -EINVAL;
    }
    if (strcmp(fan_id, "cpu") == 0) {
        result = it8613_hwmon_set_manual_pwm(&status_channels[0], 1, pwm,
                                              error, error_size);
        if (result != -ENODEV) {
            return result;
        }
        if (!force) {
            (void)snprintf(error, error_size,
                           "direct Super I/O fan writes require --force together with --apply");
            return -EPERM;
        }
        return it8613_direct_set_manual_pwm(&direct_status_channels[0], 1, pwm,
                                            error, error_size);
    }
    result = it8613_hwmon_set_manual_pwm(system_write_channels, 2, pwm,
                                         error, error_size);
    if (result != -ENODEV) {
        return result;
    }
    if (!force) {
        (void)snprintf(error, error_size,
                       "direct Super I/O fan writes require --force together with --apply");
        return -EPERM;
    }
    return it8613_direct_set_manual_pwm(direct_system_write_channels, 2, pwm,
                                        error, error_size);
}
