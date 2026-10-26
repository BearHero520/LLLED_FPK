# Almighty 发布版接入

应用分支为 `almighty`。当前固定使用发布版
[almighty-preview-20261026-923fdaa](https://github.com/BearHero520/UGREEN-NAS-Hardware-Almighty/releases/tag/almighty-preview-20261026-923fdaa)，
源码提交 `923fdaa26a72041f34cf211ae319377bfd52be53`，与相邻
`E:\工作台\UGREEN-NAS-Hardware` 的源码一致。此版是实验性预览，未在 NAS 实机验证。

## 载荷与边界

- 四个 Linux x86_64 程序全部来自同一发布包：`ugreenctl`、`ugreenctl-fand`、`ugreen_leds_cli`、`ugreenctl-ledd`。
- 九个 BIOS 模型插件及上游文档、许可证、示例随包导入。插件存在不代表该型号支持全部 BIOS 写入功能。
- BIOS、风扇、来电恢复仅由 `ugreenctl` 实现硬件访问；LED 只调用 `server/bin/ugreen_leds_cli`。
- `ugreenctl-ledd` 是特定 GPIO 机型的资源持有服务，不是应用灯光策略守护进程。已随包提供，但不自动启用或接管硬件；DXP2800 GT 等机型仍需按上游文档配置资源持有服务。
- 应用的 `led_daemon.sh` 继续处理网络、硬盘活动和用户设置，硬件操作统一走新版 CLI。启动恢复沿用现有应用适配，未重复启用上游示例服务。
- 上游运行时最低 glibc 为 2.27；本应用 manifest 当前为 x86 平台，未混入 aarch64 载荷。

新版兼容 CLI 写入必须显式带 `--force --apply`；读取只用 `-status`。
机型探测、协议、锁及硬件读回由上游负责，不再传旧的手动 I²C 协议覆盖。
iDX6011 Pro 直接使用上游 `netdev2`、`disk1` 等名字，不再重复偏移。
DXP480T 的 N76 后端依赖厂商驱动；兼容入口支持开关、快慢闪烁，保留当前颜色。
选色与呼吸请求会拒绝，界面已移除这些不支持的选项。旧呼吸设置恢复为常亮。

## 导入与校验

`scripts/hardware-release.json` 固定仓库、标签、源码提交、压缩包、发布清单和 SHA256SUMS 的哈希。
导入器验证全部发布清单文件、ELF 架构及必需文件，再运行不触及硬件的 CLI 和九插件加载检查。
通过后才替换载荷，最后写 `lib/ugreenctl/build-info.json`。
发布清单保存在 `lib/ugreenctl/release-manifest.json`，文档在 `lib/ugreenctl/upstream/`。

```powershell
python scripts/build_ugreenctl.py
# 已下载发布资产时：
python scripts/build_ugreenctl.py --asset-dir .work-almighty-release/923fdaa
```

Windows 默认使用相邻源码仓库的隔离 QEMU runner 和
`firmware-inbox/work/almighty-tools` 运行时；可用 `--runtime-root` 修改。
Linux 直接运行发布程序。`--check-only` 验证但不替换应用文件。
下载通过已认证的 `gh`；私有仓库需要读取权限。

本地打包将实际四程序与九插件的哈希逐项对照固定发布清单，拒绝旧版本混用。
远程打包使用本地已验证的载荷，不再编译旧 LED 后端。CI 同样下载固定发布包，
需要配置 `HARDWARE_READ_TOKEN`；本次未配置密钥或运行远程工作流。
最终 FPK 和校验文件由打包入口输出至 `dist/`。接入操作不自动打包、推送或发布。

## 界面

继续使用 iOS 18 半透明磨砂卡片、柔和背景、系统蓝、系统字体、圆角分组。
关于页面使用自适应排版，页面切换、按钮、开关和弹窗有动画，并尊重减少动态效果设置。
实验室入口与 API 已移除；既有自定义盘位映射保留读取兼容。

前端验证：`cd web-ui` 后运行 `npm run check`、`npm test`、`npm run build`。
本地模拟预览：`python scripts/preview_web.py --no-open --port 8086`。
