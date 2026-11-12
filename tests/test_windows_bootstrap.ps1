$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\installer\HermesInstaller.ps1'
$errors = $null; $tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Parser errors' }
$functions = $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $true)
foreach ($name in @('Invoke-Native','ConvertTo-BashBootstrap','Invoke-WslScript','Get-LaunchCommand','Test-WslDistro','Start-Install','Set-Busy','Resolve-WslUser','Deploy-WslAssets')) {
    $node = $functions | Where-Object Name -eq $name | Select-Object -First 1
    Invoke-Expression $node.Extent.Text
}
$script:Passed = 0
function Assert($condition, $message) { if (-not $condition) { throw $message }; $script:Passed++; Write-Output "PASS $message" }
$sample = 'awk -F: ''$3>=1000 {print $1}'' /etc/passwd; printf "%s" "$HOME/a b"'
$bootstrap = ConvertTo-BashBootstrap $sample
$decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($bootstrap -split ' ')[1]))
Assert ($decoded -ceq $sample) 'Bash dollar signs and quotes survive exact Base64 round trip'
$script:ScriptPath = 'C:\test space\installer.ps1'
$launch = Get-LaunchCommand $true
Assert ($launch.Arguments -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\test space\installer.ps1" -resume') 'Script elevation and RunOnce quote spaced PS1 and preserve resume'
$script:ScriptPath = $null; $script:ExePath = 'C:\test space\installer.exe'
$launch = Get-LaunchCommand $false
Assert ($launch.File -eq $script:ExePath -and $launch.Arguments -eq '') 'Packaged executable launch path'
# Compile a harmless argv/exit-code echo executable. Never invokes WSL or installation.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('HermesTests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
try {
    $echoExe = Join-Path $temp 'argv.exe'
    Add-Type -TypeDefinition 'using System; public class EchoArgs { public static int Main(string[] args) { foreach(string a in args) Console.WriteLine(Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(a))); return Environment.GetEnvironmentVariable("HERMES_TEST_FAIL") == "1" ? 37 : 0; } }' -OutputAssembly $echoExe -OutputType ConsoleApplication
    $native = @(Invoke-Native $echoExe @('-d', 'Distro with spaces', '--exec', 'bash', '-c', $bootstrap))
    $nativeDecoded = @($native | ForEach-Object {[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$_))})
    Assert ($nativeDecoded.Count -eq 6 -and $nativeDecoded[1] -ceq 'Distro with spaces' -and $nativeDecoded[5] -ceq $bootstrap) 'Real Windows native argv preserves distro spaces and Bash bootstrap as one argument'
    $env:HERMES_TEST_FAIL = '1'
    $failed = $false
    try { Invoke-Native $echoExe @('test') | Out-Null } catch { $failed = $_ -match 'exit 37' }
    Assert $failed 'Native nonzero exit 37 raises an error'
    Remove-Item Env:\HERMES_TEST_FAIL
    $script:WslDistro = 'Ubuntu-24.04'
    $script:BaseUrl = 'https://example.invalid/releases/download'
    function Invoke-Native { param($exe,$arguments) return $script:MockList }
    $script:MockList = "Ubuntu-24.04-preview`nDebian"
    Assert (-not (Test-WslDistro)) 'Distro lookup rejects substring match'
    $script:MockList = "U`0b`0u`0n`0t`0u`0-`02`04`0.`00`04`0`r`nDebian"
    Assert (Test-WslDistro) 'Distro lookup accepts exact name with WSL UTF16 NUL output'
    function Write-Log {param($msg,$color) $script:Logs += [string]$msg}
    function Set-Phase {param($text) $script:Phase = $text}
    function Test-Admin {return $true}
    function Get-Command {param($Name,$ErrorAction) return @{Source='Mock-Wsl'}}
    function Get-Service {param($Name,$ErrorAction) return @{Status='Running'}}
    function Test-UsbMuxd {return $true}
    function Ensure-WslUsbMuxBridge { if ($script:Scenario -eq 'bridgefail') { throw 'mock usbmux bridge unavailable' } }
    function Test-WslDistro {return $true}
    function Invoke-WslScript {param($text,$user) $script:WslCalls++; if ($script:WslCalls -eq 1) { if ($script:Scenario -eq 'baduser') {return 'root; echo injected'}; return 'testuser' }; if ($script:Scenario -eq 'download') {throw 'mock curl exit 22 HTTP 404'}; return '/home/testuser/hermes-installer-assets.ABCD/install.sh' }
    function Start-InstallTerminal { $script:Launches++; $script:Terminal = @{Mock=$true} }
    foreach ($scenario in @('download','baduser','bridgefail','success')) {
        $script:Scenario=$scenario; $script:Busy=$false; $script:Terminal=$null; $script:TerminalDirectory=$null; $script:WslCalls=0; $script:Launches=0; $script:Logs=@(); $script:EmbeddedBundleBase64=''
        $btn = [pscustomobject]@{Enabled=$true;Text='start'}
        $btnRenew = [pscustomobject]@{Enabled=$true}; $btnUpgrade = [pscustomobject]@{Enabled=$true}; $btnStatus = [pscustomobject]@{Enabled=$true}
        $bar = [pscustomobject]@{Value=0}
        Start-Install
        if ($scenario -eq 'success') {
            Assert ($script:Launches -eq 1 -and $bar.Value -eq 75 -and $script:Busy -and -not $btnRenew.Enabled -and -not $script:InstallComplete) 'Successful preparation waits at 75 percent and blocks concurrent actions'
            Start-Install
            Assert ($script:Launches -eq 1) 'Busy installation rejects reentrant start'
        } else {
            Assert ($script:Launches -eq 0 -and -not $script:Busy -and $btn.Enabled -and $bar.Value -lt 100) "$scenario failure stops before terminal and restores retry controls"
        }
    }
    # Embedded resources are written only to an isolated Windows temp file; WSL unpack is mocked.
    foreach ($bundleScenario in @('success','failure')) {
        $script:Busy=$false; $script:Terminal=$null; $script:TerminalDirectory=$null; $script:WslCalls=0; $script:Launches=0
        $script:EmbeddedBundleBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('mock archive'))
        $script:BundleScenario=$bundleScenario
        function Invoke-WslScript {param($text,$user) $script:WslCalls++; if ($script:WslCalls -eq 1) {return 'testuser'}; if ($script:BundleScenario -eq 'failure') {throw 'mock corrupt archive'}; return '/home/testuser/hermes-installer-assets.ABCD/install.sh' }
        Start-Install
        if ($bundleScenario -eq 'success') { Assert ($script:Launches -eq 1 -and $script:InstallShellCommand -eq "exec bash '/home/testuser/hermes-installer-assets.ABCD/install.sh' </dev/tty") 'Embedded bundle launches the validated extracted path' }
        else { Assert ($script:Launches -eq 0 -and -not $script:Busy -and $bar.Value -lt 100) 'Embedded bundle extraction failure blocks terminal launch' }
    }
    # Nonzero WSL --install exits before any RunOnce/reboot call. Native command is a function stub.
    $script:Busy=$false; $script:Terminal=$null; $script:WslCalls=0; $script:Launches=0
    Invoke-Expression (($functions | Where-Object Name -eq 'Test-WslDistro' | Select-Object -First 1).Extent.Text)
    function Invoke-Native {param($exe,$arguments) throw 'mock fresh WSL list failure'}
    function Mock-Wsl { $global:LASTEXITCODE=5; return 'mock WSL install failure' }
    Start-Install
    Assert ($script:Launches -eq 0 -and $script:WslCalls -eq 0 -and -not $script:Busy -and ($script:Logs -join '') -match 'exit 5') 'WSL install exit 5 stops before user/download/restart'
    # Build the real terminal runner but stub process launch; inspect generated PS5.1 AST and encoding.
    Invoke-Expression (($functions | Where-Object Name -eq 'Start-InstallTerminal' | Select-Object -First 1).Extent.Text)
    function Start-Process {param($FilePath,$ArgumentList,[switch]$PassThru,$ErrorAction) $script:SpawnArgs=$ArgumentList; return [pscustomobject]@{Mock=$true} }
    $script:WslExe='C:\Program Files\Mock WSL\wsl.exe'
    $script:TerminalTimer=[pscustomobject]@{}
    $script:TerminalTimer | Add-Member ScriptMethod Start {}
    Start-InstallTerminal
    $runnerFile=Join-Path $script:TerminalDirectory 'run.ps1'
    $runnerErrors=$null; $runnerTokens=$null
    [void][Management.Automation.Language.Parser]::ParseFile($runnerFile,[ref]$runnerTokens,[ref]$runnerErrors)
    $runnerBytes=[IO.File]::ReadAllBytes($runnerFile)
    Assert ($runnerErrors.Count -eq 0 -and [BitConverter]::ToString($runnerBytes[0..2]) -eq 'EF-BB-BF' -and $script:SpawnArgs -match '-File "[^"]+"') 'Interactive terminal runner parses in PS5.1 and uses UTF8 BOM plus quoted File argument'
    Remove-Item -LiteralPath $script:TerminalDirectory -Recurse -Force
    $script:Terminal=$null
    # Execute the actual GUI timer handler against fake controls and fake process objects.
    $tickCall = $ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'add_Tick'},$true) | Select-Object -First 1
    $tick = [scriptblock]::Create($tickCall.Arguments[0].ScriptBlock.Extent.Text.TrimStart('{').TrimEnd('}'))
    foreach ($outcome in @('0','23','closed','running')) {
        $resultDir = Join-Path $temp $outcome; [void](New-Item -ItemType Directory $resultDir)
        if ($outcome -in @('0','23')) { [IO.File]::WriteAllText((Join-Path $resultDir 'result.txt'),$outcome) }
        $script:TerminalDirectory=$resultDir
        $script:Terminal=[pscustomobject]@{HasExited=($outcome -ne 'running')}
        $script:Terminal | Add-Member ScriptMethod Dispose {}
        $script:TerminalTimer=[pscustomobject]@{}
        $script:TerminalTimer | Add-Member ScriptMethod Stop {}
        $script:InstallComplete=$false; $script:Busy=$true; $bar.Value=75
        & $tick
        if ($outcome -eq '0') { Assert ($script:InstallComplete -and $bar.Value -eq 100 -and -not $script:Busy) 'Terminal exit 0 alone enables completion and 100 percent' }
        elseif ($outcome -eq 'running') { Assert ($script:Busy -and $bar.Value -eq 75 -and -not $script:InstallComplete) 'Running terminal stays pending' }
        else { Assert (-not $script:InstallComplete -and $bar.Value -eq 75 -and -not $script:Busy -and $btn.Text -eq '重试') "Terminal $outcome yields retry without false success" }
    }
    Assert ($ast.Extent.Text -notmatch '(?m)^\s*wsl\.exe --shutdown|rm -f /etc/wsl.conf|> /etc/wsl.conf|\\\$3') 'First installation no longer shuts down WSL, destroys config, or backslash-escapes awk dollars'
    # Bridge tests stub every Windows networking mutation and every WSL call.
    Invoke-Expression (($functions | Where-Object Name -eq 'Get-WslUsbMuxProbe' | Select-Object -First 1).Extent.Text)
    function Invoke-WslScript {param($text,$user) $script:ProbeUser=$user; return $script:ProbeOutput}
    $script:ProbeOutput='172.27.128.1|172.27.135.11|0|0'
    $probe=Get-WslUsbMuxProbe
    Assert ($probe.Gateway -eq '172.27.128.1' -and $probe.Guest -eq '172.27.135.11' -and $script:ProbeUser -eq 'root') 'Bridge probe parses IPv4 addresses and explicitly runs as WSL root'
    $script:ProbeOutput='||0|1'
    $probe=Get-WslUsbMuxProbe
    Assert $probe.LocalReachable 'Mirrored localhost reachability works even without an IPv4 gateway'
    $script:ProbeOutput='1.2.3.4|not-an-ip|0|0'
    $failed=$false; try {Get-WslUsbMuxProbe | Out-Null} catch {$failed=$true}
    Assert $failed 'Bridge probe rejects malformed guest IPv4 before configuration'
    Invoke-Expression (($functions | Where-Object Name -eq 'Ensure-WslUsbMuxBridge' | Select-Object -First 1).Extent.Text)
    function Get-WslUsbMuxProbe {
        $script:ProbeCalls++
        return [pscustomobject]@{Gateway='172.27.128.1';Guest='172.27.135.11';GatewayReachable=($script:BridgeScenario -eq 'connected' -or ($script:ProbeCalls -gt 1 -and $script:BridgeScenario -ne 'retestfail'));LocalReachable=($script:BridgeScenario -eq 'mirrored')}
    }
    function Get-NetIPAddress {param($AddressFamily,$IPAddress,$ErrorAction) if ($script:BridgeScenario -ne 'foreigngateway') {return @{IPAddress='172.27.128.1'}} }
    function Test-UsbMuxd {return $script:BridgeScenario -ne 'nolocalservice'}
    function Invoke-Native {
        param($exe,$arguments)
        if ($arguments -contains 'show') {
            if ($script:BridgeScenario -eq 'conflict') {return '172.27.128.1 27015 192.0.2.99 8080'}
            if ($script:BridgeScenario -eq 'wildcard') {return '0.0.0.0 27015 127.0.0.1 27015'}
            if ($script:BridgeScenario -eq 'existing') {return '172.27.128.1 27015 127.0.0.1 27015'}
            return @()
        }
        $script:ProxyAdds++
        $script:ProxyArgs=$arguments
        if ($script:BridgeScenario -eq 'netshfail') {throw 'mock netsh exit 1'}
    }
    function Get-NetFirewallRule {param($Name,$ErrorAction) if ($script:BridgeScenario -eq 'firewallconflict') {return @{Enabled='False';Direction='Inbound';Action='Allow'}} }
    function Get-NetFirewallAddressFilter {param([Parameter(ValueFromPipeline=$true)]$InputObject,$ErrorAction) process {return @{LocalAddress='Any';RemoteAddress='Any'}} }
    function Get-NetFirewallPortFilter {param([Parameter(ValueFromPipeline=$true)]$InputObject,$ErrorAction) process {return @{LocalPort='27015';Protocol='TCP'}} }
    function Get-Service {param($Name,$ErrorAction) return @{Status='Stopped'}}
    function Start-Service {param($Name,$ErrorAction) $script:ServiceStarts++}
    function Start-Sleep {param($Milliseconds)}
    function New-NetFirewallRule {param($Name,$DisplayName,$Direction,$Action,$Enabled,$Profile,$Protocol,$LocalAddress,$RemoteAddress,$LocalPort,$ErrorAction) $script:FirewallAdds++; $script:FirewallArgs=@{LocalAddress=$LocalAddress;RemoteAddress=$RemoteAddress;LocalPort=$LocalPort;Protocol=$Protocol;Direction=$Direction;Action=$Action}}
    foreach ($bridgeScenario in @('connected','mirrored','new','existing','conflict','wildcard','foreigngateway','nolocalservice','firewallconflict','netshfail','retestfail')) {
        $script:BridgeScenario=$bridgeScenario; $script:ProbeCalls=0; $script:ProxyAdds=0; $script:FirewallAdds=0; $script:ServiceStarts=0; $failure=$null
        try {Ensure-WslUsbMuxBridge} catch {$failure=[string]$_}
        if ($bridgeScenario -in @('connected','mirrored')) {
            Assert (-not $failure -and $script:ProxyAdds -eq 0 -and $script:FirewallAdds -eq 0 -and $script:ServiceStarts -eq 0) "$bridgeScenario reachable path preserves Windows network configuration"
        } elseif ($bridgeScenario -in @('new','existing')) {
            $expectedAdds=if($bridgeScenario -eq 'new'){1}else{0}
            Assert (-not $failure -and $script:ProxyAdds -eq $expectedAdds -and $script:FirewallAdds -eq 1 -and $script:ProbeCalls -eq 2 -and $script:ServiceStarts -eq 1 -and $script:FirewallArgs.LocalAddress -eq '172.27.128.1' -and $script:FirewallArgs.RemoteAddress -eq '172.27.135.11' -and $script:FirewallArgs.LocalPort -eq 27015 -and $script:FirewallArgs.Protocol -eq 'TCP') "$bridgeScenario bridge limits firewall to gateway and single WSL guest then verifies connectivity"
            if ($bridgeScenario -eq 'new') {Assert ($script:ProxyArgs -contains 'listenaddress=172.27.128.1' -and $script:ProxyArgs -contains 'connectaddress=127.0.0.1' -and $script:ProxyArgs -contains 'connectport=27015' -and -not ($script:ProxyArgs -contains 'listenaddress=0.0.0.0')) 'New portproxy binds only Windows gateway and forwards to loopback usbmux'}
        } elseif ($bridgeScenario -in @('conflict','wildcard','foreigngateway','nolocalservice','firewallconflict')) {
            Assert ($failure -and $script:ProxyAdds -eq 0 -and $script:FirewallAdds -eq 0 -and $script:ServiceStarts -eq 0) "$bridgeScenario fails before any Windows networking mutation"
        } elseif ($bridgeScenario -eq 'netshfail') {
            Assert ($failure -match 'netsh exit 1' -and $script:FirewallAdds -eq 0) 'Portproxy command failure blocks firewall creation and installation'
        } else {
            Assert ($failure -match '27015' -and $script:ProbeCalls -eq 4) 'Post-configuration connection failure is reported after bounded rechecks'
        }
    }
    "TOTAL PASSED=$script:Passed"
    # The intentional native failure probe must not leak its exit code to the caller.
    $global:LASTEXITCODE = 0
} finally {
    Remove-Item Env:\HERMES_TEST_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
