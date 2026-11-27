# ── 關於與更新：版本、從 GitHub 更新、還原上一版、每天自動更新（做法比照 tungwifi） ──
$script:pgAbout = New-Page '關於與更新' $Icon.Info { Update-AboutPage }
$script:AboutNavIdx = $Pages.Count - 1
$script:UpdateScript = Join-Path $Dir 'update.ps1'
$script:Repo = 'Mux1r/tung-helper'; $script:Branch = 'main'
$script:UpdDir = Join-Path $Dir 'update'
$script:VersionFile = Join-Path $UpdDir 'version.txt'
$script:UpdTask = 'tung-helper-AutoUpdate'

$cardVer = New-Card $pgAbout 24 72 690 150
Add-CardHead $cardVer $Icon.Info '目前版本'
$script:lblCurVer = New-Lbl $cardVer '' 52 38 620 40 $F_Body $C_INK2
$lblCurVer.AutoEllipsis = $true
$script:tipVer = New-Object System.Windows.Forms.ToolTip
$script:btnChkUpd = New-Btn $cardVer '檢查更新'   52  98 124 32 $Icon.Search
$script:btnApply  = New-Btn $cardVer '立即更新'   184 98 124 32 $Icon.Download -Accent
$script:btnRollbk = New-Btn $cardVer '還原上一版' 316 98 132 32 $Icon.Undo
$script:lblUpdMsg = New-Lbl $cardVer '' 460 106 214 20 $F_Cap $C_MUTE
$btnApply.Enabled = $false

$cardAuto = New-Card $pgAbout 24 234 690 64
$null = New-Lbl $cardAuto $Icon.Sync 18 20 24 24 $F_IconL $C_INK
$null = New-Lbl $cardAuto '每天自動更新' 52 11 300 22 $F_H $C_INK
$script:lblAuto = New-Lbl $cardAuto '每天 09:00 檢查 GitHub，有新版就自動裝（電腦沒開會在開機後補做）' 52 33 480 22 $F_Cap $C_INK2
$script:swAuto = New-Toggle $cardAuto 560 16 $false
$swAuto.Width = 110

$cardNew = New-Card $pgAbout 24 310 690 190
Add-CardHead $cardNew '' 'GitHub 上的新版內容'
$btnGitHub = New-Btn $cardNew 'GitHub' 566 12 110 32 $Icon.Globe
$btnGitHub.Add_Click({ Start-Process "https://github.com/$Repo" })
$script:rtbNew = New-Rtb $cardNew 18 50 658 128
$rtbNew.Text = '按「檢查更新」看看有沒有新版。'

$cardUpdLog = New-Card $pgAbout 24 512 690 168
Add-CardHead $cardUpdLog '' '更新紀錄'
$btnAboutOpen = New-Btn $cardUpdLog '開啟程式資料夾' 534 10 140 30 $Icon.Folder
$btnAboutOpen.Add_Click({ Start-Process explorer.exe $Dir })
$script:rtbUpdLog = New-Rtb $cardUpdLog 18 50 658 106

function Get-VersionLine {
    $v = @(Get-Content $VersionFile -Encoding UTF8 -ErrorAction SilentlyContinue)
    if (-not $v) { return @{ Sha = ''; Label = "v$AppVersion（還沒透過更新功能裝過，按「檢查更新」）" } }
    $sha = "$($v[0])".Trim(); $short = $sha.Substring(0, [Math]::Min(7, $sha.Length))
    $label = if ($v.Count -ge 2 -and $v[1]) { "$($v[1])（$short）" } else { $short }
    @{ Sha = $sha; Label = $label }
}
function Test-AutoUpdate { [bool](Get-ScheduledTask -TaskName $UpdTask -ErrorAction SilentlyContinue) }
function Update-AboutPage {
    $ver = Get-VersionLine
    $lblCurVer.Text = $ver.Label
    $tipVer.SetToolTip($lblCurVer, $ver.Label)
    $lblVer.Text = if ($ver.Sha) { "版本 $($ver.Sha.Substring(0, 7))" } else { "v$AppVersion" }
    $btnRollbk.Enabled = (Test-Path (Join-Path $UpdDir 'backup')) -and (Test-Path (Join-Path $UpdDir 'backup-version.txt'))
    $swAuto.Checked = Test-AutoUpdate
    $log = Join-Path $UpdDir 'update.log'
    $rtbUpdLog.Text = if (Test-Path $log) { (Get-Content $log -Encoding UTF8 -Tail 30) -join "`r`n" } else { '還沒有更新紀錄。' }
    $rtbUpdLog.SelectionStart = $rtbUpdLog.TextLength; $rtbUpdLog.ScrollToCaret()
}

# 查 GitHub：最新 commit，以及本機版本之後的每一筆改動
$script:CheckBlock = {
    param($Repo, $Branch, $Local)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $c = Invoke-RestMethod "https://api.github.com/repos/$Repo/commits/$Branch" -TimeoutSec 15
        $list = @()
        if ($Local -and $Local -ne $c.sha) {
            try {
                $cmp = Invoke-RestMethod "https://api.github.com/repos/$Repo/compare/$Local...$($c.sha)" -TimeoutSec 15
                $list = @($cmp.commits | ForEach-Object { "• $("$($_.commit.author.date)".Substring(0, 10))　$(($_.commit.message -split "`n")[0])" })
            } catch {}
        }
        if (-not $list) { $list = @("• $("$($c.commit.author.date)".Substring(0, 10))　$(($c.commit.message -split "`n")[0])") }
        [pscustomobject]@{ Ok = $true; Sha = $c.sha; List = $list }
    } catch { [pscustomobject]@{ Ok = $false; Err = $_.Exception.Message } }
}
function Show-CheckResult($R, [string]$Local) {
    if (-not $R -or -not $R.Ok) {
        $lblUpdMsg.Text = '✕ 連不上 GitHub'; $lblUpdMsg.ForeColor = $C_CRIT
        $rtbNew.Text = "檢查失敗：$(if ($R) { $R.Err } else { '逾時' })"
        $btnApply.Enabled = $false
    } elseif ($R.Sha -eq $Local) {
        $lblUpdMsg.Text = '✓ 已經是最新版'; $lblUpdMsg.ForeColor = $C_GOOD
        $rtbNew.Text = '目前就是 GitHub 上的最新版。'
        $btnApply.Enabled = $false
    } else {
        $lblUpdMsg.Text = '有新版'; $lblUpdMsg.ForeColor = $C_WARN
        $rtbNew.Text = "按「立即更新」會裝這些改動：`r`n`r`n" + ($R.List -join "`r`n")
        $btnApply.Enabled = $true
        $Pages[$AboutNavIdx].Nav.Text = '關於與更新 •'
    }
}

$btnChkUpd.Add_Click({
    $btnChkUpd.Enabled = $false; $lblUpdMsg.Text = '檢查中...'; $lblUpdMsg.ForeColor = $C_MUTE
    $local = (Get-VersionLine).Sha
    $r = Wait-JobUI (Start-Job -ArgumentList $Repo, $Branch, $local -ScriptBlock $CheckBlock) 40
    Show-CheckResult $r $local
    $btnChkUpd.Enabled = $true
})

# 更新／退版後版本真的換了，就開一份新的住醫小幫手再關掉自己，新介面馬上生效
function Restart-IfChanged([string]$OldSha) {
    if ((Get-VersionLine).Sha -eq $OldSha) { return $false }
    if (Test-TaskRunning) { $lblUpdMsg.Text = '完成，重開程式後生效'; $lblUpdMsg.ForeColor = $C_GOOD; return $true }
    $lnk = @((Join-Path $Dir '住醫小幫手.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) '住醫小幫手.lnk')) |
           Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    try {
        if ($lnk) { Start-Process -FilePath $lnk -ErrorAction Stop }
        else {
            Start-Process "$env:SystemRoot\System32\conhost.exe" -ErrorAction Stop `
                -ArgumentList "--headless powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File `"$(Join-Path $Dir '住醫小幫手.ps1')`""
        }
    } catch {   # 開不起來就不關自己，免得什麼都不見
        $lblUpdMsg.Text = '完成，重開程式才會看到新版'; $lblUpdMsg.ForeColor = $C_GOOD; $btnChkUpd.Enabled = $true
        return $true
    }
    $form.Close()
    $true
}

$btnApply.Add_Click({
    if (Test-TaskRunning) { [System.Windows.Forms.MessageBox]::Show("「$($Task.Name)」還在執行，請等它結束再更新。", '住醫小幫手') | Out-Null; return }
    $btnApply.Enabled = $false; $btnChkUpd.Enabled = $false; $btnRollbk.Enabled = $false
    $lblUpdMsg.Text = '更新中...'; $lblUpdMsg.ForeColor = $C_MUTE
    $old = (Get-VersionLine).Sha
    $done = Invoke-ScriptUI $UpdateScript '-Apply' 300
    if (Restart-IfChanged $old) { return }
    Update-AboutPage
    $lblUpdMsg.Text = if ($done) { '跑完了但版本沒變，看下面的更新紀錄' } else { '還在跑，稍後看更新紀錄' }
    $lblUpdMsg.ForeColor = if ($done) { $C_WARN } else { $C_WARN }
    $btnChkUpd.Enabled = $true
})

$btnRollbk.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show('確定要還原至上一版本？已還原的版本不會再自動安裝。', '還原上一版', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $btnRollbk.Enabled = $false; $btnApply.Enabled = $false
    $lblUpdMsg.Text = '還原中...'; $lblUpdMsg.ForeColor = $C_MUTE
    $old = (Get-VersionLine).Sha
    $done = Invoke-ScriptUI $UpdateScript '-Rollback' 300
    if (Restart-IfChanged $old) { return }
    Update-AboutPage
    $lblUpdMsg.Text = if ($done) { '跑完了但版本沒變，看下面的更新紀錄' } else { '還在跑，稍後看更新紀錄' }
    $lblUpdMsg.ForeColor = $C_WARN
})

# 每天自動更新：開關的狀態就是排程在不在（不另外存設定）
$swAuto.Add_Click({
    $want = $swAuto.Checked
    [void](Invoke-ScriptUI $UpdateScript $(if ($want) { '-Install' } else { '-Uninstall' }) 30)
    $swAuto.Checked = Test-AutoUpdate
    if ($want -and -not $swAuto.Checked) { $lblAuto.Text = '排程建立失敗（可能沒有權限）'; $lblAuto.ForeColor = $C_CRIT }
})

# 開啟時在背景查一次，有新版就在選單上加個點
$script:StartupCheck = Start-Job -ArgumentList $Repo, $Branch, (Get-VersionLine).Sha -ScriptBlock $CheckBlock
$script:StartupTimer = New-Object System.Windows.Forms.Timer
$StartupTimer.Interval = 1000
$StartupTimer.Add_Tick({
    if ($StartupCheck.State -eq 'Running') { return }
    $StartupTimer.Stop()
    $r = Receive-Job $StartupCheck -ErrorAction SilentlyContinue; Remove-Job $StartupCheck -Force -ErrorAction SilentlyContinue
    if ($r -and $r.Ok -and $r.Sha -ne (Get-VersionLine).Sha) { Show-CheckResult $r (Get-VersionLine).Sha }
})
$StartupTimer.Start()
Update-AboutPage
