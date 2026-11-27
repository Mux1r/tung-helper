# ── 關於 ──
$script:pgAbout = New-Page '關於' $Icon.Info $null

$cardAbout = New-Card $pgAbout 24 72 690 150
Add-CardHead $cardAbout $Icon.Info "出勤小幫手 v$AppVersion"
$null = New-Lbl $cardAbout '操作「出勤系統」(OFCMB.EXE) 的工具集。讀取班表靠複製格子內容、表單用 Windows 訊息讀寫，不靠截圖、也不需要 AI。' 52 42 620 40 $F_Body $C_INK2
$null = New-Lbl $cardAbout "多人共用：班表和設定只在這次開啟期間存在，關閉後全部清除；班表只有按「匯出」時才存到自己的「下載」資料夾。" 52 84 470 40 $F_Cap $C_MUTE
$btnAboutOpen = New-Btn $cardAbout '開啟程式資料夾' 534 100 140 32 $Icon.Folder
$btnAboutOpen.Add_Click({ Start-Process explorer.exe $Dir })

$cardAdd = New-Card $pgAbout 24 234 690 160
Add-CardHead $cardAdd $Icon.List '新增功能'
$null = New-Lbl $cardAdd ("在 modules\ 放一個 .ps1（檔名開頭的數字決定在選單的順序），用 New-Page '名稱' 圖示 建立頁面。" +
    "需要操作出勤系統的工作寫在 tasks\，用 Start-Task 在背景執行，lib\ofcmb.ps1 有共用的操作函式。") 52 42 620 80 $F_Body $C_INK2
