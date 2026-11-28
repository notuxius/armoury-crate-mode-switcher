param([Parameter(Mandatory)][string]$ErrorFile)
$ErrorActionPreference = 'Stop'

try {
    . (Join-Path $PSScriptRoot 'InstallerRadio.ps1')
    $installKey = 'HKLM:\SOFTWARE\Armoury Crate Mode Switcher'
    $install = Get-ItemProperty -LiteralPath $installKey -ErrorAction SilentlyContinue
    if (-not $install.OwnerSid) { exit 0 }
    if ($install.OwnerSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        throw 'Sign in to the Windows account that installed Armoury Crate Mode Switcher before uninstalling it.'
    }

    $support = Join-Path $env:ProgramData 'ASUS Mode Shortcuts'
    $helper = Join-Path $support 'AsusMode.exe'
    $icons = Join-Path $support 'icons'
    $localPrograms = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs'
    $launcherFolder = Join-Path $localPrograms 'Armoury Crate Mode Switcher'
    $launcher = Join-Path $launcherFolder 'AsusMode.exe'
    $startFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'ASUS Mode Shortcuts'
    foreach ($path in @($support, $helper, $icons, $localPrograms, $launcherFolder, $launcher, $startFolder)) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Uninstall cannot follow a symbolic link or junction: $path"
        }
    }

    $modes = @('Silent', 'Performance', 'Turbo')
    $watcher = 'ASUS Mode Checkmark Watcher'
    $tasks = @{ $watcher = '--watch' }
    foreach ($mode in $modes) { $tasks["ASUS $mode Mode"] = "--apply $mode" }
    foreach ($name in $tasks.Keys) {
        $task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
        if (-not $task -or @($task.Actions).Count -ne 1 -or
            $task.Actions[0].Execute -ne $helper -or $task.Actions[0].Arguments -ne $tasks[$name]) { continue }
        if ($task.State -in @('Running','Queued')) {
            Stop-ScheduledTask -InputObject $task
            $stop = [Diagnostics.Stopwatch]::StartNew()
            while ((Get-ScheduledTask -TaskName $name -TaskPath '\').State -in @('Running','Queued')) {
                if ($stop.ElapsedMilliseconds -ge 5000) { throw "Could not stop the scheduled task $name." }
                Start-Sleep -Milliseconds 100
            }
        }
        Unregister-ScheduledTask -InputObject $task -Confirm:$false
    }

    if ($install.NilesoftConfig -and -not (Test-Path -LiteralPath $support -PathType Container)) {
        New-Item -ItemType Directory -Path $support | Out-Null
    }
    Remove-AsusRadioMenu -Config $install.NilesoftConfig -BackupFolder $support

    $menuRoot = 'HKLM:\Software\Classes\Directory\Background\shell\ArmouryCrateModes'
    $commands = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell'
    $menuKeys = @($menuRoot) + @($modes | ForEach-Object { Join-Path $commands "ASUSModeShortcuts.$_" })
    foreach ($key in $menuKeys) {
        if ((Get-ItemProperty -LiteralPath $key -Name ASUSModeShortcuts -ErrorAction SilentlyContinue).ASUSModeShortcuts -eq '1') {
            Remove-Item -LiteralPath $key -Recurse
        }
    }

    $shell = New-Object -ComObject WScript.Shell
    foreach ($mode in $modes) {
        $linkFile = Get-Item -LiteralPath (Join-Path $startFolder "ASUS $mode Mode.lnk") -Force -ErrorAction SilentlyContinue
        if ($linkFile -and -not ($linkFile.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory))) {
            $shortcut = $shell.CreateShortcut($linkFile.FullName)
            if ($shortcut.TargetPath -in @($launcher, $helper) -and $shortcut.Arguments -eq "--request $mode") {
                Remove-Item -LiteralPath $linkFile.FullName
            }
        }
        $icon = Join-Path $icons "$mode-menu-asus6.ico"
        if (Test-Path -LiteralPath $icon -PathType Leaf) { Remove-Item -LiteralPath $icon }
    }
    if ((Test-Path -LiteralPath $launcher -PathType Leaf) -and
        (Test-Path -LiteralPath $helper -PathType Leaf) -and
        (Get-FileHash -LiteralPath $launcher).Hash -eq (Get-FileHash -LiteralPath $helper).Hash) {
        Remove-Item -LiteralPath $launcher
    }
    if (Test-Path -LiteralPath $helper -PathType Leaf) { Remove-Item -LiteralPath $helper }
    foreach ($folder in @($startFolder, $launcherFolder, $icons, $support)) {
        if ((Test-Path -LiteralPath $folder -PathType Container) -and
            -not (Get-ChildItem -LiteralPath $folder -Force | Select-Object -First 1)) {
            [IO.Directory]::Delete($folder)
        }
    }
    Remove-ItemProperty -LiteralPath $installKey -Name OwnerSid
    if ($install.PSObject.Properties['NilesoftConfig']) {
        Remove-ItemProperty -LiteralPath $installKey -Name NilesoftConfig
    }
    if ((Get-Item -LiteralPath $installKey).ValueCount -eq 0 -and (Get-Item -LiteralPath $installKey).SubKeyCount -eq 0) {
        Remove-Item -LiteralPath $installKey
    }
    exit 0
} catch {
    Set-Content -LiteralPath $ErrorFile -Value $_.Exception.Message -Encoding UTF8
    exit 1
}
