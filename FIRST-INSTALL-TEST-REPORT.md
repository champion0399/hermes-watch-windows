# 首次一键安装检查与测试报告

本轮仅检查、修复和测试首次安装。未检查或测试续签、升级；manage.sh 及 GUI 中原 Invoke-WslAction 函数保持原样。

## 已修复的问题

| 问题 | 修复 |
|---|---|
| 原 xtool 补丁为 UTF-16LE，首次 git apply 失败 | 转为 UTF-8 无 BOM、LF |
| 原补丁漏掉 2 个新增 Swift 文件及 73 个本地 zsign 文件 | 补齐全部新增生产源码、Package.swift 和许可声明 |
| 默认 App Group 使用系统用户名，长度经常不是 22 字符，且不同用户可能撞名 | 随机生成 22 字符 ASCII 标识并持久化，通过环境变量传给签名工具 |
| native 依赖构建禁用了工具、未设置 prefix/bin；set -u 局部变量提前引用 | 恢复工具构建、修复 PATH、分开变量声明并验证产物 |
| 已有 Swift 安装被重复下载 | 先设置路径再验证确切版本；新下载校验官方 GPG 签名 |
| Apple ID 登录命令及状态判断不准确 | 使用 auth login，检查 Logged in.；保留终端输入 |
| curl 管道与交互输入混用 | 独立终端文件描述符处理确认、登录和设备交互 |
| 空设备列表、多个手机、下载 HTML/半包仍往后执行 | 增加退出码、非空、HTTP、IPA 结构、大小、可用 SHA-256 校验 |
| IPA App Group 标记变化或替换为零仍显示正常 | 检查 Watch 可执行文件，发现上游结构或标记变化就停止 |
| 解包后选中 iPhone 的 HermesCompanion.app | 从 Info.plist 校验唯一嵌入的 watchOS App，并返回绝对路径 |
| 每次共用 watch-info.json 导致独占创建冲突 | 首次安装使用每次独立的临时目录 |
| 首次 WSL 用户检测引用错误、删除或覆盖现有 wsl.conf、错误 shutdown 参数 | Base64 传输 Bash 内容，显式选择用户，保留现有 WSL 配置及其他发行版 |
| WSL 尚未安装时枚举报错，阻断安装 | 记录枚举错误，尝试受检查的 wsl --install，处理需重启状态 |
| GUI 下载失败后继续运行、终端未结束就显示完成 | 下载验证后原子替换；等待真实退出码，只有 exit 0 才显示完成 |
| 旧脚本缓存导致 EXE 实际运行内容与源码不一致 | 新测试 EXE 内嵌首次安装脚本、runtime、patch 和连接助手 |
| 无法分辨打开的是哪一版程序 | 窗口标题显示 v1.2.0 |
| 空白电脑缺少手工设置的 WSL→Windows usbmux 转发 | 先检测 gateway/localhost；确有需要时创建仅绑定本机 WSL 网关、仅允许该 WSL 客户机地址的转发和防火墙规则，重测失败则停止 |

## 测试结果

- **Python 隔离回归：36 项通过。** 包含 18 个首次安装流程场景（含管道输入、NAT 失败、mirrored localhost 回退和缺少网关时的 localhost 连接）、15 个 IPA 操作场景、3 个补丁完整性检查。
- **Windows PowerShell 5.1 隔离回归：36 项通过。** 包括真实原生 argv 传递探针、WSL 枚举、失败阻断、内嵌资源分支、终端状态和防重入，以及 16 个新增网络桥接与失败阻断断言。
- **编译后 GUI 启动检查：通过。** 使用 Windows UI Automation 查找实际主窗及启用的“开始安装”控件；不以进程仍存活代替 GUI 验证。
- **真实缓存的上游 IPA：通过。** 在临时目录替换 2 处组 ID，提取结果为 HermesEnabler2.app，未修改现有安装包。
- **Swift 6.4.1 环境变量表达式：通过。** 用现有真实编译器执行 Foundation 环境变量读取测试。
- **Swift 签名与官方公钥下载地址：HTTP 200。** 未重新下载整个 Swift 安装包。
- **补丁应用：通过。** 对独立 xtool 1.24.0 克隆执行检查、应用、反向检查；新增生产文件与原工作源码逐个对照。
- **独立 xtool 真实编译：通过，628.27 秒。** Swift 6.4.1 在全新 xtool 1.24.0 克隆、应用完整补丁后编译并链接成功；复用了依赖源码缓存，未复用既有构建产物。新二进制的 `--version`、`--help`、`install --help`、`auth --help` 均成功退出，确认包含 `--watch-udid`、`--signed-ipa-output` 和 `auth login`。

## 测试范围与限制

流程回归在临时 HOME 中运行，apt、驱动、源码获取、Swift 下载、签名和设备安装均使用模拟命令；覆盖正常流程和失败阻断，不代表在空白 Windows 上完成了一次真实安装。真实编译使用独立源码目录，复用了已缓存的依赖源码，未改动当前可用的 xtool 工作目录。

本轮未执行真实的 Apple Devices 安装、Windows 重启、Apple ID 登录或手表重装，也未更改用户现有 WSL 配置。全新 Windows 的 Microsoft Store/winget、虚拟化设置、首次重启续跑和真实设备首次安装仍需专门的空白 Windows 测试环境验证。缺少 winget 或不满足 Windows/WSL 条件时，安装器会明确停止并提示。

生成的 v1.2.0 EXE 是首次安装测试修复版。本轮未发布到 GitHub。

EXE SHA-256：`11607e2db827532e87e582d3936c84ea3efe8e44cbdb24f30960655c96105d76`。

完整 xtool 补丁 SHA-256：`dd94113654267714288fdb57295e84805d898a2b0d251b3408df5715cc5baee8`。

## 复现命令

在 Ubuntu 24.04 WSL 中，从仓库目录执行：

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tests/check_local_ipa.py
XTOOL_APP_GROUP_ID=group.0123456789abcdef /opt/swift-6.4.1/usr/bin/swift tests/check_group_environment.swift
```

在 Windows PowerShell 5.1 中，从仓库目录执行：

```powershell
.\tests\test_windows_bootstrap.ps1
.\installer\Build-Installer.ps1
.\tests\test_compiled_gui.ps1
```

构建依赖 ps2exe；测试 GUI 仅打开本轮生成的测试 EXE，检查后关闭自己启动的进程，不点击任何安装、续签或升级按钮。
