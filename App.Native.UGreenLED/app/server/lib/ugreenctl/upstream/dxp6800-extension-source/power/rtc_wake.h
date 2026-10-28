#ifndef UGREENCTL_RTC_WAKE_H
#define UGREENCTL_RTC_WAKE_H

#include <stddef.h>
#include <time.h>
struct ugreenctl_rtc_profile;

int ugreenctl_rtc_wake_parse(const char *value, time_t *epoch,
                             char *error, size_t error_size);
int ugreenctl_rtc_wake_read(const struct ugreenctl_rtc_profile *profile, time_t *epoch, char *error, size_t error_size);
int ugreenctl_rtc_wake_set(const struct ugreenctl_rtc_profile *profile, time_t epoch, char *error, size_t error_size);
int ugreenctl_rtc_wake_clear(const struct ugreenctl_rtc_profile *profile, char *error, size_t error_size);

int ugreenctl_rtc_select_at(const char *root, const struct ugreenctl_rtc_profile *profile,
                           char *path, size_t path_size, char *error, size_t error_size);
int ugreenctl_rtc_validate_epoch(const struct ugreenctl_rtc_profile *profile, time_t epoch,
                                time_t now, char *error, size_t error_size);
#endif
