#Requires -Version 5.1
# 從 GitHub 抓最新版覆蓋到這個資料夾（做法比照 tungwifi 的 update.ps1）。
# 只蓋程式檔：update\（版本、備份、紀錄）、.git\、捷徑不碰。新版裡只要有一支腳本語法錯誤就整批不更新。
#
# 用法：
#   update.ps1              檢查一次，有新版就裝（給每天的排程跑）
#   update.ps1 -Apply       立即更新到最新版（「關於與更新」頁的按鈕）
#   update.ps1 -Rollback    退回更新前的版本，並跳過這一版
#   update.ps1 -Install     註冊每天 09:00 自動更新的排程（電腦沒醒就醒來補跑）
#   update.ps1 -Uninstall   移除自動更新排程
param([switch]$Install, [switch]$Uninstall, [switch]$Apply, [switch]$Rollback)

$Repo     = 'Mux1r/tung-helper'
$Branch   = 'main'
$TaskName = 'tung-helper-AutoUpdate'
$Dir      = $PSScriptRoot

if ($Install) {
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" `
        -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -NonInteractive -File `"$PSCommandPath`""
    Register-ScheduledTask -TaskName $TaskName -Force -ErrorAction Stop `
        -Trigger (New-ScheduledTaskTrigger -Daily -At '09:00') `
        -Principal (New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited) `
        -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                        -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew) `
        -Action $action | Out-Null
    Write-Host "已註冊 $TaskName，每天 09:00 檢查 GitHub 有沒有新版。" -ForegroundColor Green
    return
}
if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "已移除 $TaskName。"
    return
}

# 版本、備份、紀錄放 update\（不是個人資料，也不進 GitHub）
$UpdDir      = Join-Path $Dir 'update'
New-Item -ItemType Directory -Force $UpdDir | Out-Null
$LogFile     = Join-Path $UpdDir 'update.log'
$VersionFile = Join-Path $UpdDir 'version.txt'        # 第一行 sha，第二行「日期 說明」給畫面顯示
$SkipFile    = Join-Path $UpdDir 'skip.txt'           # 退回過的版本，不再自動裝回來
$BackupDir   = Join-Path $UpdDir 'backup'             # 只留更新前那一版
$BackupVer   = Join-Path $UpdDir 'backup-version.txt'
function Log([string]$Msg) { try { Add-Content $LogFile "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg" -Encoding UTF8 } catch {}; Write-Host $Msg }

function Get-LocalSha { if (Test-Path $VersionFile) { "$(Get-Content $VersionFile -TotalCount 1)".Trim() } else { '' } }

# 程式檔清單：資料夾裡除了 update\、.git\、捷徑、紀錄以外的檔案
function Get-ProgramFiles([string]$Root) {
    Get-ChildItem $Root -Recurse -File -Force | Where-Object {
        $rel = $_.FullName.Substring($Root.Length + 1)
        $rel -notlike 'update\*' -and $rel -notlike '.git\*' -and $rel -notlike 'data\*' -and
        $_.Extension -notin '.log', '.lnk', '.csv'
    }
}
function Copy-Program([string]$From, [string]$To) {
    foreach ($f in (Get-ProgramFiles $From)) {
        $dest = Join-Path $To $f.FullName.Substring($From.Length + 1)
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item $f.FullName $dest -Force
    }
}

# 值班加班申請正在跑就別換檔：換到一半的腳本可能讓這筆申請出錯
function Test-TaskBusy {
    [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'tasks\\overtime\.ps1' })
}
function Wait-TaskIdle {
    for ($i = 0; $i -lt 20 -and (Test-TaskBusy); $i++) { Start-Sleep -Seconds 30 }   # 最多等 10 分鐘
    -not (Test-TaskBusy)
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ── 退回上一版 ─────────────────────────────────────────────
if ($Rollback) {
    $bakSha = if ((Test-Path $BackupVer) -and (Test-Path $BackupDir)) { "$(Get-Content $BackupVer -TotalCount 1)".Trim() } else { '' }
    if (-not $bakSha) { Log '無可還原的版本（尚未更新過，或已還原）'; return }
    if (-not (Wait-TaskIdle)) { Log '值班加班申請進行中，本次未還原'; return }
    $badSha = Get-LocalSha
    try {
        Copy-Program $BackupDir $Dir
        Copy-Item $BackupVer $VersionFile -Force
        Set-Content $SkipFile $badSha   # 自動更新別又把這版裝回來
        Remove-Item $BackupDir, $BackupVer -Recurse -Force   # 退過就沒有「上一版」了，避免連按兩次來回跳
        Log "退回到 $($bakSha.Substring(0, 7))，跳過 $($badSha.Substring(0, [Math]::Min(7, $badSha.Length)))"
    } catch { Log "退版失敗：$($_.Exception.Message)" }
    return
}

# ── 檢查／更新 ─────────────────────────────────────────────
$tmp = Join-Path $env:TEMP "tung-helper-update-$PID"
try {
    $commit = Invoke-RestMethod "https://api.github.com/repos/$Repo/commits/$Branch" -TimeoutSec 30
    $sha    = $commit.sha
    $local  = Get-LocalSha
    if ($sha -eq $local) { if ($Apply) { Log '目前已是最新版本' }; return }
    $skipped = (Test-Path $SkipFile) -and ("$(Get-Content $SkipFile -TotalCount 1)".Trim() -eq $sha)
    if ($skipped -and -not $Apply) { return }   # 退回過的版本，手動按「立即更新」才裝

    if (-not (Wait-TaskIdle)) { Log '值班加班申請進行中，這次不更新'; return }

    New-Item -ItemType Directory -Force $tmp | Out-Null
    Invoke-WebRequest "https://codeload.github.com/$Repo/zip/$sha" -OutFile "$tmp\src.zip" -UseBasicParsing -TimeoutSec 120
    Expand-Archive "$tmp\src.zip" "$tmp\src" -Force
    $src = (Get-ChildItem "$tmp\src" -Directory | Select-Object -First 1).FullName   # zip 裡多包一層 tung-helper-<sha>

    # 新版每支腳本都要能解析，有一支壞就整批不更新
    $broken = Get-ChildItem $src -Recurse -Filter *.ps1 | Where-Object {
        $err = $null
        [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err)
        $err
    }
    if ($broken) { throw "新版本語法錯誤（$($broken.Name -join ', ')）" }

    # 先備份目前這版，壞了可以「還原上一版」
    if ($local) {
        Remove-Item $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $BackupDir | Out-Null
        Copy-Program $Dir $BackupDir
        Copy-Item $VersionFile $BackupVer -Force
    }
    Copy-Program $src $Dir
    $msg = ($commit.commit.message -split "`n")[0]
    Set-Content $VersionFile @($sha, "$(Get-Date -Format 'yyyy-MM-dd') $msg") -Encoding UTF8
    Remove-Item $SkipFile -ErrorAction SilentlyContinue
    Log "更新到 $($sha.Substring(0, 7))：$msg"
    # 已經存在的捷徑換成新圖示（只改現有的）
    if (Test-Path "$Dir\app.ico") {
        try {
            $ws = New-Object -ComObject WScript.Shell
            foreach ($lnk in "$Dir\出勤小幫手.lnk", (Join-Path ([Environment]::GetFolderPath('Desktop')) '出勤小幫手.lnk')) {
                if (Test-Path $lnk) { $sc = $ws.CreateShortcut($lnk); $sc.IconLocation = "$Dir\app.ico,0"; $sc.Save() }
            }
        } catch {}
    }
} catch {
    Log "更新失敗：$($_.Exception.Message)"
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
