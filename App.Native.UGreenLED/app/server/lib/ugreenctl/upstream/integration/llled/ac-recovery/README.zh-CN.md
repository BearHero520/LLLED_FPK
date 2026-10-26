# LLLED 来电策略持久化适配补丁

本补丁只调整应用适配层及两份回归测试：成功写入后保存选择、服务启动和停止时恢复。原来两处 `dx4600` 限定改为应用已有的 `bios_supported_model` 判断，硬件访问继续完全委托 `ugreenctl`，没有应用侧寄存器或总线访问。

补丁基于 `source-hashes.json` 中列出的**修改前工作区文件**，不是整个应用仓库的 HEAD；该工作区已有其它未提交变化。实际应用前必须逐文件核对 baseline SHA-256，再执行：

```sh
git apply --check /path/to/llled-startup-persistence.patch
git apply /path/to/llled-startup-persistence.patch
```

不要用补丁去覆盖不同版本的应用文件。`modified_sha256` 是应用后的预期 SHA-256。本次工作已将这三处最小差异应用到用户本地 LLLED 工作区；没有暂存、提交、推送该应用仓库，也没有打包或发布 FPK。此处在独立私有硬件仓库保留可审查补丁，避免把应用的其他未提交内容上传。

恢复记录仍为 `精确产品名|on/off/last`，兼容已保存的 DX4600 选择。没有选择、跨精确机型、未知机型不会恢复写入；读取配置失败、无精确身份、损坏策略均拒绝。硬件写失败不保存新选择；硬件写成功但保存失败明确报错，不能宣称重启后能够恢复。

现有服务启动/停止钩子保持原样。测试覆盖十个原有精确产品名及适配层原有三种别名路由、三种策略、跨型号隔离、失败和现有 API/服务 mock。别名测试不证明底层新增 DMI 支持，实际写入仍由上游插件的精确匹配决定。历史 DX4600 实机记录不能外推到其它机型、BIOS 或 TrueNAS。

独立 Linux/TrueNAS 使用者不必依赖 FPK；见 `docs/AC_RECOVERY_PERSISTENCE.zh-CN.md` 中的协调脚本和生命周期配置说明。仅替换 `ugreenctl` 二进制不会自动安装应用适配层或服务钩子。
