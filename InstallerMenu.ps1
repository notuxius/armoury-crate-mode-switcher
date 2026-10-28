function Remove-AsusModeMenuCommands {
    param([AllowEmptyString()][string]$ExistingCommands)
    $modes = @('ASUSModeShortcuts.Silent','ASUSModeShortcuts.Performance','ASUSModeShortcuts.Turbo')
    $commands = @($ExistingCommands -split ';')
    if (-not @($commands | Where-Object { $_ -in $modes }).Count) { return $ExistingCommands }
    $original = @($commands | Where-Object { $_ -and $_ -notin $modes })
    while ($original.Count -gt 0 -and $original[0] -eq '|') { $original = @($original | Select-Object -Skip 1) }
    while ($original.Count -gt 0 -and $original[-1] -eq '|') { $original = @($original | Select-Object -SkipLast 1) }
    return (($original -join ';') -replace '(\|;)+\|','|')
}

function Show-AsusModeMenuPosition {
    param([ValidateSet('Top','Bottom')][string]$DefaultPosition = 'Top')
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    # Hidden launchers must hide the console, not this installer-owned dialog.
    if (-not ('AsusModeSetupDialog' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class AsusModeSetupDialog : Form {
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    protected override void OnShown(EventArgs e) {
        base.OnShown(e);
        ShowWindow(Handle, 5);
        Activate();
    }
}
'@
    }
    [Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object AsusModeSetupDialog
    try {
        $form.Text = 'Armory Crate Mode - Setup'
        $form.Font = New-Object Drawing.Font('Segoe UI', 10)
        $form.AutoScaleDimensions = New-Object Drawing.SizeF(96,96)
        $form.AutoScaleMode = 'Dpi'
        $form.ClientSize = New-Object Drawing.Size(490,238)
        $form.FormBorderStyle = 'FixedDialog'
        $form.StartPosition = 'CenterScreen'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        $label = New-Object Windows.Forms.Label
        $label.Text = "Where should the Armoury Crate Modes submenu`r`nappear on the desktop right-click menu?"
        $label.Location = New-Object Drawing.Point(20,18)
        $label.Size = New-Object Drawing.Size(450,52)
        $top = New-Object Windows.Forms.RadioButton
        $top.Text = '&Top of the desktop menu'
        $top.Location = New-Object Drawing.Point(24,82)
        $top.Size = New-Object Drawing.Size(440,30)
        $top.TabIndex = 0
        $bottom = New-Object Windows.Forms.RadioButton
        $bottom.Text = '&Bottom of the desktop menu'
        $bottom.Location = New-Object Drawing.Point(24,120)
        $bottom.Size = New-Object Drawing.Size(440,30)
        $bottom.TabIndex = 1
        $top.Checked = $DefaultPosition -eq 'Top'
        $bottom.Checked = $DefaultPosition -eq 'Bottom'
        $install = New-Object Windows.Forms.Button
        $install.Text = '&Install'
        $install.Location = New-Object Drawing.Point(254,187)
        $install.Size = New-Object Drawing.Size(100,32)
        $install.DialogResult = 'OK'
        $install.TabIndex = 2
        $cancel = New-Object Windows.Forms.Button
        $cancel.Text = 'Cancel'
        $cancel.Location = New-Object Drawing.Point(366,187)
        $cancel.Size = New-Object Drawing.Size(100,32)
        $cancel.DialogResult = 'Cancel'
        $cancel.TabIndex = 3
        $form.Controls.AddRange(@($label,$top,$bottom,$install,$cancel))
        $form.AcceptButton = $install
        $form.CancelButton = $cancel
        if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
        if ($bottom.Checked) { return 'Bottom' }
        return 'Top'
    } finally { $form.Dispose() }
}
