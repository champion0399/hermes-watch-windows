# 续签与升级功能检查报告（v1.3.0）

本轮检查、修复续签、升级和状态查询，并回归首次安装。结果对应 HermesInstaller-v1.3.0.exe；发布文件与本报告记录的 SHA-256 一致。

## 修复结果

| 原问题 | 本轮处理 |
|---|---|
| 管理按钮仍以默认 WSL 用户启动，可能命中旧版写坏的默认用户 | 复用经过校验的现有用户识别，显式 `-u`；管理阶段不创建用户、不改 sudoers 或 wsl.conf |
| 每次点按钮从远端覆盖 manage.sh，可能拿到旧脚本或下载失败仍运行 | 优先部署 EXE 内嵌完整资源；源码模式用本地资源；远程 fallback 检查 HTTP、非空和 shell 语法 |
| cmd 无条件显示“完成” | 统一终端结果控制器，只有实际 exit 0 才显示对应动作成功；失败、提前关闭或非法结果保持失败 |
| 续签优先选历史 grouped IPA，旧配置未及时更新可能导致版本回退 | 优先续签当前签名缓存；识别比配置路径更新的标准缓存并校验 group，避免选回历史包 |
| 升级必须先存在旧 grouped IPA | 升级只需正确的既有 App Group/设备配置，独立获取新版本并 patch |
| 写死会话“到2027”，误导用户无需再登录 | 检查实际 auth status；会话失效时在交互终端重新登录；没有交互终端则清楚停止 |
| source 配置与正则抓 profile 原始字节 | 使用只解析静态赋值的配置读取；从真实 Watch profile plist 的 App Group entitlement 导入旧安装 |
| 签名输出或 profile 无效仍继续装表 | 核对签名包存在、Watch executable 的 group、profile group/UDID/application-identifier/UUID/日期 |
| 重新安装但到期时间未延长仍叫“续签成功” | 到期时间没有延长时停止手表重装，并明确报错 |
| 只见 iPhone 安装成功就误以为手表成功 | Watch conduit 安装后查询 registry，核对 Bundle ID、版本及构建号，返回设备安装收据 |
| 操作失败覆盖上次可用缓存和版本记录 | 先在独立临时目录下载、patch、签名；只有手表收据匹配后才替换持久缓存并记录上游版本 |
| 两个任务同时处理同一套 IPA | GUI Busy 防重入；首次安装和管理脚本使用同一个文件锁 |
| 无法区分上游 1.5.1 与 app 内部固定 1.0 | 状态页区分“历史成功记录的上游版本”和“设备上报的版本”；旧安装没有可靠记录就显示未知 |

## 测试证据

| 测试 | 结果 |
|---|---|
| 续签/升级流程隔离测试 | 25 项通过 |
| 新增配置/profile/runtime 测试 | 23 项通过 |
| Watch 安装收据与只读查询测试 | 13 项通过 |
| 管理 GUI 控制器测试（Windows PowerShell 5.1） | 46 项通过 |
| 原首次安装 Python 回归 | 36 项通过 |
| 原首次安装 Windows 回归 | 36 项通过 |
| 总自动化检查 | 179 项通过（97 项 Python，82 项 Windows） |
| 补充首次安装版本记录校验 | 通过，保存 UPSTREAM_TAG 和 LAST_SUCCESS_AT |
| 最终 EXE 启动与控件检查 | 通过，窗口及文件版本 1.3.0，四个操作控件启用 |
| 实际 EXE → WSL 状态链路 | 已运行真实只读状态动作；未检测到 USB iPhone 时终端返回 1，GUI 正确显示失败 |
| 现有配置及真实签名缓存 | 校验通过，到期时间 2026-11-19 23:25:26（北京时间） |

流程测试使用临时 HOME、模拟签名器与设备服务。覆盖了正常续签、正常升级、没有旧 grouped IPA、旧配置指向历史文件、补建配置、失效登录、端口不可达、设备不匹配、下载失败、签名失败、签名输出缺失、profile 失效或 group/UDID 错误、到期时间未延长、直推失败、收据缺失或不匹配、缺失应用和并发操作。

Windows 测试包含真实运行的无害 argv/退出码探针以及实际生成的终端 runner；WSL 管理部署和设备安装使用 mock。实际 GUI 状态集成测试仅点击“状态”，没有点击“续签”或“升级”。

## 验证边界

- 本轮没有执行真实 Apple ID 登录、重新签名、iPhone 安装或手表安装。设备查询时未检测到 USB iPhone，因此尚未验证新版在真实设备上的续签/升级成功路径。
- 现有签名包的日期、设备、group 和 application-identifier 校验属于结构及字段检查，未独立验证 CMS 或 Mach-O 密码学签名。设备端安装器负责实际安装时的签名验证。
- 安装收据确认 conduit 返回成功后设备 registry 中存在匹配的 Bundle ID、版本和构建号。上游仍可能把内部版本写为 1.0；收据不等于从设备读回完整二进制并做哈希比对。
- 旧安装缺少可信上游版本记录时显示未知，避免把缓存文件名或文件修改时间当成已安装版本的证明。
- 失败时保留上次本地成功缓存，不代表自动回滚设备。签名工具的 iPhone 安装阶段可能已经完成，而后续 Watch 校验或直推失败；此时软件整体结果仍是失败。
- 本报告随 GitHub v1.3.0 发布，作为测试修复版提供；原 v1.2.0 首次安装测试 EXE 在本地保留。

## 文件校验

HermesInstaller-v1.3.0.exe SHA-256：

```text
bb9301370dbed004f50383a1908d0da61059b7b8758c81e7294c82cc1441de17
```

## 复现

WSL Ubuntu 24.04：

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tests/check_existing_management.py
bash manage.sh status
```

后两条是本机只读集成检查，需要既有安装配置；状态查询还需要 USB iPhone。

Windows PowerShell 5.1：

```powershell
.\tests\test_windows_bootstrap.ps1
.\tests\test_windows_management.ps1
.\installer\Build-Installer.ps1
.\tests\test_compiled_gui.ps1
# 可选：仅点击编译版GUI的只读状态动作，在当前WSL环境验证结果返回。
.\tests\check_live_status_gui.ps1
```
