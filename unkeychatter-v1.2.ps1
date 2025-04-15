# 加载必要的类型
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class KeyboardInterceptor {
    public delegate IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWindowsHookEx(int idHook, HookCallback lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public static HookCallback HookCallbackDelegate;

    public static IntPtr HookId = IntPtr.Zero;

    public const int WH_KEYBOARD_LL = 13; // 键盘钩子标识
    public const int WM_KEYDOWN = 0x0100; // 按键按下事件
    public const uint VK_BACK = 0x08;     // Backspace 键码
    public const int Interval = 80;      // 阻止重复按键的时间间隔（毫秒）

    public static Stopwatch Stopwatch = Stopwatch.StartNew();
    public static long LastBackspaceTime = 0;

    public static IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN) {
            KBDLLHOOKSTRUCT keyInfo = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));

            // 检测是否是 Backspace 按键
            if (keyInfo.vkCode == VK_BACK) {
                long elapsedTime = Stopwatch.ElapsedMilliseconds - LastBackspaceTime;
                if (elapsedTime < Interval) {
                    // 阻止重复的 Backspace
                    return (IntPtr)1;
                }
                LastBackspaceTime = Stopwatch.ElapsedMilliseconds;
            }
        }
        // 继续传递按键事件
        return CallNextHookEx(HookId, nCode, wParam, lParam);
    }

    public static void SetHook() {
        // 设置钩子
        HookCallbackDelegate = LowLevelKeyboardProc;
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule) {
            HookId = SetWindowsHookEx(WH_KEYBOARD_LL, HookCallbackDelegate, GetModuleHandle(curModule.ModuleName), 0);
        }
        LastBackspaceTime = Stopwatch.ElapsedMilliseconds; // 初始化时间戳
    }

    public static void Unhook() {
        // 卸载钩子
        if (HookId != IntPtr.Zero) {
            UnhookWindowsHookEx(HookId);
            HookId = IntPtr.Zero;
        }
    }

    public static long GetIdleTime() {
        LASTINPUTINFO lastInputInfo = new LASTINPUTINFO();
        lastInputInfo.cbSize = (uint)Marshal.SizeOf(lastInputInfo);
        if (GetLastInputInfo(ref lastInputInfo)) {
            return Environment.TickCount - lastInputInfo.dwTime;
        }
        return 0;
    }
}
"@

# 变量初始化
$IdleThreshold = 60000 # 60 秒无操作的阈值（毫秒）
$CheckInterval = 1000  # 每次检查的时间间隔（毫秒）
$HookActive = $false   # 钩子是否激活

# 主循环
while ($true) {
    # 检测空闲时间
    Start-Sleep -Milliseconds $CheckInterval
    $idleTime = [KeyboardInterceptor]::GetIdleTime()

    if ($idleTime -ge $IdleThreshold) {
        if ($HookActive) {
            Write-Host "Idleness is detected for more than $IdleThreshold milliseconds, and the keyboard hook is paused"
            [KeyboardInterceptor]::Unhook()
            $HookActive = $false
        }
    } else {
        if (-not $HookActive) {
            Write-Host "Activity detected, reactivating the keyboard hook"
            [KeyboardInterceptor]::SetHook()
            $HookActive = $true
        }
    }
}