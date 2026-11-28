# Armoury Crate Mode Switcher

**Unofficial project.** This utility is independently maintained and has no affiliation, sponsorship, or endorsement from ASUS. References to ASUS and Armoury Crate identify the hardware and software it works with.

Switch directly between Silent, Performance, and Turbo using keyboard shortcuts or a separate **Armoury Crate Modes** desktop context menu. Requests go through Armoury Crate's service so its operating-mode selection stays in sync.

**For ASUS laptops whose Armoury Crate service exposes compatible operating modes.** Setup checks the ASUS manufacturer, 64-bit Windows, the running service and session endpoint, and published mode capabilities instead of requiring an exact model. Tested on the ROG Zephyrus M16 GU604VZ; other models have not yet been independently tested. The utility uses an undocumented ASUS interface, which may change with ASUS updates.

## Features

| Action | Shortcut |
| --- | --- |
| Silent | Ctrl+Alt+S |
| Performance | Ctrl+Alt+P |
| Turbo | Ctrl+Alt+T |

- Direct mode selection without cycling through intermediate modes.
- A windowless background helper starts at sign-in and handles requests immediately.
- Daily switching has no administrator prompt, confirmation dialog, or terminal window. Installation requires elevation once.
- The original installed ASUS OSD displays successful changes.
- An independent **Armoury Crate Modes** submenu stays available when Armoury Crate's Game Library menu is disabled or recreated. Setup offers Automatic, Top, or Bottom placement on the desktop menu. Automatic uses Nilesoft to place it directly above ArmouryCrate; if that menu is hidden, it stays in the same section before Unblock or the next available NVIDIA/New entry.
- No desktop shortcuts. Upgrading removes only our mode commands from the old Game Library integration, retaining its other entries.
- With Nilesoft Shell 1.9 or later, a left-side radio dot marks the selected mode. The default Windows classic menu uses a trailing checkmark. Without Nilesoft, Automatic leaves positioning to Windows; exact placement relative to another menu requires Nilesoft.
- Selection follows changes made through Armoury Crate and Fn+F5. The classic-menu watcher uses registry notifications, with a periodic service health check. Reopen the context menu to see the current selection.
- If several requests arrive during a switch, the helper applies the newest pending request after the current switch finishes.

## Requirements

- 64-bit Windows on an ASUS computer with the compatible Armoury Crate operating-mode interface.
- ASUS System Control Interface, Armoury Crate, and their service/hotkey components installed and initialized.
- ASUS Optimization / AsusOSD enabled for the original popup.
- An administrator account for setup; a suitable AC adapter for Turbo mode.
- Windows .NET Framework, used by the prebuilt helper.

The Armoury Crate app window can remain closed after initialization, but its service and UserSessionHelper must be running. Nilesoft is optional and is not installed by this project. G-Helper is not required.

## Install

1. Install the ASUS prerequisites and open Armoury Crate once. Its Game Library right-click menu can remain disabled.
2. Download `Armoury-Crate-Mode-Switcher-v*-Setup.exe` from the [latest GitHub release](https://github.com/notuxius/armoury-crate-mode-switcher/releases/latest).
3. Sign in to the Windows administrator account that will use the shortcuts. Run the installer, approve the Windows setup prompt, and choose **Automatic**, **Top**, or **Bottom** for the separate desktop submenu.
4. If Nilesoft is installed, hold Ctrl while right-clicking the desktop once to reload its configuration.
5. Use the hotkeys, or right-click the desktop and open **Armoury Crate Modes**. On the default Windows 11 menu, choose **Show more options** first.

Rerun setup to update the helper or change placement. The wizard preselects your saved position. For automation, the installer accepts `/MenuPosition=Auto`, `/MenuPosition=Top`, or `/MenuPosition=Bottom` and the standard Inno Setup silent switches.

To remove the utility, use **Settings → Apps → Installed apps → Armoury Crate Mode Switcher → Uninstall** from the account that installed it. If you use Nilesoft, reload its menu afterward by holding Ctrl while right-clicking the desktop.

## Build

Run `Build.ps1` with Windows PowerShell to compile the windowless `AsusMode.exe`. To build the release installer, install Inno Setup 6 and run `./Build-Installer.ps1 -Version 1.4.0`. The resulting installer is in `dist` and includes the compiled helper. Setup prepares the menu icons during installation.

## Selection and troubleshooting

The helper tracks the mode published by the ASUS service rather than measuring firmware state independently. Windows or Manual mode clears the indicator. Changes made directly by another driver tool are not reliably tracked. Nilesoft reads the published mode when the menu opens; if the ASUS service stops, its last published value can remain visible.

Logs are stored under `%LOCALAPPDATA%\ASUS Mode Shortcuts`:

- `setup-result.txt`: installation result.
- `last-result.txt`: latest mode request and confirmation. Successful requests include `DispatchMs`, `ConfirmMs`, and `OsdMs`.
- `watcher-status.txt`: background listener and hotkey registration status.
- `watcher-error.txt`: watcher, menu, and diagnostics errors.

Other applications can reserve the same keyboard shortcuts. The helper retries unavailable hotkeys. The separate modes menu does not depend on ASUS maintaining its Game Library menu registration.

Setup installs the launcher under `%LOCALAPPDATA%\Programs\Armoury Crate Mode Switcher` and creates Silent, Performance, and Turbo shortcuts under **Start → ASUS Mode Shortcuts**. The elevated background helper and its support files stay under `%ProgramData%\ASUS Mode Shortcuts`. Full implementation notes, diagnostic commands, and removal instructions are in [README.txt](README.txt).

## Menu icons and ASUS popup

The helper executable, setup dialog, and **Armoury Crate Modes** submenu use the project's original app icon.

Setup creates the Silent, Performance, and Turbo icons for the submenu and Start shortcuts from compatible mode artwork in the installed ASUS-signed `ATKOSD2Help.dll`. The installer includes the project's app icon and original fallback mode icons. Setup uses the corresponding fallback if an ASUS image is unavailable. Rerun setup to refresh the mode icons after an ASUS update.

The installed ASUS software draws its own mode-switch popup.

## License

The utility’s original code and icons are available under the [MIT License](LICENSE). The installed DLL identifies ASUSTeK COMPUTER INC. as its copyright holder. The artwork read from it is subject to the applicable ASUS software license.
