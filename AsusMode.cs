using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Text;

internal static class Program {
    internal const string StateKey = @"Software\ASUSModeShortcuts";
    internal static string Root = AppDomain.CurrentDomain.BaseDirectory;
    internal static string[] Modes = { "Silent", "Performance", "Turbo" };

    [STAThread]
    static int Main(string[] args) {
        try {
            // The normal menu path only signals an already-running helper.
            if (args.Length == 2 && args[0] == "--request" && Array.IndexOf(Modes, args[1]) >= 0) {
                if (ModeRequests.TrySend(args[1])) return 0;
                // Recovery only: preserve prompt-free operation if the resident helper is absent.
                dynamic scheduler = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
                scheduler.Connect();
                scheduler.GetFolder(@"\").GetTask("ASUS " + args[1] + " Mode").Run(null);
                return 0;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (args.Length == 1 && args[0] == "--check") { ArmouryService.Check(); return 0; }
            if (args.Length == 1 && args[0] == "--refresh-menu") { ModeMenu.Refresh(); return 0; }
            if (args.Length == 1 && args[0] == "--clear-checkmark") { ModeMenu.Invalidate("Manual diagnostic"); return 0; }
            if (args.Length == 1 && args[0] == "--stop-watch") { ModeWatcher.Stop(); return 0; }
            if (args.Length == 1 && args[0] == "--watch") {
                bool first;
                using (var single = new System.Threading.Mutex(true, @"Local\ASUSModeCheckmarkWatcher", out first)) {
                    if (!first) return 0;
                    using (var watcher = new ModeWatcher()) Application.Run(watcher);
                }
                return 0;
            }
            if (args.Length < 2 || Array.IndexOf(Modes, args[1]) < 0) return 2;
            string mode = args[1];
            if (args[0] == "--osd-test") return NativeAsusOsd.Show(mode) ? 0 : 3;
            if (args[0] != "--apply") return 2;
            return ApplyMode(mode);
        } catch (Exception error) {
            Log(error.ToString());
            if (args.Length > 0 && (args[0] == "--apply" || args[0] == "--request"))
                Application.Run(new ModeToast(error is InvalidOperationException ? error.Message : "Could not change mode", true, null));
            return 1;
        }
    }

    internal static int ApplyMode(string mode) {
        var elapsed = Stopwatch.StartNew();
            if (mode == "Turbo" && SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline)
                throw new InvalidOperationException("Connect AC power for Turbo mode");
            bool servicePopup = ArmouryService.Select(mode);
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(StateKey)) {
                key.SetValue("LastAppliedMode", mode);
                key.SetValue("LastAppliedUtc", DateTime.UtcNow.ToString("o"));
            }
            ModeMenu.Select(mode);
            bool nativeShown = servicePopup || NativeAsusOsd.Show(mode);
            Log("Armoury Crate service confirmed " + mode + (nativeShown ? "; ASUS native OSD displayed" : "; ASUS native OSD unavailable (no replacement popup shown)") + "; helper processing " + elapsed.ElapsedMilliseconds + " ms");
            return 0;
    }
    internal static void ShowError(Exception error) {
        Log(error.ToString());
        Application.Run(new ModeToast(error is InvalidOperationException ? error.Message : "Could not change mode", true, null));
    }

    internal static void Log(string message) {
        try {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ASUS Mode Shortcuts");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "last-result.txt"), DateTime.Now.ToString("s") + " " + message);
        } catch { }
    }
}

internal static class ModeMenu {
    static void Locked(Action action) {
        using (var gate = new System.Threading.Mutex(false, @"Local\ASUSModeMenuState")) {
            bool owned = false;
            try {
                try { owned = gate.WaitOne(3000); } catch (System.Threading.AbandonedMutexException) { owned = true; }
                if (!owned) throw new TimeoutException("Mode menu state is busy");
                action();
            } finally { if (owned) gate.ReleaseMutex(); }
        }
    }
    internal static void Select(string mode) {
        Locked(delegate {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(Program.StateKey)) key.SetValue("CheckedMode", mode);
            RefreshCore();
        });
    }
    internal static void Invalidate(string reason) {
        Locked(delegate {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(Program.StateKey)) {
                key.SetValue("CheckedMode", "");
                key.SetValue("LastInvalidatedReason", reason);
                key.SetValue("LastInvalidatedUtc", DateTime.UtcNow.ToString("o"));
            }
            RefreshCore();
        });
    }
    internal static void Refresh() { Locked(RefreshCore); }
    static void RefreshCore() {
        string selected;
        using (RegistryKey state = Registry.CurrentUser.OpenSubKey(Program.StateKey))
            selected = state == null ? null : state.GetValue("CheckedMode") as string;
        foreach (string mode in Program.Modes) {
            using (RegistryKey entry = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts." + mode, true)) {
                if (entry == null || (string)entry.GetValue("ASUSModeShortcuts", "") != "1") continue;
                // Keep ASUS icons; the checkmark is alongside the selected mode's label.
                // This reflects Armoury Crate service state, not raw firmware telemetry.
                string label = mode == selected ? mode + "  \u2713" : mode;
                entry.SetValue("MUIVerb", label, RegistryValueKind.String);
                entry.SetValue("", label, RegistryValueKind.String);
            }
        }
    }
}

// Only the current user and SYSTEM can signal these fixed mode actions.
// No arbitrary command, file path or other privileged operation is accepted.
internal static class ModeRequests {
    internal static string Name(string mode) { return @"Local\ASUSArmouryFastMode." + mode; }
    internal static EventWaitHandle Create(string mode) {
        var security = new EventWaitHandleSecurity();
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new EventWaitHandleAccessRule(WindowsIdentity.GetCurrent().User, EventWaitHandleRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new EventWaitHandleAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), EventWaitHandleRights.FullControl, AccessControlType.Allow));
        bool created;
        return new EventWaitHandle(false, EventResetMode.AutoReset, Name(mode), out created, security);
    }
    internal static bool TrySend(string mode) {
        try {
            using (var signal = EventWaitHandle.OpenExisting(Name(mode), EventWaitHandleRights.Modify)) signal.Set();
            return true;
        } catch (WaitHandleCannotBeOpenedException) { return false; }
          catch (UnauthorizedAccessException) { return false; }
    }
}

// A message-only window registers the three hotkeys; it never takes focus.
internal sealed class ModeHotkeys : NativeWindow, IDisposable {
    readonly EventWaitHandle[] requests;
    readonly bool[] registered = new bool[3];
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window, int id);
    internal ModeHotkeys(EventWaitHandle[] requests) {
        this.requests = requests;
        CreateHandle(new CreateParams { Caption = "ASUS Mode Hotkeys", Parent = new IntPtr(-3) });
        RegisterMissing();
    }
    internal void RegisterMissing() {
        uint[] keys = { 0x53, 0x50, 0x54 };
        for (int i = 0; i < 3; i++)
            if (!registered[i]) registered[i] = RegisterHotKey(Handle, i + 1, 0x4003, keys[i]);
    }
    internal string Status {
        get { return "S=" + registered[0] + ", P=" + registered[1] + ", T=" + registered[2]; }
    }
    protected override void WndProc(ref Message message) {
        if (message.Msg == 0x0312) {
            int index = message.WParam.ToInt32() - 1;
            if (index >= 0 && index < 3) requests[index].Set();
        }
        base.WndProc(ref message);
    }
    public void Dispose() {
        for (int i = 0; i < 3; i++) if (registered[i]) UnregisterHotKey(Handle, i + 1);
        DestroyHandle();
    }
}

// The existing resident watcher also handles requests immediately on a worker.
internal sealed class ModeWatcher : ApplicationContext {
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly EventWaitHandle stop = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\ASUSModeCheckmarkStop");
    readonly EventWaitHandle[] requests = new EventWaitHandle[3];
    readonly Thread worker;
    readonly ModeHotkeys hotkeys;
    string lastHotkeyStatus;
    internal ModeWatcher() {
        stop.Reset();
        for (int i = 0; i < 3; i++) requests[i] = ModeRequests.Create(Program.Modes[i]);
        worker = new Thread(RunRequests) { IsBackground = true, Name = "ASUS mode requests" };
        worker.SetApartmentState(ApartmentState.STA);
        worker.Start();
        hotkeys = new ModeHotkeys(requests);
        RefreshState();
        UpdateStatus();
        timer.Interval = 1000;
        timer.Tick += delegate {
            if (stop.WaitOne(0)) { ExitThread(); return; }
            hotkeys.RegisterMissing(); UpdateStatus(); RefreshState();
        };
        timer.Start();
    }
    void RunRequests() {
        WaitHandle[] handles = { stop, requests[0], requests[1], requests[2] };
        while (true) {
            int index = WaitHandle.WaitAny(handles);
            if (index == 0) return;
            try { Program.ApplyMode(Program.Modes[index - 1]); }
            catch (Exception error) { Program.ShowError(error); }
        }
    }
    void UpdateStatus() {
        string status = hotkeys.Status;
        if (status == lastHotkeyStatus) return;
        lastHotkeyStatus = status;
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ASUS Mode Shortcuts");
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "watcher-status.txt"), DateTime.Now.ToString("s") + " Fast request listener active; hotkeys " + status + "; tracking Armoury Crate service state");
    }
    static void RefreshState() {
        try {
            string mode = ArmouryService.CurrentMode();
            string previous;
            using (RegistryKey state = Registry.CurrentUser.OpenSubKey(Program.StateKey))
                previous = state == null ? "" : state.GetValue("CheckedMode", "") as string;
            if (mode != previous) {
                if (String.IsNullOrEmpty(mode)) ModeMenu.Invalidate("Armoury Crate mode unavailable, changing, Windows or Manual");
                else ModeMenu.Select(mode);
            }
        } catch { try { ModeMenu.Invalidate("Armoury Crate state unavailable"); } catch { } }
    }
    internal static void Stop() {
        try { using (var signal = EventWaitHandle.OpenExisting(@"Local\ASUSModeCheckmarkStop")) signal.Set(); }
        catch (WaitHandleCannotBeOpenedException) { }
    }
    protected override void Dispose(bool disposing) {
        if (disposing) {
            timer.Stop(); timer.Dispose(); hotkeys.Dispose(); stop.Set();
            if (worker.Join(2000)) {
                foreach (var request in requests) request.Dispose();
                stop.Dispose();
            }
        }
        base.Dispose(disposing);
    }
}

// Registered external-program interface implemented by the installed ASUS
// ThrottlePlugin. wParam=2 selects one bit: Silent=2, Performance=4, Turbo=8.
// This queues the service's normal full-profile job and its UWP notifications.
internal static class ArmouryService {
    const string ExternalKey = @"SOFTWARE\ASUS\ARMOURY CRATE Service\ThrottlePlugin\External";
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wp, IntPtr lp, uint flags, uint timeout, out UIntPtr result);
    static IntPtr Endpoint() {
        IntPtr window = FindWindow("UserSessionManagerEventClass", "User Session Helper Window");
        if (window == IntPtr.Zero) throw new InvalidOperationException("Start the Armoury Crate service to change mode");
        uint pid; GetWindowThreadProcessId(window, out pid);
        using (Process owner = Process.GetProcessById((int)pid)) {
            string expected = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"ASUS\Armoury Crate Service\ArmouryCrate.UserSessionHelper.exe");
            if (owner.SessionId != Process.GetCurrentProcess().SessionId ||
                !String.Equals(owner.MainModule.FileName, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Armoury Crate service endpoint could not be verified");
        }
        using (var service = new System.ServiceProcess.ServiceController("ArmouryCrateService"))
            if (service.Status != System.ServiceProcess.ServiceControllerStatus.Running)
                throw new InvalidOperationException("Start the Armoury Crate service to change mode");
        return window;
    }
    static int Value(RegistryKey key, string name) {
        object value = key.GetValue(name);
        if (!(value is int)) throw new InvalidOperationException("Armoury Crate mode information is unavailable");
        return (int)value;
    }
    internal static void Check() {
        Endpoint();
        using (RegistryKey key = Registry.LocalMachine.OpenSubKey(ExternalKey)) {
            if (key == null) throw new InvalidOperationException("Open Armoury Crate once to initialize operating modes");
            Value(key, "SelectedMode"); Value(key, "EnabledModes"); Value(key, "IsLocked");
        }
    }
    internal static string CurrentMode(bool validateEndpoint = true) {
        try {
            if (validateEndpoint) Endpoint();
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(ExternalKey)) {
                if (key == null || Value(key, "IsLocked") != 0) return "";
                int mode = Value(key, "SelectedMode");
                return mode == 2 ? "Silent" : mode == 4 ? "Performance" : mode == 8 ? "Turbo" : "";
            }
        } catch { return ""; }
    }
    internal static bool Select(string mode) {
        using (var gate = new System.Threading.Mutex(false, @"Local\ASUSArmouryModeRequest")) {
            bool owned = false;
            try {
                try { owned = gate.WaitOne(15000); } catch (System.Threading.AbandonedMutexException) { owned = true; }
                if (!owned) throw new InvalidOperationException("Another mode change is still running");
                IntPtr window = Endpoint();
                int mask = mode == "Silent" ? 2 : mode == "Performance" ? 4 : 8;
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(ExternalKey)) {
                    if (key == null) throw new InvalidOperationException("Open Armoury Crate once to initialize operating modes");
                    if (Value(key, "IsLocked") != 0) throw new InvalidOperationException("Armoury Crate is busy changing profiles");
                    if ((Value(key, "EnabledModes") & mask) == 0) throw new InvalidOperationException("This mode is currently unavailable in Armoury Crate");
                }
                uint message = RegisterWindowMessage("Operating Mode Notification from External Program");
                UIntPtr result;
                if (message == 0 || SendMessageTimeout(window, message, new UIntPtr(2), new IntPtr(mask), 2, 3000, out result) == IntPtr.Zero)
                    throw new InvalidOperationException("Armoury Crate did not receive the mode request");
                // Delivery alone is not acceptance. Confirm the service's own state.
                var watch = Stopwatch.StartNew();
                bool sawPopup = false;
                while (watch.ElapsedMilliseconds < 15000) {
                    sawPopup |= NativeAsusOsd.Visible();
                    if (CurrentMode(false) == mode) return sawPopup;
                    System.Threading.Thread.Sleep(10);
                }
                throw new InvalidOperationException("Armoury Crate did not confirm the requested mode");
            } finally { if (owned) gate.ReleaseMutex(); }
        }
    }
}

// Display-only message verified against this laptop's installed ASUS OSD.
// ASUS owns the window, rendering, icons, placement and dismissal animation.
internal static class NativeAsusOsd {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindow(string className, string windowName);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);

    internal static bool Visible() {
        IntPtr window = FindWindow("CNewOsd", null);
        return window != IntPtr.Zero && IsWindowVisible(window);
    }

    internal static bool Show(string mode) {
        try {
            IntPtr window = FindWindow("CNewOsd", null);
            if (window == IntPtr.Zero) return false;
            uint pid;
            GetWindowThreadProcessId(window, out pid);
            using (Process owner = Process.GetProcessById((int)pid)) {
                if (!String.Equals(owner.ProcessName, "AsusOSD", StringComparison.OrdinalIgnoreCase) ||
                    owner.SessionId != Process.GetCurrentProcess().SessionId) return false;
            }
            // Armoury Crate uses the 200-series THROTTLEGEAR_*6 artwork.
            // 207 selects "Performance"; 200 would show "Balanced".
            // These are display-only IDs, not the driver's 2/0/1 mode values.
            uint value = mode == "Silent" ? 202u : mode == "Turbo" ? 201u : 207u;
            UIntPtr result;
            if (SendMessageTimeout(window, 0x5F7, new UIntPtr((value << 16) | 0xAEu), IntPtr.Zero,
                0x0002, 1500, out result) == IntPtr.Zero || result.ToUInt64() != 1) return false;
            // The ASUS window starts drawing on its next 41 ms animation tick.
            var draw = Stopwatch.StartNew();
            while (!IsWindowVisible(window) && draw.ElapsedMilliseconds < 250) System.Threading.Thread.Sleep(10);
            return IsWindowVisible(window);
        } catch { return false; }
    }
}

internal sealed class ModeToast : Form {
    readonly string label, popupId;
    readonly bool error;
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly Stopwatch clock = new Stopwatch();
    Image modeIcon;
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000020; return cp; }
    }
    internal ModeToast(string mode, bool isError, string id) {
        label = mode; error = isError; popupId = id;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None; ClientSize = new Size(328, 132);
        BackColor = Color.FromArgb(22, 23, 27);
        DoubleBuffered = true;
        Text = "ASUS Mode notification";
        Rectangle area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(area.Left + (area.Width - Width) / 2, area.Bottom - Height - 56);
        using (GraphicsPath shape = Rounded(new RectangleF(0, 0, Width, Height), 14)) Region = new Region(shape);
        string iconPath = Path.Combine(Program.Root, "icons", mode + ".png");
        if (!isError && File.Exists(iconPath)) modeIcon = Image.FromFile(iconPath);
        timer.Interval = 30;
        timer.Tick += delegate {
            if (popupId != null) {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(Program.StateKey)) {
                    if (key != null && (string)key.GetValue("PopupId", "") != popupId) { Close(); return; }
                }
            }
            double ms = clock.Elapsed.TotalMilliseconds;
            double duration = error ? 3200 : 1900;
            if (ms >= duration) { Close(); return; }
            Opacity = Math.Min(1, Math.Min(ms / 120, (duration - ms) / 220)) * 0.97;
        };
        Shown += delegate { Opacity = 0; clock.Start(); timer.Start(); };
    }
    static GraphicsPath Rounded(RectangleF r, float radius) {
        GraphicsPath p = new GraphicsPath(); float d = radius * 2;
        p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90); p.CloseFigure(); return p;
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e); Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (Pen border = new Pen(Color.FromArgb(65, 66, 72)))
        using (GraphicsPath outline = Rounded(new RectangleF(0.5f,0.5f,Width-1,Height-1),14)) g.DrawPath(border,outline);
        using (SolidBrush red = new SolidBrush(Color.FromArgb(237, 38, 70)))
            g.FillPolygon(red, new Point[] {new Point(25,0),new Point(118,0),new Point(110,3),new Point(25,3)});
        if (modeIcon != null) g.DrawImage(modeIcon, new Rectangle(25, 35, 62, 62));
        using (Font small = new Font("Segoe UI", 8.5f, FontStyle.Bold))
        using (Font title = new Font("Segoe UI", error ? 13 : 21, FontStyle.Regular))
        using (SolidBrush muted = new SolidBrush(Color.FromArgb(153, 155, 164)))
        using (SolidBrush white = new SolidBrush(Color.FromArgb(242, 242, 242))) {
            float x = error ? 24 : 106;
            g.DrawString(error ? "MODE UNAVAILABLE" : "OPERATING MODE", small, muted, x, 28);
            g.DrawString(label, title, white, new RectangleF(x, 48, Width-x-16, 58));
        }
    }
    protected override void Dispose(bool disposing) {
        if (disposing) { timer.Dispose(); if (modeIcon != null) modeIcon.Dispose(); }
        base.Dispose(disposing);
    }
}
