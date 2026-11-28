param([ValidateSet('Auto','Top','Bottom')][string]$MenuPosition, [switch]$Packaged, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$asusPositionArgument = if ($MenuPosition) { ' -MenuPosition ' + $MenuPosition } else { '' }
$asusSetupArguments = '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"' + $asusPositionArgument
if ($Packaged) { $asusSetupArguments += ' -Packaged' }
if ($CheckOnly) { $asusSetupArguments += ' -CheckOnly' }
# Use the native Windows registry and task tools even from a 32-bit launcher.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $asusNativePowerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $asusNativeSetup = Start-Process -FilePath $asusNativePowerShell -WindowStyle Hidden -Wait -PassThru -ArgumentList $asusSetupArguments
    exit $asusNativeSetup.ExitCode
}
$asusSetupLogFolder = Join-Path $env:LOCALAPPDATA 'ASUS Mode Shortcuts'
New-Item -ItemType Directory -Path $asusSetupLogFolder -Force | Out-Null
$asusSetupLog = Join-Path $asusSetupLogFolder 'setup-result.txt'
Set-Content -LiteralPath $asusSetupLog -Value ('STARTED ' + (Get-Date -Format o) + ' ' + $PSCommandPath)
try {
    # Prefer Windows PowerShell's own modules over paths inherited from launchers.
    $env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    $asusIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $asusPrincipalCheck = New-Object Security.Principal.WindowsPrincipal($asusIdentity)
    $asusPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not $asusPrincipalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $asusSetupProcess = Start-Process -FilePath $asusPowerShell -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $asusSetupArguments
        exit $asusSetupProcess.ExitCode
    }

    $asusInstallKey = 'HKLM:\SOFTWARE\Armoury Crate Mode Switcher'
    $asusInstallRecord = Get-ItemProperty -LiteralPath $asusInstallKey -ErrorAction SilentlyContinue
    if ($asusInstallRecord.OwnerSid -and $asusInstallRecord.OwnerSid -ne $asusIdentity.User.Value) {
        throw 'Sign in to the Windows account that installed Armoury Crate Mode Switcher before running setup.'
    }
    if ($Packaged) {
        if (-not $MenuPosition) { throw 'The installer did not supply a menu position.' }
        foreach ($asusPayloadFile in @('AsusMode.exe','asus-mode-radio.nss','icons\Fallback\Silent.ico','icons\Fallback\Performance.ico','icons\Fallback\Turbo.ico')) {
            if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $asusPayloadFile) -PathType Leaf)) {
                throw "The installer payload is missing $asusPayloadFile."
            }
        }
    }
    $asusComputer = Get-CimInstance Win32_ComputerSystem
    if (-not [Environment]::Is64BitOperatingSystem -or $asusComputer.Manufacturer -notmatch 'ASUS|ASUSTeK') {
        throw 'This package requires 64-bit Windows on an ASUS computer with compatible Armoury Crate operating modes.'
    }
    if (-not $Packaged) {
        $asusBuildScript = Join-Path $PSScriptRoot 'Build.ps1'
        if (-not (Test-Path -LiteralPath $asusBuildScript)) { throw 'Extract the complete source tree or use the installer from GitHub Releases.' }
        & $asusPowerShell -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $asusBuildScript
        if ($LASTEXITCODE -ne 0) { throw 'Could not build the windowless mode helper.' }
    }
    $asusSourceExe = Join-Path $PSScriptRoot 'AsusMode.exe'
    $asusServiceCheck = Start-Process -FilePath $asusSourceExe -ArgumentList '--check' -Wait -PassThru -WindowStyle Hidden
    if ($asusServiceCheck.ExitCode -ne 0) { throw 'A compatible Armoury Crate operating-mode service is required. Start the service and open Armoury Crate once, then rerun setup. See last-result.txt for the compatibility check result.' }
    $asusWscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

    $asusSupportDir = Join-Path $env:ProgramData 'ASUS Mode Shortcuts'
    $asusTaskScript = Join-Path $asusSupportDir 'Set-Mode.ps1'
    $asusHelper = Join-Path $asusSupportDir 'AsusMode.exe'
    $asusUserPrograms = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs'
    $asusUserApp = Join-Path $asusUserPrograms 'Armoury Crate Mode Switcher'
    $asusUserLauncher = Join-Path $asusUserApp 'AsusMode.exe'
    $asusWatcherName = 'ASUS Mode Checkmark Watcher'
    $asusExistingWatcher = Get-ScheduledTask -TaskName $asusWatcherName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($asusExistingWatcher -and (@($asusExistingWatcher.Actions).Count -ne 1 -or
        $asusExistingWatcher.Actions[0].Execute -ne $asusHelper -or $asusExistingWatcher.Actions[0].Arguments -ne '--watch')) {
        throw 'An unrelated task already uses the checkmark watcher name.'
    }
    if ($Packaged -and $asusExistingWatcher) {
        $asusWatcherAccount = $asusExistingWatcher.Principal.UserId
        $asusWatcherSid = if ($asusWatcherAccount -like 'S-1-*') {
            $asusWatcherAccount
        } else {
            ([Security.Principal.NTAccount]::new($asusWatcherAccount)).Translate([Security.Principal.SecurityIdentifier]).Value
        }
        if ($asusWatcherSid -ne $asusIdentity.User.Value) {
            throw 'Sign in to the Windows account that uses the existing Armoury Crate Mode Switcher shortcuts before upgrading.'
        }
    }
    $asusDesktop = [Environment]::GetFolderPath('Desktop')
    $asusStartFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'ASUS Mode Shortcuts'
    $asusMenuRoot = 'HKLM:\Software\Classes\Directory\Background\shell\ArmouryCrateModes'
    $asusLegacyRoot = 'HKCU:\Software\Classes\DesktopBackground\Shell\ASUSModes'
    $asusArmouryUserMenu = 'HKCU:\Software\Classes\Directory\Background\shell\GameLibrary'
    $asusArmouryMenu = 'HKLM:\Software\Classes\Directory\Background\shell\GameLibrary'
    $asusCommandStore = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell'
    if ((Test-Path -LiteralPath $asusMenuRoot) -and
        (Get-ItemProperty -LiteralPath $asusMenuRoot -Name ASUSModeShortcuts -ErrorAction SilentlyContinue).ASUSModeShortcuts -ne '1') {
        throw 'An unrelated ArmouryCrateModes menu already exists. Nothing has been replaced.'
    }
    . (Join-Path $PSScriptRoot 'InstallerMenu.ps1')
    . (Join-Path $PSScriptRoot 'InstallerRadio.ps1')
    . (Join-Path $PSScriptRoot 'InstallerIcons.ps1')
    $asusRadioConfig = Get-AsusRadioConfig
    if (-not $MenuPosition) {
        $asusPreviousPosition = 'Auto'
        foreach ($asusPositionKey in @($asusArmouryMenu, $asusLegacyRoot, $asusMenuRoot)) {
            if (Test-Path -LiteralPath $asusPositionKey) {
                $asusSavedPosition = (Get-ItemProperty -LiteralPath $asusPositionKey -Name ASUSModeShortcutsPosition -ErrorAction SilentlyContinue).ASUSModeShortcutsPosition
                if ($asusSavedPosition -in @('Auto','Top','Bottom')) { $asusPreviousPosition = $asusSavedPosition }
            }
        }
        $asusChosenPosition = Show-AsusModeMenuPosition -DefaultPosition $asusPreviousPosition
        if (-not $asusChosenPosition) {
            Add-Content -LiteralPath $asusSetupLog -Value ('CANCELLED ' + (Get-Date -Format o))
            exit 2
        }
        $MenuPosition = $asusChosenPosition
    }
    $asusShell = New-Object -ComObject WScript.Shell
    $asusModes = @(
        @{ Name = 'Silent'; Hotkey = 'CTRL+ALT+S'; MenuKey = '01Silent' },
        @{ Name = 'Performance'; Hotkey = 'CTRL+ALT+P'; MenuKey = '02Performance' },
        @{ Name = 'Turbo'; Hotkey = 'CTRL+ALT+T'; MenuKey = '03Turbo' }
    )

    # Avoid overwriting unrelated tasks or shortcuts with matching names.
    foreach ($asusMode in $asusModes) {
        $asusModeCommandKey = Join-Path $asusCommandStore ('ASUSModeShortcuts.' + $asusMode.Name)
        if ((Test-Path -LiteralPath $asusModeCommandKey) -and
            (Get-ItemProperty -LiteralPath $asusModeCommandKey -Name ASUSModeShortcuts -ErrorAction SilentlyContinue).ASUSModeShortcuts -ne '1') {
            throw 'An unrelated mode command already uses this package command name.'
        }
        $asusTaskName = 'ASUS ' + $asusMode.Name + ' Mode'
        $asusExistingTask = Get-ScheduledTask -TaskName $asusTaskName -TaskPath '\' -ErrorAction SilentlyContinue
        if ($asusExistingTask) {
            $asusKnownPath = if ($asusMode.Name -eq 'Silent') { Join-Path $env:ProgramData 'ASUS Silent Mode\Silent.ps1' } else { $asusTaskScript }
            $asusExistingActions = @($asusExistingTask.Actions)
            $asusOldTask = $asusExistingActions.Count -eq 1 -and $asusExistingActions[0].Execute -eq $asusPowerShell -and
                ($asusExistingActions[0].Arguments -like ('*"' + $asusTaskScript + '"*') -or
                 $asusExistingActions[0].Arguments -like ('*"' + $asusKnownPath + '"*'))
            $asusNewTask = $asusExistingActions.Count -eq 1 -and $asusExistingActions[0].Execute -eq $asusHelper -and
                $asusExistingActions[0].Arguments -eq ('--apply ' + $asusMode.Name)
            if (-not $asusOldTask -and -not $asusNewTask) {
                throw "An unrelated scheduled task is named $asusTaskName. Nothing has been replaced."
            }
        }
        foreach ($asusShortcutFolder in @($asusDesktop, $asusStartFolder)) {
        $asusShortcutPath = Join-Path $asusShortcutFolder ($asusTaskName + '.lnk')
        if (Test-Path -LiteralPath $asusShortcutPath) {
            $asusExistingLink = $asusShell.CreateShortcut($asusShortcutPath)
            $asusKnownLauncher = Join-Path $asusSupportDir ($asusMode.Name + '.vbs')
            $asusOldLauncher = Join-Path $env:ProgramData 'ASUS Silent Mode\Silent.vbs'
            $asusOldLink = $asusExistingLink.TargetPath -eq $asusWscript -and
                ($asusExistingLink.Arguments -like ('*"' + $asusKnownLauncher + '"*') -or
                 ($asusMode.Name -eq 'Silent' -and $asusExistingLink.Arguments -like ('*"' + $asusOldLauncher + '"*')))
            $asusNewLink = $asusExistingLink.TargetPath -in @($asusHelper, $asusUserLauncher) -and
                $asusExistingLink.Arguments -eq ('--request ' + $asusMode.Name)
            if (-not $asusOldLink -and -not $asusNewLink) {
                throw "An unrelated shortcut is named $asusTaskName. Nothing has been replaced."
            }
        }
        }
    }

    foreach ($asusUserPath in @($asusUserPrograms, $asusUserApp, $asusUserLauncher)) {
        $asusExistingPath = Get-Item -LiteralPath $asusUserPath -Force -ErrorAction SilentlyContinue
        if ($asusExistingPath -and ($asusExistingPath.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "The launcher path must not go through a symbolic link or junction: $asusUserPath"
        }
    }
    if (Test-Path -LiteralPath $asusUserLauncher -PathType Container) {
        throw "A folder already uses the launcher filename: $asusUserLauncher"
    }
    $asusSupportInfo = Get-Item -LiteralPath $asusSupportDir -Force -ErrorAction SilentlyContinue
    if ($asusSupportInfo -and (-not $asusSupportInfo.PSIsContainer -or
        ($asusSupportInfo.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        throw 'The support folder must be a directory and must not be a symbolic link or junction.'
    }
    if ($CheckOnly) {
        Add-Content -LiteralPath $asusSetupLog -Value ('PREFLIGHT ' + (Get-Date -Format o))
        exit 0
    }

    if ($Packaged) {
        if (-not (Test-Path -LiteralPath $asusInstallKey)) { New-Item -Path $asusInstallKey | Out-Null }
        New-ItemProperty -LiteralPath $asusInstallKey -Name OwnerSid -Value $asusIdentity.User.Value -PropertyType String -Force | Out-Null
        if ($asusRadioConfig) {
            New-ItemProperty -LiteralPath $asusInstallKey -Name NilesoftConfig -Value $asusRadioConfig -PropertyType String -Force | Out-Null
        }
    }
    if (-not (Test-Path -LiteralPath $asusSupportDir)) {
        New-Item -ItemType Directory -Path $asusSupportDir | Out-Null
    }
    if ((Get-Item -LiteralPath $asusSupportDir).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The support folder must not be a symbolic link or junction.'
    }
    # Elevated tasks execute only from this protected folder.
    $asusAcl = New-Object Security.AccessControl.DirectorySecurity
    $asusAcl.SetAccessRuleProtection($true, $false)
    $asusAcl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    foreach ($asusGrant in @(@('S-1-5-18','FullControl'), @('S-1-5-32-544','FullControl'), @('S-1-5-32-545','ReadAndExecute'))) {
        $asusSid = New-Object Security.Principal.SecurityIdentifier($asusGrant[0])
        $asusRule = New-Object Security.AccessControl.FileSystemAccessRule($asusSid, $asusGrant[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $asusAcl.AddAccessRule($asusRule)
    }
    Set-Acl -LiteralPath $asusSupportDir -AclObject $asusAcl
    New-Item -ItemType Directory -Path $asusUserApp -Force | Out-Null
    Copy-Item -LiteralPath $asusSourceExe -Destination $asusUserLauncher -Force
    if ($asusExistingWatcher -and $asusExistingWatcher.State -in @('Running','Queued')) {
        Start-Process -FilePath $asusSourceExe -ArgumentList '--stop-watch' -WindowStyle Hidden -Wait
        $asusStopTime = [Diagnostics.Stopwatch]::StartNew()
        while ((Get-ScheduledTask -TaskName $asusWatcherName -TaskPath '\').State -in @('Running','Queued')) {
            if ($asusStopTime.ElapsedMilliseconds -ge 2500) { break }
            Start-Sleep -Milliseconds 100
        }
        if ((Get-ScheduledTask -TaskName $asusWatcherName -TaskPath '\').State -in @('Running','Queued')) {
            Stop-ScheduledTask -TaskName $asusWatcherName -TaskPath '\'
            $asusStopTime.Restart()
            while ((Get-ScheduledTask -TaskName $asusWatcherName -TaskPath '\').State -in @('Running','Queued')) {
                if ($asusStopTime.ElapsedMilliseconds -ge 3000) { throw 'The running mode watcher could not be stopped.' }
                Start-Sleep -Milliseconds 100
            }
        }
    }
    Copy-Item -LiteralPath $asusSourceExe -Destination $asusHelper -Force
    $asusInstalledIcons = Join-Path $asusSupportDir 'icons'
    New-Item -ItemType Directory -Path $asusInstalledIcons -Force | Out-Null
    Install-AsusModeIcons -Destination $asusInstalledIcons
    if (-not (Test-Path -LiteralPath $asusStartFolder)) {
        New-Item -ItemType Directory -Path $asusStartFolder | Out-Null
    }
    $asusPrincipal = New-ScheduledTaskPrincipal -UserId $asusIdentity.Name -LogonType Interactive -RunLevel Highest
    $asusSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AsusModeLinkRefresh {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern void SHChangeNotify(uint eventId, uint flags, string item1, IntPtr item2);
}
'@
    foreach ($asusMode in $asusModes) {
        $asusTaskName = 'ASUS ' + $asusMode.Name + ' Mode'
        $asusAction = New-ScheduledTaskAction -Execute $asusHelper -Argument ('--apply ' + $asusMode.Name) -WorkingDirectory $asusSupportDir
        Register-ScheduledTask -TaskName $asusTaskName -TaskPath '\' -Action $asusAction -Principal $asusPrincipal -Settings $asusSettings -Description ('On-demand ASUS ' + $asusMode.Name + ' mode. ASUS Mode Shortcuts package; no automatic triggers.') -Force | Out-Null
        $asusShortcutPath = Join-Path $asusStartFolder ($asusTaskName + '.lnk')
        $asusShortcut = $asusShell.CreateShortcut($asusShortcutPath)
        $asusShortcut.TargetPath = $asusUserLauncher
        $asusShortcut.Arguments = '--request ' + $asusMode.Name
        $asusShortcut.WorkingDirectory = $asusUserApp
        $asusShortcut.Description = 'Enable ' + $asusMode.Name + ' mode quietly. ' + $asusMode.Hotkey
        # The resident helper owns these hotkeys; Explorer shortcut dispatch can lag.
        $asusShortcut.Hotkey = ''
        $asusShortcut.IconLocation = (Join-Path $asusInstalledIcons ($asusMode.Name + '-menu-asus6.ico')) + ',0'
        $asusShortcut.WindowStyle = 7
        $asusShortcut.Save()
        $asusLinkBytes = [IO.File]::ReadAllBytes($asusShortcutPath)
        $asusLinkBytes[0x15] = $asusLinkBytes[0x15] -band 0xDF
        [IO.File]::WriteAllBytes($asusShortcutPath, $asusLinkBytes)
        [AsusModeLinkRefresh]::SHChangeNotify(0x00002000, 0x0005, $asusShortcutPath, [IntPtr]::Zero)
        $asusMenuEntry = Join-Path $asusCommandStore ('ASUSModeShortcuts.' + $asusMode.Name)
        $asusMenuCommand = Join-Path $asusMenuEntry 'command'
        New-Item -Path $asusMenuCommand -Force | Out-Null
        Set-Item -LiteralPath $asusMenuEntry -Value $asusMode.Name
        New-ItemProperty -LiteralPath $asusMenuEntry -Name ASUSModeShortcuts -Value '1' -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $asusMenuEntry -Name MUIVerb -Value $asusMode.Name -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $asusMenuEntry -Name Icon -Value ((Join-Path $asusInstalledIcons ($asusMode.Name + '-menu-asus6.ico')) + ',0') -PropertyType String -Force | Out-Null
        Set-Item -LiteralPath $asusMenuCommand -Value ('"' + $asusHelper + '" --request ' + $asusMode.Name)
        # Remove only this package's desktop entries, checked before setup.
        $asusOldDesktopLink = Join-Path $asusDesktop ($asusTaskName + '.lnk')
        if (Test-Path -LiteralPath $asusOldDesktopLink) {
            Remove-Item -LiteralPath $asusOldDesktopLink
            [AsusModeLinkRefresh]::SHChangeNotify(0x00000004, 0x0005, $asusOldDesktopLink, [IntPtr]::Zero)
        }
    }
    # This menu belongs to the package and does not depend on ASUS Game Library.
    New-Item -Path $asusMenuRoot -Force | Out-Null
    New-ItemProperty -LiteralPath $asusMenuRoot -Name ASUSModeShortcuts -Value '1' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $asusMenuRoot -Name MUIVerb -Value 'Armoury Crate Modes' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $asusMenuRoot -Name Icon -Value ($asusHelper + ',0') -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $asusMenuRoot -Name SubCommands -Value 'ASUSModeShortcuts.Silent;ASUSModeShortcuts.Performance;ASUSModeShortcuts.Turbo' -PropertyType String -Force | Out-Null
    if ($MenuPosition -eq 'Auto') {
        Remove-ItemProperty -LiteralPath $asusMenuRoot -Name Position -ErrorAction SilentlyContinue
    } else {
        New-ItemProperty -LiteralPath $asusMenuRoot -Name Position -Value $MenuPosition -PropertyType String -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $asusMenuRoot -Name ASUSModeShortcutsPosition -Value $MenuPosition -PropertyType String -Force | Out-Null
    if ((Test-Path -LiteralPath $asusLegacyRoot) -and
        (Get-ItemProperty -LiteralPath $asusLegacyRoot -Name ASUSModeShortcuts -ErrorAction SilentlyContinue).ASUSModeShortcuts -eq '1') {
        Remove-Item -LiteralPath $asusLegacyRoot -Recurse
    }
    # Upgrade older installations without deleting or recreating ASUS's menu.
    foreach ($asusOldMenu in @($asusArmouryMenu, $asusArmouryUserMenu)) {
        if (-not (Test-Path -LiteralPath $asusOldMenu)) { continue }
        $asusOldValues = Get-ItemProperty -LiteralPath $asusOldMenu
        $asusOriginalCommands = Remove-AsusModeMenuCommands -ExistingCommands $asusOldValues.SubCommands
        if ($asusOriginalCommands -cne [string]$asusOldValues.SubCommands) {
            $asusBackupName = 'game-library-before-separate-menu-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.reg'
            & reg.exe export ((Get-Item -LiteralPath $asusOldMenu).Name) (Join-Path $asusSupportDir $asusBackupName) /y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not back up the old Game Library menu.' }
            New-ItemProperty -LiteralPath $asusOldMenu -Name SubCommands -Value $asusOriginalCommands -PropertyType String -Force | Out-Null
        }
        Remove-ItemProperty -LiteralPath $asusOldMenu -Name ASUSModeShortcutsPosition -ErrorAction SilentlyContinue
    }
    $asusMenuRefresh = Start-Process -FilePath $asusHelper -ArgumentList '--refresh-menu' -Wait -PassThru -WindowStyle Hidden
    if ($asusMenuRefresh.ExitCode -ne 0) { throw 'Could not update mode checkmarks.' }
    Install-AsusRadioMenu -Config $asusRadioConfig -SourceFolder $PSScriptRoot -BackupFolder $asusSupportDir
    $asusWatcherAction = New-ScheduledTaskAction -Execute $asusHelper -Argument '--watch' -WorkingDirectory $asusSupportDir
    $asusWatcherTrigger = New-ScheduledTaskTrigger -AtLogOn -User $asusIdentity.Name
    $asusWatcherSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    Register-ScheduledTask -TaskName $asusWatcherName -TaskPath '\' -Action $asusWatcherAction -Trigger $asusWatcherTrigger -Principal $asusPrincipal -Settings $asusWatcherSettings -Description 'ASUS Mode Shortcuts: handles Ctrl+Alt+S/P/T and immediate mode requests, and tracks Armoury Crate service selection.' -Force | Out-Null
    $asusWatcherStatusPath = Join-Path $asusSetupLogFolder 'watcher-status.txt'
    $asusWatcherStartedUtc = [DateTime]::UtcNow
    Start-ScheduledTask -TaskName $asusWatcherName -TaskPath '\'
    $asusReadyTime = [Diagnostics.Stopwatch]::StartNew()
    $asusWatcherReady = $false
    while ($asusReadyTime.ElapsedMilliseconds -lt 12000) {
        $asusStatusFile = Get-Item -LiteralPath $asusWatcherStatusPath -ErrorAction SilentlyContinue
        if ($asusStatusFile -and $asusStatusFile.LastWriteTimeUtc -ge $asusWatcherStartedUtc) {
            $asusStatusLine = Get-Content -LiteralPath $asusWatcherStatusPath -ErrorAction SilentlyContinue -TotalCount 1
            if ($asusStatusLine -match 'Fast request listener active; hotkeys S=True, P=True, T=True; PID=(\d+);') {
                $asusWatcherProcess = Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue
                if ($asusWatcherProcess -and $asusWatcherProcess.Path -eq $asusHelper) { $asusWatcherReady = $true; break }
            }
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $asusWatcherReady) {
        throw 'The background helper did not confirm all three hotkeys. Check watcher-status.txt for shortcut conflicts and watcher-error.txt for startup or menu errors.'
    }
    # The old console-based launch path is no longer used.
    foreach ($asusOldFile in @('Set-Mode.ps1','Silent.vbs','Performance.vbs','Turbo.vbs')) {
        $asusOldFilePath = Join-Path $asusSupportDir $asusOldFile
        if (Test-Path -LiteralPath $asusOldFilePath) { Remove-Item -LiteralPath $asusOldFilePath }
    }
    foreach ($asusMode in $asusModes) {
        $asusOldPng = Join-Path $asusInstalledIcons ($asusMode.Name + '.png')
        if (Test-Path -LiteralPath $asusOldPng -PathType Leaf) { Remove-Item -LiteralPath $asusOldPng }
    }
    [AsusModeLinkRefresh]::SHChangeNotify(0x08000000, 0, $null, [IntPtr]::Zero)
    Write-Output 'Ready: desktop right-click > Show more options (if shown) > Armoury Crate Modes > Silent / Performance / Turbo.'
    Write-Output 'Ready: Ctrl+Alt+S for Silent; Ctrl+Alt+P for Performance; Ctrl+Alt+T for Turbo.'
    Write-Output 'Mode changes now use the original ASUS hotkey popup through the installed AsusOSD component.'
    Write-Output 'The background checkmark watcher tracks Armoury Crate service selection.'
    Add-Content -LiteralPath $asusSetupLog -Value ('SUCCESS ' + (Get-Date -Format o) + ' MenuPosition=' + $MenuPosition)
    exit 0
} catch {
    $asusSetupError = $_.Exception.Message
    Add-Content -LiteralPath $asusSetupLog -Value ('FAILED ' + (Get-Date -Format o) + ' ' + ($_ | Out-String))
    [Console]::Error.WriteLine($asusSetupError)
    if ($Packaged) {
        Set-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-error.txt') -Value $asusSetupError -Encoding UTF8
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($asusSetupError, 'ASUS shortcut setup failed')
    }
    exit 1
}
