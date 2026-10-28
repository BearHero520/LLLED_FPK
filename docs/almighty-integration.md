# UGreen Control v3.0.5 硬件接入说明

原 LLLED_FPK 的 `almighty` 已合入 `main`，原仓库现直接更名为 [UGreen-Control](https://github.com/BearHero520/UGreen-Control)。提交历史、Issues、标签与 Releases 保留，后续源码维护、在线更新及应用内 README 使用当前仓库。应用标识仍为 `App.Native.UGreenLED`，现有用户可在 fnOS 应用中心覆盖升级。

## 固定的硬件载荷

上游 `UGREEN-NAS-Hardware/Almighty` 合入 `main`；当前应用固定使用提交 [`b6d4666`](https://github.com/BearHero520/UGREEN-NAS-Hardware/tree/b6d46660c87db1566f7c74b5abe1b37df1223f50) 中的 `artifacts/Almighty/2026-10-28-dxp6800-wake-curve-local` 预览归档。归档、manifest 及 SHA256SUMS 哈希见 [scripts/hardware-release.json](../scripts/hardware-release.json)。`git-artifact` 从不可变提交读取，构建不依赖开发机本地文件。

这是已提交的实验性预览产物，尚无新增 NAS 实机验证。归档承载提交不代表整包二进制来自同一次源码构建；基包记录和 DXP6800 扩展源码哈希保留在归档中，构建记录使用源码哈希标识扩展的实际来源。

## 载荷与边界

- 四个 Linux x86_64 程序：`ugreenctl`、`ugreenctl-fand`、`ugreen_leds_cli`、`ugreenctl-ledd`，以及十个机型插件，均经归档及逐文件 SHA-256 校验。
- BIOS、风扇、来电恢复、WOL 和 RTC 的检测、硬件访问、互斥锁与回读由上游实现；应用只提供适配、API、服务与 UI。
- LED 请求只调用 `server/bin/ugreen_leds_cli`。应用不直接写入 I2C、sysfs、Super I/O、`/dev/port` 或 MCU 寄存器，也不调用 `ugreenctl led`。
- `ugreenctl-ledd` 随包保留，不由应用自动启用。应用 `led_daemon.sh` 负责策略调度，硬件请求仍走内置 CLI。
- WOL 与 RTC 独立于风扇插件清单；物理网卡及写后回读由上游检查。未建立网口自动映射的机型需要显式选择网卡。
- DXP6800 使用独立插件，支持三路遥测、自定义曲线及 Pro 参数兼容预设；原厂 DXP6800 曲线仍未知，见 [DXP6800 接入说明](DXP6800_INTEGRATION.md)。

## 校验与打包

```bash
python scripts/build_ugreenctl.py
cd web-ui
npm ci
npm run check
npm test
npm run build
cd ..
python scripts/build_fpk.py --expect-version 3.0.5
```

Windows 导入需通过 `--source-root` 指定上游仓库，以使用其隔离 QEMU 运行环境。最终 FPK 和校验文件统一放到 `E:/工作台/LLLED_FPK/dist/`；CI 临时测试可使用 runner 的临时目录。发布附带固定文件名、版本文件名及版本文件的 SHA-256。
