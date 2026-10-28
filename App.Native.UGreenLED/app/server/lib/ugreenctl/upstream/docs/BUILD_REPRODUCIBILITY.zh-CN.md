# 构建与验证复现

Linux 原生构建需要的项目源码、头文件、机型目录、CTest 和打包器均在 Git 中。
普通构建不需要原厂固件、提取物或 `firmware-inbox/work/` 中的历史文件。
Windows 的 Linux 交叉构建与 QEMU 验证是另一条可选路径；第三方工具及运行库由使用者提供，
仓库只保存自编工具链、runner 和输入元数据，不下载或捆绑这些二进制。

## Linux 原生构建

需要 Linux x86/x86_64 或 ARM64、C11 编译器与系统开发头文件、CMake 3.20+、Make/Ninja。
安装 Python 3.10+ 可同时执行三个打包器测试，打包器本身也要求该版本。

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/ugreenctl --plugin-dir ./build/models models
```

ARM64 使用 `superio/it86x_unavailable.c`，构建通过不增加 x86 端口 I/O 能力。
本机编译产生的 glibc 符号需求取决于构建系统；部署指南中的 `GLIBC_2.27` 是已检查交叉构建
产物的要求，不能直接用于任意本机构建。运行前按 [Linux 部署说明](LINUX_DEPLOYMENT.zh-CN.md)
核对实际 ELF 与目标系统。

CTest 数量来自当前配置。原有编译测试共 23 项；历史配置加一个 `package-runtime` 后为 24 项；
加入 `package-policy` 后为25项，再加入 `startup-state` 后有 Python 时为26项，无 Python 时仍为23项。
后续功能新增测试会继续改变数量，使用 `ctest --test-dir <build> -N` 获取实际清单，
不能把历史 `24/24` 写入新报告。两个打包 Python 测试仅在宿主解析合成 ELF，不执行合成内容；`startup-state` 以模拟后端测试保存/恢复协调，不调用真实硬件：

```sh
python tests/test_package_runtime.py
python tests/test_package_almighty.py
python tests/test_startup_state.py
```

`package-policy` 在临时合成目录核验哈希、ELF 架构/类型、插件集合、安装路径、完整 CTest 日志、
未完成发布门槛和归档确定性。合成完成状态只用于测试；真实兼容目录未因此完成。
其中另有 DXP2800 GT `unknown-bios-routing` SATA 状态的拒绝用例。

## Windows 交叉工具链

使用外部 Python 3.10+、CMake 3.20+、Ninja 和 Zig 0.15.2。
自编工具链位于 `tools/toolchains/zig-linux.cmake`，目标为 `x86_64-linux-gnu` 或
`aarch64-linux-gnu`。`UGREENCTL_ZIG` 必须指向外部 `zig.exe`，并在配置及构建期间保持设置。
以下在仓库根目录的 PowerShell 中执行；工具应已安装并加入 PATH：

```powershell
$repo = (Get-Location).Path
$python = (Get-Command python).Source
$env:UGREENCTL_ZIG = (Get-Command zig).Source
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$runtime = (Resolve-Path 'firmware-inbox/work/almighty-tools').Path

foreach ($arch in @('x86_64', 'aarch64')) {
  $build = "firmware-inbox/work/reproduce-$arch"
  cmake -S . -B $build -G Ninja `
    "-DCMAKE_TOOLCHAIN_FILE=$repo/tools/toolchains/zig-linux.cmake" `
    "-DUGREENCTL_TARGET_ARCH=$arch" `
    '-DCMAKE_BUILD_TYPE=Release' '-DCMAKE_INSTALL_PREFIX=/usr/local' `
    '-DCMAKE_INSTALL_LIBDIR=lib' `
    "-DCMAKE_CROSSCOMPILING_EMULATOR=$python;$repo/tools/testing/run_linux.py;--runtime-root;$runtime"
  if ($LASTEXITCODE -ne 0) { throw 'Configure failed' }
  cmake --build $build --parallel 2
  if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
  ctest --test-dir $build --output-on-failure --output-log "$build-full.log"
  if ($LASTEXITCODE -ne 0) { throw 'CTest failed' }
}
```

已有构建目录若使用旧工具链，应为上述配置选择新目录。工具链不修改 PATH，也不自动获取工具。
当前主线在 Python 可用时配置 33 项 CTest；以实际 `ctest -N` 为准。
构建四个程序和十个插件仅需要编译工具；执行编译出的 CTest 才需要下面的外部 QEMU 运行环境。

## 外部 QEMU 运行环境

`tools/testing/run_linux.py` 要求显式 `--runtime-root <目录>`，或环境变量
`UGREENCTL_TEST_RUNTIME_ROOT`；没有隐含的作者绝对路径或自带运行库。目录结构为：

```text
<runtime-root>/
  qemu/                     完整外部 QEMU 分发目录，包含 DLL 与 share/
  rootfs.tar.gz             x86_64 Alpine 3.22.2 musl 基础系统
  vmlinuz-virt              x86_64 Linux 内核
  libc-deb/data.tar         amd64 Debian libc6 的 data.tar.xz 解压结果
  arm64/
    rootfs.tar.gz           aarch64 Alpine 3.22.2 musl 基础系统
    vmlinuz-virt            aarch64 Linux 内核
    libc-data.tar           arm64 Debian libc6 的 data.tar.xz 解压结果
```

[external-runtime.example.json](../tools/testing/external-runtime.example.json) 保存本地已用输入的
来源 URL、大小和 SHA-256，包括 Zig、QEMU 分发包/两枚执行程序、两个基础系统/内核，以及
`libc6 2.41-12+deb13u4` 两个架构的 `.deb` 与解压 tar。原始来源记录不足而重建的 URL 已明确
注明；这些是本地身份记录，不代表本次重新下载或上游真实性认证。内核 netboot URL 会更新，
不能用新下载内容冒充同一哈希。QEMU 还需要分发包内的依赖 DLL、BIOS 和 `share/`，
只复制两枚执行程序不足以运行。

原始第三方包放在使用者选择的外部目录，或被忽略的 `firmware-inbox/input/`、`work/`。
校验可使用 `Get-FileHash -Algorithm SHA256 <文件>`。Debian tar 应从对应原始 `.deb` 的
`data.tar.xz` 解压，不复制宿主机 libc。例如在 PowerShell 中用 Python 处理二进制输出，
避免旧版 PowerShell 将原始字节转成文本：

```powershell
python -c "import lzma,pathlib,subprocess,sys; data=subprocess.check_output([sys.argv[1],'ar','p',sys.argv[2],'data.tar.xz']); pathlib.Path(sys.argv[3]).write_bytes(lzma.decompress(data))" `
  $env:UGREENCTL_ZIG /path/to/libc6.deb /path/to/data.tar
```

准备好运行环境后，可单独执行一个已构建测试：

```powershell
python tools/testing/run_linux.py --runtime-root $runtime `
  firmware-inbox/work/reproduce-x86_64/test-identity
```

runner 在一次性 RAM initramfs 中执行目标，参数固定为 `-nic none`，没有宿主挂载、磁盘驱动器
或硬件直通。只把测试、同目录模型插件和外部基础系统/运行库写入临时镜像。
QEMU 必须正常退出，且串口中必须有唯一完整的开始/退出标记；超时返回 124，
基础设施或标记错误返回 125，正常时返回 VM 内测试退出码。
`UGREENCTL_TEST_VM_DMI` 仅用于隔离 x86 VM 的合成 DMI，不能作为产品硬件写入开关。
Windows QEMU 的 BIOS/内核路径相对于显式运行目录传入，以兼容包含中文的宿主目录。

该 CTest 环境覆盖软件行为与合成设备，不是 NAS 实机、真实硬件写入或完整发行版验证。
Debian 12 / Ubuntu 22.04 的独立运行库烟测使用不同原包和专用历史 harness，
其限定范围及输入哈希保留在部署指南；不能把上述 Debian 13 CTest 环境冒充该烟测。

## 打包证据

完整 Release 构建和当前全套测试完成后，按 [Almighty 打包说明](ALMIGHTY_PACKAGING.zh-CN.md)
提供当前 `verification-root.json`。其源码/二进制哈希必须来自当前文件，计数和逐项结果必须来自
本次两份独立完整 CTest 日志；不能直接复制历史 checkpoint 或只修改成功数字。
打包器会检查全部必需输入、两份日志及其 SHA-256。当前兼容目录仍有未完成项时，
须显式选择 `--preview` 预览渠道，或按正式发布请求选择 `--release`。正式渠道仍保留
未完成硬件状态；测试成功不改变机型验证等级或默认完整交付门槛。

```sh
python scripts/package-almighty.py \
  --x86_64-build firmware-inbox/work/reproduce-x86_64 \
  --aarch64-build firmware-inbox/work/reproduce-aarch64 \
  --verification firmware-inbox/work/current-verification.json \
  --preview --check-only
```

归档和验证报告保存在忽略的工作目录；仓库不提交原厂输入、提取二进制或反汇编。
