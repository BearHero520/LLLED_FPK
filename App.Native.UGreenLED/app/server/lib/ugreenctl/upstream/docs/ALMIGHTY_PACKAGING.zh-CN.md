# 主分支本地打包（沿用 Almighty 格式）

`Almighty` 已合入 `main` 并删除分支。当前正式发布为 `v0.3.0`，归档沿用
`ugreenctl-almighty` 命名，manifest 来源分支为 `main`；历史归档保持原字节。

`scripts/package-almighty.py` 使用 Python 3.10+ 标准库，将两个 Linux Release 构建目录
整理为 x86_64 / aarch64 本地归档。脚本不安装、启动服务、修改系统或发布文件。

默认要求 `verification-root.json` 的 `complete` 为布尔值 `true`，且当前兼容目录标记整合完成。
当前尚有物理 M.2 等缺口，默认完整交付门槛继续拒绝。显式 `--preview` 生成预览包；
按用户正式发布要求使用 `--release` 生成无 `-preview` 后缀的正式渠道包。两个渠道
均保留 `experimental-incomplete`、未完成机型与实际验证记录，所有哈希、ELF、
测试与载荷校验一致。正式渠道不等于硬件能力全部验证。

```sh
python scripts/package-almighty.py \
  --x86_64-build /path/to/build-x86_64 \
  --aarch64-build /path/to/build-aarch64 \
  --verification /path/to/verification-root.json \
  --preview --check-only
```

检查通过后去掉 `--check-only` 生成归档；可用 `--source-root` 指定仓库位置，
`--output` 指定一个新的输出目录。默认输出在仓库的
`firmware-inbox/work/almighty-packages/`，不写 `dist/`，不覆盖既有文件。
校验失败时不会降低要求，`--preview` 只放宽“整体完成”的门槛。

每个架构包含四个程序 `ugreenctl`、`ugreen_leds_cli`、`ugreenctl-fand`、`ugreenctl-ledd`，
十个模型插件，以及显式白名单中的许可证、官方机型目录、兼容状态、证据文档、服务示例和
只读采集器。不会递归打包工作目录、原厂镜像、原厂模块或提取文件。
`ugreen_leds_cli` 是可选兼容名称，安装前由管理员处理现有同名程序；服务只作为示例保存。

构建配置必须使用 Linux 绝对安装前缀，例如 `-DCMAKE_INSTALL_PREFIX=/usr/local`
及 `-DCMAKE_INSTALL_LIBDIR=lib`。程序中嵌入的默认插件路径也必须与该前缀一致；只修改 cache
而不重建不能通过检查。归档中的文件保存对应的 `usr/local/bin/`、
`usr/local/lib/ugreenctl/models/` 和文档目录层次。使用其他前缀时，服务示例的绝对命令路径
需要管理员相应调整，打包器不会修改经过校验的源文件。

`verification-root.json` 必须包含：

- `complete`、`target_count: 25`、`excluded_by_user: ["DH2100", "DH2100+"]`。
- `source_sha256`：仓库相对路径到 SHA-256 的对象；覆盖 `CMakeLists.txt`、全部生产及测试
  `.c/.h`、打包器自身、所有入包文档/目录/许可/服务/采集脚本。已有条目也全部重新核验。
- `binary_sha256`：仓库相对路径或本机绝对路径到 SHA-256 的对象；两个架构的四程序和
  十插件均须覆盖。报告中其他二进制条目同样不能陈旧。
- `full_suite.x86_64` / `.aarch64`：严格的计数字符串，例如 `"24/24 passed"`，或
  `{"status":"passed","passed":24,"total":24,"failed":0,"skipped":0,"not_run":0}`。
  数量必须等于相应构建的 CTest 配置数量，且不少于 23；完整测试之后的修改仍由集成者
  负责重建并执行相应回归，不能把增量日志当成完整测试。
- `full_suite_artifacts.x86_64` / `.aarch64`：`{"path":"firmware-inbox/work/...log","sha256":"..."}`。
  两份独立完整 CTest 纯文本日志需 SHA 匹配、全部配置测试逐一 Passed 且完整成功统计一致；
  打包器不使用可能被增量回归覆盖的 `LastTest.log`。两份明确日志随包留证，不递归复制提取目录。

未显式选择 `--preview` 或 `--release` 的完整本地交付还要求每个目标的 LED、SATA/NVMe 状态均为明确完成值，`remaining` 为空，
且未知 M.2 清单为空；单独改动全局 `complete` 不能把现有缺口包装为完整交付。

此外校验 ELF64/小端及正确架构，插件必须为 `ET_DYN`，十插件集合必须完整且无额外模块。
打包器还从 ELF 的 program/dynamic headers 和 GNU version requirements 读取每个载荷的
解释器、`DT_NEEDED`、依赖符号版本及 RPATH/RUNPATH，写入 manifest 的 `runtime_abi`。
它使用文件支持的 `PT_LOAD` 区间核对地址和 `PT_DYNAMIC` 映射，不运行载荷或调用 `ldd`，
也不依赖 section headers。格式依据见 [ELF program headers](https://gabi.xinuos.com/elf/07-pheader.html)、
[ELF dynamic linking](https://gabi.xinuos.com/elf/08-dynamic.html) 与
[glibc ELF 定义](https://github.com/bminor/glibc/blob/master/elf/elf.h)。
`glibc_symbol_floor` 只表示数值符号需求下限；非数值 `GLIBC_*` 约束另列，不能把一个数字当作
发行版兼容证明。当前产品为动态 glibc，完整产品下限 2.27，库与加载器不随包分发；
目标系统的检查及部署限制见 [Linux NAS 部署](LINUX_DEPLOYMENT.zh-CN.md)。
目录交叉核对要求官方条目 27、当前目标 25、排除 2；LED profile 26，其中 DXP2800 两个
独立修订，其余目标各一个。profile 数量与插件数量含义不同。

输出是两份 `.tar.gz`、各自 `.manifest.json` 和 `SHA256SUMS`。归档内也包含相同 manifest
和验证报告；manifest 列出每个载荷的 SHA-256、权限、兼容状态及实机验证范围。
相同输入具有固定时间戳和属主，可复现生成。检查归档完整性可运行：

```sh
cd /path/to/output
sha256sum -c SHA256SUMS
tar -tzf ugreenctl-almighty-0.3.0-linux-x86_64.tar.gz
```

打包器静态校验不代替集成者从实际归档目录运行只读插件加载检查：
`ugreenctl --plugin-dir /path/to/extracted/usr/local/lib/ugreenctl/models models`。
两架构都应成功列出十个插件，不能出现加载失败或跳过警告。

运行 `python tests/test_package_runtime.py` 可独立检查 ABI 解析回归。有 Python 3.10+ 时，
CMake 也将其登记为 `package-runtime` CTest；它只解析合成 ELF，不执行其中内容。
完整测试数量应以当前构建的 CTest 配置为准，不能沿用旧日志中的数量。
