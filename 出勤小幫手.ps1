#Requires -Version 5.1
<#
  出勤小幫手 — 操作「出勤系統」的工具集
  左側選單一頁一個功能；新功能放進 modules\ 資料夾（檔名數字決定順序），用 New-Page 建自己的頁面即可。
  需要操作出勤系統的工作放在 tasks\，用 Start-Task 在背景執行，視窗不會卡住，可以暫停/停止。
#>
$ErrorActionPreference = 'Stop'
$script:Dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:AppVersion = '1.3.0'

. (Join-Path $Dir 'ui\fluent.ps1')
. (Join-Path $Dir 'lib\shift-rules.ps1')

# ══════════════ 多人共用：程式資料夾不留任何個人資料 ══════════════
# 班表、設定都只放記憶體；背景工作的進度檔放在暫存資料夾，關閉時刪掉。班表只有按「匯出」時才存到使用者的「下載」資料夾。
$script:WorkDir = Join-Path $env:TEMP "出勤小幫手-$PID"
Get-ChildItem $env:TEMP -Directory -Filter '出勤小幫手-*' -ErrorAction SilentlyContinue | ForEach-Object {   # 上次沒正常關閉留下的
    $id = 0; if ([int]::TryParse(($_.Name -replace '^出勤小幫手-', ''), [ref]$id) -and (Get-Process -Id $id -ErrorAction SilentlyContinue)) { return }
    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:Schedule = @{}        # @{ 'yyyy-MM-dd' = '代碼' }，這次開啟讀到的班表
$script:ScheduleMonth = $null # [datetime] 該月 1 日

# 設定：每次開啟都是預設值，關閉後不保留
$script:Settings = [ordered]@{
    KindIndex = 0; KindPrefix = '1:'; Reason = '值班'
    DayStart = '1730'; DayEnd = '2400'; NextStart = '0000'; NextEnd = '0800'
}
function Get-SettingsArg {
    $j = ConvertTo-Json -Compress ([pscustomobject]$Settings)
    '-SettingsB64 ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($j))
}
function Get-DownloadsDir { (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path }
# 背景工作回報的班表（JSON）存進記憶體
function Set-ScheduleFromJson([string]$Json) {
    $o = ConvertFrom-Json -InputObject $Json
    $script:Schedule = @{}
    foreach ($r in @($o.Rows | ForEach-Object { $_ })) { $Schedule[$r.D] = $r.C }
    $script:ScheduleMonth = [DateTime]::new([int]$o.Year, [int]$o.Month, 1)
}

# ══════════════ 背景工作 ══════════════
# 一次只跑一個；進度從暫存資料夾的 run.log 讀，控制寫進 control.txt
$script:RunLog = Join-Path $WorkDir 'run.log'
$script:ControlFile = Join-Path $WorkDir 'control.txt'
$script:Task = $null
function Test-TaskRunning { $null -ne $Task }
function Start-Task([string]$Name, [string]$Script, [string]$ArgLine, [scriptblock]$OnLine, [scriptblock]$OnExit) {
    if (Test-TaskRunning) {
        [System.Windows.Forms.MessageBox]::Show("「$($Task.Name)」還在執行，請等它結束或先停止。", '出勤小幫手') | Out-Null
        return $false
    }
    [IO.File]::WriteAllText($RunLog, '')
    [IO.File]::WriteAllText($ControlFile, 'run')
    $path = Join-Path $Dir $Script
    # 完全不建立視窗：用 -WindowStyle Hidden 的話，Windows 11 會改用「終端機」開一個看得到的視窗
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$path`" $ArgLine -WorkDir `"$WorkDir`" $(Get-SettingsArg)"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $script:Task = @{ Name = $Name; Proc = $p; Pos = 0; Buf = ''; OnLine = $OnLine; OnExit = $OnExit }
    $true
}
function Set-TaskControl([ValidateSet('run', 'pause', 'stop')][string]$Value) { [IO.File]::WriteAllText($ControlFile, $Value) }
function Read-TaskOutput {
    if (-not $Task) { return }
    try {
        $fs = [IO.File]::Open($RunLog, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -gt $Task.Pos) {
                $fs.Position = $Task.Pos
                $bytes = New-Object byte[] ($fs.Length - $Task.Pos)
                $null = $fs.Read($bytes, 0, $bytes.Length)
                $Task.Pos = $fs.Length
                $Task.Buf += [Text.Encoding]::UTF8.GetString($bytes)
            }
        } finally { $fs.Dispose() }
    } catch { return }
    while (($i = $Task.Buf.IndexOf("`n")) -ge 0) {
        $line = $Task.Buf.Substring(0, $i).TrimEnd("`r"); $Task.Buf = $Task.Buf.Substring($i + 1)
        if (-not $line) { continue }
        $parts = $line.Split("`t", 2)
        $payload = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        try { & $Task.OnLine $parts[0] $payload } catch {}
    }
}
$script:TaskTimer = New-Object System.Windows.Forms.Timer
$TaskTimer.Interval = 400
$TaskTimer.Add_Tick({
    if (-not $Task) { return }
    Read-TaskOutput
    if ($Task.Proc.HasExited) {
        Read-TaskOutput
        $done = $Task.OnExit; $script:Task = $null
        if ($done) { try { & $done } catch {} }
    }
})

# ══════════════ 主視窗：左側選單 + 右邊頁面 ══════════════
$NavW = 200
$script:form = New-Object System.Windows.Forms.Form
$form.Text = '出勤小幫手'
$form.ClientSize = New-Object System.Drawing.Size(($NavW + 740), 700)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Fluent.Theme]::Window
$form.ForeColor = $C_INK
$form.Font = $F_Body
$appIco = Join-Path $Dir 'app.ico'
if (Test-Path $appIco) { $form.Icon = New-Object System.Drawing.Icon $appIco }

$logo = New-Object Fluent.Logo
Set-Box $logo 18 16 28 28
$form.Controls.Add($logo)
$null = New-Lbl $form '出勤小幫手' 52 20 140 24 $F_H $C_INK
$script:lblVer = New-Lbl $form "v$AppVersion" 22 670 170 20 $F_Cap $C_MUTE

# 跑一支腳本並等它結束，等的時候視窗照樣能動（不開任何主控台視窗）
function Invoke-ScriptUI([string]$File, [string]$ArgLine = '', [int]$MaxSec = 300) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -NonInteractive -File `"$File`" $ArgLine"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $t0 = Get-Date
    while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt $MaxSec) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
    $p.HasExited
}
# 背景工作（要回傳資料的，例如查 GitHub），等的時候視窗照樣能動
function Wait-JobUI($Job, [int]$MaxSec = 20) {
    $t0 = Get-Date
    while ($Job.State -eq 'Running' -and ((Get-Date) - $t0).TotalSeconds -lt $MaxSec) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
    $out = if ($Job.State -eq 'Completed') { Receive-Job $Job } else { $null }
    Remove-Job $Job -Force -ErrorAction SilentlyContinue
    $out
}

$script:stack = New-Card $form $NavW 0 760 720
$stack.Radius = 8; $stack.Fill = [Fluent.Theme]::Stack

$script:Pages = New-Object System.Collections.ArrayList
# 新增一頁：回傳頁面 Panel，內容從 y=72 開始放（上面是標題），寬 690（x=24 起）
function New-Page([string]$Name, [string]$Glyph, [scriptblock]$OnShow) {
    $pg = New-Object System.Windows.Forms.Panel
    Set-Box $pg 1 8 739 692
    $pg.BackColor = [Fluent.Theme]::Stack; $pg.Visible = $false
    [Fluent.Theme]::Buffer($pg)
    $stack.Controls.Add($pg)
    $null = New-Lbl $pg $Name 22 14 600 44 $F_Title $C_INK
    $nb = New-Object Fluent.NavItem
    $nb.Text = $Name; $nb.Glyph = $Glyph; $nb.Tag = $Pages.Count
    Set-Box $nb 8 (64 + $Pages.Count * 44) ($NavW - 16) 40
    $nb.Add_Click({ Show-Page $this.Tag })
    $form.Controls.Add($nb)
    [void]$Pages.Add(@{ Panel = $pg; Nav = $nb; OnShow = $OnShow })
    $pg
}
function Show-Page([int]$Idx) {
    for ($i = 0; $i -lt $Pages.Count; $i++) { $Pages[$i].Panel.Visible = ($i -eq $Idx); $Pages[$i].Nav.Selected = ($i -eq $Idx) }
    if ($Pages[$Idx].OnShow) { try { & $Pages[$Idx].OnShow } catch {} }
}

# ── 載入功能模組 ──
foreach ($m in (Get-ChildItem (Join-Path $Dir 'modules') -Filter '*.ps1' | Sort-Object Name)) { . $m.FullName }

$form.Add_Shown({ [Fluent.Theme]::StyleWindow($form); Show-Page 0; $TaskTimer.Start() })
$form.Add_FormClosing({
    if (Test-TaskRunning) {
        $r = [System.Windows.Forms.MessageBox]::Show("「$($Task.Name)」還在執行。要停止並關閉嗎？", '出勤小幫手', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $_.Cancel = $true; return }
        Set-TaskControl 'stop'
        try { $Task.Proc.WaitForExit(15000) | Out-Null; if (-not $Task.Proc.HasExited) { $Task.Proc.Kill() } } catch {}
    }
    $TaskTimer.Stop()
})
try { [void]$form.ShowDialog() }
finally {
    # 關閉後清掉這次的一切：暫存資料夾、記憶體裡的班表
    $script:Schedule = @{}
    Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
}
