#ifndef UGREENCTL_IT8613_DIRECT_H
#define UGREENCTL_IT8613_DIRECT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ugreenctl.h"

/*
 * Exact IT8613 hardware-monitor register map for a model's exposed fan
 * channels. The direct backend is only used when no it87 hwmon node exists.
 */
struct it8613_direct_channel {
    const char *id;
    uint8_t control_register;
    uint8_t duty_register;
    uint8_t tachometer_low_register;
    uint8_t tachometer_high_register;
    /* False when firmware proves tachometer wiring but provides no exact PWM
     * write map for this model/channel. Such channels are read-only. */
    bool pwm_supported;
};

int it8613_direct_read_fans(const struct it8613_direct_channel *channels,
                            size_t channel_count,
                            struct ugreenctl_fan_status *fans,
                            size_t *fan_count,
                            char *error, size_t error_size);

int it8613_direct_set_manual_pwm(const struct it8613_direct_channel *channels,
                                  size_t channel_count, uint8_t pwm,
                                  char *error, size_t error_size);

#endif
