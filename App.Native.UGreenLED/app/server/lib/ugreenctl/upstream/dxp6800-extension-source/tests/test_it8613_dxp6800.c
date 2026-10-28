#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fan/it8613_direct.h"
#include "fan/it8613_dxp6800.h"
#include "fan/it8613_hwmon.h"

static const struct it8613_direct_channel *captured_channels;
static size_t captured_channel_count;
static uint8_t captured_pwm;
static unsigned int direct_write_calls;
static const struct it8613_direct_channel *captured_read_channels;
static size_t captured_read_channel_count;
static int hwmon_result = -ENODEV;
static unsigned int direct_read_calls;

static void fail(const char *message)
{
    (void)fprintf(stderr, "FAIL: %s\n", message);
    exit(EXIT_FAILURE);
}

int it8613_hwmon_read_fans(const struct it8613_hwmon_channel *channels,
                           size_t channel_count,
                           struct ugreenctl_fan_status *fans,
                           size_t *fan_count,
                           char *error, size_t error_size)
{
    (void)channels;
    (void)channel_count;
    (void)fans;
    (void)fan_count;
    (void)error;
    (void)error_size;
    return hwmon_result;
}

int it8613_hwmon_set_manual_pwm(const struct it8613_hwmon_channel *channels,
                                size_t channel_count, uint8_t pwm,
                                char *error, size_t error_size)
{
    (void)channels;
    (void)channel_count;
    (void)pwm;
    (void)error;
    (void)error_size;
    return hwmon_result;
}

int it8613_direct_read_fans(const struct it8613_direct_channel *channels,
                            size_t channel_count,
                            struct ugreenctl_fan_status *fans,
                            size_t *fan_count,
                            char *error, size_t error_size)
{
    (void)fans;
    (void)error;
    (void)error_size;
    captured_read_channels = channels;
    ++direct_read_calls;
    captured_read_channel_count = channel_count;
    *fan_count = channel_count;
    return 0;
}

int it8613_direct_set_manual_pwm(const struct it8613_direct_channel *channels,
                                  size_t channel_count, uint8_t pwm,
                                  char *error, size_t error_size)
{
    (void)error;
    (void)error_size;
    captured_channels = channels;
    captured_channel_count = channel_count;
    captured_pwm = pwm;
    ++direct_write_calls;
    return 0;
}

static void expect_channel(const struct it8613_direct_channel *channel,
                           const char *id, uint8_t control, uint8_t duty,
                           uint8_t tachometer_low, uint8_t tachometer_high)
{
    if (strcmp(channel->id, id) != 0 ||
        channel->control_register != control ||
        channel->duty_register != duty ||
        channel->tachometer_low_register != tachometer_low ||
        channel->tachometer_high_register != tachometer_high ||
        !channel->pwm_supported) {
        fail("DXP6800 direct channel map");
    }
}

int main(void)
{
    char error[256] = {0};
    struct ugreenctl_fan_status fans[UGREENCTL_MAX_FANS];
    size_t fan_count = 0;

    if (it8613_dxp6800_read_fans(fans, &fan_count, error, sizeof(error)) != 0 ||
        captured_read_channel_count != 3 || fan_count != 3) {
        fail("DXP6800 direct status fallback");
    }
    expect_channel(&captured_read_channels[0], "cpu", 0x16, 0x6b, 0x0e, 0x19);
    expect_channel(&captured_read_channels[1], "sys1", 0x17, 0x73, 0x0f, 0x1a);
    expect_channel(&captured_read_channels[2], "sys2", 0x1e, 0x7b, 0x80, 0x81);

    if (it8613_dxp6800_set_fan_pwm(true, "cpu", 120, error, sizeof(error)) != 0 ||
        direct_write_calls != 1 || captured_channel_count != 1 || captured_pwm != 120) {
        fail("DXP6800 direct CPU fallback");
    }
    expect_channel(&captured_channels[0], "cpu", 0x16, 0x6b, 0x0e, 0x19);

    if (it8613_dxp6800_set_fan_pwm(true, "sys", 120, error, sizeof(error)) != 0 ||
        direct_write_calls != 2 || captured_channel_count != 2 || captured_pwm != 120) {
        fail("DXP6800 direct system fallback");
    }
    expect_channel(&captured_channels[0], "sys1", 0x17, 0x73, 0x0f, 0x1a);
    expect_channel(&captured_channels[1], "sys2", 0x1e, 0x7b, 0x80, 0x81);

    if (it8613_dxp6800_set_fan_pwm(false, "sys", 120, error, sizeof(error)) != -EPERM ||
        direct_write_calls != 2 ||
        strstr(error, "--force together with --apply") == NULL) {
        fail("DXP6800 direct fallback acknowledgement");
    }

    if (it8613_dxp6800_set_fan_pwm(true, "sys1", 120, error, sizeof(error)) != -EINVAL ||
        direct_write_calls != 2) {
        fail("DXP6800 target guard");
    }

    /* A present hwmon owner must never be bypassed on success or I/O failure. */
    {
        const int results[] = {0, -EIO, -EACCES, -EBUSY};
        size_t i;
        for (i = 0; i < sizeof(results) / sizeof(results[0]); ++i) {
            hwmon_result = results[i];
            if (it8613_dxp6800_read_fans(fans, &fan_count, error, sizeof(error)) != hwmon_result ||
                direct_read_calls != 1) {
                fail("DXP6800 must preserve hwmon read result without direct fallback");
            }
            if (it8613_dxp6800_set_fan_pwm(true, "sys", 120, error, sizeof(error)) != hwmon_result ||
                direct_write_calls != 2) {
                fail("DXP6800 must preserve hwmon write result without direct fallback");
            }
        }
    }
    (void)puts("DXP6800 direct map and hwmon fallback guard tests passed");
    return EXIT_SUCCESS;
}
