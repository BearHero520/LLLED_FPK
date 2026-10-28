# UGreen Control v3.0.6 硬件接入说明

原 LLLED_FPK 的 `almighty` 已合入 `main`，原仓库现直接更名为 [UGreen-Control](https://github.com/BearHero520/UGreen-Control)。提交历史、Issues、标签与 Releases 保留，后续源码维护、在线更新及应用内 README 使用当前仓库。应用标识仍为 `App.Native.UGreenLED`，现有用户可在 fnOS 应用中心覆盖升级。

## 固定的硬件载荷

上游原 `Almighty` 已合入 `main` 并删除分支。当前应用固定使用 [UGREEN-NAS-Hardware v0.3.0](https://github.com/BearHero520/UGREEN-NAS-Hardware/releases/tag/v0.3.0) 的 Linux x86_64 正式发布归档，来源提交为 [`754fdfb`](https://github.com/BearHero520/UGREEN-NAS-Hardware/tree/754fdfb29badb045d5a214fbf687fc167f8cb86f)。源码子模块固定到同一提交。归档、manifest 及 SHA256SUMS 哈希见 [scripts/hardware-release.json](../scripts/hardware-release.json)，构建直接下载固定版本并校验，不依赖开发机本地文件。

四程序与十插件均来自本次主线完整重建，整体替换旧的局部扩展载荷；旧 `dxp6800-extension-source` 快照不再随应用打包。上游仍标记 `experimental-incomplete`，应用 v3.0.6 正式发布不改变各机型的验证等级，尚无新增 NAS 实机验证。包内保留上游 manifest、当前源码与二进制哈希及完整 CTest 日志。

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
python scripts/build_fpk.py --expect-version 3.0.6
```

Windows 导入需通过 `--source-root` 指定上游仓库，以使用其隔离 QEMU 运行环境。最终 FPK 和校验文件统一放到 `E:/工作台/LLLED_FPK/dist/`；CI 临时测试可使用 runner 的临时目录。发布附带固定文件名、版本文件名及版本文件的 SHA-256。
