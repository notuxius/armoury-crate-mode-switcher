# Ketarin runs this as its PowerShell post-download command, with $app provided.
# Extraction only: installing remains a separate Ketarin action.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Path]::GetFullPath($app.PreviousLocation)
$folder = [IO.Path]::GetDirectoryName($archive)
$destination = Join-Path $folder 'Package'
$previous = Join-Path $folder 'Package.previous'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$stage = Join-Path $tempRoot ('extract-' + [Guid]::NewGuid().ToString('N'))

function Assert-PackagePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($full)
    $name = [IO.Path]::GetFileName($full)
    if (-not (($parent -eq $folder -and $name -in @('Package','Package.previous')) -or
              ($parent -eq $tempRoot -and $full -eq $stage -and $name -match '^extract-[0-9a-f]{32}$'))) {
        throw 'Refusing to modify an unexpected package path.'
    }
    if (Test-Path -LiteralPath $full) {
        $items = @(Get-Item -LiteralPath $full) + @(Get-ChildItem -LiteralPath $full -Recurse -Force)
        if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            throw 'The package folder must not contain a symbolic link or junction.'
        }
    }
}

# Mirror individual files so Drive can track changes under stable package directories.
function Copy-PackageTree([string]$From, [string]$To) {
    Assert-PackagePath $To
    $marker = Join-Path $To 'package.commit'
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
    & "$env:SystemRoot\System32\robocopy.exe" $From $To /E /PURGE /IS /IT /XJ /R:1 /W:1 /XF desktop.ini package.commit /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Package copy to $To failed (robocopy $LASTEXITCODE)." }
    Copy-Item -LiteralPath (Join-Path $From 'package.commit') -Destination $marker -Force
}

Assert-PackagePath $destination
Assert-PackagePath $previous
Assert-PackagePath $stage
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $expectedCommit = $app.Variables['version'].CachedContent
    if ($expectedCommit -notmatch '^[0-9a-f]{40}$') { throw 'Ketarin did not resolve a valid GitHub commit.' }
    $activeArchive = $archive
    $probe = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $downloadRoot = @($probe.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Select-Object -Unique)
    } finally { $probe.Dispose() }
    if ($downloadRoot.Count -ne 1 -or $downloadRoot[0] -ne ('armoury-crate-mode-switcher-' + $expectedCommit)) {
        # Ketarin may resolve the download URL before refreshing its version indicator.
        # Fetch the exact detected commit if main changed between those two requests.
        $activeArchive = Join-Path $stage 'detected-commit.zip'
        $client = New-Object Net.WebClient
        try {
            $client.Headers['User-Agent'] = 'ArmouryCrateModeSwitcher-Ketarin'
            $client.DownloadFile(('https://codeload.github.com/notuxius/armoury-crate-mode-switcher/zip/' + $expectedCommit), $activeArchive)
        } finally { $client.Dispose() }
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($activeArchive)
    try {
        $roots = @($zip.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Select-Object -Unique)
        if ($roots.Count -ne 1 -or $roots[0] -notmatch '^armoury-crate-mode-switcher-([0-9a-f]{40})$') {
            throw 'The download is not a commit archive from armoury-crate-mode-switcher.'
        }
        $commit = $Matches[1]
        if ($commit -ne $expectedCommit) { throw 'The downloaded archive does not match the detected GitHub commit.' }
        $stagePrefix = $stage.TrimEnd('\') + '\'
        foreach ($entry in $zip.Entries) {
            $entryPath = [IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
            if (-not $entryPath.StartsWith($stagePrefix, [StringComparison]::OrdinalIgnoreCase) -or
                $entry.FullName.Contains(':') -or $entry.FullName.Contains('\')) {
                throw 'The archive contains an invalid file path.'
            }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($activeArchive, $stage)
    $source = Join-Path $stage $roots[0]
    foreach ($required in @('Setup.ps1','Build.ps1','AsusMode.cs','app.manifest','InstallerMenu.ps1','InstallerRadio.ps1','asus-mode-radio.nss','icons\Silent.png','icons\Performance.png','icons\Turbo.png')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) {
            throw ('The package is incomplete: ' + $required)
        }
    }
    [IO.File]::WriteAllText((Join-Path $source 'package.commit'), $commit)
    if ($activeArchive -ne $archive) { Copy-Item -LiteralPath $activeArchive -Destination $archive -Force }
    if (Test-Path -LiteralPath (Join-Path $destination 'package.commit') -PathType Leaf) {
        Copy-PackageTree $destination $previous
    }
    try { Copy-PackageTree $source $destination }
    catch {
        if (Test-Path -LiteralPath (Join-Path $previous 'package.commit') -PathType Leaf) {
            Copy-PackageTree $previous $destination
        }
        throw
    }
    Write-Output ('Downloaded package ' + $commit + '. Choose Install in Ketarin to apply it.')
} finally {
    if (Test-Path -LiteralPath $stage) {
        Assert-PackagePath $stage
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
