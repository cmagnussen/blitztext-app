using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using BlitztextWin.Core;

namespace BlitztextWin.App.Services;

public sealed class GlobalHotkeyService : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint VkSpace = 0x20;
    private const uint VkR = 0x52;
    private const uint VkE = 0x45;

    private readonly Dictionary<int, WorkflowType> hotkeys = [];
    private HwndSource? source;
    private IntPtr handle;

    public event Action<WorkflowType>? HotkeyPressed;

    public void Initialize(Window window)
    {
        handle = new WindowInteropHelper(window).Handle;
        source = HwndSource.FromHwnd(handle);
        source?.AddHook(WndProc);
    }

    public void RegisterDefaults()
    {
        Register(1, ModControl | ModShift, VkSpace, WorkflowType.Transcription);
        Register(2, ModControl | ModAlt, VkSpace, WorkflowType.TextImprover);
        Register(3, ModControl | ModAlt, VkR, WorkflowType.DampfAblassen);
        Register(4, ModControl | ModAlt, VkE, WorkflowType.EmojiText);
    }

    private void Register(int id, uint modifiers, uint key, WorkflowType workflow)
    {
        if (handle == IntPtr.Zero)
        {
            return;
        }

        if (RegisterHotKey(handle, id, modifiers, key))
        {
            hotkeys[id] = workflow;
        }
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey && hotkeys.TryGetValue(wParam.ToInt32(), out var workflow))
        {
            handled = true;
            HotkeyPressed?.Invoke(workflow);
        }

        return IntPtr.Zero;
    }

    public void Dispose()
    {
        foreach (var id in hotkeys.Keys)
        {
            UnregisterHotKey(handle, id);
        }

        hotkeys.Clear();
        source?.RemoveHook(WndProc);
        source = null;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
