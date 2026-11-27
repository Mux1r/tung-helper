# ── 入院記錄：各欄位內容（手動填或從剪貼簿匯入），確定後貼進住院醫囑系統的入院記錄 ──
# 內容只放記憶體；執行時寫到暫存資料夾給背景工作讀，背景工作讀完就刪；關閉程式全部清掉
$script:pgAdm = New-Page '入院記錄' $Icon.Edit { Update-AdmButtons; if (-not $AdmPatients.Count) { Update-AdmPatients } }

$script:AdmFields = [ordered]@{
    CC   = @{ Name = '主訴';         Hint = '勾選 [v]patient，接在最後（換行）' }
    PI   = @{ Name = '現病史';       Hint = '接在最後' }
    PH   = @{ Name = '過去病史';     Hint = '插在最前面，後面換行（範本保留）' }
    PSH  = @{ Name = '個人歷史';     Hint = '全選覆蓋（範本換成這裡的內容）' }
    ROS  = @{ Name = 'ROS';          Hint = '全選覆蓋' }
    PE   = @{ Name = 'PE';           Hint = '護理評估帶入生命徵象後，從空白 Vital signs 那行起覆蓋' }
    DX   = @{ Name = '疾病診斷';     Hint = '接在最後' }
    PLAN = @{ Name = '住院診療計畫'; Hint = '全選覆蓋' }
}
$script:AdmData = @{}; foreach ($k in $AdmFields.Keys) { $AdmData[$k] = '' }
$script:AdmCur = 'CC'

# 內容卡：左邊欄位清單、右邊編輯框
$cardAdm = New-Card $pgAdm 24 72 690 262
$script:lblAdmHint = New-Lbl $cardAdm '' 176 14 500 20 $F_Cap $C_MUTE
$script:AdmNavs = @{}
$i = 0
foreach ($k in $AdmFields.Keys) {
    $nb = New-Object Fluent.NavItem
    $nb.Text = $AdmFields[$k].Name; $nb.Glyph = ''; $nb.Tag = $k
    Set-Box $nb 8 (10 + $i * 30) 156 28
    $nb.Add_Click({ Select-AdmField $this.Tag })
    $cardAdm.Controls.Add($nb)
    $AdmNavs[$k] = $nb
    $i++
}
$script:txAdm = New-Object System.Windows.Forms.TextBox
Set-Box $txAdm 176 40 498 210
$txAdm.Multiline = $true; $txAdm.ScrollBars = 'Vertical'; $txAdm.AcceptsReturn = $true; $txAdm.AcceptsTab = $false; $txAdm.WordWrap = $true
$txAdm.BorderStyle = 'FixedSingle'; $txAdm.BackColor = [Fluent.Theme]::Field; $txAdm.ForeColor = $C_INK
$txAdm.Font = New-Object System.Drawing.Font('Consolas', 10)
$cardAdm.Controls.Add($txAdm); [Fluent.Theme]::DarkScroll($txAdm)

function Save-AdmCurrent { $AdmData[$AdmCur] = $txAdm.Text; Update-AdmNavMarks }
function Update-AdmNavMarks {
    foreach ($k in $AdmFields.Keys) { $AdmNavs[$k].Text = $AdmFields[$k].Name + $(if ($AdmData[$k].Trim()) { '  ●' } else { '' }) }
}
function Select-AdmField([string]$Key) {
    Save-AdmCurrent
    $script:AdmCur = $Key
    foreach ($k in $AdmFields.Keys) { $AdmNavs[$k].Selected = ($k -eq $Key) }
    $txAdm.Text = $AdmData[$Key]
    $lblAdmHint.Text = "$($AdmFields[$Key].Name)：$($AdmFields[$Key].Hint)"
    $txAdm.Focus() | Out-Null
}
$txAdm.Add_Leave({ Save-AdmCurrent })

# 自動帶入選項
$cardAdmOpt = New-Card $pgAdm 24 344 690 82
Add-CardHead $cardAdmOpt '' '自動帶入'
function New-AdmCheck([string]$Text, [int]$X, [int]$Y) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Checked = $true; $c.AutoSize = $true
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Font = $F_Body; $c.ForeColor = $C_INK; $c.BackColor = [Fluent.Theme]::Card
    $cardAdmOpt.Controls.Add($c); $c
}
$script:ckDrug   = New-AdmCheck '用藥紀錄：匯入雲端藥歷' 18 36
$script:ckVitals = New-AdmCheck 'PE：護理評估帶入生命徵象' 250 36
$script:ckNrs    = New-AdmCheck '營養風險：五項勾「否」' 480 36
$script:ckLab    = New-AdmCheck '近期檢驗結果（兩個月內）' 18 58
$script:ckRpt    = New-AdmCheck '近期檢查報告（一個月內）' 250 58

# 操作＋進度
$cardAdmRun = New-Card $pgAdm 24 438 690 242
$script:btnAdmImport = New-Btn $cardAdmRun '從剪貼簿匯入' 18 12 150 32 $Icon.Download
$script:btnAdmClear  = New-Btn $cardAdmRun '清空' 176 12 90 32 $Icon.Clear
$script:btnAdmNext   = New-Btn $cardAdmRun '下一位病人' 274 12 140 32 $Icon.Refresh
$script:btnAdmRun    = New-Btn $cardAdmRun '貼到入院記錄' 524 12 150 32 $Icon.Play -Accent
# 病人：住院醫囑系統只會開一個視窗，這裡顯示它目前的病人；按「貼到入院記錄」時會再讀一次並在確認框顯示，避免貼錯病人
$null = New-Lbl $cardAdmRun '病人' 18 59 50 20 $F_Body $C_INK2
$script:lblAdmPt = New-Lbl $cardAdmRun '（尚未讀取）' 68 58 400 22 $F_H $C_INK
$script:btnAdmPtRefresh = New-Btn $cardAdmRun '重新整理' 476 54 110 30 $Icon.Refresh
$script:lblAdmMsg = New-Lbl $cardAdmRun '先在住院醫囑系統打開病人的「入院記錄」；貼上後請自行檢查再按暫存／完成。' 18 92 656 20 $F_Cap $C_MUTE
$script:lvAdm = New-List $cardAdmRun 12 116 666 116 @(@('步驟', 120), @('狀態', 80), @('說明', 440))
$script:AdmPatients = @()

$AdmStepText = @{ running = '進行中'; ok = '完成'; fail = '要手動處理'; skip = '略過' }
function Update-AdmButtons { $btnAdmRun.Enabled = -not (Test-TaskRunning); $btnAdmNext.Enabled = -not (Test-TaskRunning) }

# 讀病人清單：在背景跑（UI Automation 掃視窗要一兩秒），等的時候視窗照樣能動
$script:AdmPtBlock = {
    param($Lib)
    . $Lib
    @(Get-MoAdmissionWindows | ForEach-Object { [pscustomobject]@{ H = $_.H; Chart = $_.Chart; Name = $_.Name; Label = $_.Label } })
}
function Update-AdmPatients {
    $btnAdmPtRefresh.Enabled = $false
    $lblAdmPt.Text = '讀取中…'; $lblAdmPt.ForeColor = $C_MUTE
    $r = Wait-JobUI (Start-Job -ArgumentList (Join-Path $Dir 'lib\moclient.ps1') -ScriptBlock $AdmPtBlock) 30
    $script:AdmPatients = @($r | Where-Object { $_ })
    if (-not $AdmPatients.Count) { $lblAdmPt.Text = '（住院醫囑系統沒有開在入院記錄）'; $lblAdmPt.ForeColor = $C_WARN }
    else { $p = $AdmPatients[0]; $lblAdmPt.Text = $(if ($p.Label) { $p.Label } else { '（讀不到病歷號）' }); $lblAdmPt.ForeColor = $C_INK }
    $btnAdmPtRefresh.Enabled = $true
}
function Get-AdmSelectedPatient { if ($AdmPatients.Count) { $AdmPatients[0] } else { $null } }
$btnAdmPtRefresh.Add_Click({ Update-AdmPatients })
# 下一位病人：清空欄位與進度、重新讀病人清單（勾選的自動帶入保留）
$btnAdmNext.Add_Click({
    foreach ($k in $AdmFields.Keys) { $AdmData[$k] = '' }
    $txAdm.Text = ''; Update-AdmNavMarks; $lvAdm.Items.Clear()
    Select-AdmField 'CC'
    $lblAdmMsg.Text = '已清空。在住院醫囑系統打開下一位病人的入院記錄，填好內容再按「貼到入院記錄」。'; $lblAdmMsg.ForeColor = $C_INK2
    Update-AdmPatients
})

# 從剪貼簿匯入：認得「主訴：」「【現病史】」「## PE」「Chief Complaint:」這類標題，標題後面到下一個標題前的內容就是那一段
$script:AdmHeadings = @(
    @{ Key = 'CC';   Re = '主訴|Chief\s*Complaints?|C\.?C\.?' }
    @{ Key = 'PI';   Re = '現病史|Present\s*Illness|History\s*of\s*Present\s*Illness|HPI|P\.?I\.?' }
    @{ Key = 'PH';   Re = '過去病史|Past\s*(Medical\s*)?History|PMH|P\.?H\.?' }
    @{ Key = 'PSH';  Re = '個人歷史|個人史|Personal(\s*and\s*Social)?\s*History|Social\s*History' }
    @{ Key = 'ROS';  Re = 'ROS|Review\s*of\s*Systems?|器官系統複查' }
    @{ Key = 'PE';   Re = 'PE|P\.E\.|Physical\s*Exam(ination)?|身體診查|理學檢查' }
    @{ Key = 'DX';   Re = '疾病診斷|診斷|(Tentative\s*)?Diagnosis|Impression|Dx' }
    @{ Key = 'PLAN'; Re = '住院診療計[畫劃]|診療計[畫劃]|Plan(\s*(&|and)\s*Goal)?' }
)
function Import-AdmText([string]$Text) {
    $found = @{}; $cur = $null; $buf = New-Object System.Text.StringBuilder
    foreach ($line in ($Text -split "`r?`n")) {
        $hit = $null
        foreach ($h in $AdmHeadings) {
            $m = [regex]::Match($line, "^\s*(#+\s*|【|\[|\*\*)?\s*(" + $h.Re + ")\s*(】|\]|\*\*)?\s*[:：]?\s*(?<rest>.*)$", 'IgnoreCase')
            # 標題要嘛有冒號／括號／#，要嘛整行就是標題，避免把內文開頭的字誤認成標題
            if ($m.Success -and ($m.Groups[1].Success -or $m.Groups[3].Success -or $line -match '[:：]' -or -not $m.Groups['rest'].Value.Trim())) { $hit = @{ Key = $h.Key; Rest = $m.Groups['rest'].Value }; break }
        }
        if ($hit) {
            if ($cur) { $found[$cur] = $buf.ToString().Trim() }
            $cur = $hit.Key; $buf = New-Object System.Text.StringBuilder
            if ($hit.Rest.Trim()) { [void]$buf.AppendLine($hit.Rest.Trim()) }
        } elseif ($cur) { [void]$buf.AppendLine($line) }
    }
    if ($cur) { $found[$cur] = $buf.ToString().Trim() }
    $found
}
$btnAdmImport.Add_Click({
    $text = ''; try { $text = [System.Windows.Forms.Clipboard]::GetText() } catch {}
    if (-not $text.Trim()) { $lblAdmMsg.Text = '剪貼簿沒有文字'; $lblAdmMsg.ForeColor = $C_WARN; return }
    $found = Import-AdmText $text
    if (-not $found.Count) { $lblAdmMsg.Text = '剪貼簿的文字裡找不到「主訴」「現病史」這類標題'; $lblAdmMsg.ForeColor = $C_WARN; return }
    Save-AdmCurrent
    foreach ($k in $found.Keys) { $AdmData[$k] = ($found[$k] -replace "`r?`n", "`r`n") }
    $names = ($AdmFields.Keys | Where-Object { $found.Contains($_) } | ForEach-Object { $AdmFields[$_].Name }) -join '、'
    $lblAdmMsg.Text = "已匯入：$names（請逐欄檢查）"; $lblAdmMsg.ForeColor = $C_GOOD
    $txAdm.Text = $AdmData[$AdmCur]; Update-AdmNavMarks
})
$btnAdmClear.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show('清空所有欄位？', '入院記錄', 'YesNo', 'Question') -ne 'Yes') { return }
    foreach ($k in $AdmFields.Keys) { $AdmData[$k] = '' }
    $txAdm.Text = ''; Update-AdmNavMarks; $lvAdm.Items.Clear()
})

$script:AdmOnLine = {
    param($Type, $Payload)
    switch ($Type) {
        'LOG' { $lblAdmMsg.Text = $Payload; $lblAdmMsg.ForeColor = $(if ($Payload -match '✗|⚠') { $C_WARN } else { $C_INK2 }) }
        'PLAN' {
            $lvAdm.BeginUpdate(); $lvAdm.Items.Clear()
            foreach ($s in @((ConvertFrom-Json -InputObject $Payload) | ForEach-Object { $_ })) { $null = Add-ListRow $lvAdm @($s, '等待', '') $C_MUTE 1 }
            $lvAdm.EndUpdate()
        }
        'ITEM' {
            $f = $Payload.Split("`t"); $idx = [int]$f[0]
            if ($idx -lt $lvAdm.Items.Count) {
                $row = $lvAdm.Items[$idx]
                $row.SubItems[1].Text = $AdmStepText[$f[1]]
                $row.SubItems[1].ForeColor = switch ($f[1]) { 'ok' { $C_GOOD } 'fail' { $C_CRIT } 'running' { $C_ACC } default { $C_MUTE } }
                $row.SubItems[2].Text = $(if ($f.Count -gt 2) { $f[2] } else { '' })
                $row.EnsureVisible(); $lvAdm.Invalidate()
            }
        }
        'STATE' {
            if ($Payload -eq 'error') { $lblAdmMsg.ForeColor = $C_CRIT }
            elseif ($Payload -eq 'done') { $lblAdmMsg.Text = '完成。請在入院記錄檢查後自己按暫存／完成；要做下一位請按「下一位病人」。'; $lblAdmMsg.ForeColor = $C_GOOD }
        }
    }
}
$btnAdmRun.Add_Click({
    Save-AdmCurrent
    Update-AdmPatients                                     # 每次貼之前重讀，確定是現在畫面上的病人
    $pt = Get-AdmSelectedPatient
    if (-not $pt) { $lblAdmMsg.Text = '住院醫囑系統沒有開在病人的「入院記錄」'; $lblAdmMsg.ForeColor = $C_WARN; return }
    $filled = @($AdmFields.Keys | Where-Object { $AdmData[$_].Trim() })
    if (-not $filled.Count -and -not ($ckDrug.Checked -or $ckVitals.Checked -or $ckNrs.Checked -or $ckLab.Checked -or $ckRpt.Checked)) { $lblAdmMsg.Text = '沒有內容要貼'; return }
    $msg = "要貼到這位病人的入院記錄嗎？`n`n病人：$($pt.Label)`n有內容的欄位：" + $(if ($filled.Count) { ($filled | ForEach-Object { $AdmFields[$_].Name }) -join '、' } else { '（無）' }) +
           "`n`n執行中請勿動滑鼠鍵盤。不會按暫存或完成。"
    if ([System.Windows.Forms.MessageBox]::Show($msg, '貼到入院記錄', 'YesNo', 'Question') -ne 'Yes') { return }
    $data = [ordered]@{ TargetHwnd = $pt.H; Chart = $pt.Chart }
    foreach ($k in $AdmFields.Keys) { $data[$k] = $AdmData[$k] }
    $data.DrugImport = $ckDrug.Checked; $data.NurseVitals = $ckVitals.Checked; $data.Nutrition = $ckNrs.Checked
    $data.LabImport = $ckLab.Checked; $data.ReportImport = $ckRpt.Checked
    $file = Join-Path $WorkDir ('admission-{0}.json' -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($file, (ConvertTo-Json ([pscustomobject]$data)), (New-Object Text.UTF8Encoding $false))
    $lvAdm.Items.Clear()
    if (Start-Task '入院記錄' 'tasks\admission.ps1' "-DataFile `"$file`"" $AdmOnLine { Update-AdmButtons; if (Get-Command Update-OtButtons -ErrorAction SilentlyContinue) { Update-OtButtons } }) {
        $lblAdmMsg.Text = '執行中…請勿動滑鼠鍵盤'; $lblAdmMsg.ForeColor = $C_ACC
    } else { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    Update-AdmButtons
})

Select-AdmField 'CC'
