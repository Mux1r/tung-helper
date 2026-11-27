#Requires -Version 5.1
# 操作「住院醫囑系統」(MOCLIENT.EXE) 的入院記錄
# 每一段（主訴、現病史…）都是有名字的 GroupBox 裡的一個 RichEdit；文字用 Windows 訊息直接寫進那一格：
#   EM_SETSEL 選好範圍 → EM_REPLACESEL 取代，效果等於選取後貼上（會標記為已修改），不經剪貼簿、不受輸入法影響。
# 段落旁的按鈕（護理評估、近期檢驗結果…）是畫出來的，沒有視窗把手，要用滑鼠點。

Add-Type -AssemblyName System.Windows.Forms, UIAutomationClient, UIAutomationTypes
. (Join-Path $PSScriptRoot 'remote-ui.ps1')   # 樹狀清單、工具列位置；並把座標改成實體像素
if (-not ('MoW32' -as [type])) {
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class MoW32 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO { public int cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gi);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetScrollPos(IntPtr h, int bar);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, int d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, string l);
  public static string Text(IntPtr h) {
    int n = (int)SendMessage(h, 0x0E, IntPtr.Zero, IntPtr.Zero);   // WM_GETTEXTLENGTH
    var sb = new StringBuilder(n + 16); SendMessage(h, 0x0D, (IntPtr)(n + 16), sb); return sb.ToString();
  }
  public static void Select(IntPtr h, int a, int b) { SendMessage(h, 0xB1, (IntPtr)a, (IntPtr)b); }   // EM_SETSEL
  public static void Replace(IntPtr h, string s) { SendMessage(h, 0xC2, (IntPtr)1, s); }             // EM_REPLACESEL（可復原）
  public static IntPtr Focus(IntPtr top) { uint pid; uint tid = GetWindowThreadProcessId(top, out pid); var gi = new GUITHREADINFO(); gi.cbSize = Marshal.SizeOf(gi); GetGUIThreadInfo(tid, ref gi); return gi.hwndFocus; }
  public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
}
"@
}
$script:MoAE = [System.Windows.Automation.AutomationElement]

# 入院記錄的段落：系統上的 GroupBox 名稱開頭 → 內部代號（順序＝系統裡的順序）
$script:AdmSectionDefs = [ordered]@{
    CC    = '主訴'
    PI    = '現病史'
    PH    = '過去病史'
    DH    = '用藥記錄'
    PSH   = '個人歷史'
    FH    = '家族歷史'
    ROS   = '器官系統複查'
    PE    = '(1) 一般身體診查'
    NRS   = '(2) 營養風險篩選'
    LAB   = '檢查／檢驗報告'
    DX    = '疾病診斷'
    PLAN  = '住院診療計劃'
}

function Get-MoDescendants($El) {
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $list = New-Object System.Collections.ArrayList; $stack = New-Object System.Collections.Stack; $stack.Push($El)
    while ($stack.Count) { $cur = $stack.Pop(); $ch = $walker.GetFirstChild($cur); while ($ch) { [void]$list.Add($ch); $stack.Push($ch); $ch = $walker.GetNextSibling($ch) } }
    $list
}

function Connect-MoAdmission {
    $procs = @(Get-Process -Name moclient -ErrorAction SilentlyContinue)
    if (-not $procs) { throw '找不到「住院醫囑系統」(MOCLIENT.EXE)。' }
    $script:MoTop = $null
    foreach ($p in $procs) {   # 可能同時開了好幾個，找開著「入院記錄」的那個
        $cond = New-Object System.Windows.Automation.PropertyCondition($MoAE::ProcessIdProperty, $p.Id)
        foreach ($w in $MoAE::RootElement.FindAll('Children', $cond)) { if ($w.Current.Name -like '*入院記錄*') { $script:MoTop = $w; $script:MoPidCond = $cond } }
        if ($MoTop) { break }
    }
    if (-not $MoTop) { throw '住院醫囑系統沒有開在「入院記錄」畫面。' }
    $script:MoTopH = [IntPtr]$MoTop.Current.NativeWindowHandle
    # 找每一段的 GroupBox 和裡面的 RichEdit
    $script:AdmSec = [ordered]@{}
    $all = Get-MoDescendants $MoTop
    foreach ($e in $all) {
        $c = $e.Current
        if ($c.ClassName -ne 'TGroupBox') { continue }
        foreach ($k in $AdmSectionDefs.Keys) {
            if ($AdmSec.Contains($k) -or -not $c.Name.StartsWith($AdmSectionDefs[$k])) { continue }
            $w = [System.Windows.Automation.TreeWalker]::RawViewWalker
            $ch = $w.GetFirstChild($e); $edit = $null
            while ($ch) { if ($ch.Current.ClassName -eq 'TRichEdit') { $edit = $ch; break }; $ch = $w.GetNextSibling($ch) }
            if ($edit) { $AdmSec[$k] = @{ Box = [IntPtr]$c.NativeWindowHandle; Edit = [IntPtr]$edit.Current.NativeWindowHandle } }
        }
    }
    $missing = @($AdmSectionDefs.Keys | Where-Object { -not $AdmSec.Contains($_) })
    if ($missing.Count) { throw ('入院記錄找不到這些段落：' + (($missing | ForEach-Object { $AdmSectionDefs[$_] }) -join '、')) }
}

function Set-MoFront { [MoW32]::SetForegroundWindow($MoTopH) | Out-Null; Start-Sleep -Milliseconds 200 }
function Invoke-MoClick([int]$X, [int]$Y) {
    [MoW32]::SetCursorPos($X, $Y) | Out-Null; Start-Sleep -Milliseconds 60
    [MoW32]::mouse_event(2,0,0,0,[IntPtr]::Zero); [MoW32]::mouse_event(4,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 80
}
function Send-MoKeys([string]$K) { [System.Windows.Forms.SendKeys]::SendWait($K) }

# 這套系統的 RichEdit 是舊式 ANSI 版：內部位置以 Big5 位元組計、換行算 2，自己算位置很容易偏。
# 所以不算位置，只用三種動作（都等於「選取後貼上」，會標記為已修改）：
#   全選後取代 / 移到最前面插入 / 移到最後面插入。要改中間某處，就在這裡算好整段新文字再全選取代。
function Get-AdmRaw([string]$Key) { [MoW32]::Text($AdmSec[$Key].Edit) }                       # 原樣（\r\n）
function Get-AdmText([string]$Key) { (Get-AdmRaw $Key) -replace "`r`n", "`r" -replace "`n", "`r" }   # 給人看／算長度用
function ConvertTo-AdmText([string]$S) { ($S -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n") -replace "`n", "`r`n" }
function Set-AdmAll([string]$Key, [string]$New, [switch]$Raw) {
    $h = $AdmSec[$Key].Edit
    [MoW32]::Select($h, 0, -1)
    [MoW32]::Replace($h, $(if ($Raw) { $New } else { ConvertTo-AdmText $New }))
}
function Add-AdmStart([string]$Key, [string]$New) {
    $h = $AdmSec[$Key].Edit
    [MoW32]::Select($h, 0, 0)
    [MoW32]::Replace($h, (ConvertTo-AdmText $New) + "`r`n")
}
function Add-AdmEnd([string]$Key, [string]$New, [switch]$NewLine) {
    $h = $AdmSec[$Key].Edit
    $s = ConvertTo-AdmText $New
    if ($NewLine -and (Get-AdmRaw $Key).Length -gt 0) { $s = "`r`n" + $s }
    [MoW32]::Select($h, [int]::MaxValue, [int]::MaxValue)   # 超過長度會停在最後
    [MoW32]::Replace($h, $s)
}
# 把文字裡前 $Count 個「[ ]xxx」打勾成「[v]xxx」（跟點中間空白一樣）；$Count = 0 表示全部。回傳打勾幾個
function Set-AdmCheck([string]$Key, [string]$After, [int]$Count = 0) {
    $sb = New-Object System.Text.StringBuilder (Get-AdmRaw $Key)
    $find = "[ ]$After"; $n = 0; $from = 0
    while ($Count -eq 0 -or $n -lt $Count) {
        $i = $sb.ToString().IndexOf($find, $from)
        if ($i -lt 0) { break }
        $sb[$i + 1] = 'v'; $n++; $from = $i + $find.Length
    }
    if ($n -gt 0) { Set-AdmAll $Key $sb.ToString() -Raw }
    $n
}
# 捲到最上面，點主訴的文字框讓它取得焦點
function Enter-AdmTop {
    $box = [MoW32]::Rect($AdmSec.CC.Box)
    $sb = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($MoAE::FromHandle($AdmSec.CC.Box))
    [MoW32]::SendMessage([IntPtr]$sb.Current.NativeWindowHandle, 0x115, [IntPtr]6, [IntPtr]::Zero) | Out-Null   # WM_VSCROLL, SB_TOP
    Start-Sleep -Milliseconds 400
    Set-MoFront
    $r = [MoW32]::Rect($AdmSec.CC.Edit)
    Invoke-MoClick ($r.R - 30) ($r.B - 12); Start-Sleep -Milliseconds 300
    [MoW32]::Focus($MoTopH) -eq $AdmSec.CC.Edit
}
# 讓某一段的 RichEdit 取得焦點（從目前位置按 Tab 往下走，捲動框會自己捲到那一段）
function Enter-AdmSection([string]$Key) {
    $target = $AdmSec[$Key].Edit
    if ([MoW32]::Focus($MoTopH) -eq $target) { return $true }
    for ($i = 0; $i -lt 16; $i++) {
        Send-MoKeys '{TAB}'; Start-Sleep -Milliseconds 250
        $f = [MoW32]::Focus($MoTopH)
        if ($f -eq $target) { return $true }
        if ($f -ne [IntPtr]::Zero -and -not (@($AdmSec.Values | ForEach-Object { $_.Edit }) -contains $f)) { return $false }   # 跳到別的地方（例如彈出視窗）
    }
    $false
}
function Get-AdmBoxRect([string]$Key) { [MoW32]::Rect($AdmSec[$Key].Box) }

# ── 段落標題列上的按鈕（TSpeedButton：畫出來的，拿不到焦點、沒有快捷鍵，只能點）──
# 位置取自程式內的表單設計（dfm2txt）或實測，單位是 100% 縮放下的像素，相對於該段 GroupBox 左上角。
# 舊程式不支援 DPI，Windows 放大時整個視窗等比例放大，所以用「GroupBox 實際寬度 ÷ 設計寬度」換算。
$script:AdmButtons = @{
    NurseVitals = @{ Key = 'PE';  DesignW = 665; X = 315;   Y = 8; Popup = '生命徵象' }       # 護理評估（執行時被程式移到標題文字後面，實測）
    LabResults  = @{ Key = 'LAB'; DesignW = 669; X = 384.5; Y = 9; Popup = '重要檢驗資料' }   # 近期檢驗結果（sbLabRpt：Left 313, Width 143）
    Reports     = @{ Key = 'LAB'; DesignW = 669; X = 536.5; Y = 9; Popup = '檢查報告' }       # 近期檢查報告（sbExmRpt：Left 465, Width 143）
}
function Get-MoScrollBox { [IntPtr]([System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($MoAE::FromHandle($AdmSec.CC.Box)).Current.NativeWindowHandle) }
# 把某一段捲到捲動框最上面（標題列和按鈕都看得到）
function Show-AdmBox([string]$Key) {
    $sbh = Get-MoScrollBox
    for ($i = 0; $i -lt 3; $i++) {
        $d = (Get-AdmBoxRect $Key).T - [MoW32]::Rect($sbh).T - 2
        if ([math]::Abs($d) -le 2) { break }
        $pos = [math]::Max(0, [MoW32]::GetScrollPos($sbh, 1) + $d)
        [MoW32]::SendMessage($sbh, 0x115, [IntPtr](4 -bor ([int]$pos -shl 16)), [IntPtr]::Zero) | Out-Null   # SB_THUMBPOSITION
        [MoW32]::SendMessage($sbh, 0x115, [IntPtr]8, [IntPtr]::Zero) | Out-Null                              # SB_ENDSCROLL
        Start-Sleep -Milliseconds 250
    }
}
# 點段落按鈕，等它的視窗出現；跳出別的視窗就關掉。回傳彈出視窗或 $null
function Invoke-AdmButton([string]$Name) {
    $b = $AdmButtons[$Name]
    Show-AdmBox $b.Key
    Set-MoFront
    $r = Get-AdmBoxRect $b.Key
    $scale = ($r.R - $r.L) / $b.DesignW
    Invoke-MoClick ([int]($r.L + $b.X * $scale)) ([int]($r.T + $b.Y * $scale))
    $p = Wait-MoPopup $b.Popup 5
    if (-not $p) {
        foreach ($o in @(Get-MoPopups)) { [MoW32]::SetForegroundWindow($o.H) | Out-Null; Start-Sleep -Milliseconds 150; Send-MoKeys '{ESC}'; Start-Sleep -Milliseconds 300 }
    }
    $p
}
function Wait-MoPopup([string]$Title, [int]$Seconds = 6) {
    for ($i = 0; $i -lt $Seconds * 4; $i++) {
        $p = @(Get-MoPopups) | Where-Object { $_.Title -eq $Title } | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 250
    }
    $null
}
function Test-MoPopupOpen($Pop) { [bool](@(Get-MoPopups) | Where-Object { $_.H -eq $Pop.H }) }
# 對彈出視窗按鍵（先把它帶到最前面）
function Send-MoPopupKeys($Pop, [string]$Keys) {
    [MoW32]::SetForegroundWindow($Pop.H) | Out-Null; Start-Sleep -Milliseconds 200
    Send-MoKeys $Keys; Start-Sleep -Milliseconds 300
}
# 備援：鍵盤沒反應時，點有名字的按鈕（位置向系統查，不是寫死）
function Invoke-MoPopupButton($Pop, [string]$Name) {
    $b = Get-MoDescendants $Pop.El | Where-Object { $_.Current.ClassName -match 'Button' -and $_.Current.Name -eq $Name } | Select-Object -First 1
    if (-not $b) { return $false }
    $r = $b.Current.BoundingRectangle
    [MoW32]::SetForegroundWindow($Pop.H) | Out-Null; Start-Sleep -Milliseconds 150
    Invoke-MoClick ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2)); $true
}
# 「重要檢驗資料」「檢查報告」左邊的時間範圍樹：向樹狀清單查「兩個月內」那一列的位置後雙擊（雙擊才會載入）
function Open-MoTreeRange($Pop, [string]$Text) {
    $tree = Get-MoDescendants $Pop.El | Where-Object { $_.Current.ClassName -match 'Tree' } | Select-Object -First 1
    if (-not $tree) { return $false }
    $item = [RemoteUi]::TreeItems([IntPtr]$tree.Current.NativeWindowHandle) | Where-Object { $_.Text -eq $Text } | Select-Object -First 1
    if (-not $item) { return $false }
    [MoW32]::SetForegroundWindow($Pop.H) | Out-Null; Start-Sleep -Milliseconds 200
    [MoW32]::SetCursorPos($item.X, $item.Y) | Out-Null; Start-Sleep -Milliseconds 60
    1..2 | ForEach-Object { [MoW32]::mouse_event(2,0,0,0,[IntPtr]::Zero); [MoW32]::mouse_event(4,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 60 }
    $true
}
# 關掉系統跳出的訊息框（例如 RichEdit line insertion error），回傳訊息內容
function Close-MoMessages {
    $msgs = @()
    foreach ($p in @(Get-MoPopups | Where-Object { $_.Cls -eq '#32770' })) {
        $msgs += ((Get-MoDescendants $p.El | Where-Object { $_.Current.ClassName -eq 'Static' } | ForEach-Object { $_.Current.Name }) -join ' ')
        [MoW32]::SetForegroundWindow($p.H) | Out-Null; Start-Sleep -Milliseconds 150; Send-MoKeys '{ENTER}'; Start-Sleep -Milliseconds 400
    }
    ($msgs | Where-Object { $_ }) -join ' / '
}

# 住院醫囑系統跳出的視窗（不是主視窗的頂層視窗）
function Get-MoPopups {
    foreach ($w in $MoAE::RootElement.FindAll('Children', $MoPidCond)) {
        $c = $w.Current
        if ([IntPtr]$c.NativeWindowHandle -ne $MoTopH -and -not $c.IsOffscreen -and $c.BoundingRectangle.Width -gt 0) {
            [pscustomobject]@{ El = $w; H = [IntPtr]$c.NativeWindowHandle; Title = $c.Name; Cls = $c.ClassName }
        }
    }
}
