#include "superio/it86x.h"
#include <errno.h>
#include <stdio.h>
#include <string.h>

/* Non-x86 machines cannot access this x86 Super I/O transport. No caller may
 * read/write registers after open fails; the inert symbols keep shared code
 * linkable without pretending that a hardware transaction succeeded. */
int it86x_open(struct it86x_device *device, char *error, size_t size)
{
    if (device) { memset(device, 0, sizeof(*device)); device->lock_fd = -1; }
    if (error && size) (void)snprintf(error, size, "x86 Super I/O port access is unavailable on this architecture");
    return -ENOTSUP;
}
void it86x_close(struct it86x_device *device) { (void)device; }
uint8_t it86x_hwm_read(uint8_t reg) { (void)reg; return 0xff; }
void it86x_hwm_write(uint8_t reg, uint8_t value) { (void)reg; (void)value; }
uint8_t it86x_sio_read(uint8_t reg) { (void)reg; return 0xff; }
void it86x_sio_write(uint8_t reg, uint8_t value) { (void)reg; (void)value; }
