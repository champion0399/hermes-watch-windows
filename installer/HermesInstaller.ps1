#requires -Version 5.1
<#
  Hermes Watch Installer — Windows one-click GUI
  全流程：Apple Devices → WSL → Ubuntu 用户 → 启动 WSL 安装脚本
  重启自动续跑：wsl --install 需要重启时自动写 RunOnce
#>
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# PS2EXE 用宿主 EXE；直接运行脚本时必须通过 powershell.exe 重新启动。
$script:ScriptPath = $PSCommandPath
$script:ExePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$script:Busy = $false
$script:InstallComplete = $false
$script:Terminal = $null
$script:TerminalDirectory = $null
$script:WslExe = $null
$script:InstanceMutex = New-Object Threading.Mutex($false, 'Local\HermesWatchInstaller')
if (-not $script:InstanceMutex.WaitOne(0)) {
    [void][Windows.Forms.MessageBox]::Show('安装器已在运行，请回到现有窗口。')
    $script:InstanceMutex.Dispose()
    exit 1
}
$script:IsResume = [Environment]::GetCommandLineArgs() -contains '-resume'
$script:WslUser = $null
$script:WslDistro = 'Ubuntu-24.04'
$script:BaseUrl = 'https://github.com/champion0399/hermes-watch-windows/releases/latest/download'
$script:InstallShUrl = "$script:BaseUrl/install.sh"
# 构建时可将 tar.gz 资源包注入此占位；源码保留空串，避免依赖未发布资源。
$script:EmbeddedBundleBase64 = ''
$script:InstallShellCommand = 'exec bash "$HOME/install.sh" </dev/tty'

# ---------- 工具 ----------
function Write-Log([string]$msg, [string]$color = 'Black') {
    $tb.SelectionStart = $tb.TextLength
    $tb.SelectionColor = [Drawing.Color]::FromName($color)
    $tb.AppendText(('{0:HH:mm:ss}  {1}' -f (Get-Date), $msg) + "`r`n")
    $tb.SelectionColor = $tb.ForeColor
    $tb.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
function Set-Phase([string]$text) { $lbl.Text = $text; [System.Windows.Forms.Application]::DoEvents() }
function Set-Busy([bool]$value) {
    $script:Busy = $value
    foreach ($control in @($btn, $btnRenew, $btnUpgrade, $btnStatus)) { $control.Enabled = -not $value }
}
function Invoke-Native([string]$exe, [string[]]$arguments) {
    # 不使用名为 args 的参数（它是 PowerShell 自动变量）。
    $output = @(& $exe @arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$exe 失败 (exit $code): $($output -join [Environment]::NewLine)" }
    return $output
}
function ConvertTo-BashBootstrap([string]$text) {
    # 原生参数中只传 Base64，避免 PS5.1/WSL 的双重引号和 $ 展开。
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text.Replace("`r`n", "`n")))
    return "echo $encoded | base64 -d | bash"
}
function Invoke-WslScript([string]$text, [string]$user = 'root') {
    Invoke-Native $script:WslExe @('-d', $script:WslDistro, '-u', $user, '--exec', 'bash', '-c', (ConvertTo-BashBootstrap $text))
}
function Get-WslUsbMuxProbe {
    $probe = @'
set -euo pipefail
command -v ip >/dev/null
command -v timeout >/dev/null
gateway=$(ip -4 route show default | awk 'NR==1 {print $3}')
guest=''
if [ -n "$gateway" ]; then guest=$(ip -4 route get "$gateway" | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'); fi
gateway_ok=0
local_ok=0
if [ -n "$gateway" ] && timeout 3 bash -c 'exec 3<>/dev/tcp/$1/27015' _ "$gateway" 2>/dev/null; then gateway_ok=1; fi
if timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/27015' 2>/dev/null; then local_ok=1; fi
printf '%s|%s|%s|%s\n' "$gateway" "$guest" "$gateway_ok" "$local_ok"
'@
    $lines = @(Invoke-WslScript $probe 'root')
    $parts = ([string]($lines | Select-Object -Last 1)).Trim().Split('|')
    if ($parts.Count -ne 4 -or $parts[2] -notmatch '^[01]$' -or $parts[3] -notmatch '^[01]$') { throw 'WSL usbmux 连通探测结果格式错误。' }
    if ($parts[2] -eq '1' -or $parts[3] -eq '1') {
        return [pscustomobject]@{ Gateway = $parts[0]; Guest = $parts[1]; GatewayReachable = ($parts[2] -eq '1'); LocalReachable = ($parts[3] -eq '1') }
    }
    foreach ($value in $parts[0..1]) {
        $address = $null
        if (-not [Net.IPAddress]::TryParse($value, [ref]$address) -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or [Net.IPAddress]::IsLoopback($address) -or $value -eq '0.0.0.0') { throw "WSL 返回了非预期 IPv4 地址：$value" }
    }
    return [pscustomobject]@{ Gateway = $parts[0]; Guest = $parts[1]; GatewayReachable = ($parts[2] -eq '1'); LocalReachable = ($parts[3] -eq '1') }
}
function Ensure-WslUsbMuxBridge {
    $probe = Get-WslUsbMuxProbe
    if ($probe.GatewayReachable -or $probe.LocalReachable) {
        Write-Log 'WSL 已能连接 usbmux 27015，保留现有网络配置。' 'Green'
        return
    }
    $gateway = $probe.Gateway
    $guest = $probe.Guest
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $gateway -ErrorAction Stop)
    if (-not ($addresses | Where-Object { $_.IPAddress -eq $gateway })) { throw "WSL 网关 $gateway 不是 Windows 本机地址，未建立转发。" }
    if ($gateway -eq $guest) { throw 'WSL 网关与客户机地址相同，未建立转发。' }
    if (-not (Test-UsbMuxd)) { throw 'Windows 127.0.0.1:27015 未监听，请先确认 AppleMobileDeviceService 和设备连接。' }
    $rules = @(Invoke-Native netsh.exe @('interface', 'portproxy', 'show', 'v4tov4'))
    $hasProxy = $false
    foreach ($line in $rules) {
        if ([string]$line -match '^\s*(\S+)\s+27015\s+(\S+)\s+(\d+)\s*$') {
            if ($matches[1] -in @($gateway, '0.0.0.0', '*')) {
                if ($matches[1] -ne $gateway -or $matches[2] -ne '127.0.0.1' -or $matches[3] -ne '27015') { throw "已有端口转发冲突，保留现有规则：$line" }
                $hasProxy = $true
            }
        }
    }
    $ruleName = 'HermesInstaller-UsbMux-' + $gateway.Replace('.', '-') + '-' + $guest.Replace('.', '-')
    $firewall = @(Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)
    if ($firewall.Count -gt 0) {
        $addressFilters = @($firewall | Get-NetFirewallAddressFilter -ErrorAction Stop)
        $portFilters = @($firewall | Get-NetFirewallPortFilter -ErrorAction Stop)
        if ($firewall.Count -ne 1 -or [string]$firewall[0].Enabled -ne 'True' -or [string]$firewall[0].Direction -ne 'Inbound' -or [string]$firewall[0].Action -ne 'Allow' -or @($addressFilters[0].LocalAddress).Count -ne 1 -or [string]$addressFilters[0].LocalAddress -ne $gateway -or @($addressFilters[0].RemoteAddress).Count -ne 1 -or [string]$addressFilters[0].RemoteAddress -ne $guest -or [string]$portFilters[0].LocalPort -ne '27015' -or [string]$portFilters[0].Protocol -notin @('TCP', '6')) { throw "已有同名防火墙规则与预期不符，保留原规则：$ruleName" }
    }
    $service = Get-Service iphlpsvc -ErrorAction Stop
    if ($service.Status -ne 'Running') { Start-Service iphlpsvc -ErrorAction Stop }
    if (-not $hasProxy) {
        Invoke-Native netsh.exe @('interface', 'portproxy', 'add', 'v4tov4', "listenaddress=$gateway", 'listenport=27015', 'connectaddress=127.0.0.1', 'connectport=27015', 'protocol=tcp') | Out-Null
    }
    if ($firewall.Count -eq 0) {
        New-NetFirewallRule -Name $ruleName -DisplayName 'Hermes WSL usbmux (single guest)' -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalAddress $gateway -RemoteAddress $guest -LocalPort 27015 -ErrorAction Stop | Out-Null
    }
    $reachable = $false
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $after = Get-WslUsbMuxProbe
        if ($after.Gateway -ne $gateway -or $after.Guest -ne $guest) { throw 'WSL 网络地址在配置期间变化，请重试以重新检测。' }
        if ($after.GatewayReachable -or $after.LocalReachable) { $reachable = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $reachable) { throw "已配置 $gateway`:27015 -> 127.0.0.1:27015（仅允许 $guest），但 WSL 重测仍失败。请检查 iphlpsvc、防火墙策略和 Apple 服务；未继续安装。" }
    Write-Log "WSL usbmux 桥接已验证：$guest -> $gateway`:27015" 'Green'
}
function Get-LaunchCommand([bool]$resume) {
    $suffix = if ($resume) { ' -resume' } else { '' }
    if ($script:ScriptPath -and [IO.Path]::GetExtension($script:ScriptPath) -eq '.ps1') {
        $hostExe = Join-Path $PSHOME 'powershell.exe'
        return @{ File = $hostExe; Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $script:ScriptPath, $suffix) }
    }
    return @{ File = $script:ExePath; Arguments = $suffix.Trim() }
}
function Start-InstallTerminal {
    $script:TerminalDirectory = Join-Path ([IO.Path]::GetTempPath()) ('HermesInstaller-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:TerminalDirectory -ErrorAction Stop)
    $resultPath = Join-Path $script:TerminalDirectory 'result.txt'
    $runnerPath = Join-Path $script:TerminalDirectory 'run.ps1'
    $command = ConvertTo-BashBootstrap $script:InstallShellCommand
    $runner = @'
$ErrorActionPreference = 'Stop'
$rc = 1
try {
    & '__WSL__' -d '__DISTRO__' -u '__USER__' --exec bash -c '__COMMAND__'
    $rc = $LASTEXITCODE
} catch { Write-Host $_ -ForegroundColor Red }
[IO.File]::WriteAllText('__RESULT__.tmp', [string]$rc)
Move-Item -LiteralPath '__RESULT__.tmp' -Destination '__RESULT__' -Force
if ($rc -eq 0) { Write-Host '__LABEL__脚本已成功结束 (exit 0)' -ForegroundColor Green }
else { Write-Host "__LABEL__脚本失败 (exit $rc)，请保留此窗口中的错误信息。" -ForegroundColor Red }
[void](Read-Host '按 Enter 关闭终端')
exit $rc
'@
    foreach ($pair in @(@('__LABEL__', $(if ($script:TerminalLabel) { $script:TerminalLabel } else { '安装' })), @('__WSL__', $script:WslExe), @('__DISTRO__', $script:WslDistro), @('__USER__', $script:WslUser), @('__COMMAND__', $command), @('__RESULT__', $resultPath))) {
        $runner = $runner.Replace($pair[0], $pair[1].Replace("'", "''"))
    }
    [IO.File]::WriteAllText($runnerPath, $runner, (New-Object Text.UTF8Encoding($true)))
    $script:Terminal = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath) -PassThru -ErrorAction Stop
    $script:TerminalTimer.Start()
}

function Resolve-WslUser([bool]$AllowCreate = $false) {
    # Management never sends account creation or sudoers edits to WSL.
    $createUser = @'
    user=user
    if getent passwd "$user" >/dev/null; then
        echo 'Account user already exists but is not a usable normal user' >&2
        exit 1
    fi
    command -v visudo >/dev/null || { echo 'Missing dependency: visudo (sudo)' >&2; exit 1; }
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "$tmp"
    visudo -cf "$tmp" >&2
    policy="/etc/sudoers.d/$user"
    test ! -e "$policy" || { echo 'Existing sudoers policy requires manual review' >&2; exit 1; }
    install -o root -g root -m 440 "$tmp" "$policy"
    if ! useradd -m -s /bin/bash "$user"; then
        rm -f "$policy"
        exit 1
    fi
'@
    $userScript = @'
set -euo pipefail
for command in awk getent bash base64; do
    command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
user=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
if [ -z "$user" ]; then
__ON_MISSING_USER__
fi
getent passwd "$user" >/dev/null
printf '%s\n' "$user"
'@
    $missingUser = if ($AllowCreate) { $createUser } else { "echo 'No usable existing WSL user; run installation first' >&2; exit 1" }
    $users = @(Invoke-WslScript ($userScript.Replace('__ON_MISSING_USER__', $missingUser)))
    $user = ([string]($users | Select-Object -Last 1)).Trim()
    if ($user -eq 'root' -or $user -notmatch '^[a-z_][a-z0-9_-]*[$]?$') { throw "WSL 返回了非预期用户名：$user" }
    $script:WslUser = $user
    return $user
}

function Deploy-WslAssets([string]$Entry = 'install.sh') {
    if ($Entry -notin @('install.sh', 'manage.sh')) { throw 'Unexpected asset entry.' }
    $archive = $null
    try {
        $prepare = @'
set -euo pipefail
assets=$(mktemp -d "$HOME/hermes-installer-assets.XXXXXX")
trap 'rm -rf "$assets"' EXIT
__ACQUIRE__
test -s "$assets/install.sh"
test -s "$assets/manage.sh"
test -s "$assets/lib/hermes_runtime.py"
for name in install.sh manage.sh; do
    head -n 1 "$assets/$name" | grep -Eq '^#!.*(bash|/sh)([[:space:]]|$)'
    bash -n "$assets/$name"
    chmod 700 "$assets/$name"
done
trap - EXIT
printf '%s\n' "$assets/__ENTRY__"
'@
        $repo = if ($script:ScriptPath) { Split-Path (Split-Path $script:ScriptPath -Parent) -Parent } else { '' }
        if ($script:EmbeddedBundleBase64) {
            $archive = Join-Path ([IO.Path]::GetTempPath()) ('HermesAssets-' + [guid]::NewGuid().ToString('N') + '.tar.gz')
            [IO.File]::WriteAllBytes($archive, [Convert]::FromBase64String($script:EmbeddedBundleBase64))
            $acquire = @'
archive=$(wslpath -u '__PATH__')
# Reject path traversal and links before extracting a locally built bundle.
listing=$(tar -tzf "$archive")
if printf '%s\n' "$listing" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then echo 'Invalid bundle member path' >&2; exit 1; fi
if tar -tvzf "$archive" | grep -Eq '^[lh]'; then echo 'Bundle links are not supported' >&2; exit 1; fi
tar --no-same-owner -xzf "$archive" -C "$assets"
'@
            $acquire = $acquire.Replace('__PATH__', $archive.Replace("'", "'\''"))
        } elseif ($repo -and (Test-Path -LiteralPath (Join-Path $repo 'install.sh')) -and (Test-Path -LiteralPath (Join-Path $repo 'manage.sh')) -and (Test-Path -LiteralPath (Join-Path $repo 'lib\hermes_runtime.py'))) {
            $acquire = @'
repo=$(wslpath -u '__PATH__')
cp "$repo/install.sh" "$repo/manage.sh" "$assets/"
cp -R "$repo/lib" "$assets/lib"
for helper in patches watch-device-helper patch-hermes-group.py probe-paired-watch.py; do
    if [ -e "$repo/$helper" ]; then cp -R "$repo/$helper" "$assets/"; fi
done
'@
            $acquire = $acquire.Replace('__PATH__', $repo.Replace("'", "'\''"))
        } else {
            $acquire = @'
mkdir -p "$assets/lib" "$assets/watch-device-helper"
# GitHub Release assets are flat; restore the adjacent runtime/helper layout locally.
for name in install.sh manage.sh hermes_runtime.py watch_device.py watch_connection.py; do
    case "$name" in
        hermes_runtime.py) destination="$assets/lib/$name" ;;
        watch_*.py) destination="$assets/watch-device-helper/$name" ;;
        *) destination="$assets/$name" ;;
    esac
    curl --fail --show-error --location --connect-timeout 20 --max-time 180 --retry 2 '__BASE__/'"$name" -o "$destination"
    test -s "$destination"
done
'@
            $acquire = $acquire.Replace('__BASE__', $script:BaseUrl.Replace("'", "'\''"))
        }
        $paths = @(Invoke-WslScript ($prepare.Replace('__ACQUIRE__', $acquire).Replace('__ENTRY__', $Entry)) $script:WslUser)
        $assetPath = ([string]($paths | Select-Object -Last 1)).Trim()
        if ($assetPath -notmatch ('^/[^\r\n]+/hermes-installer-assets\.[A-Za-z0-9]+/' + [regex]::Escape($Entry) + '$')) { throw '资源返回了非预期执行路径。' }
        return $assetPath
    } finally {
        if ($archive) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
    }
}

# ---------- GUI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'HermesEnabler 一键安装 · Apple Watch · v1.3.0'
$form.Size = New-Object System.Drawing.Size(720, 520)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lbl = New-Object System.Windows.Forms.Label
$lbl.Location = '16,12'; $lbl.Size = '680,40'
$lbl.Font = New-Object System.Drawing.Font([string]'Microsoft YaHei UI', [single]11, [System.Drawing.FontStyle]::Bold)
$lbl.Text = '准备中…'
$form.Controls.Add($lbl)

$tb = New-Object System.Windows.Forms.RichTextBox
$tb.Location = '16,60'; $tb.Size = '672,360'
$tb.ReadOnly = $true; $tb.BackColor = 'White'
$tb.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($tb)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = '16,428'; $bar.Size = '672,14'
$bar.Maximum = 100; $bar.Style = 'Continuous'
$form.Controls.Add($bar)

$btn = New-Object System.Windows.Forms.Button
$btn.Location = '16,450'; $btn.Size = '160,28'
$btn.Text = '开始安装'
$form.Controls.Add($btn)

$btnRenew = New-Object System.Windows.Forms.Button
$btnRenew.Location = '184,450'; $btnRenew.Size = '120,28'
$btnRenew.Text = '续签 (7天)'
$form.Controls.Add($btnRenew)

$btnUpgrade = New-Object System.Windows.Forms.Button
$btnUpgrade.Location = '312,450'; $btnUpgrade.Size = '120,28'
$btnUpgrade.Text = '升级最新版'
$form.Controls.Add($btnUpgrade)

$btnStatus = New-Object System.Windows.Forms.Button
$btnStatus.Location = '440,450'; $btnStatus.Size = '100,28'
$btnStatus.Text = '状态'
$form.Controls.Add($btnStatus)

$link = New-Object System.Windows.Forms.LinkLabel
$link.Location = '600,454'; $link.Size = '100,20'
$link.Text = '打开教程'; $link.TextAlign = 'MiddleRight'
$link.add_LinkClicked({ Start-Process 'https://github.com/champion0399/hermes-watch-windows' })
$form.Controls.Add($link)

# ---------- 主流程 ----------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-WslDistro {
    try {
        $out = (Invoke-Native $script:WslExe @('--list', '--quiet')) -join "`n"
        $names = $out.Replace([string][char]0, '').Split("`n") | ForEach-Object { $_.Trim() }
        return $names -contains $script:WslDistro
    } catch {
        Write-Log "WSL 枚举尚未就绪，将尝试安装/启用：$_" 'DarkOrange'
        return $false
    }
}
function Test-UsbMuxd {
    try { return (Test-NetConnection -ComputerName 127.0.0.1 -Port 27015 -WarningAction SilentlyContinue).TcpTestSucceeded }
    catch { return $false }
}

function Start-Install {
    if ($script:Busy) { return }
    Set-Busy $true
    $script:InstallComplete = $false
    $bar.Value = 0
    try {
        if ([Environment]::OSVersion.Version.Build -lt 19041) { throw '需要 Windows 10 build 19041 或更高版本。' }
        if (-not (Test-Admin)) {
            Write-Log '需要管理员权限，正在请求 UAC…' 'DarkOrange'
            $launch = Get-LaunchCommand $script:IsResume
            $script:InstanceMutex.ReleaseMutex()
            try {
                $launchParameters = @{ FilePath = $launch.File; Verb = 'RunAs'; ErrorAction = 'Stop' }
                if ($launch.Arguments) { $launchParameters.ArgumentList = $launch.Arguments }
                [void](Start-Process @launchParameters)
            } catch { [void]$script:InstanceMutex.WaitOne(0); throw }
            $script:Busy = $false
            $form.Close()
            return
        }
        $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wslCommand) { throw '未找到 wsl.exe，请先启用或安装 WSL。' }
        $script:WslExe = $wslCommand.Source
        $bar.Value = 5
        Set-Phase '第 1 步 · 检查 Apple Devices（iPhone 驱动）'
        $service = Get-Service AppleMobileDeviceService -ErrorAction SilentlyContinue
        if (-not $service) {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $winget) { throw '没有 winget。请安装 Apple Devices / iTunes 后重试。' }
            Invoke-Native $winget.Source @('install', '--id', '9PLPB2Z1RBB8', '--source', 'msstore', '-e', '--accept-source-agreements', '--accept-package-agreements') | ForEach-Object { Write-Log ([string]$_) 'DarkGray' }
            $service = Get-Service AppleMobileDeviceService -ErrorAction SilentlyContinue
            if (-not $service) { throw '安装命令已退出，但未检测到 AppleMobileDeviceService。请完成驱动安装后重试。' }
        }
        if ($service.Status -ne 'Running') { Start-Service AppleMobileDeviceService -ErrorAction Stop }
        Write-Log 'AppleMobileDeviceService 已就绪' 'Green'
        if (-not (Test-UsbMuxd)) { Write-Log '27015 未监听，请插上 iPhone 并点“信任此电脑”；终端安装仍需确认设备连接。' 'DarkOrange' }
        $bar.Value = 25
        Set-Phase '第 2 步 · 检查 WSL / Ubuntu'
        if (-not (Test-WslDistro)) {
            $output = @(& $script:WslExe --install -d $script:WslDistro --no-launch 2>&1)
            $installCode = $LASTEXITCODE
            $output | ForEach-Object { Write-Log ([string]$_) 'DarkGray' }
            if ($installCode -notin @(0, 3010, 1641)) { throw "WSL 安装失败 (exit $installCode)" }
            if ($installCode -in @(3010, 1641) -or -not (Test-WslDistro)) {
                $launch = Get-LaunchCommand $true
                $resume = '"' + $launch.File + '" ' + $launch.Arguments
                $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
                [void](New-Item -Path $runOnce -Force -ErrorAction Stop)
                Set-ItemProperty -Path $runOnce -Name 'HermesInstaller' -Value $resume -ErrorAction Stop
                Set-Phase 'WSL 尚未就绪 · 已登记重启后重试'
                Write-Log 'WSL 尚未就绪，已登记重启后重试。若重启后仍未就绪，请保留错误信息检查虚拟化和 WSL 功能。' 'DarkOrange'
                if ([Windows.Forms.MessageBox]::Show('WSL 尚未就绪，已登记重启后重试。现在重启？', '需要重启', 'YesNo', 'Warning') -eq 'Yes') {
                    Invoke-Native shutdown.exe @('/r', '/t', '5') | Out-Null
                }
                return
            }
        }
        $bar.Value = 50
        Set-Phase '第 3 步 · 检查 Ubuntu 用户和依赖'
        # 显式指定用户，保留 /etc/wsl.conf 及运行中的其他发行版。
        $user = Resolve-WslUser $true
        Write-Log "使用 Ubuntu 用户 $user（保留现有 WSL 配置）" 'Green'
        Set-Phase '第 3 步 · 检查 WSL 到 Apple 服务连接'
        Ensure-WslUsbMuxBridge
        $bar.Value = 65
        Set-Phase '第 4 步 · 下载并校验脚本'
        $installPath = Deploy-WslAssets 'install.sh'
        $script:InstallShellCommand = "exec bash '" + $installPath.Replace("'", "'\''") + "' </dev/tty"
        $script:TerminalLabel = '安装'
        $script:TerminalAction = 'install'
        $bar.Value = 75
        Set-Phase '第 5 步 · 终端安装进行中，等待脚本退出'
        Write-Log '请在新终端完成 Apple ID / 2FA / App Group ID。请保持手机和手表解锁。' 'DarkOrange'
        Start-InstallTerminal
    } catch {
        Set-Phase '安装未完成 · 请查看错误后重试'
        Write-Log ([string]$_) 'Red'
        $btn.Text = '重试'
    } finally {
        if (-not $script:Terminal) {
            if ($script:TerminalDirectory) {
                Remove-Item -LiteralPath $script:TerminalDirectory -Recurse -Force -ErrorAction SilentlyContinue
                $script:TerminalDirectory = $null
            }
            Set-Busy $false
        }
    }
}

function Invoke-WslAction([string]$action, [string]$label) {
    if ($script:Busy) { return }
    Set-Busy $true
    try {
        if ($action -notin @('renew','upgrade','status')) { throw 'Unexpected management action.' }
        $script:TerminalAction = $action
        $script:TerminalLabel = $label
        $script:InstallComplete = $false
        $bar.Value = 0
        $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wslCommand) { throw '未找到 wsl.exe，请先完成安装。' }
        $script:WslExe = $wslCommand.Source
        if (-not (Test-WslDistro)) { throw '未找到所需 Ubuntu 发行版，请先完成安装。' }
        $user = Resolve-WslUser $false
        $managePath = Deploy-WslAssets 'manage.sh'
        $script:InstallShellCommand = "exec bash '" + $managePath.Replace("'", "'\''") + "' " + $action + ' </dev/tty'
        $bar.Value = 75
        Set-Phase "$label 进行中，等待脚本退出"
        Write-Log "使用 Ubuntu 用户 $user 执行 $label，请查看交互终端。" 'DarkOrange'
        Start-InstallTerminal
    } catch {
        Set-Phase "$label 未完成 · 请查看错误后重试"
        Write-Log ([string]$_) 'Red'
    } finally {
        if (-not $script:Terminal) {
            if ($script:TerminalDirectory) { Remove-Item -LiteralPath $script:TerminalDirectory -Recurse -Force -ErrorAction SilentlyContinue; $script:TerminalDirectory = $null }
            Set-Busy $false
        }
    }
}
# 所有动作只在终端报告 exit 0 后显示对应完成；关闭终端且无结果按失败处理。
$script:TerminalTimer = New-Object Windows.Forms.Timer
$script:TerminalTimer.Interval = 500
$script:TerminalTimer.add_Tick({
    if (-not $script:Terminal) { return }
    $resultPath = Join-Path $script:TerminalDirectory 'result.txt'
    $hasResult = Test-Path -LiteralPath $resultPath
    if (-not $hasResult -and -not $script:Terminal.HasExited) { return }
    $script:TerminalTimer.Stop()
    try {
        $code = 1
        if ($hasResult) {
            $value = [IO.File]::ReadAllText($resultPath).Trim()
            if ($value -notmatch '^\d+$') { throw '终端结果格式错误。' }
            $code = [int]$value
        }
        if ($hasResult -and $code -eq 0) {
            $script:InstallComplete = ($script:TerminalAction -eq 'install')
            $bar.Value = 100
            Set-Phase "$($script:TerminalLabel)脚本已成功结束（exit 0）"
            Write-Log "$($script:TerminalLabel)脚本成功退出（exit 0）。" 'Green'
            if ($script:InstallComplete) { $btn.Text = '完成' }
        } else {
            Set-Phase "$($script:TerminalLabel)未完成 · 请查看终端错误后重试"
            Write-Log $(if ($hasResult) { "$($script:TerminalLabel)脚本失败 (exit $code)" } else { "终端提前关闭，未收到$($script:TerminalLabel)结果。" }) 'Red'
            $btn.Text = '重试'
        }
    } catch {
        Set-Phase "$($script:TerminalLabel)结果读取失败 · 请查看终端"
        Write-Log ([string]$_) 'Red'
        $btn.Text = '重试'
    } finally {
        $script:Terminal.Dispose()
        $script:Terminal = $null
        Remove-Item -LiteralPath $script:TerminalDirectory -Recurse -Force -ErrorAction SilentlyContinue
        $script:TerminalDirectory = $null
        Set-Busy $false
    }
})
$form.add_FormClosing({
    param($sender, $eventArgs)
    if ($script:Busy) {
        $eventArgs.Cancel = $true
        Write-Log '操作仍在运行。请先在交互终端结束或取消操作，再关闭安装器。' 'DarkOrange'
    }
})
$btn.add_Click({ if ($script:InstallComplete) { $form.Close() } else { Start-Install } })
$btnRenew.add_Click({ Invoke-WslAction 'renew' '续签' })
$btnUpgrade.add_Click({ Invoke-WslAction 'upgrade' '升级' })
$btnStatus.add_Click({ Invoke-WslAction 'status' '查看状态' })

$form.add_Shown({
    Write-Log 'HermesEnabler · Apple Watch 一键安装' 'DarkBlue'
    Write-Log "准备: iPhone(解锁) + 已配对手表(戴着解锁) + 免费 Apple ID"
    Write-Log "本程序只负责 Windows 侧环境；Apple ID/2FA/组ID 在弹出的终端里输入"
    if ($script:IsResume) { Write-Log '检测到重启后续跑，直接继续…' 'DarkOrange'; Start-Install }
})

try { [void]$form.ShowDialog() }
finally {
    $script:TerminalTimer.Dispose()
    try { $script:InstanceMutex.ReleaseMutex() } catch { }
    $script:InstanceMutex.Dispose()
    $form.Dispose()
}
if ($script:InstallComplete) { exit 0 }
exit 1
