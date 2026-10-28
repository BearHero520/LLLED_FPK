#ifndef UGREENCTL_IT8613_FAN_H
#define UGREENCTL_IT8613_FAN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ugreenctl.h"

int it8613_read_fans(bool force, struct ugreenctl_fan_status *fans, size_t *fan_count,
                     char *error, size_t error_size);
int it8613_set_fan_pwm(bool force, const char *fan_id, uint8_t pwm,
                       char *error, size_t error_size);

#endif
