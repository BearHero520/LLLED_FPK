#ifndef UGREENCTL_IT8613_DXP4800_H
#define UGREENCTL_IT8613_DXP4800_H

#include <stddef.h>
#include <stdint.h>

#include "ugreenctl.h"

int it8613_dxp4800_read_fan(struct ugreenctl_fan_status *fans, size_t *fan_count,
                            char *error, size_t error_size);
int it8613_dxp4800_set_fan_pwm(const char *fan_id, uint8_t pwm,
                               char *error, size_t error_size);

#endif
