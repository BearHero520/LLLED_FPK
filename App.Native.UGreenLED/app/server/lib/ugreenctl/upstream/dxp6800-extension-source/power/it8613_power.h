#ifndef UGREENCTL_IT8613_POWER_H
#define UGREENCTL_IT8613_POWER_H

#include <stdbool.h>
#include <stddef.h>

#include "ugreenctl.h"

int it8613_read_startup_policy(bool force, enum ugreenctl_startup_policy *policy,
                               char *error, size_t error_size);
int it8613_set_startup_policy(bool force, enum ugreenctl_startup_policy policy,
                              char *error, size_t error_size);

#endif
