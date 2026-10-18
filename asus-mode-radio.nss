// ASUS Mode Shortcuts: radio selection for the existing ArmouryCrate submenu.
// Only presentation changes here. Keep the registered icons, commands and order.
modify(in="ArmouryCrate" find='Silent' title="Silent"
    where=reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Silent','ASUSModeShortcuts') == '1' && str.equals(this.title,reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Silent','MUIVerb'))
    checked=(reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','IsLocked') == 0 && reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','SelectedMode') == 2 ? 2 : 0))
modify(in="ArmouryCrate" find='Performance' title="Performance"
    where=reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Performance','ASUSModeShortcuts') == '1' && str.equals(this.title,reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Performance','MUIVerb'))
    checked=(reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','IsLocked') == 0 && reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','SelectedMode') == 4 ? 2 : 0))
modify(in="ArmouryCrate" find='Turbo' title="Turbo"
    where=reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Turbo','ASUSModeShortcuts') == '1' && str.equals(this.title,reg.get('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts.Turbo','MUIVerb'))
    checked=(reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','IsLocked') == 0 && reg.get('HKLM\SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External','SelectedMode') == 8 ? 2 : 0))
