#Requires -Version 5.1
<#
  背景工作：讀班表、找值班日、填「加班申請」並存檔
  由出勤小幫手呼叫；也可以單獨執行：
    powershell -STA -ExecutionPolicy Bypass -File tasks\overtime.ps1 -Action Schedule
    powershell -STA -ExecutionPolicy Bypass -File tasks\overtime.ps1 -Action Preview
    powershell -STA -ExecutionPolicy Bypass -File tasks\overtime.ps1 -Action Apply

  程式資料夾裡不寫任何檔案（多人共用）：班表只回報給出勤小幫手，由使用者按「匯出」才存到「下載」資料夾。
  進度寫到 <WorkDir>\run.log（暫存資料夾，出勤小幫手關閉時刪掉），一行一筆「TYPE<TAB>內容」：
    LOG 訊息 / STATE running|paused|done|stopped|error / SCHEDULE 班表 json / PLAN json / ITEM 序號<TAB>狀態<TAB>說明
  控制檔 <WorkDir>\control.txt：run / pause / stop（每筆之間檢查，不會停在一筆的中間）
#>
param(
    [ValidateSet('Schedule', 'Preview', 'Apply')][string]$Action = 'Preview',
    [string]$WorkDir = (Join-Path $env:TEMP '出勤小幫手-手動'),
    [string]$SettingsB64 = '',   # 設定（JSON 再 Base64），由出勤小幫手傳入；沒給就用預設
    [switch]$NoSave   # 測試用：填好第一筆就停，不存檔
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot
. (Join-Path $Root 'lib\shift-rules.ps1')
. (Join-Path $Root 'lib\ofcmb.ps1')
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force $WorkDir | Out-Null }
$RunLog = Join-Path $WorkDir 'run.log'
$Control = Join-Path $WorkDir 'control.txt'
$Utf8 = New-Object Text.UTF8Encoding $false

function Emit([string]$Type, [string]$Payload) {
    $line = "$Type`t$Payload"
    for ($i = 0; $i -lt 5; $i++) { try { [IO.File]::AppendAllText($RunLog, "$line`r`n", $Utf8); break } catch { Start-Sleep -Milliseconds 50 } }
    Write-Host $line
}
function Log([string]$Msg) { Emit 'LOG' ('{0:HH:mm:ss}  {1}' -f [DateTime]::Now, $Msg) }
function Get-Control { try { ([IO.File]::ReadAllText($Control)).Trim() } catch { 'run' } }

# ---------- 設定 ----------
$Settings = [ordered]@{ KindIndex = 0; KindPrefix = '1:'; Reason = '值班'
                        DayStart = '1730'; DayEnd = '2400'; NextStart = '0000'; NextEnd = '0800' }
if ($SettingsB64) {
    try {
        $j = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($SettingsB64)) | ConvertFrom-Json
        foreach ($k in @($Settings.Keys)) { if ($null -ne $j.$k -and "$($j.$k)" -ne '') { $Settings[$k] = $j.$k } }
    } catch {}
}
function Hm([string]$T) { $T.Substring(0, 2) + ':' + $T.Substring(2, 2) }

try {
    [IO.File]::WriteAllText($Control, 'run')
    Emit 'STATE' 'running'
    Connect-Ofcmb

    # ---------- 1. 讀班表 ----------
    Log '讀取排班表…'
    $s = Read-OfcSchedule
    $codes = @{}; foreach ($r in $s.Rows) { $codes[(Format-IsoDate $r.Date)] = $r.Code }
    $blank = @($s.Rows | Where-Object { -not $_.Code })
    if ($blank.Count) { Log ('⚠ 讀不到班別：' + (($blank | ForEach-Object { Format-Roc $_.Date }) -join '、')) }
    Log ("讀到 {0}/{1:D2} 共 {2} 天" -f $s.RocYear, $s.Month, $s.Rows.Count)
    $schedJson = ConvertTo-Json -Compress -InputObject @{ Year = $s.Year; Month = $s.Month
        Rows = @($s.Rows | ForEach-Object { @{ D = (Format-IsoDate $_.Date); C = $_.Code } }) }
    Emit 'SCHEDULE' $schedJson
    if ($Action -eq 'Schedule') { Emit 'STATE' 'done'; return }

    # ---------- 2. 找值班日 ----------
    $duty = @()
    for ($i = 0; $i -lt $s.Rows.Count; $i++) {
        $r = $s.Rows[$i]
        if ($i -eq $s.Rows.Count - 1) { if ($r.Code -eq '9076') { Log "⚠ $(Format-Roc $r.Date) 是月底，無法判斷隔天班別，請手動確認" }; continue }
        if (Test-OncallNight $r.Date $codes) { $duty += $r.Date }
    }
    $items = @()
    foreach ($d in $duty) { $items += [pscustomobject]@{ Date = $d; Start = $Settings.DayStart; End = $Settings.DayEnd; Round = 1 } }
    foreach ($d in $duty) { $items += [pscustomobject]@{ Date = $d.AddDays(1); Start = $Settings.NextStart; End = $Settings.NextEnd; Round = 2 } }
    $plan = @($items | ForEach-Object { @{ Date = (Format-Roc $_.Date); Time = ('{0}~{1}' -f (Hm $_.Start), (Hm $_.End)); Round = $_.Round } })
    Emit 'PLAN' (ConvertTo-Json -InputObject $plan -Compress)
    Log "值班 $($duty.Count) 天，要申請 $($items.Count) 筆"
    if ($Action -eq 'Preview' -or $items.Count -eq 0) { Emit 'STATE' 'done'; return }

    # ---------- 3. 填寫加班申請 ----------
    $form = $null; $c = $null
    function Initialize-Form {
        $script:form = Open-OfcMenu '加班申請'
        $script:c = Get-OtControls $form
        Invoke-OtBar $c '新增'; Start-Sleep -Milliseconds 800
        $m = Close-OfcDialogs; if ($m) { throw "按「新增」時出現：$m" }
        $script:c = Get-OtControls $form
        [OfcW32]::Combo($c.Kind.H, [int]$Settings.KindIndex); Start-Sleep -Milliseconds 800
        $m = Close-OfcDialogs; if ($m) { throw "選加班類別時出現：$m" }
        if ([OfcW32]::Text($c.Reason.H) -ne $Settings.Reason) { [OfcW32]::SetText($c.Reason.H, [string]$Settings.Reason); Start-Sleep -Milliseconds 300 }
    }
    function Set-RoundTime($It) { Set-OtTime $c.Start $It.Start; Set-OtTime $c.End $It.End; $script:curRound = $It.Round }

    Log '開啟加班申請…'
    Initialize-Form
    $curRound = 0; $ok = 0; $fail = 0
    for ($n = 0; $n -lt $items.Count; $n++) {
        $it = $items[$n]
        $label = '{0} {1}~{2}' -f (Format-Roc $it.Date), (Hm $it.Start), (Hm $it.End)

        # 暫停 / 停止：只在兩筆之間生效
        $ctl = Get-Control
        if ($ctl -eq 'pause') {
            Emit 'STATE' 'paused'; Log '已暫停，按「繼續」接著做'
            while (($ctl = Get-Control) -eq 'pause') { Start-Sleep -Milliseconds 300 }
            if ($ctl -ne 'stop') { Emit 'STATE' 'running'; Log '繼續'; Connect-Ofcmb; Initialize-Form; $curRound = 0 }   # 暫停期間可能動過畫面，整張表重填
        }
        if ($ctl -eq 'stop') { Log '已停止'; for ($k = $n; $k -lt $items.Count; $k++) { Emit 'ITEM' "$k`tskip`t未執行" }; Emit 'STATE' 'stopped'; return }

        Emit 'ITEM' "$n`trunning`t填寫中"
        Set-OfcFront
        if ($curRound -ne $it.Round) { Set-RoundTime $it }
        [void](Set-OtDate $c.Date $it.Date)
        Invoke-OfcClick $c.End.X $c.End.Y; Start-Sleep -Milliseconds 200; Send-OfcKeys '{TAB}'; Start-Sleep -Milliseconds 500   # 讓程式重算時數
        $f = Read-OtFields $c
        $good = $f.日期 -eq (Format-Roc $it.Date) -and $f.起 -eq (Hm $it.Start) -and $f.迄 -eq (Hm $it.End) -and
                $f.類別.StartsWith([string]$Settings.KindPrefix) -and $f.理由 -eq $Settings.Reason -and (-not $c.Hours -or ($f.時數 -and $f.時數 -ne '0'))
        if (-not $good) {
            $txt = ($f.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
            Log "✗ $label 欄位不符，未送出（$txt）"; Emit 'ITEM' "$n`tfail`t欄位不符，未送出"; $fail++
            $curRound = 0; continue
        }
        if ($NoSave) { Log "$label 已填好（測試模式，未存檔）"; Emit 'ITEM' "$n`ttest`t已填好，未存檔"; Emit 'STATE' 'done'; return }

        Invoke-OtBar $c '存檔'; Start-Sleep -Milliseconds 1500
        $msg = Close-OfcDialogs
        if ($msg -and $msg -notmatch '成功|完成') {
            Log "✗ $label 未送出：$msg"; Emit 'ITEM' "$n`tfail`t$msg"; $fail++
            if ($msg -match '尚未核准') {
                Log '班表尚未核准，停止。請等主管核班後再執行。'
                for ($k = $n + 1; $k -lt $items.Count; $k++) { Emit 'ITEM' "$k`tskip`t未執行" }
                Emit 'STATE' 'stopped'; return
            }
            continue
        }
        $ok++
        Log "✓ $label 已送出"; Emit 'ITEM' "$n`tok`t已送出$(if ($msg) { "（$msg）" })"
    }
    Log "完成：送出 $ok 筆，失敗 $fail 筆。請到「已申請資料」核對。"
    Emit 'STATE' 'done'
} catch {
    Log "✗ 錯誤：$($_.Exception.Message)"
    Emit 'STATE' 'error'
}
