# 来电策略的保存和生命周期恢复

`ugreenctl power startup set` 写入并回读当前 IT8613 寄存器，不写 BIOS NVRAM。
BIOS、服务或关机流程可能重置这些寄存器；写入成功不等于选择会跨重启或断电保留。
保存管理员的明确选择，再在服务启动和停止时通过原有受保护接口重新应用，是独立的软件协调层。

## 覆盖范围与边界

本修复用于原有来电策略后端已支持的精确机型：DX4600、DX4600+、DX4600 Pro、
DXP4800、DXP4800 Plus、DXP4800 Pro、DXP4800S、DXP480T Plus、DXP6800 Plus、DXP6800 Pro。
协调脚本不新增机型或寄存器映射，实际能力仍由已安装的 `ugreenctl` 和对应插件决定。
其余 LED/盘位档案不会因此获得来电策略能力。

所有硬件操作仍经过底层精确 DMI、芯片身份、控制器所有者、进程锁及寄存器回读。
`--force` 只表示明确接受实验写入，不能绕过这些检查；不会为恢复而自动卸载驱动。
当前值为 `unknown` 但读取成功时，允许管理员已明确选择的受保护写入恢复已知策略；
读取错误、损坏状态或不匹配身份不能用默认策略掩盖。

## LLLED 应用适配层

原应用的 `bios_set_startup_saved` 和 `bios_startup_restore` 曾只处理 `dx4600`。
这会使 DXP4800 Plus / Pro 等机型虽然写入成功，却跳过保存及启停恢复。
现改为复用已有的 `bios_supported_model`；保留现有启动/停止钩子和底层写入参数。

应用继续保存 `精确产品名|on/off/last`，兼容已有 DX4600 记录。
无保存选择、未知机型、跨精确 DMI 不恢复写入；读取配置失败、无法取得精确身份、
损坏策略均拒绝。写失败不替换旧选择，保存失败明确提示硬件已写入但下次不能保证恢复。
应用的 `last` 仍转换成上游的 `restore`。

可审查补丁、修改前/后 SHA-256 和范围说明在
[integration/llled/ac-recovery](../integration/llled/ac-recovery/README.zh-CN.md)。
它只包含应用协调层和回归测试，不复制硬件寄存器访问。仅替换 `ugreenctl` 二进制
不会把这个补丁或生命周期钩子部署到应用中。

## 独立 Linux 协调脚本

不使用 FPK 的系统可以显式调用 `scripts/ugreenctl-startup.py`。
它是可选的 Linux/Python 3.10+ 工具，默认 dry-run，不是常驻守护，也不自动安装或启用服务。
Unraid 等系统需管理员先确认 Python 依赖存在，不能假定已内置。

初次设置示例（路径须与自己的安装一致）：

```sh
sudo python3 scripts/ugreenctl-startup.py set on \
  --binary /usr/local/bin/ugreenctl \
  --plugin-dir /usr/local/lib/ugreenctl/models \
  --state-dir /var/lib/ugreenctl/startup --force --apply
```

策略为 `on`、`off`、`restore`；`last` 规范化为 `restore`。
只有同时提供 `--force --apply` 才会写入；脚本首先取得可读取的后端状态，再调用底层设置，
再次读取必须与期望一致，最后才原子保存。无上述写入标志时不调用后端、不创建状态或锁。
读取成功但值为 `unknown` 不阻止已确认身份的恢复；后置读取仍为未知或不一致则报错，
不会替换旧保存记录。输出的 `hardware_written`、`state_saved` 及错误信息区分部分完成，
不能把保存的期望值当作当前硬件读回。
底层设置命令报错或超时可能发生在部分寄存器已经写入之后；此时输出
`hardware_write_attempted=true`、`hardware_written=null`，明确结果未知，不能声称硬件未变化。

查看的是**保存的选择**，不是实时硬件状态：

```sh
sudo python3 scripts/ugreenctl-startup.py show --state-dir /var/lib/ugreenctl/startup
```

在启动或正常停止时重新应用：

```sh
sudo python3 scripts/ugreenctl-startup.py apply \
  --binary /usr/local/bin/ugreenctl \
  --plugin-dir /usr/local/lib/ugreenctl/models \
  --state-dir /var/lib/ugreenctl/startup --force --apply
```

无保存记录时返回未配置，不写硬件。状态按精确产品名、产品/主板修订和 BIOS 信息绑定；
BIOS 或身份变化后默认拒绝自动恢复，需管理员重新检查兼容性并明确执行 `set`。
这不同于旧应用记录的仅产品名绑定，也不把 BIOS 字符串一致当成兼容性证明。

状态目录及祖先必须由 root 管理、不可被其他用户写，最终状态目录私有；
脚本拒绝符号链接、非普通文件、错误所有者/权限/链接数、重复 JSON 键、未知字段、
非法策略或过大记录。进程锁串行化整个设置/保存事务；保存使用临时文件、原子替换和 fsync。
若替换成功后目录同步失败，报告持久性不确定，不能宣称事务已回滚或保存成功。

## 启动与停止入口

Debian/Ubuntu、PVE 等使用 systemd 的宿主机可审阅
`scripts/ugreenctl-startup.service` 示例，调整 Python、完整版本目录、插件和状态目录路径。
只有管理员明确设置并确认回读后再配置服务；示例不由安装脚本自动启用。
`ExecStart`、`ExecStop` 都调用上述 `apply`，不是重新猜测或保存开机时读到的默认值。

TrueNAS SCALE 使用者应将程序、插件、脚本及状态放在可执行的持久数据集，例如
`/mnt/<pool>/tools/ugreenctl/`；状态目录需 root 专有，并等待数据集挂载/解锁完成。
在平台的 `Post Init` 和 `Shutdown` 入口分别调用同一条绝对路径 `apply` 命令，
按本机运行时间配置足够超时，且在数据集或控制器访问条件撤销前完成。
不依赖手工修改 `/etc` 或 `/usr/local` 跨 TrueNAS 更新保留；不要执行通用 apt 安装流程。
平台入口的限制及官方说明见 [Linux 部署说明](LINUX_DEPLOYMENT.zh-CN.md)。

即使启停钩子成功，BIOS 仍可能在之后的关机阶段再次改写寄存器；突然断电也不会执行停止钩子。
本修复不能保证所有 BIOS 的最终断电行为，不能冒充 BIOS NVRAM 刷写或实机验收。
历史 DX4600 的用户验证不自动扩展到 DXP4800 Plus、TrueNAS 或其它版本。
当前验证结果按具体软件测试及平台边界保存在 `validation/almighty/`。
