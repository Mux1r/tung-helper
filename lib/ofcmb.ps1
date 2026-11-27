#Requires -Version 5.1
# 操作「出勤系統」(O:\runtime\exe\OFCMB.EXE) 的共用函式
# 讀取：班表格子用「雙擊 → Ctrl+C → Enter 跳下一格」；表單欄位用 Windows 訊息讀寫（不靠截圖、不用 AI）
# 輸入：文字用 WM_CHAR 直接送進欄位，不經鍵盤，不受注音輸入法影響

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
if (-not ('OfcW32' -as [type])) {
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class OfcW32 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, int d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, string l);
  public static string Text(IntPtr h) { var sb = new StringBuilder(1024); SendMessage(h, 0x0D, (IntPtr)1024, sb); return sb.ToString(); }
  public static void SetText(IntPtr h, string s) { SendMessage(h, 0x0C, IntPtr.Zero, s); }
  public static void Chars(IntPtr h, string s) { foreach (char c in s) { PostMessage(h, 0x0102, (IntPtr)c, IntPtr.Zero); System.Threading.Thread.Sleep(40); } }
  public static void Combo(IntPtr h, int idx) {
    SendMessage(h, 0x014E, (IntPtr)idx, IntPtr.Zero);
    PostMessage(GetParent(h), 0x0111, (IntPtr)((1 << 16) | (GetDlgCtrlID(h) & 0xFFFF)), h);
  }
}
"@
}
$script:AE = [System.Windows.Automation.AutomationElement]

# ---------- 連線與基本動作 ----------
function Connect-Ofcmb {
    $p = Get-Process -Name OFCMB -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { throw '找不到「出勤系統」(OFCMB.EXE)，請先開啟並登入。' }
    $script:OfcPidCond = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $p.Id)
    $script:OfcTop = $null
    foreach ($w in $AE::RootElement.FindAll('Children', $OfcPidCond)) { if ($w.Current.ClassName -eq 'Tfm_OFCMB') { $script:OfcTop = $w } }
    if (-not $OfcTop) { throw '找不到出勤系統主視窗。' }
    $script:OfcTopH = [IntPtr]$OfcTop.Current.NativeWindowHandle
    if ([OfcW32]::IsIconic($OfcTopH)) { [OfcW32]::ShowWindow($OfcTopH, 3) | Out-Null; Start-Sleep -Milliseconds 500 }   # 縮小了就還原成最大化
}
function Set-OfcFront { [OfcW32]::SetForegroundWindow($OfcTopH) | Out-Null; Start-Sleep -Milliseconds 200 }
function Invoke-OfcClick([int]$X, [int]$Y, [switch]$Double) {
    [OfcW32]::SetCursorPos($X, $Y) | Out-Null; Start-Sleep -Milliseconds 60
    $n = 1; if ($Double) { $n = 2 }
    for ($i = 0; $i -lt $n; $i++) { [OfcW32]::mouse_event(2,0,0,0,[IntPtr]::Zero); [OfcW32]::mouse_event(4,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 50 }
}
function Send-OfcKeys([string]$K) { [System.Windows.Forms.SendKeys]::SendWait($K) }   # 只用在 Esc、Tab、Enter、方向鍵、Ctrl+C
function Get-UiDescendants($El) {
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $list = New-Object System.Collections.ArrayList; $stack = New-Object System.Collections.Stack; $stack.Push($El)
    while ($stack.Count) { $cur = $stack.Pop(); $ch = $walker.GetFirstChild($cur); while ($ch) { [void]$list.Add($ch); $stack.Push($ch); $ch = $walker.GetNextSibling($ch) } }
    $list
}
function Get-UiInfo($E) {
    $c = $E.Current; $r = $c.BoundingRectangle
    [pscustomobject]@{ H = [IntPtr]$c.NativeWindowHandle; Cls = $c.ClassName; Name = $c.Name; L = [int]$r.X; T = [int]$r.Y; W = [int]$r.Width; Hh = [int]$r.Height
                       X = [int]($r.X + $r.Width / 2); Y = [int]($r.Y + $r.Height / 2) }
}
function Find-OfcForm([string]$Cls) {
    foreach ($e in (Get-UiDescendants $OfcTop)) { if ($e.Current.ClassName -eq $Cls) { return $e } }
    $null
}
# 左側選單：排班申請在選單面板頂端往下 60px，加班申請 250px
$script:OfcMenu = @{ '排班申請' = @{ Cls = 'Tfm_OFCMB_1_1'; Dy = 60 }; '加班申請' = @{ Cls = 'Tfm_OFCMB_1_5'; Dy = 250 } }
function Open-OfcMenu([string]$Name) {
    $m = $OfcMenu[$Name]
    Set-OfcFront
    $nav = $null
    foreach ($w in (Get-UiDescendants $OfcTop | Select-Object -First 12)) { $i = Get-UiInfo $w; if ($i.Cls -eq 'TPanel' -and $i.W -lt 100 -and $i.Hh -gt 300) { $nav = $i; break } }
    $top = if ($nav) { $nav.T } else { 80 }
    Invoke-OfcClick 37 ($top + $m.Dy); Start-Sleep -Milliseconds 900
    $f = Find-OfcForm $m.Cls
    if (-not $f) { throw "無法開啟「$Name」畫面" }
    $f
}
# 程式跳出的訊息框（Delphi TMessageForm / Windows #32770）
function Get-OfcDialogs {
    foreach ($w in $AE::RootElement.FindAll('Children', $OfcPidCond)) {
        if ($w.Current.ClassName -in @('TMessageForm', '#32770')) {
            $txt = (Get-UiDescendants $w | ForEach-Object { $_.Current.Name } |
                    Where-Object { $_ -and $_ -notin @('OK', '確定', 'Yes', 'No', 'Cancel', '是', '否', '取消') }) -join ' '
            [pscustomobject]@{ H = [IntPtr]$w.Current.NativeWindowHandle; Text = $txt }
        }
    }
}
function Close-OfcDialogs {
    $msgs = @()
    foreach ($d in @(Get-OfcDialogs)) { $msgs += $d.Text; [OfcW32]::SetForegroundWindow($d.H) | Out-Null; Start-Sleep -Milliseconds 150; Send-OfcKeys '{ENTER}'; Start-Sleep -Milliseconds 400 }
    ($msgs -join ' / ')
}

# ---------- 讀班表 ----------
# 回傳 @{ Year; Month; RocYear; Rows = @(@{ Date = [datetime]; Code = '9076' }) }
function Read-OfcSchedule {
    $sched = Open-OfcMenu '排班申請'
    $kids = Get-UiDescendants $sched | ForEach-Object { Get-UiInfo $_ }
    $ym = ($kids | Where-Object { $_.Cls -eq 'TMaskEdit' -and $_.Name -match '^\d{3}/\d{2}$' } | Select-Object -First 1).Name
    if (-not $ym) { throw '讀不到排班年月' }
    $roc = [int]$ym.Split('/')[0]; $mon = [int]$ym.Split('/')[1]; $year = $roc + 1911
    $days = [DateTime]::DaysInMonth($year, $mon)
    $grid = $kids | Where-Object { $_.Cls -eq 'TDBGrid' } | Sort-Object { $_.W * $_.Hh } -Descending | Select-Object -First 1
    $row1Y = $grid.T + 30; $codeX = $grid.L + 124
    $clip = $null; try { $clip = [System.Windows.Forms.Clipboard]::GetText() } catch {}
    Invoke-OfcClick $codeX $row1Y; Start-Sleep -Milliseconds 400
    Invoke-OfcClick $codeX $row1Y -Double; Start-Sleep -Milliseconds 300
    $rows = @()
    for ($d = 1; $d -le $days; $d++) {
        [System.Windows.Forms.Clipboard]::Clear()
        Send-OfcKeys '^c'; Start-Sleep -Milliseconds 120
        $code = ([System.Windows.Forms.Clipboard]::GetText()).Trim()
        if ($d -lt $days) { Send-OfcKeys '{ENTER}'; Start-Sleep -Milliseconds 200 }
        $rows += [pscustomobject]@{ Date = [DateTime]::new($year, $mon, $d); Code = $code }
    }
    Send-OfcKeys '{ESC}'; Start-Sleep -Milliseconds 150; Send-OfcKeys '{ESC}'   # 離開編輯，不改班表
    if ($clip) { try { [System.Windows.Forms.Clipboard]::SetText($clip) } catch {} }
    @{ Year = $year; Month = $mon; RocYear = $roc; Rows = $rows }
}

# ---------- 加班申請表單 ----------
function Get-OtControls($Form) {
    $k = Get-UiDescendants $Form | ForEach-Object { Get-UiInfo $_ }
    $m = @($k | Where-Object { $_.Cls -eq 'TMaskEdit' } | Sort-Object L)
    $e = @($k | Where-Object { $_.Cls -eq 'TEdit' -and $_.W -gt 500 } | Sort-Object T)
    @{ Kind = ($k | Where-Object { $_.Cls -eq 'TComboBox' } | Select-Object -First 1)
       Date = ($k | Where-Object { $_.Cls -eq 'TDateTimePicker' } | Select-Object -First 1)
       Start = $m[0]; End = $m[1]; Reason = $e[0]
       Hours = ($k | Where-Object { $_.Cls -eq 'TEdit' -and $_.W -lt 100 -and $m.Count -ge 2 -and [math]::Abs($_.T - $m[1].T) -lt 6 -and $_.L -gt $m[1].L } | Select-Object -First 1)
       Bar = ($k | Where-Object { $_.Cls -eq 'TToolBar' } | Select-Object -First 1) }
}
function Invoke-OtBar($C, [string]$Name) {
    $idx = @{ '新增' = 0; '查詢' = 1; '修改' = 2; '存檔' = 3; '放棄' = 4 }[$Name]
    Invoke-OfcClick ($C.Bar.L + 26 + 48 * $idx) $C.Bar.Y
}
function Set-OtTime($O, [string]$Hhmm) {
    Invoke-OfcClick $O.X $O.Y; Start-Sleep -Milliseconds 150
    Send-OfcKeys '{HOME}+{END}'; Start-Sleep -Milliseconds 150
    [OfcW32]::Chars($O.H, $Hhmm); Start-Sleep -Milliseconds 200
    Send-OfcKeys '{TAB}'; Start-Sleep -Milliseconds 300
}
function Set-OtDate($O, [datetime]$Dt) {
    $p = (Format-Roc $Dt).Split('/')
    for ($try = 0; $try -lt 2; $try++) {
        Invoke-OfcClick ($O.L + 40) $O.Y; Start-Sleep -Milliseconds 150
        Send-OfcKeys '{LEFT}{LEFT}{LEFT}'; Start-Sleep -Milliseconds 150   # 移到「年」
        [OfcW32]::Chars($O.H, $p[0]); Start-Sleep -Milliseconds 200
        Send-OfcKeys '{RIGHT}'; Start-Sleep -Milliseconds 150
        [OfcW32]::Chars($O.H, $p[1]); Start-Sleep -Milliseconds 200
        Send-OfcKeys '{RIGHT}'; Start-Sleep -Milliseconds 150
        [OfcW32]::Chars($O.H, $p[2]); Start-Sleep -Milliseconds 400
        if ([OfcW32]::Text($O.H) -eq (Format-Roc $Dt)) { return $true }
    }
    $false
}
function Read-OtFields($C) {
    $hrs = ''; if ($C.Hours) { $hrs = [OfcW32]::Text($C.Hours.H) }
    [ordered]@{ 日期 = [OfcW32]::Text($C.Date.H); 起 = [OfcW32]::Text($C.Start.H); 迄 = [OfcW32]::Text($C.End.H)
                時數 = $hrs; 類別 = [OfcW32]::Text($C.Kind.H); 理由 = [OfcW32]::Text($C.Reason.H) }
}
