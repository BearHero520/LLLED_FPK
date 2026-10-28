# UGreen Control 迁移与主线合并

2026-10-28，配套应用从 LLLED_FPK 的 `almighty` 迁移至 [UGreen-Control/main](https://github.com/BearHero520/UGreen-Control/tree/main)。LLLED_FPK 的 `almighty` 可以并入其 `main`，并发布 v3.0.5 迁移包；应用内后续更新及 README 指向新仓库。

本仓库原分支名为 `Almighty`（区分大小写），现已合入 `main` 并删除远端与本地分支；当前独立 WOL/RTC、DXP6800 与兼容温控实现也已合入主线。当前源码、README 和使用说明以 `main` 为准。硬件能力与安全保护仍在本仓库实现，应用只提供适配、API 和 UI。此次迁移不新增硬件控制后端。

迁移时应用固定使用 `artifacts/Almighty/2026-10-28-dxp6800-wake-curve-local/` 的不可变预览包及其 SHA-256。该目录是历史固定产物，名称保留生成时的来源，不代表已经通过全部机型实测；归档内源码哈希与基包记录是其二进制来源依据，承载归档的 Git 提交不是旧包源码的统一构建版本。本次 `v0.3.0-preview.1` 为当前主线重新完整构建的独立预发布；旧固定包保持原字节，新包使用自身 manifest 与验证报告。

本次重新配置、构建并运行 Linux x86_64 隔离 QEMU 测试，33 项全部通过；未向 NAS 硬件写入，未新增实机验证。DXP6800 原厂曲线仍未知，兼容预设使用 Pro 参数。

后续按用户要求将同批已验证硬件程序与插件正式发布为 `v0.3.0`，配套 UGreen Control
固定使用正式发布包；当前入口见 [v0.3.0 说明](RELEASE_v0.3.0.zh-CN.md)。
旧预发布与迁移固定归档保留，正式分发不改变各机型实验状态。
