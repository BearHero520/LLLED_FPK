# DH2600 / DXP480T Plus 灯光只读采集

`scripts/collect-led-evidence.sh` 收集这两款 N76 机型的最小环境证据，帮助确认原厂驱动是否存在、实际绑定到哪里、哪些公开属性可读。它不会使未知寄存器自动变成可安全控制的接口。

## 运行

在设备上的仓库目录执行：

```sh
sh scripts/collect-led-evidence.sh --help
sh scripts/collect-led-evidence.sh > led-evidence.txt
```

脚本只接受 Linux 真实 DMI 的精确 `DH2600` 或 `DXP480T Plus`，没有机型、sysfs 路径或环境变量替换入口。通常无需 root；不可读属性标记为 `<unavailable>` 或 `<read-failed>`，不会自动提权。若需要补全权限受限的元信息，可以自行用 `sudo sh` 再运行。报告仅输出到标准输出，文件由上面的重定向创建，不会自动上传。分享前可自行检查文本。

退出码：`0` 表示已生成报告，缺失属性仍会注明；`2` 表示参数错误；`3` 表示非 Linux、DMI 不可读或不在这两款机型中。报告成功不等于灯光能力验证成功。

## 读取范围与含义

| 内容 | 来源 | 能说明什么 |
| --- | --- | --- |
| 型号、产品/主板/BIOS 版本及厂商 | 固定 DMI 字段白名单 | 设备身份及版本；不读取 serial/UUID |
| 内核版本与架构 | `uname -r`、`uname -m` | 当前内核环境；不读取 hostname |
| 相关 module 名、版本、srcversion、initstate | `/sys/module/` | 已加载或内建模块的存在及元信息；内建模块可没有 initstate |
| I2C 适配器名称、已存在 client 的 driver/module 链接 | sysfs 元信息 | 已建立的适配器与绑定关系；不枚举地址、不读取设备内容 |
| `max_brightness`、`trigger` | 固定 LED class 节点 | 声明范围与缓存的 trigger 配置；方括号标记 active trigger |
| `brightness`、`rbrightness`、`color`、`delay_on/off` | 已核对 N76 绑定后的公开属性 | 驱动/LED core 缓存的配置，不能当作当前物理输出回读 |
| `mode` | 已核对 N76 绑定后的原厂 getter | 已证实的 `0x50/0x51 + led_bit` 模式寄存器读取，不能证明当前开关、颜色、强度或完整时序 |

DXP480T Plus 只检查 `power`，不把四个 NVMe 插槽当作四个盘灯。DH2600 检查 `power`、`disk1`、`disk2`。自定义属性读取要求 LED 节点位于真实 `/sys/devices/`，driver 精确为 `mcu_led`，module 分别为 `leds_mcu_n76e003` 或 `leds_mcu_n76e003_dh2600`。不匹配时只列出属性是否存在及标准元信息，跳过 `mode` 和自定义缓存 getter。名称绑定一致不替代模块字节校验或实机协议验证。

这不是“零总线事务”采集：读取原厂 `mode` 会由已绑定的驱动执行上述已知 I2C 读。脚本不直接调用 SMBus、`i2cdetect`、`i2cget`、`i2cdump`、端口工具或设备探测，不读取 `version` getter，不访问未知寄存器。

脚本不写 sysfs、不改变 trigger/亮度/颜色、不启动灯效或 holder、不加载卸载模块、不读磁盘、不读取网络 MAC/IP、主板序列号、UUID、hostname、进程命令行或日志，也不上传。它不需要停止现有灯光服务；服务持续改变配置时，不同字段可能来自不同时间，报告不构成原子快照。

## 后续判断

`color`、`rbrightness` 读到的值来自缓存；`mode=steady` 也不能区分 steady 下当前灯是否关闭。即使读到了芯片标识、ACK、非零 mode 或全零数据，也不能由此证明 `A0/B1/E0/E1` 等目标字段具有可靠读回能力，不能据此开放无原厂驱动的裸 I2C 写入。

下一步需要官方 MCU 协议/MCU 程序中明确的状态读取定义，或另行设计、限定机型与版本并记录已知灯态的实机实验。当前脚本不执行这类实验。已恢复寄存器及原包/模块 SHA-256 记录见 [N76 证据与限制](ALL_MODELS_LED_EVIDENCE.zh-CN.md)。

采集脚本验证使用隔离 QEMU 的临时系统：检查 shell 语法、help/参数错误、非 Linux 分支、非目标机型拒绝，以及真实模拟 DMI 分别为两款目标时的无驱动报告行为，运行时将 sysfs 挂为只读。另用临时 sysfs fixture 验证绑定匹配后的缓存/mode 标签；绑定不匹配时把自定义属性替换为无写入端 FIFO，确认脚本不会读取它们。fixture 的 mode 是测试文本，不是硬件读回。测试不访问宿主硬件；不是两款实体 NAS 的灯光验证，也不改变现有支持状态。未修改原始固件或 `LLLED_FPK`。
