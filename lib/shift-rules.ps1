#Requires -Version 5.1
# 班別代碼與規則（與 tungwifi 的 shift-lib.ps1 / punch-lib.ps1 同一套）
# 班表只放在記憶體 @{ 'yyyy-MM-dd' = '代碼' }，不寫進程式資料夾（多人共用這台電腦）

$ShiftCodeInfo = [ordered]@{
    '9076' = '全天班 07:30–17:30'
    '908'  = '值班隔天，中午下班 08:00–11:30'
    '906'  = '值班隔天，早上下班'
    '100'  = '休假，不用打卡'
    '102'  = '休假，不用打卡'
}

function Get-ShiftText([string]$Code) {
    if (-not $Code) { return '（讀不到）' }
    if ($ShiftCodeInfo.Contains($Code)) { return $ShiftCodeInfo[$Code] }
    '未知代碼'
}

# 當天要不要值班：當天是全天班 9076，而且隔天是 906／908
function Test-OncallNight {
    param([Parameter(Mandatory)][datetime]$Date, [Parameter(Mandatory)][hashtable]$Codes)
    ($Codes[$Date.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)] -eq '9076') -and
    ($Codes[$Date.AddDays(1).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)] -in '906', '908')
}

# 民國日期（系統地區設定可能用民國曆，一律自己用數字格式化）
function Format-Roc([datetime]$Dt) { '{0}/{1:D2}/{2:D2}' -f ($Dt.Year - 1911), $Dt.Month, $Dt.Day }
function Format-IsoDate([datetime]$Dt) { '{0:D4}-{1:D2}-{2:D2}' -f $Dt.Year, $Dt.Month, $Dt.Day }
function Get-WeekdayText([datetime]$Dt) { '日一二三四五六'[[int]$Dt.DayOfWeek] }
