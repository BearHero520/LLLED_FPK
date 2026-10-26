# DH2100 / DH2100+ 原厂固件检索记录

2026-10-16 范围更新：用户明确排除 DH2100 和 DH2100+，本记录保留为历史证据，
以下后续取证建议不再是当前定时任务的待办。未适配不能改记为已支持或硬件不适用。

记录日期：2026-10-16。目标是取得这两款旧 UGOS 设备的原厂固件或足以核验 LED 与盘位接线的板级原始资料。当前尚未取得两款原厂系统包，不能以其他机型的 UGOS Pro 包、客户端安装包或第三方 DTB 代替。

## 已走过的公开来源

| 来源 | 已确认结果 | 证据边界 |
| --- | --- | --- |
| [DH2100 官网固件页](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D99?id=99&product_type=nas&type=2) | 最新与历史固件列表均无条目、链接和 MD5 | 仅说明当前公开页面没有提供，不证明从未发布固件 |
| [DH2100+ 官网固件页](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D100?id=100&product_type=nas&type=2) | 同上；页面的 UGOS Pro 提示为通用文本 | 不把通用 x86 包套给旧 ARM 设备 |
| [官网保留的旧 DH2100 参数页](https://jxs.ugnas.com/parameter/2) | 处理器 RTD1296，ARM Cortex-A53，2 GB 内存、8 GB 闪存、两个 SATA 盘位 | 不提供 LED GPIO 或物理槽号与控制器端口接线 |
| 旧参数页指向的 `jxs.ugnas.com/support/download/2` | 当前重定向新版官网下载中心 | 未取得旧版固件目录 |
| [官网 UGOS 客户端入口](https://cloud.ugreengroup.com/download/) | 官方 JS 使用公开 GET `https://cloud.ugreengroup.com/api/system/v2/sa/apk` | 返回 Android、Windows、macOS、iOS、TV 客户端元数据，未列 NAS 固件 |
| [官方开源组织](https://github.com/ugreen-opensource) | 可继续核对内核与板级源码；当次列表含 Rockchip 与 x86 内核仓库 | 未发现即不能推定 Realtek 板型接线；需按路径、提交和内容记录 |

官网下载页快照保存在忽略目录 `firmware-inbox/work/almighty-all-models/pages/{99,100}.html`；旧站、客户端页面与接口响应保存在 `firmware-inbox/work/almighty-all-models/legacy/`。这些请求未使用登录凭据，也未对需要设备身份的升级接口伪造序列号或型号参数。

## 官方客户端取证

为核对公开的升级元数据，正常下载了官网 API 已列出的两个客户端，并与接口给出的 MD5 核对。安装包只做静态读取，没有安装或执行。这些文件保存在工作目录，不计入固件覆盖数。

| 文件 | 字节数 | MD5 | SHA-256 |
| --- | ---: | --- | --- |
| `UGREEN_Nas_V6.2.0.11458-6a6c1-win32_ia32.exe` | 83,526,048 | `bc931d316b1559ca0b757895f9a25d44` | `f892d102179927ed486bb3ca1b6f349c843691c5db8c130fc0e417d46b564fcb` |
| `NasApp_v5.2.0_f32b5d1ac_20240415_release.apk` | 157,055,384 | `70512a6d4341a411e59dfb763d40e8e5` | `40c3c7f8cc6249a0cf6390cee3563b707b98b16c20b2b5b84fd789b1ab769156` |

Windows 包为 NSIS → `app-32.7z` → Electron `resources/app.asar`；入口使用 bytenode，前端为 `render/render.ugnas`。Android 包的 DEX 可见部分为包装入口。现有静态检查未取得可直接下载旧 NAS 固件的公开链接。客户端版本号不是 NAS 固件版本号。

## 其他原始资料线索

- [原机作者的 CM316P / DH2100+ 记录](https://post.smzdm.com/p/avvovzop/)附板图，称设备使用 RTD1619B，并提供自制 `rtd1619b-cm316p.dtb` 与名为 `00boot_emmc.bind.bin` 的原厂 boot 备份线索。文章网页快照已保存；尚未取得、核验这些二进制，不能用作者描述证明生产接线或官方发布。
- [ophub/fnnas 第 635 号讨论](https://github.com/ophub/fnnas/issues/635)引用上述原机文章，没有提供独立原厂固件输入。
- [NASchecker 原始研究仓库](https://github.com/niannianwgz/NASchecker)记录其 DH2100+ 测试固件为 `V4.2.0.601`；仓库目录未列原厂镜像。该版本只作检索线索，不作为当前硬件支持证据。

原机作者链接到的百度分享被浏览器站点安全策略阻止访问，未尝试其他浏览器、代理或接口绕过。官网临时下载接口此前返回频率限制与验证码要求后，也未重复请求或自动处理验证码。上述限制与本项目自己的硬件身份检查无关。

## 后续最小输入

可继续查官方旧 UGOS 公告、公开原厂恢复包、官方开源板级文件和无需伪造身份的公开升级元数据。若公开渠道仍无可核验输入，以下任一种原始材料可推进工作：

1. 绿联官方提供、明确适用于 **DH2100** 或 **DH2100+** 的离线升级/恢复包，附原始下载页或官方提供来源、精确型号和版本；收到后先只读记录长度、magic 与 SHA-256。
2. 来自对应原机、保留来源的设备树、原厂 LED 驱动/控制程序及相关启动脚本，同时附板型/固件版本。仅有营销参数和其他设备的通用 DTB 不足以开放写入。
3. 对应原机的只读硬件识别与拓扑资料，补齐精确系统身份、LED 设备节点及 ATA 控制器与端口结构；物理槽号仍须原厂表或可核验的逐槽确认记录。

本记录不要求用户刷机、恢复出厂或修改原机启动链。未经明确授权，不联系第三方、不发送邮件或发布论坛消息。

本轮没有产品代码改动，因此没有新增构建测试结论；功能测试由当前接入阶段单独记录。未修改、删除任何原始固件输入，未修改 `LLLED_FPK`，未提交或推送。
