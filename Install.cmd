@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" %*
if "%errorlevel%"=="2" exit /b 2
if errorlevel 1 (
    echo Setup did not complete. See the error message above.
) else (
    echo Silent, Performance and Turbo are ready in the separate Armoury Crate Modes menu.
    echo On Windows 11, select Show more options if needed.
    echo No desktop shortcuts are created. The background helper handles hotkeys.
    echo Silent: Ctrl+Alt+S    Performance: Ctrl+Alt+P    Turbo: Ctrl+Alt+T
    echo Each change shows a brief mode indicator. No admin or confirmation prompts.
)
pause
