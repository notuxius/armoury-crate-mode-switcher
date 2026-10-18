# Ketarin runs this as its PowerShell post-download command, with $app provided.
# Extraction only: installing remains a separate Ketarin action.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Path]::GetFullPath($app.PreviousLocation)
$folder = [IO.Path]::GetDirectoryName($archive)
$destination = Join-Path $folder 'Package'
$previous = Join-Path $folder 'Package.previous'
$stage = Join-Path $folder ('extract-' + [Guid]::NewGuid().ToString('N'))

function Assert-PackagePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetDirectoryName($full) -ne $folder -or
        [IO.Path]::GetFileName($full) -notmatch '^(Package(\.previous)?|extract-[0-9a-f]{32})$') {
        throw 'Refusing to modify a path outside the package download folder.'
    }
    if (Test-Path -LiteralPath $full) {
        $items = @(Get-Item -LiteralPath $full) + @(Get-ChildItem -LiteralPath $full -Recurse -Force)
        if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            throw 'The package folder must not contain a symbolic link or junction.'
        }
    }
}

Assert-PackagePath $destination
Assert-PackagePath $previous
Assert-PackagePath $stage
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $roots = @($zip.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Select-Object -Unique)
        if ($roots.Count -ne 1 -or $roots[0] -notmatch '^armoury-crate-mode-switcher-([0-9a-f]{40})$') {
            throw 'The download is not a commit archive from armoury-crate-mode-switcher.'
        }
        $commit = $Matches[1]
        $stagePrefix = $stage.TrimEnd('\') + '\'
        foreach ($entry in $zip.Entries) {
            $entryPath = [IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
            if (-not $entryPath.StartsWith($stagePrefix, [StringComparison]::OrdinalIgnoreCase) -or
                $entry.FullName.Contains(':') -or $entry.FullName.Contains('\')) {
                throw 'The archive contains an invalid file path.'
            }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $stage)
    $source = Join-Path $stage $roots[0]
    foreach ($required in @('Setup.ps1','Build.ps1','AsusMode.cs','app.manifest','InstallerMenu.ps1','InstallerRadio.ps1','asus-mode-radio.nss','icons\Silent.png','icons\Performance.png','icons\Turbo.png')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) {
            throw ('The package is incomplete: ' + $required)
        }
    }
    [IO.File]::WriteAllText((Join-Path $source 'package.commit'), $commit)
    if (Test-Path -LiteralPath $previous) {
        Assert-PackagePath $previous
        Remove-Item -LiteralPath $previous -Recurse -Force
    }
    if (Test-Path -LiteralPath $destination) {
        Assert-PackagePath $destination
        Move-Item -LiteralPath $destination -Destination $previous
    }
    try { Move-Item -LiteralPath $source -Destination $destination }
    catch {
        if ((Test-Path -LiteralPath $previous) -and -not (Test-Path -LiteralPath $destination)) {
            Assert-PackagePath $previous
            Move-Item -LiteralPath $previous -Destination $destination
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
