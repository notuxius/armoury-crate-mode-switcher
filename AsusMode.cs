using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using Microsoft.Win32.SafeHandles;

internal static class Program {
    internal const string StateKey = @"Software\ASUSModeShortcuts";
    internal static string[] Modes = { "Silent", "Performance", "Turbo" };

    [STAThread]
    static int Main(string[] args) {
        long received = Stopwatch.GetTimestamp();
        try {
            // The normal menu path only signals an already-running helper.
            if (args.Length == 2 && args[0] == "--request" && Array.IndexOf(Modes, args[1]) >= 0) {
                if (ModeRequests.TrySend(Array.IndexOf(Modes, args[1]), received)) return 0;
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
            ApplyMode(mode, received);
            RefreshMenuSafely(true, true);
            return 0;
        } catch (Exception error) {
            Log(error.ToString(), args.Length == 1 && args[0] == "--watch" ? "watcher-error.txt" : "last-result.txt");
            if (args.Length > 0 && (args[0] == "--apply" || args[0] == "--request"))
                Application.Run(new ModeToast(ErrorMessage(error)));
            return 1;
        }
    }

    internal static void ApplyMode(string mode, long received) {
        long started = Stopwatch.GetTimestamp();
        if (mode == "Turbo" && SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline)
            throw new InvalidOperationException("Connect AC power for Turbo mode");
        bool servicePopup = ArmouryService.Select(mode);
        long confirmed = Stopwatch.GetTimestamp();
        bool nativeShown = servicePopup || NativeAsusOsd.Show(mode);
        long feedback = Stopwatch.GetTimestamp();
        Log("Armoury Crate service confirmed " + mode + (nativeShown ? "; ASUS native OSD observed" : "; ASUS native OSD unavailable")
            + "; DispatchMs=" + Milliseconds(received, started) + "; ConfirmMs=" + Milliseconds(started, confirmed)
            + "; OsdMs=" + Milliseconds(confirmed, feedback));
        try {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(StateKey)) {
                key.SetValue("LastAppliedMode", mode);
                key.SetValue("LastAppliedUtc", DateTime.UtcNow.ToString("o"));
            }
        } catch (Exception error) { Log(error.ToString(), "watcher-error.txt"); }
    }

    static long Milliseconds(long start, long end) {
        return (long)((end - start) * 1000.0 / Stopwatch.Frequency);
    }

    internal static void RefreshMenuSafely(bool serviceAvailable, bool repair = false) {
        try { ModeMenu.Sync(serviceAvailable, repair); }
        catch (Exception error) { Log(error.ToString(), "watcher-error.txt"); }
    }

    internal static string ErrorMessage(Exception error) {
        return error is InvalidOperationException ? error.Message : "Could not change mode";
    }

    internal static bool Log(string message, string file = "last-result.txt") {
        try {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ASUS Mode Shortcuts");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, file), DateTime.Now.ToString("s") + " " + message);
            return true;
        } catch { return false; }
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
    internal static void Sync(bool serviceAvailable, bool repair) {
        Locked(delegate {
            string mode = serviceAvailable ? ArmouryService.CurrentMode() : "";
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(Program.StateKey)) {
                if (!String.Equals(key.GetValue("CheckedMode") as string, mode)) {
                    RefreshCore(mode);
                    key.SetValue("CheckedMode", mode);
                } else if (repair) RefreshCore(mode);
            }
        });
    }
    internal static void Invalidate(string reason) {
        Locked(delegate {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(Program.StateKey)) {
                key.SetValue("CheckedMode", "");
                key.SetValue("LastInvalidatedReason", reason);
                key.SetValue("LastInvalidatedUtc", DateTime.UtcNow.ToString("o"));
            }
            RefreshCore("");
        });
    }
    internal static void Refresh() {
        Locked(delegate {
            using (RegistryKey state = Registry.CurrentUser.OpenSubKey(Program.StateKey))
                RefreshCore(state == null ? null : state.GetValue("CheckedMode") as string);
        });
    }
    static void RefreshCore(string selected) {
        foreach (string mode in Program.Modes) {
            using (RegistryKey entry = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\ASUSModeShortcuts." + mode, true)) {
                if (entry == null || (string)entry.GetValue("ASUSModeShortcuts", "") != "1") continue;
                // Keep the installed icon; the checkmark is alongside the selected mode's label.
                // This reflects Armoury Crate service state, not raw firmware telemetry.
                string label = mode == selected ? mode + "  \u2713" : mode;
                if (!String.Equals(entry.GetValue("MUIVerb") as string, label)) entry.SetValue("MUIVerb", label);
                if (!String.Equals(entry.GetValue("") as string, label)) entry.SetValue("", label);
            }
        }
    }
}

// The current user and SYSTEM can submit one of three fixed actions. The newest
// pending request replaces older requests without interrupting an active switch.
internal sealed class ModeRequests : IDisposable {
    const int SlotSize = 16;
    const int ModeOffset = 8;
    readonly MemoryMappedFile map;
    readonly MemoryMappedViewAccessor slot;
    readonly Mutex gate;
    internal readonly EventWaitHandle Signal;

    static string Prefix(SecurityIdentifier user) { return @"Local\ASUSArmouryFastMode.v2." + user.Value; }

    internal ModeRequests() {
        SecurityIdentifier user;
        using (var identity = WindowsIdentity.GetCurrent()) user = identity.User;
        var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        var memorySecurity = new MemoryMappedFileSecurity();
        var mutexSecurity = new MutexSecurity();
        var eventSecurity = new EventWaitHandleSecurity();
        foreach (SecurityIdentifier sid in new[] { user, system }) {
            memorySecurity.AddAccessRule(new AccessRule<MemoryMappedFileRights>(sid, MemoryMappedFileRights.FullControl, AccessControlType.Allow));
            mutexSecurity.AddAccessRule(new MutexAccessRule(sid, MutexRights.FullControl, AccessControlType.Allow));
            eventSecurity.AddAccessRule(new EventWaitHandleAccessRule(sid, EventWaitHandleRights.FullControl, AccessControlType.Allow));
        }
        string name = Prefix(user);
        bool created;
        try {
            map = MemoryMappedFile.CreateNew(name + ".Slot", SlotSize, MemoryMappedFileAccess.ReadWrite,
                MemoryMappedFileOptions.None, memorySecurity, HandleInheritability.None);
            slot = map.CreateViewAccessor(0, SlotSize);
            gate = new Mutex(false, name + ".Gate", out created, mutexSecurity);
            Signal = new EventWaitHandle(false, EventResetMode.AutoReset, name + ".Ready", out created, eventSecurity);
        } catch { Dispose(); throw; }
    }

    internal static bool TrySend(int mode, long received) {
        string name;
        using (var identity = WindowsIdentity.GetCurrent()) name = Prefix(identity.User);
        try {
            using (var signal = EventWaitHandle.OpenExisting(name + ".Ready", EventWaitHandleRights.Modify))
            using (var sharedGate = Mutex.OpenExisting(name + ".Gate", MutexRights.Synchronize | MutexRights.Modify))
            using (var sharedMap = MemoryMappedFile.OpenExisting(name + ".Slot", MemoryMappedFileRights.ReadWrite))
            using (var sharedSlot = sharedMap.CreateViewAccessor(0, SlotSize))
                return Publish(sharedSlot, sharedGate, signal, mode, received);
        } catch (WaitHandleCannotBeOpenedException) { return false; }
          catch (FileNotFoundException) { return false; }
          catch (UnauthorizedAccessException) { return false; }
    }

    static bool Enter(Mutex mutex) {
        try { return mutex.WaitOne(250); }
        catch (AbandonedMutexException) { return true; }
    }

    static bool Publish(MemoryMappedViewAccessor queue, Mutex mutex, EventWaitHandle signal, int mode, long received) {
        if (!Enter(mutex)) return false;
        try {
            if (received >= queue.ReadInt64(0)) {
                // Wake the worker while we still hold the gate. If the sender is
                // terminated mid-write, an empty slot is safer than a mixed request.
                signal.Set();
                queue.Write(ModeOffset, 0);
                queue.Write(0, received);
                queue.Write(ModeOffset, mode + 1);
            }
            return true;
        } finally { mutex.ReleaseMutex(); }
    }

    internal bool Publish(int mode, long received) { return Publish(slot, gate, Signal, mode, received); }

    internal int Take(out long received) {
        received = 0;
        if (!Enter(gate)) {
            Signal.Set();
            return -1;
        }
        try {
            int mode = slot.ReadInt32(ModeOffset) - 1;
            received = slot.ReadInt64(0);
            slot.Write(ModeOffset, 0);
            return mode;
        } finally { gate.ReleaseMutex(); }
    }

    public void Dispose() {
        if (Signal != null) Signal.Dispose();
        if (gate != null) gate.Dispose();
        if (slot != null) slot.Dispose();
        if (map != null) map.Dispose();
    }
}

// A message-only window registers the three hotkeys; it never takes focus.
internal sealed class ModeHotkeys : NativeWindow, IDisposable {
    static readonly uint[] Keys = { 0x53, 0x50, 0x54 };
    readonly ModeRequests requests;
    readonly bool[] registered = new bool[3];
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window, int id);
    internal ModeHotkeys(ModeRequests requests) {
        this.requests = requests;
        CreateHandle(new CreateParams { Caption = "ASUS Mode Hotkeys", Parent = new IntPtr(-3) });
        RegisterMissing();
    }
    internal void RegisterMissing() {
        for (int i = 0; i < 3; i++)
            if (!registered[i]) registered[i] = RegisterHotKey(Handle, i + 1, 0x4003, Keys[i]);
    }
    internal bool AllRegistered { get { return registered[0] && registered[1] && registered[2]; } }
    internal string Status {
        get { return "S=" + registered[0] + ", P=" + registered[1] + ", T=" + registered[2]; }
    }
    protected override void WndProc(ref Message message) {
        if (message.Msg == 0x0312) {
            int index = message.WParam.ToInt32() - 1;
            if (index >= 0 && index < 3 && !requests.Publish(index, Stopwatch.GetTimestamp()))
                Program.Log("The mode request slot was busy.", "watcher-error.txt");
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
    readonly System.Windows.Forms.Timer healthTimer = new System.Windows.Forms.Timer { Interval = 15000 };
    readonly System.Windows.Forms.Timer retryTimer = new System.Windows.Forms.Timer { Interval = 1000 };
    readonly EventWaitHandle stop = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\ASUSModeCheckmarkStop");
    readonly WindowsFormsSynchronizationContext ui = new WindowsFormsSynchronizationContext();
    readonly ModeRequests requests;
    readonly RegistryModeWatch registryWatch;
    readonly RegisteredWaitHandle stopWait;
    readonly Thread worker;
    readonly ModeHotkeys hotkeys;
    readonly int pid;
    string lastHotkeyStatus;
    ModeToast errorToast;
    bool serviceAvailable;
    volatile bool disposed;

    internal ModeWatcher() {
        try {
            stop.Reset();
            using (Process self = Process.GetCurrentProcess()) pid = self.Id;
            requests = new ModeRequests();
            hotkeys = new ModeHotkeys(requests);
            registryWatch = new RegistryModeWatch(ArmouryService.OpenModeKey, delegate { Post(OnRegistryChange); });
            stopWait = ThreadPool.RegisterWaitForSingleObject(stop, delegate { Post(ExitThread); }, null, Timeout.Infinite, true);
            worker = new Thread(RunRequests) { IsBackground = true, Name = "ASUS mode requests" };
            worker.SetApartmentState(ApartmentState.STA);
            worker.Start();
            CheckHealth();
            healthTimer.Tick += delegate { CheckHealth(); };
            healthTimer.Start();
            retryTimer.Tick += delegate { hotkeys.RegisterMissing(); UpdateStatus(); };
            UpdateStatus();
        } catch { Dispose(); throw; }
    }

    void Post(Action action) {
        if (disposed) return;
        try { ui.Post(delegate { if (!disposed) action(); }, null); }
        catch (InvalidOperationException error) {
            if (!disposed) Program.Log(error.ToString(), "watcher-error.txt");
        }
    }

    void RunRequests() {
        WaitHandle[] handles = { stop, requests.Signal };
        while (WaitHandle.WaitAny(handles) == 1) {
            try {
                long received;
                int mode = requests.Take(out received);
                if (!disposed && mode >= 0 && mode < Program.Modes.Length)
                    Program.ApplyMode(Program.Modes[mode], received);
            } catch (Exception error) {
                Program.Log(error.ToString());
                Post(delegate {
                    if (errorToast != null) errorToast.Dispose();
                    errorToast = new ModeToast(Program.ErrorMessage(error));
                    errorToast.Show();
                });
            }
        }
    }

    void UpdateStatus() {
        string status = hotkeys.Status;
        if (status != lastHotkeyStatus && Program.Log("Fast request listener active; hotkeys " + status
                + "; PID=" + pid + "; tracking Armoury Crate service state", "watcher-status.txt"))
            lastHotkeyStatus = status;
        retryTimer.Enabled = !hotkeys.AllRegistered || status != lastHotkeyStatus;
    }

    void CheckHealth() {
        serviceAvailable = ArmouryService.IsAvailable();
        registryWatch.EnsureRegistered();
        Program.RefreshMenuSafely(serviceAvailable, true);
    }

    void OnRegistryChange() {
        registryWatch.Rearm();
        Program.RefreshMenuSafely(serviceAvailable);
    }
    internal static void Stop() {
        try { using (var signal = EventWaitHandle.OpenExisting(@"Local\ASUSModeCheckmarkStop")) signal.Set(); }
        catch (WaitHandleCannotBeOpenedException) { }
    }
    protected override void Dispose(bool disposing) {
        if (disposing && !disposed) {
            disposed = true;
            if (stopWait != null) stopWait.Unregister(null);
            healthTimer.Dispose();
            retryTimer.Dispose();
            if (registryWatch != null) registryWatch.Dispose();
            if (errorToast != null) errorToast.Dispose();
            if (hotkeys != null) hotkeys.Dispose();
            ui.Dispose();
            stop.Set();
            if (worker == null || !worker.IsAlive || worker.Join(1000)) {
                if (requests != null) requests.Dispose();
                stop.Dispose();
            }
        }
        base.Dispose(disposing);
    }
}

internal sealed class RegistryModeWatch : IDisposable {
    const uint NotifyLastSet = 0x00000004;
    readonly Func<RegistryKey> openKey;
    readonly Action onChange;
    readonly EventWaitHandle signal = new AutoResetEvent(false);
    RegistryKey key;
    RegisteredWaitHandle wait;

    [DllImport("advapi32.dll")]
    static extern int RegNotifyChangeKeyValue(SafeRegistryHandle key, bool subtree, uint filter,
        SafeWaitHandle signal, bool asynchronous);

    internal RegistryModeWatch(Func<RegistryKey> openKey, Action onChange) {
        this.openKey = openKey;
        this.onChange = onChange;
    }

    internal void EnsureRegistered() {
        if (wait != null) return;
        try {
            if (key == null) key = openKey();
            if (key == null) return;
            int result = RegNotifyChangeKeyValue(key.Handle, false, NotifyLastSet, signal.SafeWaitHandle, true);
            if (result != 0) throw new System.ComponentModel.Win32Exception(result);
            wait = ThreadPool.RegisterWaitForSingleObject(signal, delegate { onChange(); }, null, Timeout.Infinite, true);
        } catch (Exception error) {
            if (key != null) key.Dispose();
            key = null;
            signal.Reset();
            Program.Log(error.ToString(), "watcher-error.txt");
        }
    }

    internal void Rearm() {
        if (wait != null) wait.Unregister(null);
        wait = null;
        EnsureRegistered();
    }

    public void Dispose() {
        if (wait != null) wait.Unregister(null);
        if (key != null) key.Dispose();
        signal.Dispose();
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
        using (RegistryKey key = OpenModeKey()) {
            if (key == null) throw new InvalidOperationException("Open Armoury Crate once to initialize operating modes");
            Value(key, "SelectedMode"); Value(key, "IsLocked");
            if ((Value(key, "EnabledModes") & (2 | 4 | 8)) == 0)
                throw new InvalidOperationException("Armoury Crate does not expose compatible Silent, Performance or Turbo modes on this computer");
        }
    }
    internal static bool IsAvailable() {
        try { Endpoint(); return true; }
        catch { return false; }
    }
    internal static RegistryKey OpenModeKey() { return Registry.LocalMachine.OpenSubKey(ExternalKey); }
    internal static string CurrentMode() {
        try {
            using (RegistryKey key = OpenModeKey()) {
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
                using (RegistryKey key = OpenModeKey()) {
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
                    if (CurrentMode() == mode) return sawPopup;
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
    readonly string label;
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly Stopwatch clock = new Stopwatch();
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000020; return cp; }
    }
    internal ModeToast(string message) {
        label = message;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None; ClientSize = new Size(328, 132);
        BackColor = Color.FromArgb(22, 23, 27);
        DoubleBuffered = true;
        Text = "ASUS Mode notification";
        Rectangle area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(area.Left + (area.Width - Width) / 2, area.Bottom - Height - 56);
        using (GraphicsPath shape = Rounded(new RectangleF(0, 0, Width, Height), 14)) Region = new Region(shape);
        timer.Interval = 30;
        timer.Tick += delegate {
            double ms = clock.Elapsed.TotalMilliseconds;
            const double duration = 3200;
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
        using (Font small = new Font("Segoe UI", 8.5f, FontStyle.Bold))
        using (Font title = new Font("Segoe UI", 13, FontStyle.Regular))
        using (SolidBrush muted = new SolidBrush(Color.FromArgb(153, 155, 164)))
        using (SolidBrush white = new SolidBrush(Color.FromArgb(242, 242, 242))) {
            const float x = 24;
            g.DrawString("MODE UNAVAILABLE", small, muted, x, 28);
            g.DrawString(label, title, white, new RectangleF(x, 48, Width-x-16, 58));
        }
    }
    protected override void Dispose(bool disposing) {
        if (disposing) timer.Dispose();
        base.Dispose(disposing);
    }
}
