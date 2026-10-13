# Heartnet Debloat - entry point.
#   UI (default):  powershell -ExecutionPolicy Bypass -File app\Main.ps1
#   Headless:      powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Cli [-Json out.json] [-Html out.html]
# This version only scans. It never changes the system.

param(
    [switch]$Cli,
    [string]$Json,
    [string]$Html,
    [ValidateSet('id', 'en')][string]$Lang = 'id',
    [string]$Category,      # open the UI on this category (handy for testing/screenshots)
    [switch]$ShowAll
)

$ErrorActionPreference = 'Stop'
$AppDir = $PSScriptRoot
. (Join-Path $AppDir 'core\Lang.ps1')
. (Join-Path $AppDir 'core\Scan.ps1')
. (Join-Path $AppDir 'core\Report.ps1')
Initialize-HDLang $Lang

# ------------------------------------------------------------------ headless mode
if ($Cli -or $Json -or $Html) {
    $scan = Invoke-HDScan -Progress { param($s) Write-Host ('  ' + (T 'ui.scan.step' (T "step.$s"))) }
    $visible = @($scan.Items | Where-Object { $_.State -ne 'NotPresent' })
    foreach ($c in 'warn', 'apps', 'ads', 'startup', 'oem', 'xbox', 'privacy', 'system', 'security') {
        $items = @($visible | Where-Object Category -eq $c)
        if (-not $items.Count) { continue }
        Write-Host ''
        Write-Host ('== ' + (T "cat.$c")) -ForegroundColor Magenta
        foreach ($i in $items) {
            $mark = if ($i.Checked) { '[x]' } elseif ($i.Selectable) { '[ ]' } else { '   ' }
            $state = if ($i.Kind -eq 'Action') { T "state.$($i.State)" } else { T "risk.$($i.Risk)" }
            Write-Host ('{0} {1,-52} {2,-11} {3}' -f $mark, $i.Title, (T "risk.$($i.Risk)"), $state)
            foreach ($w in $i.Warnings) { Write-Host "      ! $w" -ForegroundColor Yellow }
        }
    }
    if ($Json) { Export-HDReport -Scan $scan -Path $Json; Write-Host (T 'ui.saved' $Json) }
    if ($Html) { Export-HDReport -Scan $scan -Path $Html; Write-Host (T 'ui.saved' $Html) }
    return
}

# ------------------------------------------------------------------ UI
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Lang', $Lang) -WindowStyle Hidden
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

[xml]$xaml = Get-Content -LiteralPath (Join-Path $AppDir 'ui\MainWindow.xaml') -Raw -Encoding UTF8
$Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$UI = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1 -ExpandProperty Value
    $UI[$n] = $Window.FindName($n)
}

function New-HDBrush([string]$Hex) { New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Hex)) }
function New-HDImage([string]$Path) {
    $bmp = New-Object Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit(); $bmp.UriSource = New-Object Uri $Path; $bmp.CacheOption = 'OnLoad'; $bmp.EndInit(); $bmp.Freeze()
    return $bmp
}

$Colors = @{ Ink = '#2E1E1F'; Navy = '#3F5F80'; Wing = '#761D31'; Slate = '#708DAB'; SlateLight = '#DCE7F1'; Amber = '#E3A33B'; Muted = '#3B4650' }
$RiskStyle = @{
    Low          = @{ Bg = $Colors.Navy; Fg = '#FFFFFF' }
    Optional     = @{ Bg = $Colors.Amber; Fg = $Colors.Ink }
    Experimental = @{ Bg = $Colors.Wing;  Fg = '#FFFFFF' }
    Info         = @{ Bg = '#FFFFFF';     Fg = $Colors.Ink }
    Warning      = @{ Bg = $Colors.Amber; Fg = $Colors.Ink }
}
$Categories = 'warn', 'apps', 'ads', 'startup', 'oem', 'xbox', 'privacy', 'system', 'security', 'notdone'

$State = @{ Scan = $null; Selection = @{}; Category = $null; Job = $null }

$mascot = New-HDImage (Join-Path $AppDir 'assets\mascot.png')
$UI.HeaderMascot.Source = $mascot
$UI.ScanMascot.Source = $mascot
try { $Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri (Join-Path $AppDir 'assets\icon.ico'))) } catch {}
$UI.AppTitle.Text = T 'ui.appname'
$UI.Tagline.Text = T 'ui.tagline'
$UI.MvpLabel.Text = T 'ui.mvp'
$UI.ScanTitle.Text = T 'ui.scanning'
$UI.ScanSub.Text = T 'ui.scanning.sub'
$UI.ChkShowAll.Content = T 'ui.showall'
$UI.BtnSave.Content = T 'ui.save'
$UI.BtnRescan.Content = T 'ui.rescan'
$UI.BtnRun.Content = T 'ui.run'
$UI.BtnRun.ToolTip = T 'ui.run.soon'
$UI.BtnAdmin.Content = T 'ui.admin.rescan'
$UI.BtnAdmin.ToolTip = T 'ui.admin.why'
$UI.ChkShowAll.IsChecked = [bool]$ShowAll

# ------------------------------------------------------------------ rendering

function Test-HDVisible($Item) {
    if ($UI.ChkShowAll.IsChecked) { return $true }
    return -not ($Item.State -eq 'NotPresent' -or ($Item.Kind -eq 'Action' -and $Item.State -eq 'Done'))
}

function New-HDText([string]$Text, [double]$Size = 14, [string]$Color = $Colors.Ink, [string]$Weight = 'Normal') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = $Size; $t.Foreground = New-HDBrush $Color; $t.FontWeight = $Weight
    $t.TextWrapping = 'Wrap'
    return $t
}

function New-HDBadge([string]$Text, [string]$Bg, [string]$Fg) {
    $b = New-Object Windows.Controls.Border
    $b.Background = New-HDBrush $Bg; $b.BorderBrush = New-HDBrush $Colors.Ink; $b.BorderThickness = 1.5
    $b.CornerRadius = 9; $b.Padding = '9,1'; $b.Margin = '8,0,0,0'; $b.VerticalAlignment = 'Center'
    $b.Child = New-HDText $Text 11 $Fg 'SemiBold'
    return $b
}

function New-HDCard($Item) {
    $outer = New-Object Windows.Controls.Grid
    $outer.Margin = '0,0,0,14'
    $shadow = New-Object Windows.Controls.Border
    $shadow.Background = New-HDBrush $Colors.Ink; $shadow.CornerRadius = 12; $shadow.Margin = '4,4,0,0'
    $card = New-Object Windows.Controls.Border
    $bg = if ($Item.Kind -eq 'Warning') { '#FFF6E6' } elseif ($Item.State -in 'Done', 'NotPresent') { '#F7FAFA' } else { '#FFFFFF' }
    $card.Background = New-HDBrush $bg; $card.BorderBrush = New-HDBrush $Colors.Ink; $card.BorderThickness = 2
    $card.CornerRadius = 12; $card.Margin = '0,0,4,4'; $card.Padding = '14,10'
    [void]$outer.Children.Add($shadow); [void]$outer.Children.Add($card)

    $stack = New-Object Windows.Controls.StackPanel
    $card.Child = $stack

    # header: [checkbox] title .......... [risk] state
    $head = New-Object Windows.Controls.DockPanel
    $right = New-Object Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'; [Windows.Controls.DockPanel]::SetDock($right, 'Right')
    if ($Item.Kind -eq 'Action') {
        $stateColor = switch ($Item.State) { 'Applicable' { $Colors.Navy } 'Partial' { $Colors.Navy } 'Blocked' { $Colors.Wing } default { $Colors.Muted } }
        $st = New-HDText (T "state.$($Item.State)") 12 $stateColor 'SemiBold'
        $st.VerticalAlignment = 'Center'; $st.Margin = '10,0,0,0'
        [void]$right.Children.Add((New-HDBadge (T "risk.$($Item.Risk)") $RiskStyle[$Item.Risk].Bg $RiskStyle[$Item.Risk].Fg))
        [void]$right.Children.Add($st)
    } else {
        [void]$right.Children.Add((New-HDBadge (T "risk.$($Item.Risk)") $RiskStyle[$Item.Risk].Bg $RiskStyle[$Item.Risk].Fg))
    }
    [void]$head.Children.Add($right)

    $title = New-HDText $Item.Title 15 $Colors.Ink 'Bold'
    $title.VerticalAlignment = 'Center'
    if ($Item.Selectable) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Tag = $Item.Id; $cb.VerticalContentAlignment = 'Center'; $cb.Content = $title
        $cb.IsChecked = [bool]$State.Selection[$Item.Id]
        $cb.Add_Checked({ param($s, $e) $State.Selection[$s.Tag] = $true; Update-HDCount })
        $cb.Add_Unchecked({ param($s, $e) $State.Selection[$s.Tag] = $false; Update-HDCount })
        [void]$head.Children.Add($cb)
    } else {
        if ($Item.Kind -eq 'Warning') { $title.Foreground = New-HDBrush $Colors.Wing }
        [void]$head.Children.Add($title)
    }
    [void]$stack.Children.Add($head)

    $desc = New-HDText $Item.Desc 13.5 $Colors.Ink
    $desc.Margin = '0,6,0,0'
    [void]$stack.Children.Add($desc)

    $trade = New-Object Windows.Controls.TextBlock
    $trade.TextWrapping = 'Wrap'; $trade.Margin = '0,4,0,0'; $trade.FontSize = 13; $trade.Foreground = New-HDBrush $Colors.Muted
    $lead = New-Object Windows.Documents.Run ((T 'ui.tradeoff') + ': ')
    $lead.FontWeight = 'SemiBold'
    [void]$trade.Inlines.Add($lead); [void]$trade.Inlines.Add((New-Object Windows.Documents.Run $Item.Tradeoff))
    [void]$stack.Children.Add($trade)

    foreach ($w in $Item.Warnings) {
        $wt = New-HDText ("(!) " + $w) 13 $Colors.Wing 'SemiBold'
        $wt.Margin = '0,6,0,0'
        [void]$stack.Children.Add($wt)
    }
    foreach ($n in $Item.Notes) {
        $nt = New-HDText $n 12 $Colors.Muted
        $nt.FontStyle = 'Italic'; $nt.Margin = '0,4,0,0'
        [void]$stack.Children.Add($nt)
    }
    if ($Item.Details.Count) {
        $exp = New-Object Windows.Controls.Expander
        $exp.Header = T 'ui.details'; $exp.Margin = '0,6,0,0'; $exp.FontSize = 12; $exp.Foreground = New-HDBrush $Colors.Navy
        $dt = New-HDText (($Item.Details) -join "`n") 12 $Colors.Muted
        $dt.FontFamily = 'Consolas'; $dt.Margin = '18,4,0,0'
        $exp.Content = $dt
        [void]$stack.Children.Add($exp)
    }
    return $outer
}

function New-HDSummaryCard {
    $s = $State.Scan
    $actionable = @($s.Items | Where-Object { $_.Kind -eq 'Action' -and $_.State -in 'Applicable', 'Partial' }).Count
    $done = @($s.Items | Where-Object { $_.Kind -eq 'Action' -and $_.State -eq 'Done' }).Count
    $check = @($s.Items | Where-Object { $_.Kind -eq 'Warning' -or ($_.State -in 'Applicable', 'Partial' -and $_.Warnings.Count) }).Count
    $outer = New-Object Windows.Controls.Grid
    $outer.Margin = '0,0,0,18'
    $shadow = New-Object Windows.Controls.Border
    $shadow.Background = New-HDBrush $Colors.Ink; $shadow.CornerRadius = 14; $shadow.Margin = '4,4,0,0'
    $card = New-Object Windows.Controls.Border
    $card.Background = New-HDBrush $Colors.SlateLight; $card.BorderBrush = New-HDBrush $Colors.Ink; $card.BorderThickness = 2
    $card.CornerRadius = 14; $card.Margin = '0,0,4,4'; $card.Padding = '12,10'
    $dock = New-Object Windows.Controls.DockPanel
    $img = New-Object Windows.Controls.Image
    $img.Source = $mascot; $img.Width = 84; $img.Height = 84
    [Windows.Controls.DockPanel]::SetDock($img, 'Left')
    [void]$dock.Children.Add($img)
    $txt = New-HDText (T 'ui.summary' @($actionable, $done, $check)) 16 $Colors.Ink 'Bold'
    $txt.VerticalAlignment = 'Center'; $txt.Margin = '12,0,0,0'
    [void]$dock.Children.Add($txt)
    $card.Child = $dock
    [void]$outer.Children.Add($shadow); [void]$outer.Children.Add($card)
    return $outer
}

function Show-HDCategory([string]$Cat) {
    $State.Category = $Cat
    $UI.CardPanel.Children.Clear()
    [void]$UI.CardPanel.Children.Add((New-HDSummaryCard))
    $head = New-HDText (T "cat.$Cat") 20 $Colors.Ink 'Black'
    $head.Margin = '0,0,0,10'
    [void]$UI.CardPanel.Children.Add($head)
    $items = @($State.Scan.Items | Where-Object { $_.Category -eq $Cat -and (Test-HDVisible $_) })
    $order = @{ Warning = 0; Applicable = 1; Partial = 1; Blocked = 2; Info = 3; Done = 4; NotPresent = 5 }
    # Sort-Object is not stable in PowerShell 5.1, so the original (catalog) order is the tie-breaker.
    $idx = 0
    $items = $items | ForEach-Object { [pscustomobject]@{ I = $_; N = $idx++ } } |
        Sort-Object { if ($_.I.Kind -eq 'Warning') { 0 } else { $order[$_.I.State] } }, N | ForEach-Object { $_.I }
    if (-not $items) {
        $hidden = @($State.Scan.Items | Where-Object { $_.Category -eq $Cat }).Count
        $key = if ($hidden) { 'ui.empty.hidden' } else { 'ui.empty' }
        [void]$UI.CardPanel.Children.Add((New-HDText (T $key) 14 $Colors.Muted))
    }
    foreach ($i in $items) { [void]$UI.CardPanel.Children.Add((New-HDCard $i)) }
    $UI.CardScroll.ScrollToTop()
}

function Update-HDNav {
    $keep = $State.Category
    $UI.NavList.Items.Clear()
    foreach ($c in $Categories) {
        $items = @($State.Scan.Items | Where-Object { $_.Category -eq $c -and (Test-HDVisible $_) })
        if ($c -eq 'warn' -and -not $items.Count) { continue }
        $todo = @($items | Where-Object { $_.Kind -eq 'Action' -and $_.State -in 'Applicable', 'Partial' }).Count
        $row = New-Object Windows.Controls.DockPanel
        $row.Tag = $c
        $count = if ($c -eq 'warn') { $items.Count } else { $todo }
        if ($count -gt 0) {
            $bg = if ($c -eq 'warn') { $Colors.Amber } else { $Colors.Navy }
            $fg = if ($c -eq 'warn') { $Colors.Ink } else { '#FFFFFF' }
            $badge = New-HDBadge ([string]$count) $bg $fg
            [Windows.Controls.DockPanel]::SetDock($badge, 'Right')
            [void]$row.Children.Add($badge)
        }
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = T "cat.$c"; $label.FontWeight = 'SemiBold'; $label.VerticalAlignment = 'Center'; $label.TextWrapping = 'Wrap'
        [void]$row.Children.Add($label)
        [void]$UI.NavList.Items.Add($row)
    }
    $target = if ($keep) { $keep } elseif (@($State.Scan.Items | Where-Object Category -eq 'warn').Count) { 'warn' } else { 'apps' }
    foreach ($row in $UI.NavList.Items) { if ($row.Tag -eq $target) { $UI.NavList.SelectedItem = $row } }
    if (-not $UI.NavList.SelectedItem) { $UI.NavList.SelectedIndex = 0 }
}

function Update-HDCount {
    $n = @($State.Selection.Keys | Where-Object { $State.Selection[$_] }).Count
    $UI.SelectedCount.Text = T 'ui.selected' $n
}

function Show-HDScan($Scan) {
    $State.Scan = $Scan
    $State.Selection = @{}
    foreach ($i in $Scan.Items) { if ($i.Selectable) { $State.Selection[$i.Id] = [bool]$i.Checked } }
    $m = $Scan.Machine
    $admin = if ($m.IsAdmin) { T 'ui.admin.yes' } else { T 'ui.admin.no' }
    $UI.PcInfo.Text = T 'ui.pc' @($m.Manufacturer, $m.Model, $m.OS, $m.Build, $admin)
    if (-not $m.IsAdmin) {
        $UI.BtnAdmin.Visibility = 'Visible'
        $UI.StatusText.Text = T 'ui.admin.why'
    }
    if (-not $State.Category) { $State.Category = $Category }
    Update-HDNav
    Update-HDCount
    $UI.ScanOverlay.Visibility = 'Collapsed'
}

# ------------------------------------------------------------------ background scan

function Start-HDScan {
    $UI.ScanOverlay.Visibility = 'Visible'
    $UI.StatusText.Text = ''
    $sync = [hashtable]::Synchronized(@{ Step = ''; Result = $null; Error = $null; Done = $false })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
            param($AppDir, $Lang, $sync)
            try {
                . (Join-Path $AppDir 'core\Lang.ps1')
                . (Join-Path $AppDir 'core\Scan.ps1')
                Initialize-HDLang $Lang
                $sync.Result = Invoke-HDScan -Progress { param($s) $sync.Step = $s }
            } catch { $sync.Error = $_.ToString() + "`n" + $_.ScriptStackTrace }
            $sync.Done = $true
        }).AddArgument($AppDir).AddArgument($Lang).AddArgument($sync)
    $State.Job = @{ Sync = $sync; PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
    $timer.Start()
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
        $job = $State.Job
        if (-not $job) { $timer.Stop(); return }
        if ($job.Sync.Step) { $UI.ScanStep.Text = T 'ui.scan.step' (T "step.$($job.Sync.Step)") }
        if (-not $job.Sync.Done) { return }
        $timer.Stop()
        try { [void]$job.PS.EndInvoke($job.Handle) } catch {}
        $job.PS.Dispose(); $job.RS.Dispose()
        $State.Job = $null
        if ($job.Sync.Error) {
            $UI.ScanProgress.IsIndeterminate = $false
            $UI.ScanStep.Text = T 'ui.error' $job.Sync.Error
            return
        }
        Show-HDScan $job.Sync.Result
    })

# ------------------------------------------------------------------ events

$UI.NavList.Add_SelectionChanged({
        $row = $UI.NavList.SelectedItem
        if ($row -and $State.Scan) { Show-HDCategory $row.Tag }
    })
$UI.ChkShowAll.Add_Click({ if ($State.Scan) { Update-HDNav; Show-HDCategory $State.Category } })
$UI.BtnRescan.Add_Click({ if (-not $State.Job) { Start-HDScan } })
$UI.BtnAdmin.Add_Click({
        try {
            $args2 = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-Lang', $Lang)
            if ($State.Category) { $args2 += @('-Category', $State.Category) }
            Start-Process powershell.exe -Verb RunAs -ArgumentList $args2
            $Window.Close()
        } catch { $UI.StatusText.Text = T 'ui.admin.cancel' }
    })
$UI.BtnSave.Add_Click({
        if (-not $State.Scan) { return }
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.FileName = 'heartnet-scan-' + (Get-Date -Format 'yyyyMMdd-HHmm')
        $dlg.Filter = 'HTML (*.html)|*.html|JSON (*.json)|*.json'
        $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if ($dlg.ShowDialog($Window)) {
            try {
                Export-HDReport -Scan $State.Scan -Path $dlg.FileName
                $UI.StatusText.Text = T 'ui.saved' $dlg.FileName
                if ($dlg.FileName -like '*.html') { Start-Process $dlg.FileName }
            } catch { $UI.StatusText.Text = $_.Exception.Message }
        }
    })

$Window.Add_ContentRendered({ Start-HDScan })
[void]$Window.ShowDialog()
