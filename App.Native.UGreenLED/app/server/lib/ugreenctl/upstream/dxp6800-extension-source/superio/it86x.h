#ifndef UGREENCTL_IT86X_H
#define UGREENCTL_IT86X_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct it86x_device {
    bool ports_enabled;
    bool config_open;
    int lock_fd;
    uint16_t chip_id;
    uint8_t revision;
};

int it86x_open(struct it86x_device *device, char *error, size_t error_size);
void it86x_close(struct it86x_device *device);
uint8_t it86x_hwm_read(uint8_t reg);
void it86x_hwm_write(uint8_t reg, uint8_t value);
uint8_t it86x_sio_read(uint8_t reg);
void it86x_sio_write(uint8_t reg, uint8_t value);

#endif
