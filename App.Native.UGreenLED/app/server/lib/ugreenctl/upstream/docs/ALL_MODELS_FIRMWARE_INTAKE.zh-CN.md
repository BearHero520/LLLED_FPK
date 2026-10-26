# 官网全机型固件输入与覆盖清单

取证日期：2026-10-16（Asia/Shanghai）。官网 NAS 下载目录共 **27 个商品机型**，其中 **25 个机型已有与官网 MD5 一致的当前固件输入**，去重后为 **4 个原包**。用户于本日明确排除 DH2100、DH2100+，当前交付范围为其余 **25 款**；两款的历史缺包记录保留，不再列入本轮待办。

本清单记录输入和来源，不能用“官网列出”或“共用固件包”代替硬件实现、协议和实机验证。发布支持状态继续以 `models/compatibility.json` 为准；结构化目录见 `models/official-products.json`。

## 官网逐项核对

| 官网 ID | 商品机型 | 当前固件 | 输入组 / 状态 |
| --- | --- | --- | --- |
| 42 | [DXP2800 GT](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D42?id=42&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 41 | [DXP4800 GT](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D41?id=41&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 38 | [DXP8800 Ultra](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D38?id=38&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 36 | [DXP6800 Ultra](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D36?id=36&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 32 | [DXP4800 Pro](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D32?id=32&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 30 | [DXP4800S](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D30?id=30&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 29 | [iDX6011 Pro](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D29?id=29&product_type=nas&type=2) | 1.20.12.0030 | idx-1.20.12 |
| 28 | [DXP6800](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D28?id=28&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 27 | [DH4300 Plus](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D27?id=27&product_type=nas&type=2) | 1.20.0.0142 | rk3588-1.20 |
| 24 | [DH2300](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D24?id=24&product_type=nas&type=2) | 1.20.0.0142 | rk3576-1.20 |
| 21 | [DX4600](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D21?id=21&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 20 | [DX4600+](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D20?id=20&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 19 | [DX4600 Pro](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D19?id=19&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 18 | [DH2600](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D18?id=18&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 17 | [DX4700+](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D17?id=17&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 16 | [DX4700](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D16?id=16&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 14 | [DXP8800 Pro](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D14?id=14&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 13 | [DXP8800 Plus](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D13?id=13&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 12 | [DXP8800](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D12?id=12&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 11 | [DXP6800 Pro](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D11?id=11&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 10 | [DXP6800 Plus](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D10?id=10&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 9 | [DXP4800 Plus](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D9?id=9&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 8 | [DXP480T Plus](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D8?id=8&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 6 | [DXP2800](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D6?id=6&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 4 | [DXP4800](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D4?id=4&product_type=nas&type=2) | 1.20.0.0142 | x86-1.20 |
| 99 | [DH2100](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D99?id=99&product_type=nas&type=2) | 未列出 | 用户排除；历史缺原厂 UGOS 包 |
| 100 | [DH2100+](https://www.ugnas.com/support/download-list/product_type%3Dnas%26id%3D100?id=100&product_type=nas&type=2) | 未列出 | 用户排除；历史缺原厂 UGOS 包 |

## 唯一原包与校验

22 个 x86 官网条目的最新包 MD5 均为 `c5358c7713ccf2811aaa7c5adcc10721`，包含 GT AMD、Ultra、DX4600 系列、DX4700 系列和 DH2600。已只读重新校验用户提供的 `E:\工作台\固件\6800plus.img`，复用其相同内容，未重复下载 22 份。

### x86-1.20（22 个官网机型）

- 原文件：`6800plus.img`，1,303,473,152 字节。
- MD5：`c5358c7713ccf2811aaa7c5adcc10721`；与对应官网页面一致。
- SHA-256：`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。
- 架构：`amd64`；容器 magic 与清单确认 GNU tar，内部逐层识别 SquashFS 和应用包。
- 临时提取：`firmware-inbox/work/dxp6800plus/`。

### rk3576-1.20（1 个官网机型）

- 原文件：`release_20260921-firmware_image-1.20.0.142-rk3576_release_arm64_6.1.27_nasync.img`，963,269,632 字节。
- MD5：`bb1023df9dc93de46f26bea857f57e3c`；与对应官网页面一致。
- SHA-256：`a3a645e4f61d3a49d69b0b2c06d61b269a776dd769aa673dedceced4a616b9d3`。
- 架构：`arm64`；容器 magic 与清单确认 GNU tar，内部逐层识别 SquashFS 和应用包。
- 临时提取：`firmware-inbox/work/almighty-all-models/packages/24/`。

### rk3588-1.20（1 个官网机型）

- 原文件：`release_20260921-firmware_image-1.20.0.142-rk3588_release_arm64_6.1.27_nasync.img`，875,359,232 字节。
- MD5：`ae6c93eca31f4e8938205b1dee87777e`；与对应官网页面一致。
- SHA-256：`837ebfe8fffa4b6221ac8aee13d4b364289eccffcc4076bed6660ee1a6cfe836`。
- 架构：`arm64`；容器 magic 与清单确认 GNU tar，内部逐层识别 SquashFS 和应用包。
- 临时提取：`firmware-inbox/work/almighty-all-models/packages/27/`。

### idx-1.20.12（1 个官网机型）

- 原文件：`release_agent_cli_20260930-firmware_image-1.20.12.30-intel_release_amd64_6.18_nasync.img`，1,298,240,512 字节。
- MD5：`780940b4a35a42288216b5b727afd71e`；与对应官网页面一致。
- SHA-256：`10edeeb661587c4cb495e078b1f3e004d6005c83e6aa7b1c05d764c57df5b50e`。
- 架构：`amd64`；容器 magic 与清单确认 GNU tar，内部逐层识别 SquashFS 和应用包。
- 临时提取：`firmware-inbox/work/almighty-all-models/packages/29/`。

新下载的三个原包保存在 `firmware-inbox/input/`，使用服务器原文件名。下载先写工作区临时文件，完成长度、官网 MD5 和 SHA-256 校验后才作为输入保留；未覆盖、修改或删除任何已有输入。用户提供的 8 个镜像均完成只读 MD5/SHA-256 核对，记录在工作区 `local-inputs.json`。

## 已交付的选择性提取

- 公共 x86 1.20 包：既有 `dxp6800plus/fw/`、`kernel/` 以及 `disk-mapping-1.20/sbin/storage_serv` 可复用；机型分支仍需逐项取证。
- DH2300：`packages/24/ug-rk3576-dh2300.dtb`，以及 `fw/` 中的路由/温控脚本、`kernel/` 中的 UGREEN 模块、`storage/sbin/storage_serv`。
- DH4300 Plus：`packages/27/ug-rk3588c-4300plus.dtb` 和对应脚本/模块/储存服务；同包另有 DH2300 **Plus** 的 DTB，不能拿它替代官网 DH2300 的 RK3576 板型。
- iDX6011 Pro：`packages/29/fw/`、`kernel/`、`storage/sbin/storage_serv`，对应 1.20.12.0030，未用通用 1.20 包代替该型号的当前版本。
- 三包的 `outer-manifest.json` 记录原始容器成员、提取文件 magic 和 SHA-256；`storage-manifest.json` 记录储存包及选取二进制。

ARM 两个包的 `storage_serv` 内容相同，SHA-256 为 `7c88375afad6c64b80eca612d1c3db137774da22b8e27514aefd9e6a499dcca8`；iDX 当前包的该程序为 `cb95cc079b7d9fcf466fc814cfbf0a4528733be1893b88c4b6f00263a0a1aaa4`。这些是静态取证输入，不代表硬件已实机验证。

两个 ARM 原包的文件名都含 `6.1.27`，但实际 `ug_kernel` 的内嵌配置和 `kernel.squashfs` 模块目录分别为 **DH2300：6.1.115+**、**DH4300 Plus：6.1.84**。两者均内建 `CONFIG_SATA_AHCI=y`、`CONFIG_AHCI_DWC=y`；不能把文件名或单个机型版本当作另一机型的实际内核。新增 `packages/{24,27}/ug_kernel`、`kernel-config.txt`、`kernel-metadata/` 和 `kernel-extra-manifest.json` 保留原始内核及取证摘要。

## 补充公开原始资料

### 官网说明书

官网下载中心说明书页直接给出下列 PDF 路径，无需请求已限流的临时固件链接接口。第 1 页指示灯表已经渲染核对：DH2300 为白色/橙色，DH4300 Plus 为白色/红色；这些是物理色调说明，本身不证明驱动数值与 GPIO 通道的对应关系。

| 机型 | 官网原始 PDF | SHA-256 |
| --- | --- | --- |
| DH2300 | [2025-10-21 说明书](https://www.ugnas.com/file/upload/2025-10/21/202510211835592504.pdf) | `36896080bc29e77eea311d90e02ca34305fdb9995df5b04729e280aaa04d26e7` |
| DH4300 Plus | [2025-05-13 说明书](https://www.ugnas.com/file/upload/2025-05/13/202505131131143507.pdf) | `8111996ee7d21a16660d92e87c3e5580805efce54b835521767b57afe12a0049` |

文件、页面快照、渲染页及摘要在工作目录 `manuals/`，`manifest.json` 记录长度和 SHA-256。

### 官方公开内核源码

[UGREEN 官方开源组织](https://github.com/ugreen-opensource)提供了与当前硬件路线相关的内核仓库。取证按精确提交固定，原始源码仅保留在忽略目录；其许可证不因本项目使用 MIT 而改变。

| 仓库及提交 | 选择性读取路径 | 用途与边界 |
| --- | --- | --- |
| `rk3576_kernel@d0bf43d155dd957944aace847dbefe821ffbefb2` | `drivers/ugreen/ug-gpio-leds.c`、`ug_sataio.c`、`ug_ata_sequancedboot.c`、DH2300 与 DHx300Plus DTS | 交叉核验 GPIO 控制、原厂 SATA 分组上电/延后注册；源码不自动证明每个发布固件行为相同 |
| `rk3588_kernel@8365d0fac1d65f6035cadab55df41202c8a87e2c` | `drivers/ugreen/ug-gpio-leds.c`、`ug_sataio.c`、`Makefile` | 与 DH4300 Plus 原厂模块交叉核验 |
| `kernel-6.12@c75c5abd60dd45f45966720293ce1ee505fb8615` | `drivers/ugreen/ug_201x.c`、`leds-sio-201x.c`、`Makefile` | 源码头明确 `For 2800gt`、控制器 `CSCS201X`；可补通用升级包缺少 `ug_201x_sio.ko` 的协议证据，仍须独立验证身份与读写接口 |

原始路径、提交、下载 URL、长度和 SHA-256 记录在 `official-source/manifest.json`。GitHub 整个 Linux 树的递归列表会截断；判断驱动是否存在时已单独读取 `drivers/ugreen` 子树，不能因为截断列表未显示而判定缺失。

## 缺项与下载边界

DH2100（官网 ID 99）、DH2100+（ID 100）页面均没有最新或历史固件条目、下载链接及 MD5，只显示 UGOS Pro 升级的通用提示。因此不能将通用 UGOS Pro x86 包当作这两款旧设备的证据。这两款已由用户排除，本轮停止寻找原包，不计完成也不阻塞其余 25 款。

旧站、官方 UGOS 客户端公开元数据和原机板级线索的检索经过及最小缺资料见 [DH2100 / DH2100+ 原厂固件检索记录](DH2100_FIRMWARE_SEARCH.zh-CN.md)。取得的客户端安装包仅保存在工作目录，不计作 NAS 固件，也不增加上述 25 款覆盖数。

公开下载 API 首次正常签发了 ARM 两款与 iDX 的三个临时链接。再次请求时返回 3103，提示频率限制并要求验证码；此后停止请求 API，没有绕过或自动处理验证码。三个下载使用此前合法取得的签名链接，CDN 正常返回 200，均完成官网 MD5 校验。

本轮只新增取证清单和临时提取物；未提交、推送，未修改 `LLLED_FPK`。固件、内核模块和其他原厂二进制保留在忽略目录，不进入仓库。构建、自动测试及各系统/机型的运行验收由功能接入阶段分别记录。

## 复现资料

工作目录 `firmware-inbox/work/almighty-all-models/` 保留 `pages/<官网ID>.html`、`catalog.json`、`local-inputs.json`、`intake-{24,27,29}.json`，以及 `intake.py`、`hash_local.py`、`download_missing.py`、`extract_selected.py`、`extract_storage.py`。

重跑取证应优先复用已校验原包和页面快照，不重复请求已限流 API；新输入必须先识别 magic，再选择提取方式。
