#Requires -Version 5.1
# 在程式資料夾（和桌面，可選）建立「住醫小幫手」捷徑，指向這個資料夾目前的位置。
# 資料夾搬家後重新執行一次即可。
#   powershell -ExecutionPolicy Bypass -File .\make-shortcut.ps1 [-Desktop]
param([switch]$Desktop)
$root = $PSScriptRoot
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$targets = @(Join-Path $root '住醫小幫手.lnk')
if ($Desktop) { $targets += Join-Path ([Environment]::GetFolderPath('Desktop')) '住醫小幫手.lnk' }
$ws = New-Object -ComObject WScript.Shell
foreach ($t in $targets) {
    $lnk = $ws.CreateShortcut($t)
    # conhost --headless：不開任何主控台視窗（Windows 11 的終端機會無視「隱藏視窗」）
    $lnk.TargetPath = "$env:SystemRoot\System32\conhost.exe"
    $lnk.Arguments = "--headless `"$ps`" -NoProfile -STA -ExecutionPolicy Bypass -File `"$root\住醫小幫手.ps1`""
    $lnk.WorkingDirectory = $root
    $lnk.IconLocation = Join-Path $root 'app.ico'
    $lnk.WindowStyle = 7
    $lnk.Save()
    Write-Host "已建立：$t"
}
