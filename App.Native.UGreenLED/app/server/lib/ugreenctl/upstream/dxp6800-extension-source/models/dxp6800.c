#include "ugreenctl.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "fan/it8613_dxp6800.h"
#include "power/it8613_power.h"

static const char * const product_names[] = {
    "DXP6800",
    NULL
};

static int require_experimental_override(const struct ugreenctl_request *request,
                                         char *error, size_t error_size)
{
    if (request->force) {
        return 0;
    }
    (void)snprintf(error, error_size,
                   "DXP6800 writes are firmware-reversed but await physical validation; "
                   "use --force together with --apply on an exact DXP6800");
    return -EPERM;
}

static int read_fans(const struct ugreenctl_request *request,
                     struct ugreenctl_fan_status *fans, size_t *fan_count,
                     char *error, size_t error_size)
{
    (void)request;
    return it8613_dxp6800_read_fans(fans, fan_count, error, error_size);
}

static int read_startup_policy(const struct ugreenctl_request *request,
                               enum ugreenctl_startup_policy *policy,
                               char *error, size_t error_size)
{
    return it8613_read_startup_policy(request->force, policy, error, error_size);
}

static int read_status(const struct ugreenctl_request *request,
                       struct ugreenctl_status *status,
                       char *error, size_t error_size)
{
    char startup_error[256] = {0};
    int result;

    memset(status, 0, sizeof(*status));
    (void)snprintf(status->controller, sizeof(status->controller),
                   "ITE IT8613 hwmon/direct");
    result = read_fans(request, status->fans, &status->fan_count, error, error_size);
    if (result != 0) {
        return result;
    }
    status->startup_policy = UGREENCTL_STARTUP_UNKNOWN;
    (void)read_startup_policy(request, &status->startup_policy,
                              startup_error, sizeof(startup_error));
    status->wol_policy = UGREENCTL_WOL_UNKNOWN;
    return 0;
}

static int set_fan_pwm(const struct ugreenctl_request *request,
                       const char *fan_id, uint8_t pwm,
                       char *error, size_t error_size)
{
    int result = require_experimental_override(request, error, error_size);

    if (result != 0) {
        return result;
    }
    return it8613_dxp6800_set_fan_pwm(true, fan_id, pwm, error, error_size);
}

static int set_startup_policy(const struct ugreenctl_request *request,
                              enum ugreenctl_startup_policy policy,
                              char *error, size_t error_size)
{
    int result = require_experimental_override(request, error, error_size);

    if (result != 0) {
        return result;
    }
    return it8613_set_startup_policy(request->force, policy, error, error_size);
}

const struct ugreenctl_plugin *ugreenctl_plugin_v5(void)
{
    static const struct ugreenctl_plugin plugin = {
        .abi_version = UGREENCTL_PLUGIN_ABI_V5,
        .id = "dxp6800",
        .display_name = "UGREEN DXP6800 (firmware-reversed)",
        .dmi_product_names = product_names,
        .capabilities = UGREENCTL_CAP_FAN | UGREENCTL_CAP_POWER,
        .read_status = read_status,
        .set_fan_pwm = set_fan_pwm,
        .set_startup_policy = set_startup_policy,
        .set_led = NULL,
        .set_fan_mode = NULL,
        .read_fans = read_fans,
        .read_startup_policy = read_startup_policy,
        .controller_name = "ITE IT8613 hwmon/direct",
        .set_wol_policy = NULL,
        .read_wol_policy = NULL
    };
    return &plugin;
}
