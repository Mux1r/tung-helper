# ── 值班加班申請：讀班表 → 找值班日 → 逐筆填「加班申請」並存檔 ──
$script:pgOt = New-Page '值班加班申請' $Icon.Work { Update-OtButtons }

$script:tileOtMonth = New-Tile $pgOt '排班月份' $Icon.Calendar 24
$script:tileOtDays  = New-Tile $pgOt '值班天數' $Icon.Moon 200
$script:tileOtCount = New-Tile $pgOt '申請進度' $Icon.List 376
$script:tileOtState = New-Tile $pgOt '狀態' $Icon.Clock 552
Set-Tile $tileOtState '待命' $C_MUTE

$cardOtOp = New-Card $pgOt 24 168 690 112
Add-CardHead $cardOtOp '' '操作'
$script:btnOtRun     = New-Btn $cardOtOp '執行' 18 46 156 32 $Icon.Play -Accent
$script:btnOtPause   = New-Btn $cardOtOp '暫停' 182 46 156 32 $Icon.Pause
$script:btnOtStop    = New-Btn $cardOtOp '停止' 346 46 156 32 $Icon.Stop
$script:btnOtPreview = New-Btn $cardOtOp '只預覽' 510 46 162 32 $Icon.Eye
$null = New-Lbl $cardOtOp '出勤系統要先開啟並最大化；執行中請勿動滑鼠鍵盤。暫停和停止會在目前這一筆做完後生效。' 18 84 660 20 $F_Cap $C_MUTE

$cardOtList = New-Card $pgOt 24 292 690 236
Add-CardHead $cardOtList '' '申請項目'
$script:lvOt = New-List $cardOtList 12 46 666 178 @(@('日期', 120), @('時段', 120), @('類型', 90), @('狀態', 90), @('說明', 220))

$cardOtLog = New-Card $pgOt 24 540 690 140
Add-CardHead $cardOtLog '' '執行紀錄'
$btnOtClear = New-Btn $cardOtLog '清除' 584 10 90 30 $Icon.Clear
$script:rtbOt = New-Rtb $cardOtLog 18 46 658 84

$script:OtState = 'idle'
$script:OtTotal = 0
$StateText = @{ idle = '待命'; running = '執行中'; paused = '已暫停'; done = '完成'; stopped = '已停止'; error = '發生錯誤' }
$ItemText  = @{ wait = '等待'; running = '填寫中'; ok = '已送出'; fail = '未送出'; skip = '未執行'; test = '測試' }

function Update-OtButtons {
    $busy = Test-TaskRunning
    $mine = $busy -and $Task.Name -eq '值班加班申請'
    $btnOtRun.Enabled = -not $busy
    $btnOtPreview.Enabled = -not $busy
    $btnOtPause.Enabled = $mine -and $OtState -in 'running', 'paused'
    $btnOtStop.Enabled = $mine
    $btnOtPause.Text = if ($OtState -eq 'paused') { '繼續' } else { '暫停' }
    $btnOtPause.Glyph = if ($OtState -eq 'paused') { $Icon.Play } else { $Icon.Pause }
}
function Add-OtLog([string]$Text) {
    $rtbOt.AppendText("$Text`r`n"); $rtbOt.SelectionStart = $rtbOt.TextLength; $rtbOt.ScrollToCaret()
}
function Update-OtCount {
    $ok = @($lvOt.Items | Where-Object { $_.SubItems[3].Text -eq $ItemText.ok }).Count
    Set-Tile $tileOtCount ("{0} / {1}" -f $ok, $OtTotal) $(if ($OtTotal -and $ok -eq $OtTotal) { $C_GOOD } else { $C_INK })
}
$script:OtOnLine = {
    param($Type, $Payload)
    switch ($Type) {
        'LOG' { Add-OtLog $Payload }
        'STATE' {
            $script:OtState = $Payload
            $col = switch ($Payload) { 'running' { $C_ACC } 'paused' { $C_WARN } 'done' { $C_GOOD } 'error' { $C_CRIT } default { $C_MUTE } }
            Set-Tile $tileOtState $StateText[$Payload] $col
            Update-OtButtons
        }
        'SCHEDULE' {
            Set-ScheduleFromJson $Payload
            Set-Tile $tileOtMonth ('{0}/{1:D2}' -f ($ScheduleMonth.Year - 1911), $ScheduleMonth.Month) $C_INK
            if (Get-Command Update-SchedulePage -ErrorAction SilentlyContinue) { Update-SchedulePage }
        }
        'PLAN' {
            $plan = @((ConvertFrom-Json -InputObject $Payload) | ForEach-Object { $_ })   # PS 5.1 會把整個陣列當成一個物件，要攤開
            $lvOt.BeginUpdate(); $lvOt.Items.Clear()
            foreach ($p in $plan) { $null = Add-ListRow $lvOt @($p.Date, $p.Time, $(if ($p.Round -eq 1) { '值班當天' } else { '值班隔天' }), $ItemText.wait, '') $C_MUTE 3 }
            $lvOt.EndUpdate()
            $script:OtTotal = $plan.Count
            Set-Tile $tileOtDays ("{0} 天" -f [int]($plan.Count / 2)) $C_INK
            Update-OtCount
        }
        'ITEM' {
            $f = $Payload.Split("`t"); $idx = [int]$f[0]
            if ($idx -lt $lvOt.Items.Count) {
                $row = $lvOt.Items[$idx]
                $row.SubItems[3].Text = $ItemText[$f[1]]
                $row.SubItems[3].ForeColor = switch ($f[1]) { 'ok' { $C_GOOD } 'fail' { $C_CRIT } 'running' { $C_ACC } 'test' { $C_ACC } default { $C_MUTE } }
                $row.SubItems[4].Text = $(if ($f.Count -gt 2) { $f[2] } else { '' })
                $row.EnsureVisible(); $lvOt.Invalidate()
            }
            Update-OtCount
        }
    }
}
function Start-Overtime([string]$Mode) {
    $argLine = "-Action $Mode"
    $rtbOt.Clear(); $lvOt.Items.Clear(); $script:OtTotal = 0
    Set-Tile $tileOtCount '—' $C_MUTE; Set-Tile $tileOtDays '—' $C_MUTE
    $script:OtState = 'running'
    if (Start-Task '值班加班申請' 'tasks\overtime.ps1' $argLine $OtOnLine { if ($OtState -eq 'running') { Set-Tile $tileOtState '已結束' $C_MUTE; $script:OtState = 'done' }; Update-OtButtons }) {
        Set-Tile $tileOtState $StateText.running $C_ACC
    } else { $script:OtState = 'idle' }
    Update-OtButtons
}

$btnOtRun.Add_Click({ Start-Overtime 'Apply' })
$btnOtPreview.Add_Click({ Start-Overtime 'Preview' })
$btnOtPause.Add_Click({
    if ($OtState -eq 'paused') { Set-TaskControl 'run'; Add-OtLog '要求繼續…' }
    else { Set-TaskControl 'pause'; Add-OtLog '要求暫停，這一筆做完後暫停…'; Set-Tile $tileOtState '暫停中…' $C_WARN }
})
$btnOtStop.Add_Click({ Set-TaskControl 'stop'; Add-OtLog '要求停止，這一筆做完後停止…'; Set-Tile $tileOtState '停止中…' $C_WARN })
$btnOtClear.Add_Click({ $rtbOt.Clear() })
Update-OtButtons
