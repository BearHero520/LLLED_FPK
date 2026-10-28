#ifndef UGREENCTL_H
#define UGREENCTL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define UGREENCTL_PLUGIN_ABI_V2 2U
#define UGREENCTL_PLUGIN_ABI_V3 3U
#define UGREENCTL_PLUGIN_ABI_V4 4U
#define UGREENCTL_PLUGIN_ABI_V5 5U
#define UGREENCTL_MAX_FANS 8U
#define UGREENCTL_MAX_LEDS 16U

enum ugreenctl_capability {
    UGREENCTL_CAP_FAN = 1U << 0,
    UGREENCTL_CAP_LED = 1U << 1,
    UGREENCTL_CAP_POWER = 1U << 2,
    UGREENCTL_CAP_WOL = 1U << 3
};

enum ugreenctl_startup_policy {
    UGREENCTL_STARTUP_UNKNOWN = 0,
    UGREENCTL_STARTUP_ON,
    UGREENCTL_STARTUP_OFF,
    UGREENCTL_STARTUP_RESTORE
};

enum ugreenctl_wol_policy {
    UGREENCTL_WOL_UNKNOWN = 0,
    UGREENCTL_WOL_OFF,
    UGREENCTL_WOL_ON
};

enum ugreenctl_led_state {
    UGREENCTL_LED_UNKNOWN = 0,
    UGREENCTL_LED_OFF,
    UGREENCTL_LED_ON,
    UGREENCTL_LED_BLINK
};

struct ugreenctl_request {
    bool force;
};

struct ugreenctl_fan_status {
    char id[16];
    uint8_t pwm;
    bool pwm_known;
    bool manual;
    bool mode_known;
    uint16_t tachometer;
    unsigned long rpm;
};

struct ugreenctl_led_status {
    char id[32];
    enum ugreenctl_led_state state;
};

struct ugreenctl_status {
    char controller[32];
    uint8_t revision;
    enum ugreenctl_startup_policy startup_policy;
    struct ugreenctl_fan_status fans[UGREENCTL_MAX_FANS];
    size_t fan_count;
    struct ugreenctl_led_status leds[UGREENCTL_MAX_LEDS];
    size_t led_count;
    /* Appended for ABI compatibility with v2-v4 model plugins. */
    enum ugreenctl_wol_policy wol_policy;
};

struct ugreenctl_plugin {
    unsigned int abi_version;
    const char *id;
    const char *display_name;
    const char * const *dmi_product_names;
    unsigned int capabilities;
    int (*read_status)(const struct ugreenctl_request *request,
                       struct ugreenctl_status *status,
                       char *error, size_t error_size);
    int (*set_fan_pwm)(const struct ugreenctl_request *request,
                       const char *fan_id, uint8_t pwm,
                       char *error, size_t error_size);
    int (*set_startup_policy)(const struct ugreenctl_request *request,
                              enum ugreenctl_startup_policy policy,
                              char *error, size_t error_size);
    int (*set_led)(const struct ugreenctl_request *request,
                   const char *led_id, enum ugreenctl_led_state state,
                   char *error, size_t error_size);
    int (*set_fan_mode)(const struct ugreenctl_request *request,
                        const char *fan_id, bool automatic,
                        char *error, size_t error_size);
    int (*read_fans)(const struct ugreenctl_request *request,
                     struct ugreenctl_fan_status *fans, size_t *fan_count,
                     char *error, size_t error_size);
    int (*read_startup_policy)(const struct ugreenctl_request *request,
                               enum ugreenctl_startup_policy *policy,
                               char *error, size_t error_size);
    const char *controller_name;
    int (*set_wol_policy)(const struct ugreenctl_request *request,
                          enum ugreenctl_wol_policy policy,
                          char *error, size_t error_size);
    int (*read_wol_policy)(const struct ugreenctl_request *request,
                           enum ugreenctl_wol_policy *policy,
                           char *error, size_t error_size);
};

typedef const struct ugreenctl_plugin *(*ugreenctl_plugin_entrypoint)(void);

#endif
