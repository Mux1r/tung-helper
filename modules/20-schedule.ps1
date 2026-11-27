# ── 班表：從出勤系統讀取，讀完可按一鍵匯出到「下載」資料夾 ──
$script:pgSched = New-Page '班表' $Icon.Calendar { Update-SchedulePage }

$cardSchOp = New-Card $pgSched 24 72 690 132
Add-CardHead $cardSchOp $Icon.Calendar '從出勤系統讀取班表'
$script:lblSchInfo = New-Lbl $cardSchOp '讀取「排班申請」畫面目前顯示的月份（不會修改班表）' 52 36 460 20 $F_Cap $C_MUTE
$script:btnSchRead = New-Btn $cardSchOp '讀取班表' 534 16 140 32 $Icon.Refresh -Accent
$null = New-Lbl $cardSchOp $Icon.Download 18 82 24 24 $F_IconL $C_INK
$null = New-Lbl $cardSchOp '匯出到下載資料夾' 52 76 200 22 $F_H $C_INK
$script:lblSchExport = New-Lbl $cardSchOp '讀取後可匯出成「班表_年-月.csv」，存到自己的下載資料夾' 52 98 460 20 $F_Cap $C_INK2
$script:btnSchExport = New-Btn $cardSchOp '匯出' 534 82 140 32 $Icon.Download
$btnSchExport.Enabled = $false

$cardSchList = New-Card $pgSched 24 216 690 464
Add-CardHead $cardSchList '' '班表'
$script:lblSchMonth = New-Lbl $cardSchList '' 300 16 374 20 $F_Cap $C_MUTE
$lblSchMonth.TextAlign = 'TopRight'
$script:lvSch = New-List $cardSchList 12 46 666 406 @(@('日期', 110), @('星期', 60), @('班別', 70), @('值班', 70), @('說明', 330))

function Update-SchedulePage {
    $codes = $Schedule
    $lvSch.BeginUpdate(); $lvSch.Items.Clear()
    $btnSchExport.Enabled = [bool]$ScheduleMonth
    if (-not $ScheduleMonth) { $lblSchMonth.Text = '尚未讀取（關閉程式後不保留）'; $lvSch.EndUpdate(); return }
    $y = $ScheduleMonth.Year; $m = $ScheduleMonth.Month
    $lblSchMonth.Text = '{0} 年 {1} 月（只在這次開啟期間顯示，關閉後不保留）' -f ($y - 1911), $m
    for ($d = 1; $d -le [DateTime]::DaysInMonth($y, $m); $d++) {
        $dt = [DateTime]::new($y, $m, $d); $code = $codes[(Format-IsoDate $dt)]
        $oncall = Test-OncallNight $dt $codes
        $row = Add-ListRow $lvSch @((Format-Roc $dt), (Get-WeekdayText $dt), $code, $(if ($oncall) { '值班' } else { '' }), (Get-ShiftText $code))
        if ($oncall) { $row.SubItems[3].ForeColor = $C_ACC; $row.SubItems[2].ForeColor = $C_ACC }
        if ($dt.DayOfWeek -in 'Saturday', 'Sunday') { $row.SubItems[1].ForeColor = $C_CRIT }
        if (-not $code) { $row.SubItems[4].ForeColor = $C_WARN }
    }
    $lvSch.EndUpdate()
}

# 一鍵匯出：把記憶體裡的班表存到使用者自己的下載資料夾，存完在檔案總管標出檔案
$btnSchExport.Add_Click({
    if (-not $ScheduleMonth) { return }
    try {
        $y = $ScheduleMonth.Year; $m = $ScheduleMonth.Month
        $out = Join-Path (Get-DownloadsDir) ('班表_{0}-{1:D2}.csv' -f ($y - 1911), $m)
        $rows = for ($d = 1; $d -le [DateTime]::DaysInMonth($y, $m); $d++) {
            $dt = [DateTime]::new($y, $m, $d); $code = $Schedule[(Format-IsoDate $dt)]
            [pscustomobject]@{ 日期 = (Format-Roc $dt); 星期 = (Get-WeekdayText $dt); 班別 = $code
                               值班 = $(if (Test-OncallNight $dt $Schedule) { '值班' } else { '' }); 說明 = (Get-ShiftText $code) }
        }
        $rows | Export-Csv $out -NoTypeInformation -Encoding UTF8
        $lblSchExport.Text = "已匯出：$out"; $lblSchExport.ForeColor = $C_GOOD
        Start-Process explorer.exe "/select,`"$out`""
    } catch {
        $lblSchExport.Text = "匯出失敗：$($_.Exception.Message)"; $lblSchExport.ForeColor = $C_CRIT
    }
})

$btnSchRead.Add_Click({
    $onLine = {
        param($Type, $Payload)
        switch ($Type) {
            'LOG'      { $lblSchInfo.Text = $Payload; $lblSchInfo.ForeColor = $(if ($Payload -match '✗|⚠') { $C_WARN } else { $C_INK2 }) }
            'SCHEDULE' { Set-ScheduleFromJson $Payload; Update-SchedulePage }
            'STATE'    { if ($Payload -eq 'error') { $lblSchInfo.ForeColor = $C_CRIT } }
        }
    }
    if (Start-Task '讀取班表' 'tasks\overtime.ps1' '-Action Schedule' $onLine { $btnSchRead.Enabled = $true; if (Get-Command Update-OtButtons -ErrorAction SilentlyContinue) { Update-OtButtons } }) {
        $btnSchRead.Enabled = $false; $lblSchInfo.Text = '讀取中…（請勿動滑鼠鍵盤）'; $lblSchInfo.ForeColor = $C_ACC
        $lblSchExport.Text = '讀取後可匯出成「班表_年-月.csv」，存到自己的下載資料夾'; $lblSchExport.ForeColor = $C_INK2
        if (Get-Command Update-OtButtons -ErrorAction SilentlyContinue) { Update-OtButtons }
    }
})
