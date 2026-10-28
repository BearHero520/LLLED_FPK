#ifndef UGREENCTL_IT8613_HWMON_H
#define UGREENCTL_IT8613_HWMON_H

#include <stddef.h>
#include <stdint.h>

#include "ugreenctl.h"

struct it8613_hwmon_channel {
    const char *id;
    unsigned int pwm_index;
    unsigned int fan_index;
};

int it8613_hwmon_read_fans(const struct it8613_hwmon_channel *channels,
                           size_t channel_count,
                           struct ugreenctl_fan_status *fans,
                           size_t *fan_count,
                           char *error, size_t error_size);

int it8613_hwmon_set_manual_pwm(const struct it8613_hwmon_channel *channels,
                                size_t channel_count, uint8_t pwm,
                                char *error, size_t error_size);

#endif
