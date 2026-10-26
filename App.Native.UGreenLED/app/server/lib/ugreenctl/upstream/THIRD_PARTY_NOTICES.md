# Third-party notices

The legacy LED wire protocol and command-line compatibility behavior are based on
[miskcoo/ugreen_leds_controller](https://github.com/miskcoo/ugreen_leds_controller),
MIT license, copyright (c) 2024 miskcoo@gmail.com. The full license is preserved in
[led/LICENSE.upstream-led](led/LICENSE.upstream-led) and installed with the documentation.
The implementation is C and does not run or bundle the old CLI binary or kernel module.

Reference source commit: `f0fcd8192abdd92244aba9f6f0d10572f5561380`.
The upstream physical slot reports used by the new sysfs implementation, their
limitations, calibration instructions and attribution are in
[disk/NOTICE.md](disk/NOTICE.md).

Linux I2C userspace API documentation:
<https://www.kernel.org/doc/html/latest/i2c/dev-interface.html>.
No Linux kernel or systemd implementation source is copied into this project.
