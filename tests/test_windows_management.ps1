#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\installer\HermesInstaller.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Installer parser errors' }
$functions = $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $true)
foreach ($name in @('ConvertTo-BashBootstrap','Invoke-WslScript','Resolve-WslUser','Deploy-WslAssets','Invoke-WslAction','Start-InstallTerminal','Set-Busy')) {
    Invoke-Expression (($functions | Where-Object Name -eq $name | Select-Object -First 1).Extent.Text)
}
$script:Passed = 0
function Assert($condition, $message) { if (-not $condition) { throw $message }; $script:Passed++; Write-Output "PASS $message" }
function Write-Log {param($msg,$color) $script:Logs += [string]$msg}
function Set-Phase {param($text) $script:Phase = $text}
function Get-Command {param($Name,$ErrorAction) if ($script:Scenario -ne 'nowsl') { return @{Source='Mock-Wsl'} } }
function Test-WslDistro { return $script:Scenario -ne 'nodistro' }
# Every WSL call is intercepted; no WSL process, installer, signing command or networking command runs.
function Invoke-WslScript {
    param($text,$user='root')
    $script:Calls += [pscustomobject]@{Text=$text;User=$user}
    if ($text -match 'user=\$\(awk') {
        if ($script:Scenario -eq 'nouser') { throw 'mock no existing usable user' }
        if ($script:Scenario -eq 'baduser') { return 'alice; id' }
        return 'alice'
    }
    if ($script:Scenario -eq 'deployfail') { throw 'mock curl HTTP 404 or invalid bundle' }
    if ($script:Scenario -eq 'badpath') { return '/tmp/injected/manage.sh' }
    return '/home/alice/hermes-installer-assets.ABCD/manage.sh'
}
function Start-InstallTerminal { $script:Launches++; $script:Terminal = [pscustomobject]@{Mock=$true} }
function Ensure-WslUsbMuxBridge { throw 'Unexpected network bridge configuration' }
function Start-Service { throw 'Unexpected service mutation' }
function New-NetFirewallRule { throw 'Unexpected firewall mutation' }
function Invoke-Native { throw 'Unexpected dependency/system installation' }
$script:WslDistro='Ubuntu-24.04'
$script:BaseUrl='https://example.invalid/releases/download'
$script:ScriptPath=$installer
$script:EmbeddedBundleBase64=''
$btn=[pscustomobject]@{Enabled=$true;Text='开始安装'}
$btnRenew=[pscustomobject]@{Enabled=$true}; $btnUpgrade=[pscustomobject]@{Enabled=$true}; $btnStatus=[pscustomobject]@{Enabled=$true}
$bar=[pscustomobject]@{Value=0}
$labels=@{renew='续签';upgrade='升级';status='查看状态'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('HermesManagementTests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $temp)
try {
    foreach ($action in @('renew','upgrade','status')) {
        $script:Scenario='success'; $script:Busy=$false; $script:Terminal=$null; $script:TerminalDirectory=$null; $script:Calls=@(); $script:Launches=0; $script:Logs=@(); $script:InstallComplete=$true
        Invoke-WslAction $action $labels[$action]
        Assert ($script:Launches -eq 1 -and $script:Busy -and -not $btn.Enabled -and -not $btnRenew.Enabled -and -not $btnUpgrade.Enabled -and -not $btnStatus.Enabled -and $bar.Value -eq 75) "$action launches once and disables all action buttons until real completion"
        Assert ($script:WslUser -eq 'alice' -and $script:Calls[0].User -eq 'root' -and $script:Calls[1].User -eq 'alice') "$action discovers an existing nondefault user and deploys assets explicitly as that user"
        Assert ($script:Calls[0].Text -match 'No usable existing WSL user' -and $script:Calls[0].Text -notmatch 'useradd|sudoers|apt(-get)? |/etc/wsl.conf') "$action selects read-only management user discovery without configuration/dependency installation"
        Assert ($script:InstallShellCommand -eq ("exec bash '/home/alice/hermes-installer-assets.ABCD/manage.sh' " + $action + ' </dev/tty') -and $script:TerminalAction -eq $action -and $script:TerminalLabel -eq $labels[$action] -and -not $script:InstallComplete) "$action executes adjacent-lib asset path and records the correct controller label"
        Assert ($script:Calls[1].Text -match 'cp -R "\$repo/lib" "\$assets/lib"' -and $script:Calls[1].Text -notmatch 'curl --fail') "$action prefers source repository assets over network"
        Invoke-WslAction 'renew' '续签'
        Assert ($script:Launches -eq 1 -and $script:Calls.Count -eq 2) "$action Busy guard blocks repeated management clicks"
    }
    foreach ($scenario in @('nowsl','nodistro','nouser','baduser','deployfail','badpath')) {
        $script:Scenario=$scenario; $script:Busy=$false; $script:Terminal=$null; $script:TerminalDirectory=$null; $script:Calls=@(); $script:Launches=0
        Invoke-WslAction 'renew' '续签'
        Assert ($script:Launches -eq 0 -and -not $script:Busy -and $btnRenew.Enabled -and $script:Phase -match '续签.*未完成') "$scenario failure blocks execution and restores management buttons"
    }
    # Inspect both non-source resource paths without contacting any network.
    $script:Scenario='success'; $script:ScriptPath=$null; $script:Calls=@(); $script:WslUser='alice'
    $path=Deploy-WslAssets 'manage.sh'
    Assert ($path -like '*/manage.sh' -and $script:Calls[0].Text -match 'curl --fail --show-error --location --connect-timeout 20 --max-time 180 --retry 2' -and $script:Calls[0].Text -match 'lib/hermes_runtime.py' -and $script:Calls[0].Text -match 'bash -n' -and $script:Calls[0].Text -match 'test -s') 'Remote fallback checks transfer failure, nonempty scripts/runtime, shebang and shell syntax'
    $script:EmbeddedBundleBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('mock bundle')); $script:Calls=@()
    $path=Deploy-WslAssets 'manage.sh'
    Assert ($path -like '*/manage.sh' -and $script:Calls[0].Text -match 'tar --no-same-owner' -and $script:Calls[0].Text -match 'Invalid bundle member path' -and $script:Calls[0].Text -match 'Bundle links are not supported' -and $script:Calls[0].Text -notmatch 'curl --fail|cp "\$repo') 'Embedded deployment validates bundle paths/links and preserves complete extracted assets'
    $script:EmbeddedBundleBase64='invalid base64'; $script:Calls=@(); $failed=$false
    try { Deploy-WslAssets 'manage.sh' | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:Calls.Count -eq 0) 'Corrupt embedded encoding fails before any WSL operation'
    # Real terminal-runner generation; Start-Process is stubbed, and generated native executable is harmless.
    Invoke-Expression (($functions | Where-Object Name -eq 'Start-InstallTerminal' | Select-Object -First 1).Extent.Text)
    function Start-Process {param($FilePath,$ArgumentList,[switch]$PassThru,$ErrorAction) $script:SpawnArgs=$ArgumentList; return [pscustomobject]@{Mock=$true} }
    $script:TerminalTimer=[pscustomobject]@{}; $script:TerminalTimer | Add-Member ScriptMethod Start {}
    $mockExe=Join-Path $temp 'mock-wsl.exe'
    Add-Type -TypeDefinition 'using System; using System.IO; public class MockManagementWsl { public static int Main(string[] args) { File.WriteAllLines(Environment.GetEnvironmentVariable("HERMES_MGMT_ARGV"), args); return Int32.Parse(Environment.GetEnvironmentVariable("HERMES_MGMT_EXIT")); } }' -OutputAssembly $mockExe -OutputType ConsoleApplication
    $script:WslExe=$mockExe; $script:WslUser='alice'; $script:TerminalLabel='升级'; $script:TerminalAction='upgrade'; $script:InstallShellCommand="exec bash '/home/alice/hermes-installer-assets.ABCD/manage.sh' upgrade </dev/tty"
    Start-InstallTerminal
    $runner=Join-Path $script:TerminalDirectory 'run.ps1'
    $runnerText=[IO.File]::ReadAllText($runner)
    $runnerBytes=[IO.File]::ReadAllBytes($runner)
    $env:HERMES_MGMT_ARGV=Join-Path $temp 'argv.txt'; $env:HERMES_MGMT_EXIT='29'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ('function Read-Host { param($Prompt) return '''' }; & ''' + $runner.Replace("'","''") + '''; exit $LASTEXITCODE') | Out-Null
    $runnerExit=$LASTEXITCODE
    $result=[IO.File]::ReadAllText((Join-Path $script:TerminalDirectory 'result.txt'))
    $argv=[IO.File]::ReadAllLines($env:HERMES_MGMT_ARGV)
    Assert ($runnerExit -eq 29 -and $result -eq '29') 'Actual runner publishes real native exit 29 atomically and propagates it to its PowerShell process'
    Assert ($argv[2] -eq '-u' -and $argv[3] -eq 'alice' -and $argv[4] -eq '--exec' -and $argv[7] -like 'echo * | base64 -d | bash') 'Actual runner invokes explicit WSL user and Base64 bootstrap as one native argument'
    Assert ([BitConverter]::ToString($runnerBytes[0..2]) -eq 'EF-BB-BF' -and $runnerText -match '升级脚本' -and $runnerText -notmatch 'cmd.exe|完成，可关闭') 'Management runner retains PS5.1 BOM and action-specific real-result message'
    Remove-Item -LiteralPath $script:TerminalDirectory -Recurse -Force; $script:Terminal=$null
    # Run the actual GUI timer callback with fake process/controls for every management action/outcome.
    $tickCall=$ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'add_Tick'},$true) | Select-Object -First 1
    $tick=[scriptblock]::Create($tickCall.Arguments[0].ScriptBlock.Extent.Text.TrimStart('{').TrimEnd('}'))
    foreach ($action in @('renew','upgrade','status')) {
        foreach ($outcome in @('0','23','closed','running','invalid')) {
            $dir=Join-Path $temp ($action+'-'+$outcome); [void](New-Item -ItemType Directory $dir)
            if ($outcome -in @('0','23','invalid')) { [IO.File]::WriteAllText((Join-Path $dir 'result.txt'),$outcome) }
            $script:TerminalDirectory=$dir; $script:Terminal=[pscustomobject]@{HasExited=($outcome -ne 'running')}; $script:Terminal | Add-Member ScriptMethod Dispose {}
            $script:TerminalTimer=[pscustomobject]@{}; $script:TerminalTimer | Add-Member ScriptMethod Stop {}
            $script:TerminalAction=$action; $script:TerminalLabel=$labels[$action]; $script:Busy=$true; $script:InstallComplete=$false; $bar.Value=75; $script:Logs=@()
            & $tick
            if ($outcome -eq 'running') { Assert ($script:Busy -and $bar.Value -eq 75) "$action running terminal remains pending" }
            elseif ($outcome -eq '0') { Assert (-not $script:Busy -and $bar.Value -eq 100 -and -not $script:InstallComplete -and $script:Phase -match ([regex]::Escape($labels[$action])+'.*exit 0')) "$action exit 0 shows its own completion label without claiming installation completion" }
            else { Assert (-not $script:Busy -and $bar.Value -eq 75 -and -not $script:InstallComplete -and $script:Phase.StartsWith($labels[$action])) "$action $outcome reports action-specific failure without false success" }
        }
    }
    $bytes=[IO.File]::ReadAllBytes($installer)
    Assert ([BitConverter]::ToString($bytes[0..2]) -eq 'EF-BB-BF' -and $ast.Extent.Text -match 'v1.3.0') 'Installer keeps UTF8 BOM and version v1.3.0 title'
    "TOTAL PASSED=$script:Passed"
    $global:LASTEXITCODE=0
} finally {
    Remove-Item Env:\HERMES_MGMT_ARGV,Env:\HERMES_MGMT_EXIT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    if ($script:TerminalDirectory -and (Test-Path -LiteralPath $script:TerminalDirectory)) { Remove-Item -LiteralPath $script:TerminalDirectory -Recurse -Force -ErrorAction SilentlyContinue }
}
