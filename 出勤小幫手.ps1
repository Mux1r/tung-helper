#Requires -Version 5.1
# 舊名稱相容：程式已改名「住醫小幫手」（住醫小幫手.ps1）。
# 舊的「出勤小幫手」捷徑會執行這支：把捷徑換成新名稱（資料夾裡的，以及桌面上原本有的），再開啟住醫小幫手。
$root = $PSScriptRoot
$desk = [Environment]::GetFolderPath('Desktop')
$oldInFolder = Join-Path $root '出勤小幫手.lnk'
$oldOnDesk   = Join-Path $desk '出勤小幫手.lnk'
try {
    if ((Test-Path $oldInFolder) -or (Test-Path $oldOnDesk)) {
        $mk = Join-Path $root 'make-shortcut.ps1'
        if (Test-Path $oldOnDesk) { & $mk -Desktop | Out-Null } else { & $mk | Out-Null }
        Remove-Item $oldInFolder, $oldOnDesk -Force -ErrorAction SilentlyContinue
    }
} catch {}
& (Join-Path $root '住醫小幫手.ps1')
