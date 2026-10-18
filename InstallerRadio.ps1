function Get-AsusRadioConfig {
    $registration = 'Registry::HKEY_CLASSES_ROOT\CLSID\{BAE3934B-8A6A-4BFB-81BD-3FC599A1BAF1}\InprocServer32'
    if (-not (Test-Path -LiteralPath $registration)) { return $null }
    $dll = [Environment]::ExpandEnvironmentVariables((Get-Item -LiteralPath $registration).GetValue('')).Trim('"')
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { return $null }
    $folder = Split-Path -Parent $dll
    $config = Join-Path $folder 'shell.nss'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return $null }
    $version = (Get-Item -LiteralPath $dll).VersionInfo
    if ($version.FileMajorPart -lt 1 -or ($version.FileMajorPart -eq 1 -and $version.FileMinorPart -lt 9)) {
        throw 'Radio selection needs Nilesoft Shell 1.9 or later.'
    }
    $rule = Join-Path $folder 'imports\asus-mode-radio.nss'
    if ((Test-Path -LiteralPath $rule) -and
        [IO.File]::ReadAllText($rule) -notlike '// ASUS Mode Shortcuts: radio selection*') {
        throw 'An unrelated asus-mode-radio.nss file already exists.'
    }
    return $config
}

function Install-AsusRadioMenu {
    param([string]$Config, [string]$SourceFolder, [string]$BackupFolder)
    if (-not $Config) {
        Write-Output 'Nilesoft Shell not found: the classic menu keeps its text selection marker.'
        return
    }
    $imports = Join-Path (Split-Path -Parent $Config) 'imports'
    New-Item -ItemType Directory -Path $imports -Force | Out-Null
    $source = Join-Path $SourceFolder 'asus-mode-radio.nss'
    $destination = Join-Path $imports 'asus-mode-radio.nss'
    $content = [IO.File]::ReadAllText($Config)
    # Keep one package import, retaining every unrelated existing setting.
    $import = "import 'imports/asus-mode-radio.nss'"
    $hasImport = $content -match '(?im)^\s*import\s+[''"]imports[/\\]asus-mode-radio\.nss[''"]\s*$'
    if (-not $hasImport) {
        $backup = Join-Path $BackupFolder ('shell-before-radio-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.nss')
        Copy-Item -LiteralPath $Config -Destination $backup
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
    if (-not $hasImport) {
        [IO.File]::WriteAllText($Config, ($content.TrimEnd() + "`r`n`r`n" + $import + "`r`n"), [Text.UTF8Encoding]::new($true))
    }
    Write-Output 'Radio selection installed. Hold Ctrl while opening the desktop menu once to reload Nilesoft.'
}
