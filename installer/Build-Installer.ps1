#requires -Version 5.1
param(
    [string]$OutputFile = (Join-Path $PSScriptRoot 'HermesInstaller-v1.3.0.exe'),
    [string]$Version = '1.3.0.0'
)
$ErrorActionPreference = 'Stop'
Import-Module ps2exe -ErrorAction Stop
$repo = Split-Path $PSScriptRoot -Parent
$staging = Join-Path ([IO.Path]::GetTempPath()) ('hermes-build-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $staging)
try {
    $bundle = Join-Path $staging 'assets.tar.gz'
    & tar.exe -czf $bundle -C $repo install.sh manage.sh lib/hermes_runtime.py patches/xtool-watch-1.24.0.patch watch-device-helper/watch_device.py watch-device-helper/watch_connection.py
    if ($LASTEXITCODE -ne 0) { throw 'Bundling installation assets failed' }
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'HermesInstaller.ps1'), [Text.Encoding]::UTF8)
    $placeholder = '$script:EmbeddedBundleBase64 = '''''
    if (-not $source.Contains($placeholder)) { throw 'Embedded assets placeholder is missing' }
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($bundle))
    $source = $source.Replace($placeholder, ('$script:EmbeddedBundleBase64 = ''' + $encoded + ''''))
    $compiledSource = Join-Path $staging 'HermesInstaller.ps1'
    # Windows PowerShell 5.1 needs a BOM for reliable Chinese source decoding.
    [IO.File]::WriteAllText($compiledSource, $source, (New-Object Text.UTF8Encoding($true)))
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($compiledSource, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
    Invoke-PS2EXE -InputFile $compiledSource -OutputFile $OutputFile -NoConsole -x64 -STA -Title 'Hermes Watch Installer' -Version $Version -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $OutputFile)) { throw 'Compiler did not produce an EXE' }
    $built = Get-Item -LiteralPath $OutputFile
    if ($built.VersionInfo.FileVersion -ne $Version) { throw 'Unexpected output EXE version' }
    Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
