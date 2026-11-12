#requires -Version 5.1
<#
  Hermes Watch Installer — Windows one-click GUI
  全流程：Apple Devices → WSL → Ubuntu 用户 → 启动 WSL 安装脚本
  重启自动续跑：wsl --install 需要重启时自动写 RunOnce
#>
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:ExePath = [Environment]::GetCommandLineArgs()[0]
$script:IsResume = [Environment]::GetCommandLineArgs() -contains '-resume'
$script:WslUser = 'user'
$script:WslDistro = 'Ubuntu-24.04'
$script:BaseUrl = 'https://github.com/champion0399/hermes-watch-windows/releases/latest/download'
$script:InstallShUrl = "$script:BaseUrl/install.sh"

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
function Invoke-Visible([string]$exe, [string]$args, [string]$failMsg) {
    Write-Log ">> $exe $args" 'DarkGray'
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -NoNewWindow -PassThru
    if ($p.ExitCode -ne 0) { Write-Log "$failMsg (exit $($p.ExitCode))" 'Red'; return $false }
    return $true
}

# ---------- GUI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'HermesEnabler 一键安装 · Apple Watch'
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
        $out = (wsl.exe -l -q) -join "`n"
        return $out -match [regex]::Escape($script:WslDistro)
    } catch { return $false }
}
function Test-UsbMuxd {
    try { return (Test-NetConnection -ComputerName 127.0.0.1 -Port 27015 -WarningAction SilentlyContinue).TcpTestSucceeded }
    catch { return $false }
}

function Start-Install {
    $btn.Enabled = $false
    # 0. 管理员
    if (-not (Test-Admin)) {
        Write-Log '需要管理员权限，正在请求 UAC…' 'DarkOrange'
        Start-Process -FilePath $script:ExePath -Verb RunAs -ArgumentList $(if ($script:IsResume){'-resume'})
        $form.Close(); return
    }
    $bar.Value = 5

    # 1. Apple Devices
    Set-Phase '第 1 步 · 检查 Apple Devices（iPhone 驱动）'
    if (Get-Service AppleMobileDeviceService -ErrorAction SilentlyContinue) {
        Write-Log 'AppleMobileDeviceService 已安装' 'Green'
    } else {
        Write-Log '未检测到 Apple Devices / iTunes，尝试 winget 安装 Apple Devices…' 'DarkOrange'
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $rc = Invoke-Visible winget 'install --id 9PLPB2Z1RBB8 --source msstore -e --accept-source-agreements --accept-package-agreements' 'winget 安装失败'
            if (-not $rc) {
                Write-Log '自动安装失败。请手动从 Microsoft Store 安装 "Apple Devices"，或安装 iTunes 后重跑。' 'Red'
                $btn.Text='重试'; $btn.Enabled=$true; return
            }
        } else {
            Write-Log '没有 winget。请手动安装 iTunes（apple.com/itunes）后重跑。' 'Red'
            $btn.Text='重试'; $btn.Enabled=$true; return
        }
        if (Get-Service AppleMobileDeviceService -ErrorAction SilentlyContinue) {
            Write-Log 'Apple Devices 安装完成' 'Green'
        } else { Write-Log '未确认服务，请检查是否安装成功' 'DarkOrange' }
    }
    if (Test-UsbMuxd) { Write-Log 'usbmuxd (27015) 正常' 'Green' }
    else { Write-Log '27015 未监听 — 请插上 iPhone 并点"信任此电脑"' 'DarkOrange' }
    $bar.Value = 25

    # 2. WSL
    Set-Phase '第 2 步 · 检查 WSL / Ubuntu'
    if (Test-WslDistro) {
        Write-Log "$($script:WslDistro) 已存在" 'Green'
    } else {
        Write-Log "安装 WSL + $($script:WslDistro)（可能需要重启）…" 'DarkOrange'
        $rc = Invoke-Visible wsl '--install -d Ubuntu-24.04 --no-launch' 'wsl --install 失败'
        if (-not $rc) {
            Write-Log '自动安装失败。请手动在管理员 PowerShell 运行: wsl --install -d Ubuntu-24.04' 'Red'
            $btn.Text='重试'; $btn.Enabled=$true; return
        }
        if (-not (Test-WslDistro)) {
            # 需要重启：写 RunOnce，关机重启后自动续跑
            Write-Log '需要重启才能继续。重启后本程序会自动续跑。' 'DarkOrange'
            $resume = '"' + $script:ExePath + '" -resume'
            Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' 'HermesInstaller' $resume
            if ([System.Windows.Forms.MessageBox]::Show('WSL 安装需要重启电脑。重启后会自动继续安装。现在重启？','需要重启','YesNo','Warning') -eq 'Yes') {
                shutdown /r /t 5
            }
            return
        }
        Write-Log 'WSL 安装完成' 'Green'
    }
    $bar.Value = 50

    # 3. Ubuntu 用户
    Set-Phase '第 3 步 · 配置 WSL 用户'
    # 先清掉旧版可能写坏的 wsl.conf（default=user 但用户不存在 → USER_NOT_FOUND）
    wsl.exe -d $script:WslDistro -u root bash -c "grep -q 'default=user' /etc/wsl.conf 2>/dev/null && rm -f /etc/wsl.conf" 2>$null | Out-Null
    # 优先用已存在的普通用户（uid>=1000），没有才创建 'user'
    $user = $null
    $existing = wsl.exe -d $script:WslDistro -u root bash -c "awk -F: '\$3>=1000 && \$3<65534 {print \$1; exit}' /etc/passwd" 2>$null
    if ($existing -and $existing.Trim()) {
        $user = $existing.Trim()
        Write-Log "检测到已存在用户 $user" 'Green'
    } else {
        $user = $script:WslUser
        Write-Log "没有普通用户，创建 $user …"
        wsl.exe -d $script:WslDistro -u root useradd -m -s /bin/bash $user 2>$null | Out-Null
        wsl.exe -d $script:WslDistro -u root bash -c "echo '$user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$user && chmod 440 /etc/sudoers.d/$user"
        Write-Log "用户 $user 已创建" 'Green'
    }
    # 统一写 wsl.conf：让 wsl 默认就以该用户进入（不用每次 -u）
    wsl.exe -d $script:WslDistro -u root bash -c "printf '[user]\ndefault=$user\n' > /etc/wsl.conf"
    wsl.exe --shutdown $script:WslDistro
    $script:WslUser = $user
    $bar.Value = 65

    # 4. 下载脚本进 WSL（wsl.conf 已设默认用户，直接 wsl 进入）
    Set-Phase '第 4 步 · 下载脚本进 WSL'
    wsl.exe -d $script:WslDistro bash -c "curl -sL '$script:InstallShUrl' -o ~/install.sh && chmod +x ~/install.sh && curl -sL '$script:BaseUrl/manage.sh' -o ~/manage.sh && chmod +x ~/manage.sh && echo OK" | ForEach-Object { Write-Log $_ 'DarkGray' }
    $bar.Value = 75

    # 5. 启动 WSL 安装（弹终端交互）
    Set-Phase '第 5 步 · 启动 WSL 安装（弹出终端窗口）'
    Write-Log '即将弹出终端窗口，请在里面完成：Apple ID 登录 / 2FA / App Group ID' 'DarkOrange'
    Write-Log '全程保持 iPhone 解锁亮屏、手表戴着解锁' 'DarkOrange'
    Start-Sleep -Milliseconds 800
    $wslCmd = "wsl -d $($script:WslDistro) bash ~/install.sh"
    Start-Process 'cmd.exe' -ArgumentList "/k title HermesEnabler Watch Installer & $wslCmd & echo. & echo 安装结束，可关闭此窗口 & pause >nul"
    $bar.Value = 100
    Set-Phase 'Windows 侧已完成 — 请在新弹出的终端窗口中继续'
    $btn.Text = '完成'; $btn.Enabled = $true
}

function Invoke-WslAction([string]$action, [string]$label) {
    Set-Phase "$label 中（弹出终端窗口）…"
    Write-Log "执行 $action，请在终端窗口中查看进度" 'DarkOrange'
    # 先确保 manage.sh 存在（在 PowerShell 里跑，避免 bash -c 引号嵌套）
    wsl.exe -d $script:WslDistro bash -c "curl -sL '$script:BaseUrl/manage.sh' -o ~/manage.sh 2>/dev/null; chmod +x ~/manage.sh" | Out-Null
    $cmd = "wsl -d $($script:WslDistro) bash ~/manage.sh $action"
    Start-Process 'cmd.exe' -ArgumentList "/k title Hermes $action & $cmd & echo. & echo 完成，可关闭窗口 & pause >nul"
}

$btn.add_Click({ if ($btn.Text -eq '完成') { $form.Close() } else { Start-Install } })
$btnRenew.add_Click({ Invoke-WslAction 'renew' '续签' })
$btnUpgrade.add_Click({ Invoke-WslAction 'upgrade' '升级' })
$btnStatus.add_Click({ Invoke-WslAction 'status' '查看状态' })

$form.add_Shown({
    Write-Log 'HermesEnabler · Apple Watch 一键安装' 'DarkBlue'
    Write-Log "准备: iPhone(解锁) + 已配对手表(戴着解锁) + 免费 Apple ID"
    Write-Log "本程序只负责 Windows 侧环境；Apple ID/2FA/组ID 在弹出的终端里输入"
    if ($script:IsResume) { Write-Log '检测到重启后续跑，直接继续…' 'DarkOrange'; Start-Install }
})

[void]$form.ShowDialog()
