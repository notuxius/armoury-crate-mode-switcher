# Armoury Crate Mode Switcher

Switch directly between Silent, Performance, and Turbo using keyboard shortcuts or the existing ArmouryCrate desktop context menu. Requests go through Armoury Crate's service so its operating-mode selection stays in sync.

**For ASUS laptops whose Armoury Crate service exposes compatible operating modes.** Setup checks the ASUS manufacturer, 64-bit Windows, the running service and session endpoint, and published mode capabilities instead of requiring an exact model. Tested on the ROG Zephyrus M16 GU604VZ; other models have not yet been independently tested. This is an unofficial utility and uses an undocumented ASUS interface, which may change with ASUS updates.

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
- Modes appear inside the existing ArmouryCrate submenu, with a top/bottom placement choice during installation.
- No desktop shortcuts or separate ASUS Mode root menu.
- With Nilesoft Shell 1.9 or later, a left-side radio dot marks the selected mode. The default Windows classic menu uses a trailing checkmark.
- Selection follows changes made through Armoury Crate and Fn+F5. Reopen the context menu to refresh it; the classic-menu watcher checks once per second.

## Requirements

- 64-bit Windows on an ASUS computer with the compatible Armoury Crate operating-mode interface.
- ASUS System Control Interface, Armoury Crate, and their service/hotkey components installed and initialized.
- Armoury Crate's Game Library desktop context menu enabled.
- ASUS Optimization / AsusOSD enabled for the original popup.
- An administrator account for setup; a suitable AC adapter for Turbo mode.
- Windows .NET Framework compiler, used by setup to build the helper locally.

The Armoury Crate app window can remain closed after initialization, but its service and UserSessionHelper must be running. Nilesoft is optional and is not installed by this project. G-Helper is not required.

## Install

1. Install the ASUS prerequisites and open Armoury Crate once. Enable its Game Library right-click menu.
2. Download this repository using **Code > Download ZIP**, or clone it, and extract the complete folder.
3. Run `Install.cmd`, approve the Windows setup prompt, and choose **Top** or **Bottom** for the mode entries.
4. If Nilesoft is installed, hold Ctrl while right-clicking the desktop once to reload its configuration.
5. Use the hotkeys, or right-click the desktop and open **ArmouryCrate**. On the default Windows 11 menu, choose **Show more options** first.

To select placement without the setup selection window:

```bat
Install.cmd -MenuPosition Top
Install.cmd -MenuPosition Bottom
```

Rerun setup to update the helper or change placement. After reinstalling Windows, reinstall the ASUS prerequisites and run setup again; copying only the Start menu shortcuts is insufficient.

## Build

Run `Build.ps1` with Windows PowerShell. It compiles `AsusMode.cs` to a windowless `AsusMode.exe` and regenerates the menu ICO files from the supplied PNGs. Setup runs this build automatically; a precompiled executable is not tracked in Git.

## Ketarin

`ketarin/Armory Crate Mode.xml` imports a GitHub updater entry. Ketarin checks the latest commit on `main` and downloads that exact commit archive when it changes. The post-download PowerShell command validates and extracts it into `Package` beside the ZIP, retaining the previous extracted package as `Package.previous`.

By default downloads go to `..\_Drivers\ASUS\Armory Crate\Mode\_.zip` relative to Ketarin's startup directory. Change the target path for your layout; extraction and installation follow the downloaded ZIP location. **Update** downloads and prepares files; **Install** runs the downloaded setup and offers Top/Bottom placement. It does not change the installed helper merely because an update was downloaded. No GitHub login or token is required.

The readable post-download command is also provided as `ketarin/Extract-Package.ps1`; the XML embeds the same script so the first download works without a preinstalled bootstrap file.

## Selection and troubleshooting

The helper tracks the mode published by the ASUS service rather than measuring firmware state independently. Windows or Manual mode clears the indicator. Changes made directly by another driver tool are not reliably tracked. Nilesoft reads the published mode when the menu opens; if the ASUS service stops, its last published value can remain visible.

Logs are stored under `%LOCALAPPDATA%\ASUS Mode Shortcuts`:

- `setup-result.txt`: installation result.
- `last-result.txt`: latest mode request and confirmation.
- `watcher-status.txt`: background listener and hotkey registration status.

Other applications can reserve the same keyboard shortcuts. The helper retries unavailable hotkeys. If an Armoury Crate update recreates its menu, rerun setup to restore the mode entries.

Support files are installed under `%ProgramData%\ASUS Mode Shortcuts`. Full implementation notes, diagnostic commands, and removal instructions are in [README.txt](README.txt).

## ASUS artwork

Popup artwork is rendered by the installed ASUS software. The saved menu icons are ASUS artwork; their origin and resource names are documented in [icons/ASSETS.txt](icons/ASSETS.txt). These assets remain the property of their respective owner and do not automatically update when ASUS changes its icons. This project is not affiliated with or endorsed by ASUS.
