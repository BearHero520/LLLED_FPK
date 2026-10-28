#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "fan/thermal_curve.h"

static void fail(const char *message)
{
    (void)fprintf(stderr, "FAIL: %s\n", message);
    exit(EXIT_FAILURE);
}

static void write_file(const char *path, const char *content)
{
    FILE *stream = fopen(path, "w");
    if (stream == NULL || fputs(content, stream) < 0 || fclose(stream) != 0) {
        fail("cannot write fixture");
    }
}

int main(void)
{
    char temporary[] = "/tmp/ugreenctl-thermal-XXXXXX";
    char path[512];
    struct ugreenctl_fan_curve_config config;
    struct ugreenctl_thermal_snapshot snapshot;
    struct ugreenctl_fan_curve_plan plan;
    char error[256] = {0};
    unsigned int pwm;
    int smart_temperature;
    unsigned char smart_data[512] = {0};

    if (mkdtemp(temporary) == NULL) {
        fail("cannot create temporary directory");
    }
    (void)snprintf(path, sizeof(path), "%s/hwmon0", temporary);
    if (mkdir(path, 0700) != 0) fail("cannot create CPU fixture");
    (void)snprintf(path, sizeof(path), "%s/hwmon0/name", temporary);
    write_file(path, "coretemp\n");
    (void)snprintf(path, sizeof(path), "%s/hwmon0/temp10_input", temporary);
    write_file(path, "43000\n");
    (void)snprintf(path, sizeof(path), "%s/hwmon0/temp11_input", temporary);
    write_file(path, "70000\n");
    (void)snprintf(path, sizeof(path), "%s/hwmon1", temporary);
    if (mkdir(path, 0700) != 0) fail("cannot create HDD fixture");
    (void)snprintf(path, sizeof(path), "%s/hwmon1/name", temporary);
    write_file(path, "drivetemp\n");
    (void)snprintf(path, sizeof(path), "%s/hwmon1/temp1_input", temporary);
    write_file(path, "52000\n");
    if (setenv("UGREENCTL_THERMAL_HWMON_ROOT", temporary, 1) != 0) fail("cannot set env");
    if (ugreenctl_read_thermal_snapshot(&snapshot, error, sizeof(error)) != 0 ||
        snapshot.cpu_celsius != 43 || snapshot.cpu_peak_celsius != 70 ||
        snapshot.hdd_celsius != 52 || snapshot.ssd_celsius != -1) {
        fail("thermal snapshot did not classify hwmon sensors");
    }
    smart_data[2] = 190;
    smart_data[7] = 42;
    smart_data[14] = 194;
    smart_data[19] = 47;
    if (ugreenctl_parse_ata_smart_temperature(smart_data, sizeof(smart_data),
                                               &smart_temperature) != 0 ||
        smart_temperature != 47) {
        fail("ATA SMART parser did not prefer Temperature_Celsius");
    }
    memset(smart_data, 0, sizeof(smart_data));
    smart_data[2] = 190;
    smart_data[7] = 42;
    if (ugreenctl_parse_ata_smart_temperature(smart_data, sizeof(smart_data),
                                               &smart_temperature) != 0 ||
        smart_temperature != 42) {
        fail("ATA SMART parser did not use Airflow_Temperature fallback");
    }
    ugreenctl_fan_curve_config_defaults(&config);
    if (ugreenctl_fan_curve_evaluate(&config, &snapshot, &pwm, error, sizeof(error)) != 0 ||
        pwm != 158) {
        fail("fan curve did not use the hottest source");
    }
    (void)snprintf(path, sizeof(path), "%s/stock.conf", temporary);
    write_file(path, "profile=stock-4800\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0) {
        fail("cannot load DXP4800 stock profile");
    }
    snapshot = (struct ugreenctl_thermal_snapshot){
        .cpu_celsius = 70, .hdd_celsius = -1, .ssd_celsius = -1, .cpu_peak_celsius = 70
    };
    if (ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 128 || plan.system_pwm != 128) {
        fail("DXP4800 stock channels did not preserve recovered points");
    }
    write_file(path, "profile=stock-4600\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0) {
        fail("cannot load DX4600 stock profile");
    }
    if (config.cpu.stop != 40 || config.cpu.start != 45 ||
        config.hdd.stop != 30 || config.hdd.start != 35 ||
        config.ssd.stop != 35 || config.ssd.start != 40 ||
        config.system_pwm.idle != 64 || config.system_pwm.mid != 152 ||
        config.system_pwm.full != 228 || config.system_pwm.maximum != 255) {
        fail("DX4600 stock profile did not apply vendor mode 2 adjustments");
    }
    snapshot = (struct ugreenctl_thermal_snapshot){
        .cpu_celsius = 70, .hdd_celsius = -1, .ssd_celsius = -1, .cpu_peak_celsius = 70
    };
    if (ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 152 || plan.system_pwm != 152) {
        fail("DX4600 stock channel did not preserve recovered effective points");
    }
    (void)snprintf(path, sizeof(path), "%s/stock.conf", temporary);
    write_file(path, "profile=stock-4800plus\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0) {
        fail("cannot load DXP4800 Plus stock profile");
    }
    snapshot = (struct ugreenctl_thermal_snapshot){
        .cpu_celsius = 65, .hdd_celsius = 42, .ssd_celsius = -1, .cpu_peak_celsius = 65
    };
    if (ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 108 || plan.system_pwm != 110) {
        fail("DXP4800 Plus stock channels did not preserve recovered points");
    }
    write_file(path, "profile=stock-480tplus\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0) {
        fail("cannot load DXP480T Plus stock profile");
    }
    snapshot = (struct ugreenctl_thermal_snapshot){
        .cpu_celsius = 80, .hdd_celsius = 70, .ssd_celsius = 50, .cpu_peak_celsius = 80
    };
    if (ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 140 || plan.system_pwm != 100) {
        fail("DXP480T Plus stock channels did not preserve recovered points");
    }
    write_file(path, "profile=stock-6800pro\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0) {
        fail("cannot load DXP6800 Pro stock profile");
    }
    snapshot = (struct ugreenctl_thermal_snapshot){
        .cpu_celsius = 46, .hdd_celsius = 39, .ssd_celsius = -1, .cpu_peak_celsius = 46
    };
    if (ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 103 || plan.system_pwm != 97) {
        fail("DXP6800 Pro stock channels did not preserve recovered points");
    }
    write_file(path, "profile=stock-6800plus\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0 ||
        ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 103 || plan.system_pwm != 97 ||
        !config.system_cpu_floor_enabled || config.system_cpu_floor_start_pwm != 125 ||
        config.system_cpu_floor_end_pwm != 220) {
        fail("DXP6800 Plus compatibility preset must retain Pro points and CPU floor");
    }
    write_file(path, "profile=stock-6800\ninterval_seconds=2\n");
    if (ugreenctl_fan_curve_load_config(path, &config, error, sizeof(error)) != 0 ||
        ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan, error, sizeof(error)) != 0 ||
        plan.cpu_pwm != 103 || plan.system_pwm != 97 ||
        !config.system_cpu_floor_enabled || config.system_cpu_floor_start_pwm != 125 ||
        config.system_cpu_floor_end_pwm != 220) {
        fail("DXP6800 compatibility preset must retain Pro points and CPU floor");
    }
    snapshot.cpu_celsius = -1;
    snapshot.cpu_peak_celsius = -1;
    if (ugreenctl_fan_curve_evaluate(&config, &snapshot, &pwm, error, sizeof(error)) != -ENODATA ||
        pwm != 255) {
        fail("missing CPU temperature did not use failsafe PWM");
    }
    (void)unsetenv("UGREENCTL_THERMAL_HWMON_ROOT");
    (void)snprintf(path, sizeof(path), "%s/hwmon0/name", temporary); (void)unlink(path);
    (void)snprintf(path, sizeof(path), "%s/hwmon0/temp10_input", temporary); (void)unlink(path);
    (void)snprintf(path, sizeof(path), "%s/hwmon0/temp11_input", temporary); (void)unlink(path);
    (void)snprintf(path, sizeof(path), "%s/hwmon1/name", temporary); (void)unlink(path);
    (void)snprintf(path, sizeof(path), "%s/hwmon1/temp1_input", temporary); (void)unlink(path);
    (void)snprintf(path, sizeof(path), "%s/hwmon0", temporary); (void)rmdir(path);
    (void)snprintf(path, sizeof(path), "%s/hwmon1", temporary); (void)rmdir(path);
    (void)snprintf(path, sizeof(path), "%s/stock.conf", temporary); (void)unlink(path);
    (void)rmdir(temporary);
    return EXIT_SUCCESS;
}
