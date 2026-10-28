#include "fan/it8613_direct.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "superio/it86x.h"

#define IT8613_DIRECT_MIN_MANUAL_PWM 40U
#define IT8613_DIRECT_MANUAL_BIT 0x80U
#define IT8613_TACHOMETER_DIVIDEND 675000UL
#define IT8613_TACHOMETER_INVALID_12BIT 0x0fffU

static void set_error(char *error, size_t error_size, const char *format,
                      const char *detail)
{
    if (error != NULL && error_size > 0) {
        (void)snprintf(error, error_size, format, detail);
    }
}

static int validate_mapping(const struct it8613_direct_channel *channels,
                            size_t channel_count, char *error, size_t error_size)
{
    size_t index;

    if (channels == NULL || channel_count == 0 ||
        channel_count > UGREENCTL_MAX_FANS) {
        set_error(error, error_size, "invalid IT8613 direct fan mapping: %s", "count");
        return -EINVAL;
    }
    for (index = 0; index < channel_count; ++index) {
        if (channels[index].id == NULL || channels[index].id[0] == '\0') {
            set_error(error, error_size, "invalid IT8613 direct fan mapping: %s", "id");
            return -EINVAL;
        }
    }
    return 0;
}

static void read_channel(const struct it8613_direct_channel *channel,
                         struct ugreenctl_fan_status *fan)
{
    uint8_t control = 0;
    uint16_t tachometer = (uint16_t)((uint16_t)it86x_hwm_read(
                                      channel->tachometer_high_register) << 8) |
                         it86x_hwm_read(channel->tachometer_low_register);

    memset(fan, 0, sizeof(*fan));
    (void)snprintf(fan->id, sizeof(fan->id), "%s", channel->id);
    if (channel->pwm_supported) {
        control = it86x_hwm_read(channel->control_register);
        fan->pwm = it86x_hwm_read(channel->duty_register);
        fan->pwm_known = true;
        fan->manual = (control & IT8613_DIRECT_MANUAL_BIT) == 0;
        /* A set bit does not establish the vendor's software temperature policy;
         * present only the supported manual state as known. */
        fan->mode_known = fan->manual;
    }
    fan->tachometer = tachometer;
    /* The stock ug_it86x-cpufan driver treats both all-ones encodings as
     * invalid tachometer data. 0x0fff otherwise looks like a plausible
     * low RPM, which made a stopped/unwired DXP480T Plus channel display
     * roughly 164 RPM through the direct fallback. */
    fan->rpm = tachometer == 0 || tachometer == IT8613_TACHOMETER_INVALID_12BIT ||
                   tachometer == UINT16_MAX
                   ? 0
                   : IT8613_TACHOMETER_DIVIDEND / tachometer;
}

static int set_channel_manual_pwm(const struct it8613_direct_channel *channel,
                                  uint8_t pwm, char *error, size_t error_size)
{
    uint8_t control = it86x_hwm_read(channel->control_register);
    uint8_t readback;

    control &= (uint8_t)~IT8613_DIRECT_MANUAL_BIT;
    it86x_hwm_write(channel->control_register, control);
    readback = it86x_hwm_read(channel->control_register);
    if ((readback & IT8613_DIRECT_MANUAL_BIT) != 0) {
        set_error(error, error_size,
                  "direct fan control verification failed for: %s", channel->id);
        return -EIO;
    }

    it86x_hwm_write(channel->duty_register, pwm);
    readback = it86x_hwm_read(channel->duty_register);
    if (readback != pwm) {
        char detail[64];
        (void)snprintf(detail, sizeof(detail), "%s wrote %u but read back %u",
                       channel->id, pwm, readback);
        set_error(error, error_size,
                  "direct fan PWM verification failed for: %s", detail);
        return -EIO;
    }
    return 0;
}

int it8613_direct_read_fans(const struct it8613_direct_channel *channels,
                            size_t channel_count,
                            struct ugreenctl_fan_status *fans,
                            size_t *fan_count,
                            char *error, size_t error_size)
{
    struct it86x_device device;
    size_t index;
    int result;

    if (fans == NULL || fan_count == NULL) {
        set_error(error, error_size, "invalid IT8613 direct fan output: %s", "buffer");
        return -EINVAL;
    }
    result = validate_mapping(channels, channel_count, error, error_size);
    if (result != 0) {
        return result;
    }
    result = it86x_open(&device, error, error_size);
    if (result != 0) {
        return result;
    }
    for (index = 0; index < channel_count; ++index) {
        read_channel(&channels[index], &fans[index]);
    }
    *fan_count = channel_count;
    it86x_close(&device);
    return 0;
}

int it8613_direct_set_manual_pwm(const struct it8613_direct_channel *channels,
                                  size_t channel_count, uint8_t pwm,
                                  char *error, size_t error_size)
{
    struct it86x_device device;
    size_t index;
    int result;

    result = validate_mapping(channels, channel_count, error, error_size);
    if (result != 0) {
        return result;
    }
    if (pwm < IT8613_DIRECT_MIN_MANUAL_PWM) {
        if (error != NULL && error_size > 0) {
            (void)snprintf(error, error_size,
                           "refusing unsafe PWM %u; choose a value of 40-255", pwm);
        }
        return -EPERM;
    }
    for (index = 0; index < channel_count; ++index) {
        if (!channels[index].pwm_supported) {
            set_error(error, error_size,
                      "direct fan PWM is unavailable for: %s", channels[index].id);
            return -EOPNOTSUPP;
        }
    }
    result = it86x_open(&device, error, error_size);
    if (result != 0) {
        return result;
    }
    for (index = 0; index < channel_count; ++index) {
        result = set_channel_manual_pwm(&channels[index], pwm, error, error_size);
        if (result != 0) {
            it86x_close(&device);
            return result;
        }
    }
    it86x_close(&device);
    return 0;
}
