# Optional integration check: clicks ONLY the read-only Status action in this test EXE.
# It deploys temporary script assets into the current WSL account, but never signs/installs.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class HermesStatusClick { [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l); }'
$exe = Join-Path $PSScriptRoot '..\installer\HermesInstaller-v1.3.0.exe'
$p = Start-Process -FilePath $exe -PassThru
$children = @()
try {
    $window = $null
    $statusLabel = [string][char]0x72b6 + [char]0x6001
    $status = $null
    for ($attempt=0; $attempt -lt 25 -and -not $status; $attempt++) {
        Start-Sleep -Milliseconds 200
        if ($p.HasExited) { throw 'Test EXE exited before the status action' }
        $condition = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
        $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
        foreach ($item in $windows) { if ($item.Current.Name -like 'HermesEnabler*v1.3.0') { $window=$item; break } }
        if ($window) {
            $items=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
            foreach ($item in $items) { if ($item.Current.Name -ceq $statusLabel) { $status=$item; break } }
        }
    }
    if (-not $status -or -not $status.Current.NativeWindowHandle) { throw 'Status control handle missing' }
    [void][HermesStatusClick]::PostMessage([IntPtr]$status.Current.NativeWindowHandle,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
    $result=$null
    for ($attempt=0; $attempt -lt 180; $attempt++) {
        Start-Sleep -Milliseconds 500
        if ($p.HasExited) { throw 'Test GUI exited during status processing' }
        $items=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
        $text=($items | ForEach-Object {$_.Current.Name}) -join "`n"
        if ($text -match '\(exit ([0-9]+)\)') { $result=[int]$matches[1]; break }
    }
    if ($null -eq $result) { throw ('Status did not report a real terminal exit: ' + $text) }
    $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $p.Id) | Select-Object -ExpandProperty ProcessId)
    if (-not $children.Count) { throw ('A preparation error occurred before the real terminal started: ' + $text) }
    Write-Output ('PASS: compiled GUI launched real WSL Status and received terminal exit ' + $result)
    if ($result -ne 0) { Write-Output 'Device connection or status failed; GUI correctly did not report success. Inspect terminal output for the current environment.' }
} finally {
    if (-not $children.Count) { $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $p.Id) -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessId) }
    foreach ($childId in $children) { Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue }
    if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
    $p.Dispose()
}
