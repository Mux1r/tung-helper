# ── 設定：加班類別、理由、兩段時間 ──
$script:pgSet = New-Page '設定' $Icon.Setting $null

$cardSet = New-Card $pgSet 24 72 690 312
Add-CardHead $cardSet $Icon.Work '值班加班申請'
$script:btnSetSave = New-Btn $cardSet '套用' 554 16 120 32 $Icon.Save -Accent
$script:lblSetMsg = New-Lbl $cardSet '' 330 52 344 18 $F_Cap $C_GOOD
$lblSetMsg.TextAlign = 'TopRight'

# 出勤系統「加班類別」下拉選單的順序（第 0 項起）
$script:KindChoices = @('1:領錢', '2:積時數', '3:補時數', '4:積時數-特定On Call', '6:領錢(達文西)', '7:加班費-特定On Call', '8:加班費', 'A:特定積時數-夜間支援社保')
$null = New-Lbl $cardSet '加班類別' 52 85 150 20 $F_Body $C_INK2
$script:cbSetKind = New-Combo $cardSet 232 79 260 $KindChoices ([int]$Settings.KindIndex)
$null = New-Lbl $cardSet '加班理由' 52 125 150 20 $F_Body $C_INK2
$script:txSetReason = New-Field $cardSet 232 118 260 ([string]$Settings.Reason)

function Format-HhmmField([string]$V) { if ($V -match '^\d{4}$') { $V.Substring(0, 2) + ':' + $V.Substring(2) } else { $V } }
$null = New-Lbl $cardSet '值班當天' 52 165 150 20 $F_Body $C_INK2
$script:txSetDayS = New-Field $cardSet 232 158 100 (Format-HhmmField $Settings.DayStart)
$null = New-Lbl $cardSet '~' 342 165 20 20 $F_Body $C_INK2
$script:txSetDayE = New-Field $cardSet 362 158 100 (Format-HhmmField $Settings.DayEnd)
$null = New-Lbl $cardSet '值班隔天' 52 205 150 20 $F_Body $C_INK2
$script:txSetNextS = New-Field $cardSet 232 198 100 (Format-HhmmField $Settings.NextStart)
$null = New-Lbl $cardSet '~' 342 205 20 20 $F_Body $C_INK2
$script:txSetNextE = New-Field $cardSet 362 198 100 (Format-HhmmField $Settings.NextEnd)
$null = New-Lbl $cardSet '時間格式 17:30 或 1730；24:00 代表當天午夜。設定只在這次開啟有效，關閉後恢復預設。' 52 248 600 20 $F_Cap $C_MUTE
$null = New-Lbl $cardSet '值班日的判斷：當天是 9076，且隔天是 906 或 908。' 52 272 600 20 $F_Cap $C_MUTE

$cardCodes = New-Card $pgSet 24 396 690 200
Add-CardHead $cardCodes $Icon.Info '班別代碼'
$y = 46
foreach ($k in $ShiftCodeInfo.Keys) {
    $null = New-Lbl $cardCodes $k 52 $y 70 22 $F_H $C_INK
    $null = New-Lbl $cardCodes $ShiftCodeInfo[$k] 130 $y 540 22 $F_Body $C_INK2
    $y += 28
}

function ConvertTo-Hhmm([string]$V) {
    $v = $V.Trim() -replace '[:：]', ''
    if ($v -match '^\d{3}$') { $v = '0' + $v }
    if ($v -notmatch '^\d{4}$') { return $null }
    $h = [int]$v.Substring(0, 2); $m = [int]$v.Substring(2, 2)
    if ($m -gt 59 -or $h -gt 24 -or ($h -eq 24 -and $m -ne 0)) { return $null }
    $v
}
$btnSetSave.Add_Click({
    $times = @{ DayStart = $txSetDayS.Text; DayEnd = $txSetDayE.Text; NextStart = $txSetNextS.Text; NextEnd = $txSetNextE.Text }
    foreach ($k in @($times.Keys)) {
        $v = ConvertTo-Hhmm $times[$k]
        if (-not $v) { $lblSetMsg.ForeColor = $C_CRIT; $lblSetMsg.Text = "時間格式不對：$($times[$k])"; return }
        $times[$k] = $v
    }
    if (-not $txSetReason.Text.Trim()) { $lblSetMsg.ForeColor = $C_CRIT; $lblSetMsg.Text = '加班理由不能空白'; return }
    foreach ($k in $times.Keys) { $Settings[$k] = $times[$k] }
    $Settings.KindIndex = $cbSetKind.SelectedIndex
    $Settings.KindPrefix = ($KindChoices[$cbSetKind.SelectedIndex]).Split(':')[0] + ':'
    $Settings.Reason = $txSetReason.Text.Trim()
    $lblSetMsg.ForeColor = $C_GOOD; $lblSetMsg.Text = '已套用（關閉程式後恢復預設）'
})
