#Requires -Version 5.1
# 向別的程式的標準 Windows 元件「問」它的按鈕／項目在哪裡，取代寫死的座標（換電腦、換縮放比例也準）。
#   工具列（ToolbarWindow32 / Delphi TToolBar）：每顆按鈕的文字與位置
#   樹狀清單（SysTreeView32 / Delphi TTreeView）：每一列的文字與位置
# 這兩種訊息要傳結構進去，所以在對方程式裡借一小塊記憶體（VirtualAllocEx），用完就還。
# 出勤系統、住院醫囑系統都是 32 位元程式，結構照 32 位元排。
if (-not ('RemoteUi' -as [type])) {
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class RemoteUi {
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, uint s, uint t, uint pr);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr a, uint s, uint t);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, uint s, out IntPtr w);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, uint s, out IntPtr r);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public class Item { public string Text; public int X, Y, L, T, R, B; public IntPtr Handle; public int Command; public string Raw; }
  public static bool Debug = false;

  class Remote : IDisposable {
    IntPtr proc; public IntPtr Mem; const uint Size = 4096;
    public Remote(IntPtr hwnd) {
      uint pid; GetWindowThreadProcessId(hwnd, out pid);
      proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid);   // VM_OPERATION|VM_READ|VM_WRITE|QUERY_INFORMATION
      if (proc == IntPtr.Zero) throw new Exception("OpenProcess failed");
      Mem = VirtualAllocEx(proc, IntPtr.Zero, Size, 0x1000 | 0x2000, 0x04);
      if (Mem == IntPtr.Zero) throw new Exception("VirtualAllocEx failed");
    }
    public void Write(int off, byte[] b) { IntPtr w; WriteProcessMemory(proc, Mem + off, b, (uint)b.Length, out w); }
    public byte[] Read(int off, int n) { var b = new byte[n]; IntPtr r; ReadProcessMemory(proc, Mem + off, b, (uint)n, out r); return b; }
    public void Dispose() { VirtualFreeEx(proc, Mem, 0, 0x8000); CloseHandle(proc); }
  }
  static Item FromRect(IntPtr hwnd, byte[] r) {
    var it = new Item();
    POINT a = new POINT { X = BitConverter.ToInt32(r, 0), Y = BitConverter.ToInt32(r, 4) };
    POINT b = new POINT { X = BitConverter.ToInt32(r, 8), Y = BitConverter.ToInt32(r, 12) };
    ClientToScreen(hwnd, ref a); ClientToScreen(hwnd, ref b);
    it.L = a.X; it.T = a.Y; it.R = b.X; it.B = b.Y; it.X = (a.X + b.X) / 2; it.Y = (a.Y + b.Y) / 2;
    return it;
  }
  static string ReadText(Remote m, int off, int maxBytes, bool unicode) {
    var b = m.Read(off, maxBytes);
    if (unicode) { var s = Encoding.Unicode.GetString(b); int z = s.IndexOf('\0'); return z >= 0 ? s.Substring(0, z) : s; }
    int n = Array.IndexOf(b, (byte)0); if (n < 0) n = b.Length;
    return Encoding.GetEncoding(950).GetString(b, 0, n);
  }

  // 工具列按鈕：TB_BUTTONCOUNT / TB_GETBUTTON / TB_GETITEMRECT / TB_GETBUTTONTEXTW
  public static List<Item> ToolbarButtons(IntPtr hwnd) {
    var list = new List<Item>();
    using (var m = new Remote(hwnd)) {
      int n = (int)SendMessage(hwnd, 0x0418, IntPtr.Zero, IntPtr.Zero);
      for (int i = 0; i < n; i++) {
        SendMessage(hwnd, 0x0417, (IntPtr)i, m.Mem);              // TB_GETBUTTON → TBBUTTON（32 位元：20 bytes）
        var tb = m.Read(0, 20);
        int cmd = BitConverter.ToInt32(tb, 4); byte style = tb[9];
        if ((style & 0x01) != 0 && !Debug) continue;            // TBSTYLE_SEP 分隔線
        m.Write(64, new byte[16]);
        SendMessage(hwnd, 0x041D, (IntPtr)i, m.Mem + 64);       // TB_GETITEMRECT
        var it = FromRect(hwnd, m.Read(64, 16));
        m.Write(128, new byte[512]);
        SendMessage(hwnd, 0x044B, (IntPtr)cmd, m.Mem + 128);    // TB_GETBUTTONTEXTW
        it.Text = ReadText(m, 128, 512, true);
        it.Command = cmd; it.Raw = BitConverter.ToString(tb);
        list.Add(it);
      }
    }
    return list;
  }

  // 樹狀清單：TVM_GETNEXTITEM 走訪所有看得到的項目，TVM_GETITEMRECT 拿位置，TVM_GETITEMW 拿文字
  public static List<Item> TreeItems(IntPtr hwnd) {
    var list = new List<Item>();
    using (var m = new Remote(hwnd)) {
      IntPtr h = SendMessage(hwnd, 0x110A, (IntPtr)0x0, IntPtr.Zero);                       // TVGN_ROOT
      int guard = 0;
      while (h != IntPtr.Zero && guard++ < 500) {
        m.Write(0, BitConverter.GetBytes(h.ToInt32())); m.Write(4, new byte[12]);
        SendMessage(hwnd, 0x1104, (IntPtr)1, m.Mem);                                         // TVM_GETITEMRECT（只取文字範圍）
        var it = FromRect(hwnd, m.Read(0, 16));
        // TVITEMW（32 位元：40 bytes）：mask=TVIF_TEXT, hItem, ..., pszText, cchTextMax
        var tv = new byte[40];
        BitConverter.GetBytes(0x0001).CopyTo(tv, 0);
        BitConverter.GetBytes(h.ToInt32()).CopyTo(tv, 4);
        BitConverter.GetBytes((m.Mem + 256).ToInt32()).CopyTo(tv, 16);
        BitConverter.GetBytes(255).CopyTo(tv, 20);
        m.Write(64, tv); m.Write(256, new byte[512]);
        SendMessage(hwnd, 0x113E, IntPtr.Zero, m.Mem + 64);                                  // TVM_GETITEMW
        it.Text = ReadText(m, 256, 510, true);
        if (string.IsNullOrEmpty(it.Text)) {                                                 // ANSI 版樹狀清單
          m.Write(64, tv); m.Write(256, new byte[512]);
          SendMessage(hwnd, 0x110C, IntPtr.Zero, m.Mem + 64);                                // TVM_GETITEMA
          it.Text = ReadText(m, 256, 255, false);
        }
        it.Handle = h;
        list.Add(it);
        h = SendMessage(hwnd, 0x110A, (IntPtr)0x6, h);                                       // TVGN_NEXTVISIBLE
      }
    }
    return list;
  }
}
"@
}
# 座標以實體像素為準（Windows 縮放 125%、150% 時才不會偏掉）
[void][RemoteUi]::SetProcessDPIAware()
