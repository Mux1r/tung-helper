#Requires -Version 5.1
# Fluent 外觀（Windows 11 設定那種）：圓角卡片、強調色按鈕、滑動開關、左側選單，跟著系統深淺色
# 元件與色票比照 tungwifi 的 wifi-dashboard.ps1

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not ('Fluent.Theme' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Fluent
{
    public static class Theme
    {
        public static bool Dark = true;
        public static Color Window, Stack, Card, Stroke, Text, Text2, Text3, Accent, AccentHover, AccentPressed, AccentText,
            Control, ControlHover, ControlPressed, ControlStroke, Field, NavHover, NavSel, Disabled;
        public static Font Body, Icon;

        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = rad * 2;
            if (d <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);
        public static void StyleWindow(Form f)
        {
            try { int v = Dark ? 1 : 0; DwmSetWindowAttribute(f.Handle, 20, ref v, 4); } catch { }
            try { int m = 2; DwmSetWindowAttribute(f.Handle, 38, ref m, 4); } catch { }   // Windows 11：Mica 背景
        }
        public static void DarkScroll(Control c) { try { if (Dark) SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { } }
        public static void DarkCombo(Control c) { try { if (Dark) SetWindowTheme(c.Handle, "DarkMode_CFD", null); } catch { } }
        public static void DrawLogo(Graphics g, RectangleF r, Color c, float stroke)
        {
            float s = r.Width / 24f; float x = r.X, y = r.Y;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen p = new Pen(c, stroke * s))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                using (GraphicsPath f = new GraphicsPath())
                {
                    f.AddLine(x + 21 * s, y + 7.5f * s, x + 21 * s, y + 6 * s);
                    f.AddArc(x + 17 * s, y + 4 * s, 4 * s, 4 * s, 0, -90);
                    f.AddLine(x + 19 * s, y + 4 * s, x + 5 * s, y + 4 * s);
                    f.AddArc(x + 3 * s, y + 4 * s, 4 * s, 4 * s, 270, -90);
                    f.AddLine(x + 3 * s, y + 6 * s, x + 3 * s, y + 20 * s);
                    f.AddArc(x + 3 * s, y + 18 * s, 4 * s, 4 * s, 180, -90);
                    f.AddLine(x + 5 * s, y + 22 * s, x + 8.5f * s, y + 22 * s);
                    g.DrawPath(p, f);
                }
                g.DrawLine(p, x + 16 * s, y + 2 * s, x + 16 * s, y + 6 * s);
                g.DrawLine(p, x + 8 * s, y + 2 * s, x + 8 * s, y + 6 * s);
                g.DrawLine(p, x + 3 * s, y + 10 * s, x + 8 * s, y + 10 * s);
                g.DrawEllipse(p, x + 10 * s, y + 10 * s, 12 * s, 12 * s);
                g.DrawLines(p, new PointF[] { new PointF(x + 17.5f * s, y + 17.5f * s), new PointF(x + 16 * s, y + 16.3f * s), new PointF(x + 16 * s, y + 14 * s) });
            }
        }
        public static void Buffer(Control c)
        {
            typeof(Control).GetProperty("DoubleBuffered", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).SetValue(c, true, null);
        }
    }

    public abstract class Drawn : Control
    {
        protected bool hover, down;
        protected Drawn()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent; Cursor = Cursors.Hand; Font = Theme.Body;
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
    }

    public class Card : Panel
    {
        public int Radius = 6; public Color Fill = Color.Empty; public bool Border = true;
        public Card()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath p = Theme.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius))
            using (SolidBrush b = new SolidBrush(Fill.IsEmpty ? Theme.Card : Fill))
            {
                g.FillPath(b, p);
                if (Border) using (Pen pen = new Pen(Theme.Stroke)) g.DrawPath(pen, p);
            }
            base.OnPaint(e);
        }
    }

    public class FButton : Drawn
    {
        public bool Accent;
        string glyph = "";
        public string Glyph { get { return glyph; } set { glyph = value ?? ""; Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            Color bg, fg, st;
            if (Accent)
            {
                bg = !Enabled ? Theme.Disabled : down ? Theme.AccentPressed : hover ? Theme.AccentHover : Theme.Accent;
                fg = Enabled ? Theme.AccentText : Theme.Text3; st = bg;
            }
            else
            {
                bg = !Enabled ? Theme.Control : down ? Theme.ControlPressed : hover ? Theme.ControlHover : Theme.Control;
                fg = Enabled ? Theme.Text : Theme.Text3; st = Theme.ControlStroke;
            }
            using (GraphicsPath p = Theme.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 4))
            using (SolidBrush b = new SolidBrush(bg))
            using (Pen pen = new Pen(st)) { g.FillPath(b, p); g.DrawPath(pen, p); }
            TextFormatFlags f = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
            Size ts = TextRenderer.MeasureText(g, Text, Font, Size.Empty, f);
            Size gs = glyph.Length > 0 ? TextRenderer.MeasureText(g, glyph, Theme.Icon, Size.Empty, f) : Size.Empty;
            int gap = (gs.Width > 0 && Text.Length > 0) ? 8 : 0;
            int x = (Width - ts.Width - gs.Width - gap) / 2;
            if (glyph.Length > 0) TextRenderer.DrawText(g, glyph, Theme.Icon, new Point(x, (Height - gs.Height) / 2 + 1), fg, f);
            TextRenderer.DrawText(g, Text, Font, new Point(x + gs.Width + gap, (Height - ts.Height) / 2), fg, f);
        }
    }

    public class Toggle : Drawn
    {
        bool on;
        public string OnText = "開啟", OffText = "關閉";
        public bool Checked { get { return on; } set { on = value; Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            float h = 20, w = 40;
            RectangleF r = new RectangleF(0.5f, (Height - h) / 2f, w, h);
            using (GraphicsPath p = Theme.Round(r, h / 2f))
            {
                if (on) using (SolidBrush b = new SolidBrush(!Enabled ? Theme.Disabled : hover ? Theme.AccentHover : Theme.Accent)) g.FillPath(b, p);
                else
                {
                    using (SolidBrush b = new SolidBrush(hover ? Theme.ControlHover : Theme.Control)) g.FillPath(b, p);
                    using (Pen pen = new Pen(Enabled ? Theme.Text2 : Theme.Text3)) g.DrawPath(pen, p);
                }
            }
            float d = (hover && Enabled) ? 14 : 12;
            float cx = on ? r.Right - 10 : r.X + 10, cy = r.Y + h / 2f;
            using (SolidBrush b = new SolidBrush(on ? Theme.AccentText : (Enabled ? Theme.Text2 : Theme.Text3)))
                g.FillEllipse(b, cx - d / 2f, cy - d / 2f, d, d);
            string t = on ? OnText : OffText;
            Size ts = TextRenderer.MeasureText(g, t, Font);
            TextRenderer.DrawText(g, t, Font, new Point((int)w + 10, (Height - ts.Height) / 2), Enabled ? Theme.Text : Theme.Text3);
        }
        protected override void OnClick(EventArgs e) { if (Enabled) { on = !on; Invalidate(); } base.OnClick(e); }
    }

    public class Logo : Control
    {
        public Logo()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }
        protected override void OnPaint(PaintEventArgs e) { Theme.DrawLogo(e.Graphics, new RectangleF(0, 0, Width, Height), Theme.Accent, 2); }
    }

    public class NavItem : Drawn
    {
        public string Glyph = "";
        bool sel;
        public bool Selected { get { return sel; } set { sel = value; Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            if (sel || hover)
                using (GraphicsPath p = Theme.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 4))
                using (SolidBrush b = new SolidBrush(sel ? Theme.NavSel : Theme.NavHover)) g.FillPath(b, p);
            if (sel)
                using (GraphicsPath p = Theme.Round(new RectangleF(1, (Height - 16) / 2f, 3, 16), 1.5f))
                using (SolidBrush b = new SolidBrush(Theme.Accent)) g.FillPath(b, p);
            Size gs = TextRenderer.MeasureText(g, Glyph, Theme.Icon);
            TextRenderer.DrawText(g, Glyph, Theme.Icon, new Point(14, (Height - gs.Height) / 2 + 1), Theme.Text);
            Size ts = TextRenderer.MeasureText(g, Text, Font);
            TextRenderer.DrawText(g, Text, Font, new Point(46, (Height - ts.Height) / 2), Theme.Text);
        }
    }
}
'@
}

# ── 色票：跟著系統深淺色；強調色取 Windows 個人化設定 ──
function C([string]$Hex) { [System.Drawing.ColorTranslator]::FromHtml($Hex) }
function Mix($A, $B, [double]$T) {
    [System.Drawing.Color]::FromArgb([int]($A.R + ($B.R - $A.R) * $T), [int]($A.G + ($B.G - $A.G) * $T), [int]($A.B + ($B.B - $A.B) * $T))
}
$script:IsDark = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme -ne 1
$T = [Fluent.Theme]
$T::Dark = $IsDark
$palette = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -ErrorAction SilentlyContinue).AccentPalette
$ai = if ($IsDark) { 1 } else { 4 }
$accent = if ($palette -and $palette.Length -ge 32) { [System.Drawing.Color]::FromArgb($palette[$ai * 4], $palette[$ai * 4 + 1], $palette[$ai * 4 + 2]) }
          elseif ($IsDark) { C '#60CDFF' } else { C '#005FB8' }
if ($IsDark) {
    $T::Window = C '#202020'; $T::Stack = C '#272727'; $T::Card = C '#2D2D2D'; $T::Stroke = C '#1C1C1C'
    $T::Text = C '#FFFFFF'; $T::Text2 = C '#C5C5C5'; $T::Text3 = C '#8B8B8B'
    $T::Control = C '#363636'; $T::ControlHover = C '#3B3B3B'; $T::ControlPressed = C '#303030'; $T::ControlStroke = C '#424242'
    $T::Field = C '#383838'; $T::NavHover = C '#2A2A2A'; $T::NavSel = C '#2D2D2D'; $T::Disabled = C '#434343'
    $T::AccentText = C '#000000'
    $script:C_GOOD = C '#6CCB5F'; $script:C_WARN = C '#FCE100'; $script:C_CRIT = C '#FF99A4'
} else {
    $T::Window = C '#F3F3F3'; $T::Stack = C '#F9F9F9'; $T::Card = C '#FFFFFF'; $T::Stroke = C '#E5E5E5'
    $T::Text = C '#1B1B1B'; $T::Text2 = C '#5D5D5D'; $T::Text3 = C '#8A8A8A'
    $T::Control = C '#FBFBFB'; $T::ControlHover = C '#F6F6F6'; $T::ControlPressed = C '#F0F0F0'; $T::ControlStroke = C '#E0E0E0'
    $T::Field = C '#FFFFFF'; $T::NavHover = C '#EDEDED'; $T::NavSel = C '#EAEAEA'; $T::Disabled = C '#C5C5C5'
    $T::AccentText = C '#FFFFFF'
    $script:C_GOOD = C '#0F7B0F'; $script:C_WARN = C '#9D5D00'; $script:C_CRIT = C '#C42B1C'
}
$T::AccentHover = Mix $accent $T::Window 0.1; $T::AccentPressed = Mix $accent $T::Window 0.2
$T::Accent = $accent
$script:C_INK = $T::Text; $script:C_INK2 = $T::Text2; $script:C_MUTE = $T::Text3; $script:C_ACC = $accent; $script:C_CARD = $T::Card

# 字型：微軟正黑體 UI（中文清楚、英數字照 Segoe 設計）；圖示用 Segoe Fluent Icons
$fontNames = (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name
$iconFont = if ($fontNames -contains 'Segoe Fluent Icons') { 'Segoe Fluent Icons' } else { 'Segoe MDL2 Assets' }
$ui = if ($fontNames -contains 'Microsoft JhengHei UI') { 'Microsoft JhengHei UI' } else { 'Segoe UI' }
$Bold = [System.Drawing.FontStyle]::Bold
$script:F_Title = New-Object System.Drawing.Font($ui, 20, $Bold)
$script:F_H     = New-Object System.Drawing.Font($ui, 10, $Bold)
$script:F_Body  = New-Object System.Drawing.Font($ui, 10)
$script:F_Cap   = New-Object System.Drawing.Font($ui, 9)
$script:F_Val   = New-Object System.Drawing.Font($ui, 11, $Bold)
$script:F_Mono  = New-Object System.Drawing.Font($ui, 9.5)
$script:F_Icon  = New-Object System.Drawing.Font($iconFont, 12)
$script:F_IconL = New-Object System.Drawing.Font($iconFont, 16)
$T::Body = $F_Body; $T::Icon = $F_Icon

function G([int]$Code) { [string][char]$Code }
$script:Icon = @{
    Home = G 0xE80F; History = G 0xE81C; Setting = G 0xE713; Info = G 0xE946; Calendar = G 0xE787; Clock = G 0xE823
    Play = G 0xE768; Pause = G 0xE769; Stop = G 0xE71A; Search = G 0xE721; Refresh = G 0xE72C; Download = G 0xE896
    Folder = G 0xE838; Save = G 0xE74E; Clear = G 0xE894; List = G 0xEA37; Eye = G 0xE7B3; Work = G 0xE821; Moon = G 0xE708
}

# ── UI 輔助 ──
function Set-Box($Ctl, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $Ctl.Location = New-Object System.Drawing.Point($X, $Y); $Ctl.Size = New-Object System.Drawing.Size($W, $H)
}
function New-Card([System.Windows.Forms.Control]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $p = New-Object Fluent.Card; Set-Box $p $X $Y $W $H; $Parent.Controls.Add($p); $p
}
function New-Lbl([System.Windows.Forms.Control]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H,
                 [System.Drawing.Font]$Font = $F_Body, [System.Drawing.Color]$Color = $C_INK) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; Set-Box $l $X $Y $W $H; $l.Font = $Font; $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $Parent.Controls.Add($l); $l
}
function New-Btn([System.Windows.Forms.Control]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H,
                 [string]$Glyph = '', [switch]$Accent) {
    $b = New-Object Fluent.FButton
    $b.Text = $Text; $b.Glyph = $Glyph; $b.Accent = [bool]$Accent
    Set-Box $b $X $Y $W $H; $Parent.Controls.Add($b); $b
}
function Add-CardHead($Card, [string]$Glyph, [string]$Title, [int]$Width = 400) {
    if ($Glyph) {
        $null = New-Lbl $Card $Glyph 18 14 24 24 $F_IconL $C_INK
        $null = New-Lbl $Card $Title 52 14 $Width 22 $F_H $C_INK
    } else { $null = New-Lbl $Card $Title 18 14 $Width 22 $F_H $C_INK }
}
function New-Tile([System.Windows.Forms.Control]$Parent, [string]$Caption, [string]$Glyph, [int]$X, [int]$Y = 72) {
    $card = New-Card $Parent $X $Y 162 84
    $null = New-Lbl $card $Glyph 14 14 22 22 $F_Icon $C_ACC
    $null = New-Lbl $card $Caption 40 15 116 18 $F_Cap $C_INK2
    New-Lbl $card '—' 14 44 144 26 $F_Val $C_MUTE
}
function Set-Tile([System.Windows.Forms.Label]$Lbl, [string]$Text, [System.Drawing.Color]$Color = $C_INK) { $Lbl.Text = $Text; $Lbl.ForeColor = $Color }
function New-Rtb([System.Windows.Forms.Control]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $r = New-Object System.Windows.Forms.RichTextBox
    Set-Box $r $X $Y $W $H
    $r.ReadOnly = $true; $r.BackColor = $C_CARD; $r.ForeColor = $C_INK2; $r.Font = $F_Mono
    $r.BorderStyle = 'None'; $r.ScrollBars = 'Vertical'
    $Parent.Controls.Add($r); [Fluent.Theme]::DarkScroll($r); $r
}
function New-Field([System.Windows.Forms.Control]$Parent, [int]$X, [int]$Y, [int]$W, [string]$Value) {
    $box = New-Card $Parent $X $Y $W 32
    $box.Radius = 4; $box.Fill = [Fluent.Theme]::Field
    $t = New-Object System.Windows.Forms.TextBox
    Set-Box $t 10 7 ($W - 20) 20
    $t.BorderStyle = 'None'; $t.BackColor = [Fluent.Theme]::Field; $t.ForeColor = $C_INK; $t.Font = $F_Body; $t.Text = $Value
    $box.Controls.Add($t); $t
}
function New-Combo([System.Windows.Forms.Control]$Parent, [int]$X, [int]$Y, [int]$W, [string[]]$Items, [int]$Index = 0) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    if ($IsDark) { $c.BackColor = [Fluent.Theme]::Field; $c.ForeColor = $C_INK }
    $c.Font = $F_Body; $c.MaxDropDownItems = 12
    Set-Box $c $X $Y $W 30
    $Parent.Controls.Add($c); [Fluent.Theme]::DarkCombo($c)
    $c.Items.AddRange($Items)
    if ($Index -ge 0 -and $Index -lt $Items.Count) { $c.SelectedIndex = $Index }
    $c
}
function New-Toggle([System.Windows.Forms.Control]$Parent, [int]$X, [int]$Y, [bool]$On, [string]$OnText = '開啟', [string]$OffText = '關閉') {
    $sw = New-Object Fluent.Toggle
    $sw.OnText = $OnText; $sw.OffText = $OffText; $sw.Checked = $On
    Set-Box $sw $X $Y 160 32; $Parent.Controls.Add($sw); $sw
}
# 清單：整張自己畫（系統畫法是白底藍色選取，跟介面不搭）。$Columns = @(@('標題', 寬度), ...)
function New-List([System.Windows.Forms.Control]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H, [object[]]$Columns) {
    $lv = New-Object System.Windows.Forms.ListView
    Set-Box $lv $X $Y $W $H
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HeaderStyle = 'Nonclickable'
    $lv.BorderStyle = 'None'; $lv.BackColor = $C_CARD; $lv.ForeColor = $C_INK2; $lv.Font = $F_Body
    $lv.SmallImageList = New-Object System.Windows.Forms.ImageList
    $lv.SmallImageList.ImageSize = New-Object System.Drawing.Size(1, 28)
    foreach ($col in $Columns) { [void]$lv.Columns.Add($col[0], $col[1]) }
    $lv.OwnerDraw = $true
    $lv.Add_DrawColumnHeader({
        $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $C_CARD), $_.Bounds)
        $_.Graphics.DrawLine((New-Object System.Drawing.Pen ([Fluent.Theme]::Stroke)), $_.Bounds.Left, $_.Bounds.Bottom - 1, $_.Bounds.Right, $_.Bounds.Bottom - 1)
        $r = $_.Bounds; $r.X += 8
        [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, $_.Header.Text, $F_Cap, $r, $C_MUTE, [System.Windows.Forms.TextFormatFlags]'VerticalCenter, Left')
    })
    $lv.Add_DrawItem({ $_.DrawDefault = $false })
    $lv.Add_DrawSubItem({
        $bg = if ($_.Item.Selected) { [Fluent.Theme]::ControlHover } else { $C_CARD }
        $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $bg), $_.Bounds)
        if ($_.Item.Selected -and $_.ColumnIndex -eq 0) {
            $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $C_ACC), $_.Bounds.Left, $_.Bounds.Top + 7, 3, $_.Bounds.Height - 14)
        }
        $fg = $_.SubItem.ForeColor   # Add-ListRow 每格都設好顏色
        $r = $_.Bounds; $r.X += 8; $r.Width -= 8
        [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, $_.SubItem.Text, $F_Body, $r, $fg, [System.Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
    })
    [Fluent.Theme]::Buffer($lv)
    $Parent.Controls.Add($lv); [Fluent.Theme]::DarkScroll($lv); $lv
}
function Add-ListRow($Lv, [string[]]$Cells, [System.Drawing.Color]$Color = [System.Drawing.Color]::Empty, [int]$ColorCol = -1) {
    $it = New-Object System.Windows.Forms.ListViewItem($Cells[0])
    $it.UseItemStyleForSubItems = $false
    for ($i = 1; $i -lt $Cells.Count; $i++) { [void]$it.SubItems.Add($Cells[$i]) }
    for ($i = 0; $i -lt $Cells.Count; $i++) { $it.SubItems[$i].ForeColor = $(if ($i -eq 0) { $C_INK } else { $C_INK2 }) }
    if (-not $Color.IsEmpty -and $ColorCol -ge 0) { $it.SubItems[$ColorCol].ForeColor = $Color }
    [void]$Lv.Items.Add($it); $it
}
