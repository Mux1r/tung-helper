#Requires -Version 5.1
<#
  背景工作：把住醫小幫手「入院記錄」頁的內容貼進住院醫囑系統的入院記錄（不按暫存／完成，交給使用者確認）
    powershell -STA -ExecutionPolicy Bypass -File tasks\admission.ps1 -DataFile <json> [-WorkDir <dir>]

  json：{ "CC": "...", "PI": "...", "PH": "...", "PSH": "...", "ROS": "...", "PE": "...", "DX": "...", "PLAN": "...",
          "DrugImport": true, "NurseVitals": true, "Nutrition": true, "LabImport": true, "ReportImport": true }
  各段做法：
    主訴      勾 [v]patient，接在最後（換行）
    現病史    接在最後
    過去病史  插在最前面，後面換行
    用藥記錄  進入時跳出「雲端藥歷匯入」→ Enter（預設就是匯入）；不匯入就按取消
    個人歷史  全選覆蓋
    家族史    跳過
    ROS       全選覆蓋
    PE        游標放最前面 → 護理評估 → Tab、空白鍵（確定）帶入生命徵象；再把空白的「Vital signs:」那行起到最後覆蓋成 UI 內容
    營養風險  五個 [ ]否 打勾
    檢查檢驗  近期檢驗結果（兩個月內，全選、匯入）、近期檢查報告（一個月內，全選、確定）
    疾病診斷  接在最後
    住院診療計畫  全選覆蓋
  進度寫到 <WorkDir>\run.log（LOG / STATE / ITEM 序號<TAB>狀態<TAB>說明），格式同 overtime.ps1。
#>
param(
    [Parameter(Mandatory)][string]$DataFile,
    [string]$WorkDir = (Join-Path $env:TEMP '住醫小幫手-手動'),
    [string]$SettingsB64 = ''   # 住醫小幫手統一會傳，這支用不到
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot
. (Join-Path $Root 'lib\moclient.ps1')
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force $WorkDir | Out-Null }
$RunLog = Join-Path $WorkDir 'run.log'
$Utf8 = New-Object Text.UTF8Encoding $false
function Emit([string]$Type, [string]$Payload) {
    for ($i = 0; $i -lt 5; $i++) { try { [IO.File]::AppendAllText($RunLog, "$Type`t$Payload`r`n", $Utf8); break } catch { Start-Sleep -Milliseconds 50 } }
    Write-Host "$Type`t$Payload"
}
function Log([string]$Msg) { Emit 'LOG' ('{0:HH:mm:ss}  {1}' -f [DateTime]::Now, $Msg) }

# 步驟清單（ITEM 序號對應這個順序，畫面上顯示每一步的狀態）
$Steps = @('主訴', '現病史', '過去病史', '用藥記錄', '個人歷史', 'ROS', 'PE', '營養風險', '檢查檢驗', '疾病診斷', '住院診療計畫')
function Step([int]$I, [string]$State, [string]$Msg = '') { Emit 'ITEM' "$I`t$State`t$Msg" }

# 這套系統是 Big5（ANSI）文字框：先把常見的全形／特殊符號換成 Big5 有的，其他打不出來的字列出來提醒
function ConvertTo-Big5Safe([string]$S) {
    if (-not $S) { return '' }
    $S = $S -replace "[‐-―−]", '-' -replace "[‘’]", "'" -replace "[“”]", '"' -replace " ", ' ' -replace "…", '...' -replace "\t", '    '
    $S
}
function Get-NonBig5([string]$S) {
    $enc = [Text.Encoding]::GetEncoding(950, [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback)
    $bad = @()
    foreach ($ch in $S.ToCharArray()) { if ($ch -eq "`r" -or $ch -eq "`n") { continue }; try { [void]$enc.GetBytes([string]$ch) } catch { $bad += $ch } }
    ($bad | Select-Object -Unique) -join ' '
}

try {
    $d = Get-Content $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $Txt = @{}
    foreach ($k in 'CC', 'PI', 'PH', 'PSH', 'ROS', 'PE', 'DX', 'PLAN') {
        $Txt[$k] = ConvertTo-Big5Safe ([string]$d.$k).Trim()
        $bad = Get-NonBig5 $Txt[$k]
        if ($bad) { Log "⚠ $($AdmSectionDefs[$k]) 有系統打不出來的字（會變成 ?）：$bad" }
    }
    Emit 'PLAN' (ConvertTo-Json -Compress -InputObject $Steps)
    Emit 'STATE' 'running'

    Connect-MoAdmission ([int64]$d.TargetHwnd) ([string]$d.Chart)
    $pt = Get-MoPatient $MoTop
    Log "入院記錄已找到（病歷號 $($pt.Chart)），開始貼上（執行中請勿動滑鼠鍵盤）"
    if (-not (Enter-AdmTop)) { throw '無法點進主訴欄位' }

    # 0 主訴
    Step 0 running
    if ($Txt.CC) { [void](Set-AdmCheck CC 'patient' 1); Add-AdmEnd CC $Txt.CC -NewLine; Step 0 ok '勾 patient，接在最後' } else { Step 0 skip '沒有內容' }

    # 1 現病史
    Step 1 running
    [void](Enter-AdmSection PI)
    if ($Txt.PI) { Add-AdmEnd PI $Txt.PI -NewLine; Step 1 ok '接在最後' } else { Step 1 skip '沒有內容' }

    # 2 過去病史
    Step 2 running
    [void](Enter-AdmSection PH)
    if ($Txt.PH) { Add-AdmStart PH $Txt.PH; Step 2 ok '插在最前面' } else { Step 2 skip '沒有內容' }

    # 3 用藥記錄：進入就會跳出「雲端藥歷匯入」
    Step 3 running
    [void](Enter-AdmSection DH)
    $pop = Wait-MoPopup '雲端藥歷匯入' 6
    if ($pop) {
        if ($d.DrugImport) {
            Send-MoPopupKeys $pop '{ENTER}'                                  # 預設已選好「匯入」
            Start-Sleep -Milliseconds 1200
            if (Test-MoPopupOpen $pop) { [void](Invoke-MoPopupButton $pop '匯入'); Start-Sleep -Milliseconds 1200 }
            Step 3 ($(if (Test-MoPopupOpen $pop) { 'fail' } else { 'ok' })) $(if (Test-MoPopupOpen $pop) { '匯入視窗沒關，請手動處理' } else { '已匯入雲端藥歷／過敏史' })
        } else {
            [void](Invoke-MoPopupButton $pop '取消'); Start-Sleep -Milliseconds 800
            Step 3 skip '不匯入'
        }
    } else { Step 3 $(if ($d.DrugImport) { 'fail' } else { 'skip' }) '沒有跳出雲端藥歷匯入' }
    # 匯入後焦點可能不在用藥記錄，點回用藥記錄再往下走
    if ([MoW32]::Focus($MoTopH) -ne $AdmSec.DH.Edit) {
        Show-AdmBox DH; Set-MoFront
        $r = [MoW32]::Rect($AdmSec.DH.Edit); Invoke-MoClick ($r.R - 30) ($r.B - 10); Start-Sleep -Milliseconds 400
        $p2 = @(Get-MoPopups) | Where-Object { $_.Title -eq '雲端藥歷匯入' } | Select-Object -First 1
        if ($p2) { [void](Invoke-MoPopupButton $p2 '取消'); Start-Sleep -Milliseconds 800 }   # 再跳一次就取消，不重複匯入
    }

    # 4 個人歷史
    Step 4 running
    [void](Enter-AdmSection PSH)
    if ($Txt.PSH) { Set-AdmAll PSH $Txt.PSH; Step 4 ok '全選覆蓋' } else { Step 4 skip '沒有內容' }

    # 5 ROS（中間經過家族史，跳過）
    Step 5 running
    [void](Enter-AdmSection ROS)
    if ($Txt.ROS) { Set-AdmAll ROS $Txt.ROS; Step 5 ok '全選覆蓋' } else { Step 5 skip '沒有內容' }

    # 6 PE
    Step 6 running
    [void](Enter-AdmSection PE)
    [MoW32]::Select($AdmSec.PE.Edit, 0, 0)                                  # 游標放最前面，生命徵象會插在這裡
    $msg = @()
    if ($d.NurseVitals) {
        $pop = Invoke-AdmButton 'NurseVitals'
        if ($pop) {
            Send-MoPopupKeys $pop '{TAB}'; Send-MoPopupKeys $pop ' '        # Tab 到確定，空白鍵
            Start-Sleep -Milliseconds 1000
            if (Test-MoPopupOpen $pop) { [void](Invoke-MoPopupButton $pop '確定'); Start-Sleep -Milliseconds 1000 }
            $msg += $(if (Test-MoPopupOpen $pop) { '生命徵象視窗沒關' } else { '已帶入生命徵象' })
        } else { $msg += '找不到「護理評估」按鈕，請手動帶入生命徵象' }
    }
    if ($d.DifficultIntubation) {
        # 困難插管評估：焦點預設在「不符合困難插管」→ 空白鍵勾選 → Shift+Tab 兩次到確定 → 空白鍵。
        # 已經勾過的話不能再按空白鍵（會取消勾選）。結果存在系統裡，不會出現在 PE 文字中；按確定後要等幾秒存檔
        $pop = Invoke-AdmButton 'DifTub'
        if ($pop) {
            $cb = Get-MoDescendants $pop.El | Where-Object { $_.Current.ClassName -eq 'TCheckBox' -and $_.Current.Name -eq '不符合困難插管' } | Select-Object -First 1
            $cbh = if ($cb) { [IntPtr]$cb.Current.NativeWindowHandle } else { [IntPtr]::Zero }
            $isChecked = { if ($cbh -ne [IntPtr]::Zero) { [int][MoW32]::SendMessage($cbh, 0xF0, [IntPtr]::Zero, [IntPtr]::Zero) } else { -1 } }
            if ((& $isChecked) -eq 0) { Send-MoPopupKeys $pop ' ' }
            if ((& $isChecked) -ne 1) { $msg += '困難插管：勾不到「不符合困難插管」，請手動處理'; [void](Invoke-MoPopupButton $pop '取消') }
            else {
                Send-MoPopupKeys $pop '+{TAB 2}'; Send-MoPopupKeys $pop ' '
                for ($w = 0; $w -lt 32 -and (Test-MoPopupOpen $pop); $w++) { Start-Sleep -Milliseconds 250 }
                if (Test-MoPopupOpen $pop) { [void](Invoke-MoPopupButton $pop '確定'); for ($w = 0; $w -lt 32 -and (Test-MoPopupOpen $pop); $w++) { Start-Sleep -Milliseconds 250 } }
                $msg += $(if (Test-MoPopupOpen $pop) { '困難插管視窗沒關，請手動處理' } else { '困難插管：不符合' })
            }
        } else { $msg += '找不到「困難插管評估」按鈕，請手動處理' }
    }
    if ($Txt.PE) {
        $raw = Get-AdmRaw PE
        # 空白的「Vital signs: Body Temperature:   ℃」那一行（溫度沒填的是範本原本那行）起到最後，換成 UI 內容
        $m = [regex]::Match($raw, '(?m)^[ \t]*Vital signs:[ \t]*Body Temperature:[ \t]+℃')
        if ($m.Success) { Set-AdmAll PE ($raw.Substring(0, $m.Index) + (ConvertTo-AdmText $Txt.PE)) -Raw; $msg += '已從空白 v/s 起覆蓋' }
        else { Add-AdmEnd PE $Txt.PE -NewLine; $msg += '找不到空白 v/s 那行，內容接在最後，請檢查' }
    }
    $peFail = ($msg -join ' ') -match '找不到|沒關|勾不到'
    Step 6 $(if ($peFail) { 'fail' } elseif ($msg) { 'ok' } else { 'skip' }) ($msg -join '；')

    # 7 營養風險
    Step 7 running
    [void](Enter-AdmSection NRS)
    if ($d.Nutrition) { $n = Set-AdmCheck NRS '否' 5; Step 7 $(if ($n -eq 5) { 'ok' } else { 'fail' }) "勾了 $n 個「否」" } else { Step 7 skip '' }

    # 8 檢查檢驗
    Step 8 running
    [void](Enter-AdmSection LAB)
    $msg = @(); $fail = $false
    if ($d.LabImport) {
        $before = (Get-AdmText LAB).Length
        $pop = Invoke-AdmButton 'LabResults'
        if ($pop -and (Open-MoTreeRange $pop '兩個月內')) {
            Start-Sleep -Milliseconds 4000                                   # 等資料載入
            Send-MoPopupKeys $pop '{TAB 3}'; Send-MoPopupKeys $pop ' '       # Tab 3 次到全選
            Send-MoPopupKeys $pop '+{TAB 2}'; Send-MoPopupKeys $pop ' '      # Shift+Tab 2 次回到匯入
            Start-Sleep -Milliseconds 2000
            if (Test-MoPopupOpen $pop) { [void](Invoke-MoPopupButton $pop '全選'); Start-Sleep -Milliseconds 600; [void](Invoke-MoPopupButton $pop '匯入'); Start-Sleep -Milliseconds 2000 }
            $err = Close-MoMessages
            if (Test-MoPopupOpen $pop) { $fail = $true; $msg += '檢驗結果視窗沒關，請手動處理' }
            else { $msg += "檢驗結果匯入 $((Get-AdmText LAB).Length - $before) 字" + $(if ($err) { "（系統訊息：$err）" }) }
        } else { $fail = $true; $msg += '開不了近期檢驗結果，請手動匯入'; if ($pop) { [void](Invoke-MoPopupButton $pop '取消') } }
    }
    if ($d.ReportImport) {
        $before = (Get-AdmText LAB).Length
        $pop = Invoke-AdmButton 'Reports'
        if ($pop -and (Open-MoTreeRange $pop '一個月內')) {
            Start-Sleep -Milliseconds 4000
            Send-MoPopupKeys $pop '+{TAB}'; Send-MoPopupKeys $pop ' '        # Shift+Tab 1 次到全選
            Send-MoPopupKeys $pop '+{TAB 2}'; Send-MoPopupKeys $pop ' '      # 再 Shift+Tab 2 次到確定（匯入）
            Start-Sleep -Milliseconds 2000
            if (Test-MoPopupOpen $pop) { [void](Invoke-MoPopupButton $pop '全選'); Start-Sleep -Milliseconds 600; [void](Invoke-MoPopupButton $pop '確定'); Start-Sleep -Milliseconds 2000 }
            $err = Close-MoMessages
            if (Test-MoPopupOpen $pop) { $fail = $true; $msg += '檢查報告視窗沒關，請手動處理' }
            else { $msg += "檢查報告匯入 $((Get-AdmText LAB).Length - $before) 字" + $(if ($err) { "（系統訊息：$err）" }) }
        } else { $fail = $true; $msg += '開不了近期檢查報告，請手動匯入'; if ($pop) { [void](Invoke-MoPopupButton $pop '取消') } }
    }
    Step 8 $(if ($fail) { 'fail' } elseif ($msg) { 'ok' } else { 'skip' }) ($msg -join '；')

    # 9 疾病診斷
    Step 9 running
    [void](Enter-AdmSection DX)
    if ($Txt.DX) { Add-AdmEnd DX $Txt.DX -NewLine; Step 9 ok '接在最後' } else { Step 9 skip '沒有內容' }

    # 10 住院診療計畫
    Step 10 running
    [void](Enter-AdmSection PLAN)
    if ($Txt.PLAN) { Set-AdmAll PLAN $Txt.PLAN; Step 10 ok '全選覆蓋' } else { Step 10 skip '沒有內容' }

    Log '完成。請在入院記錄檢查內容，確認後自己按「暫存」或「完成」。'
    Emit 'STATE' 'done'
} catch {
    Log "✗ 錯誤：$($_.Exception.Message)"
    Emit 'STATE' 'error'
} finally {
    Remove-Item $DataFile -Force -ErrorAction SilentlyContinue   # 內容含病人資料，用完就刪
}
