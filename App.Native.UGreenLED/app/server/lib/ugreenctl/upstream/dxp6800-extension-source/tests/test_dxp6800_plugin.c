#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ugreenctl.h"

const struct ugreenctl_plugin *ugreenctl_plugin_v5(void);

static unsigned int unexpected_hardware_calls;

int it8613_dxp6800_read_fans(struct ugreenctl_fan_status *fans, size_t *fan_count,
                           char *error, size_t error_size)
{
    (void)fans;
    (void)fan_count;
    (void)error;
    (void)error_size;
    ++unexpected_hardware_calls;
    return -EIO;
}

int it8613_dxp6800_set_fan_pwm(bool force, const char *fan_id, uint8_t pwm,
                              char *error, size_t error_size)
{
    (void)force;
    (void)fan_id;
    (void)pwm;
    (void)error;
    (void)error_size;
    ++unexpected_hardware_calls;
    return -EIO;
}

int it8613_read_startup_policy(bool force, enum ugreenctl_startup_policy *policy,
                               char *error, size_t error_size)
{
    (void)force;
    (void)policy;
    (void)error;
    (void)error_size;
    ++unexpected_hardware_calls;
    return -EIO;
}

int it8613_set_startup_policy(bool force, enum ugreenctl_startup_policy policy,
                              char *error, size_t error_size)
{
    (void)force;
    (void)policy;
    (void)error;
    (void)error_size;
    ++unexpected_hardware_calls;
    return -EIO;
}

static void fail(const char *message)
{
    (void)fprintf(stderr, "FAIL: %s\n", message);
    exit(EXIT_FAILURE);
}

int main(void)
{
    const struct ugreenctl_plugin *plugin = ugreenctl_plugin_v5();
    struct ugreenctl_request request = {0};
    char error[256] = {0};

    if (plugin == NULL || plugin->abi_version != UGREENCTL_PLUGIN_ABI_V5 ||
        strcmp(plugin->id, "dxp6800") != 0 ||
        plugin->dmi_product_names == NULL ||
        strcmp(plugin->dmi_product_names[0], "DXP6800") != 0 ||
        plugin->dmi_product_names[1] != NULL) {
        fail("DXP6800 exact DMI metadata");
    }
    if (plugin->capabilities !=
        (UGREENCTL_CAP_FAN | UGREENCTL_CAP_POWER) ||
        plugin->set_fan_pwm == NULL || plugin->set_startup_policy == NULL ||
        plugin->set_wol_policy != NULL || plugin->set_led != NULL) {
        fail("DXP6800 capability metadata");
    }
    request.force = false;
    if (plugin->set_fan_pwm(&request, "sys", 120, error, sizeof(error)) != -EPERM ||
        strstr(error, "--force") == NULL) {
        fail("DXP6800 fan experimental-write guard");
    }
    memset(error, 0, sizeof(error));
    if (plugin->set_startup_policy(&request, UGREENCTL_STARTUP_RESTORE,
                                   error, sizeof(error)) != -EPERM ||
        strstr(error, "--force") == NULL) {
        fail("DXP6800 startup experimental-write guard");
    }
    if (unexpected_hardware_calls != 0) {
        fail("DXP6800 guard reached a hardware function");
    }

    (void)puts("DXP6800 plugin metadata and write guards passed");
    return EXIT_SUCCESS;
}
