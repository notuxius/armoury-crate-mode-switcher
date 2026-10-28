ASUS MODE SHORTCUTS - ARMOURY CRATE SERVICE EDITION

For ASUS laptops with compatible Armoury Crate operating-mode services.
Tested on ASUS ROG Zephyrus M16 GU604VZ; other models are not independently tested.

DAILY USE
Right-click an empty area of the desktop, choose Show more options if shown,
then Armoury Crate Modes > Silent, Performance, or Turbo.
Setup offers Automatic, Top, or Bottom placement for this separate submenu.
Automatic uses Nilesoft to place it immediately above ArmouryCrate. If that
menu is hidden, it stays before Unblock or the next NVIDIA/New entry in that
section. Without Nilesoft, Automatic uses the normal Windows menu position.
It works even when Armoury Crate's Game Library menu is disabled or recreated.
No desktop shortcuts are created. Upgrading removes our three commands from
the old Game Library integration while retaining its other entries.

Ctrl+Alt+S: Silent.
Ctrl+Alt+P: Performance.
Ctrl+Alt+T: Turbo (requires a suitable AC power adapter).
The background helper registers the hotkeys directly for an immediate response.
Start > ASUS Mode Shortcuts also contains clickable mode entries.
The background helper starts automatically at sign-in; it has no visible window.
Daily use has no administrator prompt, confirmation dialog or terminal window.
Errors appear as a brief notification; successful changes use the ASUS popup.

MODE SWITCHING AND ARMOURY CRATE UI
The helper now requests the whole profile through Armoury Crate's service.
It no longer writes directly to the ASUS driver. The service applies its
normal profile settings and updates the selected mode in the Armoury Crate UI.
ArmouryCrateService and its UserSessionHelper must be running. The Armoury
Crate app window can be closed. Open the app once after installing it so
operating modes are initialized.

The helper uses ASUS's registered external-program message, verified against
the installed ThrottlePlugin, and confirms the result through the service's
published External.SelectedMode state. Locked or unavailable modes are rejected.
Requests select a mode directly; they do not cycle through other modes.
The deliberate one-second confirmation delay has been removed. The helper
continues as soon as ASUS reports the requested mode, with a bounded timeout
if the service does not respond. ASUS still takes time to apply profile settings.
There is no direct-driver fallback that would leave the app out of sync.
This is an undocumented ASUS interface; future ASUS updates may need changes.

MENU CHECKMARK
With Nilesoft Shell 1.9 or later already installed, the selected mode has a
radio dot in the left selection column, just like the desktop View menu.
The ASUS icons stay beside the labels; the trailing text checkmark is hidden.
Setup adds one import for imports/asus-mode-radio.nss to Nilesoft's shell.nss,
backing up the previous config in the support folder. It does not install
Nilesoft or add the retired ASUS Mode root-menu cleanup rule.
After installation, hold Ctrl while opening the desktop context menu once
to reload the configuration. Automatic placement needs Nilesoft; Top/Bottom also work with Windows menus.
Without Nilesoft, the classic menu retains its existing text checkmark.

The watcher reads the mode published by the Armoury Crate service once per
second. It follows our shortcuts, Armoury Crate UI selections and mode changes
that the service handles, including Fn+F5. The app may remain open.
Reopen the context menu to see the updated checkmark.
The radio dot reads Armoury Crate's published SelectedMode and IsLocked values
directly whenever the menu opens, avoiding a stale cached menu selection.
It disappears while IsLocked is set or Windows/Manual is selected. If the ASUS
service stops, its last published registry value may remain until it restarts.
The mark clears when the service is unavailable, changing/locking its mode,
or reports Windows or Manual. This reflects ASUS service state, not independent
firmware telemetry. Changes made directly by a third-party driver tool cannot
be detected reliably. Polling only reads state; mode changes occur only in
response to an explicit hotkey, menu or Start-entry request.

ORIGINAL ASUS POPUP AND ICONS
The installed ASUS AsusOSD component draws the popup with its built-in artwork,
layout and animation. If a service popup was observed during the request, the
helper does not request another. Otherwise it requests the original popup
only after the service confirms the selected mode. No imitation popup is used.
ASUS Optimization / AsusOSD must remain enabled to display it.
The popup uses its own ASUS resources, not images in this package.

The icons folder contains original ASUS THROTTLEGEAR_*6 PNG artwork and gray
multi-size ICO conversions for the menu and Start entries. Build.ps1 regenerates
the ICOs from the PNGs, preserving transparency. ASSETS.txt records their source.
These saved menu icons do not automatically change with ASUS software updates.
They remain ASUS artwork included in this personal setup package.

INSTALLATION AND WINDOWS REINSTALL
1. Keep the complete ASUS Mode Shortcuts.zip on USB or cloud storage.
2. Install the ASUS System Control Interface driver and Armoury Crate for the
   laptop, including its service and ASUS hotkey/OSD components. Restart if asked.
3. Open Armoury Crate once. Its Game Library right-click menu can stay disabled.
4. Extract the whole ZIP. Sign in to the Windows administrator account that
   will use these shortcuts. Run Install.cmd and approve Windows' one-time
   setup prompt. Setup also supports updates of an existing installation.
   Alternatively, update Armory Crate Mode in Ketarin, then choose Install.
   Ketarin downloads the latest GitHub main-branch commit to _.zip and extracts
   it into Package beside the ZIP. Updates alone do not reinstall the helper.
   Choose Automatic, Top, or Bottom in the setup window, then click Install. Setup remembers
   your selection for the next installation. Cancel leaves the installed menu
   unchanged. Rerun setup whenever you want to change the position.
5. Use the three hotkeys or Armoury Crate Modes submenu entries. Other applications
   can reserve the same keys; watcher-status.txt lists each registration result.
   The helper retries keys that are temporarily unavailable.

Copying only .lnk shortcuts is insufficient. Setup recreates their scheduled
tasks and support files. The extracted folder is not required after installation.
Setup checks for ASUS hardware, 64-bit Windows, the running Armoury Crate
service/session endpoint and published operating-mode capabilities. It does not
require an exact model. This is not a universal fan controller: incompatible
service interfaces are rejected, and unavailable modes are rejected per request.
The ASUS OSD is optional at runtime and may differ across ASUS software versions.

For installation without the position dialog, use Setup.ps1 -MenuPosition Auto,
Setup.ps1 -MenuPosition Top, or Setup.ps1 -MenuPosition Bottom. Install.cmd accepts the same argument.
The one-time Windows elevation prompt may still appear during installation.

IMPLEMENTATION AND DIAGNOSTICS
Support files: C:\ProgramData\ASUS Mode Shortcuts.
The ASUS Mode Checkmark Watcher task starts --watch at login. This existing
resident helper now also receives mode requests immediately, without waiting
for its one-second checkmark poll. Ctrl+Alt+S/P/T are registered directly with
Windows; Explorer's shortcut hotkey launcher is no longer used.
Start links and menu entries use --request to signal a per-user, per-session
fixed mode event. Only the current user and SYSTEM have access; no arbitrary
command or path is accepted. The background worker calls Armoury Crate's
service and displays its original OSD without launching another process.
Three on-demand scheduled mode tasks remain as a recovery path if the resident
helper is absent. They have no automatic triggers and are not used for normal
switches. No shell or script interpreter runs during daily use, and no G-Helper
or additional third-party app is required.

Setup builds the windowless helper with the Windows .NET Framework compiler,
protects the installed files, and creates the tasks and shortcuts. It uses
64-bit Windows PowerShell even when launched by 32-bit Ketarin. Setup requires
the initialized Armoury Crate service endpoint and its published mode state.
It does not patch ASUS binaries, edit ASUS's selected-mode registry values,
or stop/restart ASUS services to force a refresh.

Logs under %LOCALAPPDATA%\ASUS Mode Shortcuts:
setup-result.txt: installation result.
last-result.txt: most recent mode request, confirmation and helper processing time.
The logged time excludes keyboard/menu dispatch and is not hardware settling time.
watcher-status.txt: request listener status and S/P/T hotkey registrations.

--check validates the service endpoint and mode information without switching.
--osd-test Silent/Performance/Turbo displays only a popup, with no mode change.
The diagnostic's exit code 0 confirms that the native popup window was visible.

REMOVAL
Open Task Scheduler as administrator, end and delete ASUS Mode Checkmark
Watcher, then delete these three tasks from the
Task Scheduler Library: ASUS Silent Mode, ASUS Performance Mode, ASUS Turbo Mode.
Delete ASUS Mode Shortcuts from the current user's Start menu Programs folder
and the ASUS Mode Shortcuts support folder under ProgramData.
To remove the modes submenu, delete this package-owned key:
HKEY_LOCAL_MACHINE\Software\Classes\Directory\Background\shell\ArmouryCrateModes
It has the ASUSModeShortcuts ownership marker and title Armoury Crate Modes.
Do not delete ASUS's GameLibrary key.
Remove these three package command keys under
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell:
ASUSModeShortcuts.Silent, ASUSModeShortcuts.Performance, ASUSModeShortcuts.Turbo.
No ASUS driver needs to be removed.
If Nilesoft is installed, also remove the imports/asus-mode-radio.nss import
from shell.nss and the package-owned asus-mode-radio.nss file, then reload it.
