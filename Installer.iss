#ifndef AppVersion
  #error Specify AppVersion using Build-Installer.ps1.
#endif
#define AppName "Armoury Crate Mode Switcher"
#define AppFolder "{commonpf}\Armoury Crate Mode Switcher"

[Setup]
AppId={{0C9C3FF1-2E47-4D40-A351-B25B9CD7487B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=notuxius
AppPublisherURL=https://github.com/notuxius/armoury-crate-mode-switcher
AppSupportURL=https://github.com/notuxius/armoury-crate-mode-switcher/issues
DefaultDirName={#AppFolder}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableStartupPrompt=yes
UsePreviousAppDir=no
UninstallDisplayIcon={commonappdata}\ASUS Mode Shortcuts\AsusMode.exe
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible or arm64
ArchitecturesInstallIn64BitMode=x64compatible or arm64
SetupMutex=Global\ArmouryCrateModeSwitcherSetup
CloseApplications=no
ChangesAssociations=yes
AllowCancelDuringInstall=no
WizardStyle=modern
SetupIconFile=icons\App.ico
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoDescription=Armoury Crate Mode Switcher Setup
Compression=lzma2
SolidCompression=yes
OutputDir=dist
OutputBaseFilename=Armoury-Crate-Mode-Switcher-v{#AppVersion}-Setup

[Messages]
FinishedLabelNoIcons=Silent, Performance, and Turbo are ready. Use Ctrl+Alt+S, Ctrl+Alt+P, or Ctrl+Alt+T.%n%nIf you use Nilesoft Shell, hold Ctrl while right-clicking the desktop once to reload its menu.

[Files]
Source: "Setup.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "AsusMode.exe"; DestDir: "{tmp}"; Flags: dontcopy
Source: "InstallerMenu.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "InstallerIcons.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "InstallerRadio.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "asus-mode-radio.nss"; DestDir: "{tmp}"; Flags: dontcopy
Source: "icons\Fallback\Silent.ico"; DestDir: "{tmp}\icons\Fallback"; Flags: dontcopy
Source: "icons\Fallback\Performance.ico"; DestDir: "{tmp}\icons\Fallback"; Flags: dontcopy
Source: "icons\Fallback\Turbo.ico"; DestDir: "{tmp}\icons\Fallback"; Flags: dontcopy
Source: "Uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "InstallerRadio.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Code]
const
  MenuKey = 'Software\Classes\Directory\Background\shell\ArmouryCrateModes';
  LegacyMenuKey = 'Software\Classes\DesktopBackground\Shell\ASUSModes';
  GameLibraryKey = 'Software\Classes\Directory\Background\shell\GameLibrary';
var
  PlacementPage: TInputOptionWizardPage;
  RequestedPosition: String;
  PayloadExtracted: Boolean;
  SetupError: String;

function TryReadPlacement(Root: Integer; Key: String; var Value: String): Boolean;
begin
  Result := False;
  if RegQueryStringValue(Root, Key, 'ASUSModeShortcutsPosition', Value) then
    Result := (Value = 'Auto') or (Value = 'Top') or (Value = 'Bottom');
end;

function ReadPlacement: String;
var
  Value: String;
begin
  Result := 'Auto';
  if TryReadPlacement(HKLM64, GameLibraryKey, Value) then Result := Value;
  if TryReadPlacement(HKCU, LegacyMenuKey, Value) then Result := Value;
  if TryReadPlacement(HKLM64, MenuKey, Value) then Result := Value;
end;

procedure InitializeWizard;
var
  Value: String;
begin
  RequestedPosition := ExpandConstant('{param:MenuPosition|}');
  Value := RequestedPosition;
  if Value = '' then Value := ReadPlacement;
  PlacementPage := CreateInputOptionPage(wpWelcome, 'Desktop menu placement',
    'Choose where Armoury Crate Modes appears.',
    'This setting applies to the desktop right-click menu.', True, False);
  PlacementPage.Add('&Automatic');
  PlacementPage.Add('&Top');
  PlacementPage.Add('&Bottom');
  PlacementPage.SelectedValueIndex := 0;
  if CompareText(Value, 'Top') = 0 then PlacementPage.SelectedValueIndex := 1;
  if CompareText(Value, 'Bottom') = 0 then PlacementPage.SelectedValueIndex := 2;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = PlacementPage.ID) and (RequestedPosition <> '');
end;

function SelectedPlacement: String;
begin
  case PlacementPage.SelectedValueIndex of
    1: Result := 'Top';
    2: Result := 'Bottom';
  else
    Result := 'Auto';
  end;
end;

function RunPowerShell(Script, Arguments, ErrorFile: String): String;
var
  ExitCode: Integer;
  ErrorLines: TArrayOfString;
begin
  Result := '';
  DeleteFile(ErrorFile);
  if not Exec(
    ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "' + Script + '" ' + Arguments,
    ExtractFileDir(Script), SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    Result := 'Could not start Windows PowerShell. ' + SysErrorMessage(ExitCode)
  else if ExitCode <> 0 then begin
    Result := 'The setup script exited with code ' + IntToStr(ExitCode) + '.';
    if LoadStringsFromFile(ErrorFile, ErrorLines) and (GetArrayLength(ErrorLines) > 0) then
      Result := ErrorLines[0];
    Log(Result);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if CompareText(ExpandConstant('{app}'), ExpandConstant('{#AppFolder}')) <> 0 then begin
    Result := 'Setup uses the standard Program Files folder.';
    Exit;
  end;
  if (RequestedPosition <> '') and (CompareText(RequestedPosition, SelectedPlacement) <> 0) then begin
    Result := 'MenuPosition must be Auto, Top, or Bottom.';
    Exit;
  end;
  if not PayloadExtracted then begin
    ExtractTemporaryFiles('{tmp}\*');
    PayloadExtracted := True;
  end;
  Result := RunPowerShell(ExpandConstant('{tmp}\Setup.ps1'),
    '-CheckOnly -Packaged -MenuPosition ' + SelectedPlacement, ExpandConstant('{tmp}\setup-error.txt'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    WizardForm.StatusLabel.Caption := 'Registering hotkeys and the desktop menu...';
    SetupError := RunPowerShell(ExpandConstant('{tmp}\Setup.ps1'),
      '-Packaged -MenuPosition ' + SelectedPlacement, ExpandConstant('{tmp}\setup-error.txt'));
  end;
end;

procedure CurPageChanged(PageID: Integer);
begin
  if (PageID = wpFinished) and (SetupError <> '') then begin
    WizardForm.FinishedHeadingLabel.Caption := 'Setup could not finish';
    WizardForm.FinishedLabel.Caption := SetupError + #13#10#13#10 +
      'See setup-result.txt in %LOCALAPPDATA%\ASUS Mode Shortcuts. You can run Setup again or remove the app from Installed apps.';
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if SetupError <> '' then Result := 1;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ErrorFile, ErrorMessage: String;
begin
  if CurUninstallStep = usUninstall then begin
    ErrorFile := ExpandConstant('{tmp}\uninstall-error.txt');
    ErrorMessage := RunPowerShell(ExpandConstant('{app}\Uninstall.ps1'), '-ErrorFile "' + ErrorFile + '"', ErrorFile);
    if ErrorMessage <> '' then RaiseException(ErrorMessage);
  end;
end;
