param([ValidateSet('Top','Bottom')][string]$MenuPosition)
$ErrorActionPreference = 'Stop'
$asusPositionArgument = if ($MenuPosition) { ' -MenuPosition ' + $MenuPosition } else { '' }
# Ketarin is 32-bit; setup must use the native Windows registry and task tools.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $asusNativePowerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $asusNativeSetup = Start-Process -FilePath $asusNativePowerShell -WindowStyle Hidden -Wait -PassThru -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"' + $asusPositionArgument)
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
        $asusSetupProcess = Start-Process -FilePath $asusPowerShell -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"' + $asusPositionArgument)
        exit $asusSetupProcess.ExitCode
    }

    $asusComputer = Get-CimInstance Win32_ComputerSystem
    if (-not [Environment]::Is64BitOperatingSystem -or $asusComputer.Manufacturer -notmatch 'ASUS|ASUSTeK') {
        throw 'This package requires 64-bit Windows on an ASUS computer with compatible Armoury Crate operating modes.'
    }
    $asusBuildScript = Join-Path $PSScriptRoot 'Build.ps1'
    if (-not (Test-Path -LiteralPath $asusBuildScript)) { throw 'Extract the complete ZIP before running Install.cmd.' }
    & $asusPowerShell -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $asusBuildScript
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the windowless mode helper.' }
    $asusSourceExe = Join-Path $PSScriptRoot 'AsusMode.exe'
    $asusServiceCheck = Start-Process -FilePath $asusSourceExe -ArgumentList '--check' -Wait -PassThru -WindowStyle Hidden
    if ($asusServiceCheck.ExitCode -ne 0) { throw 'A compatible Armoury Crate operating-mode service is required. Start the service and open Armoury Crate once, then rerun setup. See last-result.txt for the compatibility check result.' }
    $asusWscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

    $asusSupportDir = Join-Path $env:ProgramData 'ASUS Mode Shortcuts'
    $asusTaskScript = Join-Path $asusSupportDir 'Set-Mode.ps1'
    $asusHelper = Join-Path $asusSupportDir 'AsusMode.exe'
    $asusWatcherName = 'ASUS Mode Checkmark Watcher'
    $asusExistingWatcher = Get-ScheduledTask -TaskName $asusWatcherName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($asusExistingWatcher -and (@($asusExistingWatcher.Actions).Count -ne 1 -or
        $asusExistingWatcher.Actions[0].Execute -ne $asusHelper -or $asusExistingWatcher.Actions[0].Arguments -ne '--watch')) {
        throw 'An unrelated task already uses the checkmark watcher name.'
    }
    $asusDesktop = [Environment]::GetFolderPath('Desktop')
    $asusStartFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'ASUS Mode Shortcuts'
    $asusMenuRoot = 'HKCU:\Software\Classes\DesktopBackground\Shell\ASUSModes'
    $asusArmouryUserMenu = 'HKCU:\Software\Classes\Directory\Background\shell\GameLibrary'
    $asusArmouryMenu = 'HKLM:\Software\Classes\Directory\Background\shell\GameLibrary'
    $asusArmourySource = $asusArmouryMenu
    $asusCommandStore = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell'
    if (-not (Test-Path -LiteralPath $asusArmourySource)) {
        throw 'Enable the ArmouryCrate Game Library right-click menu first, then rerun setup. This package adds modes to that existing menu.'
    }
    $asusArmouryValues = Get-ItemProperty -LiteralPath $asusArmourySource
    if ($asusArmouryValues.MUIVerb -ne 'ArmouryCrate' -or -not $asusArmouryValues.SubCommands) {
        throw 'The existing ArmouryCrate menu uses an unrecognized format. Its entries have not been changed.'
    }
    if ((Test-Path -LiteralPath $asusArmouryUserMenu) -and
        (Get-ItemProperty -LiteralPath $asusArmouryUserMenu -Name ASUSModeShortcuts -ErrorAction SilentlyContinue).ASUSModeShortcuts -ne '1') {
        throw 'An existing user-specific ArmouryCrate menu must be reviewed before merging.'
    }
    if ((Test-Path -LiteralPath $asusMenuRoot) -and
        (Get-ItemProperty -LiteralPath $asusMenuRoot -Name ASUSModeShortcuts -ErrorAction SilentlyContinue).ASUSModeShortcuts -ne '1') {
        throw 'An unrelated ASUSModes desktop menu already exists. Nothing has been replaced.'
    }
    . (Join-Path $PSScriptRoot 'InstallerMenu.ps1')
    . (Join-Path $PSScriptRoot 'InstallerRadio.ps1')
    $asusRadioConfig = Get-AsusRadioConfig
    if (-not $MenuPosition) {
        $asusPreviousPosition = 'Top'
        if ($asusArmouryValues.ASUSModeShortcutsPosition -in @('Top','Bottom')) {
            $asusPreviousPosition = $asusArmouryValues.ASUSModeShortcutsPosition
        } elseif ($asusArmouryValues.SubCommands -match ';ASUSModeShortcuts\.Turbo$') {
            $asusPreviousPosition = 'Bottom'
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
            $asusNewLink = $asusExistingLink.TargetPath -eq $asusHelper -and
                $asusExistingLink.Arguments -eq ('--request ' + $asusMode.Name)
            if (-not $asusOldLink -and -not $asusNewLink) {
                throw "An unrelated shortcut is named $asusTaskName. Nothing has been replaced."
            }
        }
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
    if ($asusExistingWatcher) {
        $asusStopWatcher = Start-Process -FilePath $asusSourceExe -ArgumentList '--stop-watch' -WindowStyle Hidden -Wait -PassThru
        Start-Sleep -Milliseconds 1500
        if ((Get-ScheduledTask -TaskName $asusWatcherName -TaskPath '\').State -eq 'Running') {
            Stop-ScheduledTask -TaskName $asusWatcherName -TaskPath '\'
            Start-Sleep -Milliseconds 500
        }
    }
    Copy-Item -LiteralPath $asusSourceExe -Destination $asusHelper -Force
    $asusInstalledIcons = Join-Path $asusSupportDir 'icons'
    New-Item -ItemType Directory -Path $asusInstalledIcons -Force | Out-Null
    foreach ($asusMode in $asusModes) {
        foreach ($asusExtension in @('.png','.ico')) {
            $asusInstalledIconName = if ($asusExtension -eq '.ico') { $asusMode.Name + '-menu-asus6.ico' } else { $asusMode.Name + $asusExtension }
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('icons\' + $asusMode.Name + $asusExtension)) -Destination (Join-Path $asusInstalledIcons $asusInstalledIconName) -Force
        }
    }
    if (-not (Test-Path -LiteralPath $asusStartFolder)) {
        New-Item -ItemType Directory -Path $asusStartFolder | Out-Null
    }
    # Extend ASUS's own menu registration, retaining all its original commands.
    # Reinstalling replaces our entries instead of accumulating duplicates.
    $asusMergedCommands = Get-AsusModeMenuCommands -ExistingCommands $asusArmouryValues.SubCommands -Position $MenuPosition

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
        $asusShortcut.TargetPath = $asusHelper
        $asusShortcut.Arguments = '--request ' + $asusMode.Name
        $asusShortcut.WorkingDirectory = $asusSupportDir
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
    New-ItemProperty -LiteralPath $asusArmouryMenu -Name SubCommands -Value $asusMergedCommands -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $asusArmouryMenu -Name ASUSModeShortcutsPosition -Value $MenuPosition -PropertyType String -Force | Out-Null
    if (Test-Path -LiteralPath $asusArmouryUserMenu) { Remove-Item -LiteralPath $asusArmouryUserMenu -Recurse }
    if (Test-Path -LiteralPath $asusMenuRoot) { Remove-Item -LiteralPath $asusMenuRoot -Recurse }
    $asusMenuRefresh = Start-Process -FilePath $asusHelper -ArgumentList '--refresh-menu' -Wait -PassThru -WindowStyle Hidden
    if ($asusMenuRefresh.ExitCode -ne 0) { throw 'Could not update mode checkmarks.' }
    Install-AsusRadioMenu -Config $asusRadioConfig -SourceFolder $PSScriptRoot -BackupFolder $asusSupportDir
    $asusWatcherAction = New-ScheduledTaskAction -Execute $asusHelper -Argument '--watch' -WorkingDirectory $asusSupportDir
    $asusWatcherTrigger = New-ScheduledTaskTrigger -AtLogOn -User $asusIdentity.Name
    $asusWatcherSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    Register-ScheduledTask -TaskName $asusWatcherName -TaskPath '\' -Action $asusWatcherAction -Trigger $asusWatcherTrigger -Principal $asusPrincipal -Settings $asusWatcherSettings -Description 'ASUS Mode Shortcuts: handles Ctrl+Alt+S/P/T and immediate mode requests, and tracks Armoury Crate service selection.' -Force | Out-Null
    Start-ScheduledTask -TaskName $asusWatcherName -TaskPath '\'
    # The old console-based launch path is no longer used.
    foreach ($asusOldFile in @('Set-Mode.ps1','Silent.vbs','Performance.vbs','Turbo.vbs')) {
        $asusOldFilePath = Join-Path $asusSupportDir $asusOldFile
        if (Test-Path -LiteralPath $asusOldFilePath) { Remove-Item -LiteralPath $asusOldFilePath }
    }
    [AsusModeLinkRefresh]::SHChangeNotify(0x08000000, 0, $null, [IntPtr]::Zero)
    Write-Output 'Ready: desktop right-click > Show more options (if shown) > ArmouryCrate > Silent / Performance / Turbo.'
    Write-Output 'Ready: Ctrl+Alt+S for Silent; Ctrl+Alt+P for Performance; Ctrl+Alt+T for Turbo.'
    Write-Output 'Mode changes now use the original ASUS hotkey popup through the installed AsusOSD component.'
    Write-Output 'The background checkmark watcher tracks Armoury Crate service selection.'
    Add-Content -LiteralPath $asusSetupLog -Value ('SUCCESS ' + (Get-Date -Format o) + ' MenuPosition=' + $MenuPosition)
    exit 0
} catch {
    $asusSetupError = $_.Exception.Message
    Add-Content -LiteralPath $asusSetupLog -Value ('FAILED ' + (Get-Date -Format o) + ' ' + ($_ | Out-String))
    [Console]::Error.WriteLine($asusSetupError)
    # Setup errors remain visible even if setup was elevated in a hidden window.
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($asusSetupError, 'ASUS shortcut setup failed')
    exit 1
}
