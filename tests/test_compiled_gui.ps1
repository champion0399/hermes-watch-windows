# Run only the specified test EXE; never clicks installation or management buttons.
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\installer\HermesInstaller-v1.3.0.exe'),
    [string]$ExpectedVersion = '1.3.0.0'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$p = Start-Process -FilePath $exe -PassThru
try {
    $window = $null
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        Start-Sleep -Milliseconds 400
        if ($p.HasExited) { throw ('GUI exited prematurely: ' + $p.ExitCode) }
        $condition = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
        $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $condition)
        foreach ($candidate in $windows) {
            if ($candidate.Current.Name -like 'HermesEnabler*') { $window = $candidate; break }
        }
        if ($window) { break }
    }
    if (-not $window) { throw 'Main installer window was not found; a live process alone is not a passing smoke test' }
    # Legacy WinForms controls may be exposed as UIA Pane, not Button.
    $startLabel = [string][char]0x5f00 + [char]0x59cb + [char]0x5b89 + [char]0x88c5
    $startControl = $null
    for ($attempt = 0; $attempt -lt 15 -and -not $startControl; $attempt++) {
        $all = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
        foreach ($item in $all) { if ($item.Current.Name -ceq $startLabel) { $startControl = $item; break } }
        if (-not $startControl) { Start-Sleep -Milliseconds 400 }
    }
    if (-not $startControl -or -not $startControl.Current.IsEnabled) { throw 'Enabled first-install control was not found' }
    if ($all.Count -lt 7) { throw 'Installer controls are incomplete' }
    $renewLabel = [string][char]0x7eed + [char]0x7b7e + ' (7' + [char]0x5929 + ')'
    $upgradeLabel = [string][char]0x5347 + [char]0x7ea7 + [char]0x6700 + [char]0x65b0 + [char]0x7248
    $statusLabel = [string][char]0x72b6 + [char]0x6001
    foreach ($label in @($renewLabel, $upgradeLabel, $statusLabel)) {
        $found = $false
        foreach ($item in $all) { if ($item.Current.Name -ceq $label -and $item.Current.IsEnabled) { $found = $true; break } }
        if (-not $found) { throw 'An enabled management control is missing' }
    }
    $displayVersion = ($ExpectedVersion.Split('.')[0..2] -join '.')
    if ($window.Current.Name -notlike ('*v' + $displayVersion)) { throw 'Window version label is missing' }
    $version = (Get-Item $exe).VersionInfo.FileVersion
    if ($version -ne $ExpectedVersion) { throw ('Unexpected EXE version: ' + $version) }
    Write-Output ('PASS: main window and four enabled action controls are visible; descendant controls=' + $all.Count)
    Write-Output ('PASS: EXE and window version=' + $displayVersion)
} finally {
    if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
    $p.Dispose()
}
