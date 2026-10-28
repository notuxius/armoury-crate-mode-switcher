// ASUS Mode Shortcuts: radio selection for the independent Armoury Crate Modes submenu.
// Auto placement follows the visible ASUS menu, then its usual following entries.
modify(type="desktop|dir.back" mode="none" find='Armoury Crate Modes'
    where=str.equals(this.title,'Armoury Crate Modes') && reg.get('HKLM\Software\Classes\Directory\Background\shell\ArmouryCrateModes','ASUSModeShortcutsPosition') == 'Auto'
    pos=indexof('ArmouryCrate|Unblock|NVIDIA App|NVIDIA Control Panel|New', 0, pos.middle))
// Keep the registered icons and commands; only change selection presentation.
modify(in="Armoury Crate Modes" find='Silent' title="Silent"
    where=reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Silent','ASUSModeShortcuts') == '1' && str.equals(this.title,reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Silent','MUIVerb'))
    checked=(reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','IsLocked') == 0 && reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','SelectedMode') == 2 ? 2 : 0))
modify(in="Armoury Crate Modes" find='Performance' title="Performance"
    where=reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Performance','ASUSModeShortcuts') == '1' && str.equals(this.title,reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Performance','MUIVerb'))
    checked=(reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','IsLocked') == 0 && reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','SelectedMode') == 4 ? 2 : 0))
modify(in="Armoury Crate Modes" find='Turbo' title="Turbo"
    where=reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Turbo','ASUSModeShortcuts') == '1' && str.equals(this.title,reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Turbo','MUIVerb'))
    checked=(reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','IsLocked') == 0 && reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','SelectedMode') == 8 ? 2 : 0))
