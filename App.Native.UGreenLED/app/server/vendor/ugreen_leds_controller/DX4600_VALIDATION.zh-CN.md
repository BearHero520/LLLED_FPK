# DX4600 已实测灯控基准

取证输入 E:\工作台\固件\4600.img：
1,277,740,032 bytes；SHA-256 `f36ac819032fa98d7cbf058bed95959860ef95873ac10fe0141417a7e014758f`。
UGOS Pro 1.19.1.0126，构建 20260824.162341，内核 6.18.15。
临时反汇编在上游工作区 firmware-inbox/work/dx4600-dh2600-f36ac819/analysis，
仅作为取证材料；LED 实现始终只在本仓库内置 ugreen_leds_cli 的源码补丁内。

## DX4600

新 leds-mcu-28a48.ko SHA-256：
`ddbbf9d606d27eea79d66dedd4580414e14874416a893a1fca8f9c386d8009ba`。
init 从适配器 0..14 按编号扫描 SMBus/Synopsys，读取 WORD 0x5a=0xc5b2；
失败最多 3 次、间隔 100ms。read_state 在 0x81+ID 读取 11 字节并校验非零和。
color_set `.text+0x1a70` 的块写仍是 command=LED ID、12 字节 payload，重复
LED ID，校验和不包含 ID。ACK 0x80=1 才成功，重试间隔 30ms。

主线旧 CLI 只打开第一个 I801，未验证 MCU 身份。本轮补丁为精确 DX4600 /
DX4600+ / DX4600 Pro 恢复有签名验证的候选扫描、30ms 重试，并给全部 CLI
硬件入口加进程锁。保留原厂 I2C-block 帧和严格 ACK；不会将 ioctl 成功冒充
灯光成功，也不将全零状态帧当作有效回读。

参考 temp/dx4600-v2.0.39 的试验记录：曾出现芯片 ID 稳定但 ACK 与块状态持续
全零。该记录不能证明换驱动或改 PMIO 已修好；本轮未引入驱动替换、启动参数、
直接端口试验或诊断时闪灯。新固件也仍使用同一块协议。该历史记录不再代表当前
实测结论；当前版本的 DX4600 控制已由用户实测确认，基准见下节。

### DX4600 已实测基准（2026-09-19 确认）

用户明确确认颜色切换、开灯和关灯可用，应保留当前控制实现。依据为用户实测反馈、
`ugreen-led-application-2026-09-17T13-35-18-645Z.log` 和
`ugreen-led-diagnostics-20260918-205146.txt`。原始日志保留在用户侧，此处只记录必要证据。

- 实测应用版本：2.1.2；机器：DX4600；内核：6.18.18.c1032-trim。
- CLI 版本：`ugreen_leds_cli 1e881da+llled-firmware-1.19`。
- 实测 CLI SHA-256：`bfce4bfa9f4f819699e589292cd2287fae66cd0fcf4ef49268fcf7f9535f30c4`。
  2026-09-19 核对仓库 `app/server/bin/ugreen_leds_cli` 及配套校验文件，均与实测指纹一致。
  最初记录基准时工作区 manifest 为 2.1.3，这不代表该整包已经实测。
- 对应本地 `patches/dx4600-dh2600-firmware-1.19.patch` SHA-256：
  `774bc79e71315a806f10f38edc144fd1931c164f88e31aae693d4ee5a5fd2eef`。
- 诊断选中 SMBus I801 `/dev/i2c-1`、地址 `0x3a`、`legacy` 协议；
  `controller_start=ok`、`power_status_read=ok`、`power_mode=1`、
  `power_brightness=28`、`ack_read=ok`、`ack_value=0x01`。

保留基准包括：内置 CLI 单一硬件入口、MCU 签名校验、现有总线候选选择、
legacy I2C-block 帧、DX4600 重试时序和进程锁。不能因日志报错而回退已实测的控制路径。
总线编号是这台机器的观测值，不能据此硬编码所有 DX4600 都使用 `/dev/i2c-1`。

剩余问题单独跟踪：部分写灯命令 ACK 为 `0x00`、历史超时/锁竞争、候选总线探测时
DesignWare 仲裁报错。它们不否定用户已验证的控制能力，也不等于每条命令都成功。
后续若优化扫描、确认时序或重试，须保留本基准，并再次实测颜色切换、开关灯及原有
灯位映射；不得把 ACK 为零无条件改成成功。本次实测不扩展为 DH2600 或其他机型已验证。

## 主线整理

原始实测二进制与混合源码已保存在本地保留分支和仓库外备份中。主线补丁为
`patches/dx4600-firmware-1.19.patch`，仅移除 DH2600 的入口及专用源码，
保留 DX4600 的总线选择、签名、帧格式、重试间隔和锁。重新构建后校验值会改变，
不能将新文件指纹冒充原始实测指纹。DH2600 另存独立分支。

拆分后主线 CLI SHA-256：`21024c2b98662cb4a6cf7c58877f9c1be76515e275416c005cca9f8980a9ee86`。已通过固定上游补丁重放、Linux 编译、
隔离 Linux 环境的 `--version` / `--help` 启动检查。未新增实机写入测试。
