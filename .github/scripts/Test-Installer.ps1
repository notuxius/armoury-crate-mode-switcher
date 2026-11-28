param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$UnsupportedHardware
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\..'
foreach ($script in Get-ChildItem -LiteralPath $source -Filter '*.ps1' -File) {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
}

$installer = Get-Item -LiteralPath (Join-Path $source "dist\Armoury-Crate-Mode-Switcher-v$Version-Setup.exe")
if ($installer.VersionInfo.ProductVersion.Trim() -ne $Version) {
    throw "Installer ProductVersion does not match $Version."
}
$log = Join-Path $env:TEMP ('armoury-setup-test-' + [Guid]::NewGuid().ToString('N') + '.log')
if ($UnsupportedHardware -and (Get-CimInstance Win32_ComputerSystem).Manufacturer -match 'ASUS|ASUSTeK') {
    throw 'Run the unsupported-hardware test on a non-ASUS Windows runner.'
}
$position = if ($UnsupportedHardware) { 'Bottom' } else { 'Invalid' }
$expected = if ($UnsupportedHardware) {
    'This package requires 64-bit Windows on an ASUS computer'
} else {
    'MenuPosition must be Auto, Top, or Bottom.'
}
$arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /MenuPosition=' + $position + ' /LOG="' + $log + '"'
$result = Start-Process -FilePath $installer.FullName -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($result.ExitCode -ne 7 -or -not (Select-String -LiteralPath $log -SimpleMatch $expected -Quiet)) {
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Out-Host }
    throw "Setup did not reject the test input as expected. Exit code $($result.ExitCode)."
}
Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256

. (Join-Path $source 'InstallerRadio.ps1')
$fixture = Join-Path $env:TEMP ('armoury-radio-test-' + [Guid]::NewGuid().ToString('N'))
$imports = Join-Path $fixture 'imports'
New-Item -ItemType Directory -Path $imports | Out-Null
$config = Join-Path $fixture 'shell.nss'
$rule = Join-Path $imports 'asus-mode-radio.nss'
$other = "import 'imports/keep.nss'"
$import = "import 'imports/asus-mode-radio.nss'"
$remaining = $other + [Environment]::NewLine
$original = $remaining + $import + [Environment]::NewLine
$utf8 = [Text.UTF8Encoding]::new($true)
[IO.File]::WriteAllText($config, $original, $utf8)
[IO.File]::WriteAllText($rule, '// An unrelated rule')
Remove-AsusRadioMenu -Config $config -BackupFolder $fixture
if ([IO.File]::ReadAllText($config) -cne $original -or -not (Test-Path -LiteralPath $rule)) {
    throw 'Uninstall modified an unrelated rule or its import.'
}
[IO.File]::WriteAllText($rule, '// ASUS Mode Shortcuts: radio selection')
Remove-AsusRadioMenu -Config $config -BackupFolder $fixture
$backup = Get-ChildItem -LiteralPath $fixture -Filter 'shell-before-uninstall-*.nss' -File
if ([IO.File]::ReadAllText($config) -cne $remaining -or
    (Test-Path -LiteralPath $rule) -or @($backup).Count -ne 1 -or
    [IO.File]::ReadAllText($backup.FullName) -cne $original) {
    throw 'Uninstall did not back up the config and remove only the package import and rule.'
}
Remove-Item -LiteralPath $config, $backup.FullName, $log
[IO.Directory]::Delete($imports)
[IO.Directory]::Delete($fixture)
Write-Output 'Installer version, preflight refusal, and Nilesoft cleanup checks passed.'
