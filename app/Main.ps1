# Heartnet Debloat - entry point.
#   UI (default):  powershell -ExecutionPolicy Bypass -File app\Main.ps1
#   Headless scan: powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Cli [-Json out.json] [-Html out.html]
#   Headless run:  ... -Cli -Apply default|<id>,<id> [-AllowNoRestorePoint]   (one UAC prompt for system items)
#   Undo:          ... -Cli -Undo latest|all|<runId>|<runId>:<itemId>,...
#   Past runs:     ... -Cli -ListRuns
# The scan only reads. Changes happen only after "Backup & jalankan" (or -Apply), always with a backup.

param(
    [switch]$Cli,
    [string]$Json,
    [string]$Html,
    [ValidateSet('id', 'en')][string]$Lang = 'id',
    [string]$Category,      # open the UI on this category (handy for testing/screenshots)
    [switch]$ShowAll,
    [string[]]$Apply,
    [string[]]$Undo,
    [switch]$ListRuns,
    [switch]$AllowNoRestorePoint,
    [string]$Screenshot,    # render the window to this PNG after the scan, then close (changes nothing)
    [ValidateSet('main', 'confirm', 'undo')][string]$Screen = 'main'
)

$ErrorActionPreference = 'Stop'
$AppDir = $PSScriptRoot
foreach ($f in 'Lang', 'Scan', 'Report', 'Backup', 'Safety', 'Apply', 'Undo') { . (Join-Path $AppDir "core\$f.ps1") }
foreach ($f in Get-ChildItem (Join-Path $AppDir 'handlers') -Filter *.ps1) { . $f.FullName }
Initialize-HDLang $Lang

function Write-HDItemResults {
    param([object[]]$Items)
    foreach ($i in $Items) {
        $color = switch ($i.Result) { 'Success' { 'Green' } 'Failed' { 'Red' } default { 'Gray' } }
        Write-Host ('  {0,-10} {1}' -f (T "result.$($i.Result)"), $i.Title) -ForegroundColor $color
        foreach ($r in @($i.Reasons)) { Write-Host "             - $r" }
        foreach ($l in @($i.Links)) { if ($l) { Write-Host "             > $l" } }
    }
}

# ------------------------------------------------------------------ headless: past runs / undo / apply
if ($ListRuns) {
    foreach ($m in Get-HDRunList) {
        Write-Host ''
        Write-Host ('== {0}  ({1})  {2}' -f $m.RunId, $m.CreatedAt, $m.Folder) -ForegroundColor Magenta
        foreach ($i in @($m.Items)) { Write-Host ('  {0,-10} {1,-12} {2,-28} {3}' -f (T "result.$($i.Result)"), (T "undo.state.$($i.UndoState)"), $i.Id, $i.Title) }
    }
    return
}

if ($Undo) {
    $runs = @(Get-HDRunList)
    $sel = @()
    foreach ($u in @($Undo | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
        if ($u -eq 'all') { $sel += @($runs | ForEach-Object { @{ RunId = $_.RunId; Items = @('*') } }) }
        elseif ($u -eq 'latest') { if ($runs.Count) { $sel += @{ RunId = $runs[0].RunId; Items = @('*') } } }
        elseif ($u -match '^([\d-]+):(.+)$') { $sel += @{ RunId = $Matches[1]; Items = @($Matches[2]) } }
        else { $sel += @{ RunId = $u; Items = @('*') } }
    }
    if (-not $sel.Count) { Write-Host (T 'undo.none'); return }
    $res = Invoke-HDUndoHeadless -Selection $sel
    Write-Host ''
    Write-HDItemResults $res
    return
}

if ($Apply) {
    $scan = Invoke-HDScan -Progress { param($s) Write-Host ('  ' + (T 'ui.scan.step' (T "step.$s"))) }
    $ids = @($Apply | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    if ($ids -contains 'default') { $ids = @($scan.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Id }) }
    $bad = @($ids | Where-Object { $id = $_; -not ($scan.Items | Where-Object { $_.Id -eq $id -and $_.Selectable }) })
    foreach ($b in $bad) { Write-Host (T 'cli.notselectable' $b) -ForegroundColor Yellow }
    $ids = @($ids | Where-Object { $bad -notcontains $_ })
    if (-not $ids.Count) { Write-Host (T 'undo.none'); return }
    $m = Invoke-HDRunHeadless -Scan $scan -Ids $ids -AllowNoRestorePoint:$AllowNoRestorePoint
    Write-Host ''
    $rp = $m.RestorePoint
    Write-Host $(if ($rp -and $rp.Status -eq 'Created') { T 'run.rp.ok' $rp.Sequence } elseif ($rp) { T 'rp.failed' $rp.Reason } else { T 'run.rp.none' })
    Write-HDItemResults $m.Items
    Write-Host (T 'run.report.folder' $m.Folder)
    return
}

# ------------------------------------------------------------------ headless scan
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

$State = @{ Scan = $null; Selection = @{}; Category = $null; Job = $null; Run = $null }

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
$UI.BtnUndo.Content = T 'ui.undo'
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
    $UI.BtnRun.IsEnabled = ($n -gt 0)
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
    if ($Screenshot) {
        if ($Screen -eq 'confirm') { Show-HDConfirm } elseif ($Screen -eq 'undo') { Show-HDUndoScreen }
        [void]$Window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ContextIdle, [action] { Save-HDScreenshot $Screenshot; $Window.Close() })
    }
}

function Save-HDScreenshot([string]$Path) {
    $Window.UpdateLayout()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$Window.ActualWidth), ([int]$Window.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($Window)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Close() }
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

# ------------------------------------------------------------------ confirm / run / result / undo screens

$ResultStyle = @{
    Success = @{ Bg = $Colors.Navy; Fg = '#FFFFFF' }
    Skipped = @{ Bg = '#FFFFFF'; Fg = $Colors.Ink }
    Failed  = @{ Bg = $Colors.Wing; Fg = '#FFFFFF' }
}

function New-HDPanelCard([string]$Bg = '#FFFFFF') {
    # White sticker card with the flat ink shadow; returns @{ Outer; Stack }.
    $outer = New-Object Windows.Controls.Grid
    $outer.Margin = '0,0,0,14'
    $shadow = New-Object Windows.Controls.Border
    $shadow.Background = New-HDBrush $Colors.Ink; $shadow.CornerRadius = 12; $shadow.Margin = '4,4,0,0'
    $card = New-Object Windows.Controls.Border
    $card.Background = New-HDBrush $Bg; $card.BorderBrush = New-HDBrush $Colors.Ink; $card.BorderThickness = 2
    $card.CornerRadius = 12; $card.Margin = '0,0,4,4'; $card.Padding = '14,10'
    [void]$outer.Children.Add($shadow); [void]$outer.Children.Add($card)
    $stack = New-Object Windows.Controls.StackPanel
    $card.Child = $stack
    return @{ Outer = $outer; Stack = $stack }
}

function New-HDButton([string]$Text, [scriptblock]$OnClick, [switch]$Primary, [object]$Tag) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $Text
    $b.Style = $Window.FindResource($(if ($Primary) { 'HDPrimary' } else { 'HDButton' }))
    $b.Tag = $Tag
    $b.Add_Click($OnClick)
    return $b
}

function Show-HDFlow([string]$Title, [string]$Sub) {
    $UI.FlowPanel.Children.Clear()
    $UI.FlowButtons.Children.Clear()
    $UI.FlowStatus.Text = ''
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = '0,0,0,14'
    $img = New-Object Windows.Controls.Image
    $img.Source = $mascot; $img.Width = 72; $img.Height = 72
    [Windows.Controls.DockPanel]::SetDock($img, 'Left')
    [void]$head.Children.Add($img)
    $txt = New-Object Windows.Controls.StackPanel
    $txt.Margin = '12,0,0,0'; $txt.VerticalAlignment = 'Center'
    [void]$txt.Children.Add((New-HDText $Title 22 $Colors.Ink 'Black'))
    if ($Sub) { $st = New-HDText $Sub 14 $Colors.Muted; $st.Margin = '0,4,0,0'; [void]$txt.Children.Add($st) }
    [void]$head.Children.Add($txt)
    [void]$UI.FlowPanel.Children.Add($head)
    $UI.FlowOverlay.Visibility = 'Visible'
    $UI.FlowScroll.ScrollToTop()
}

function Add-HDFlowNote([string]$Text, [string]$Bg = '#FFF6E6', [string]$Color = $Colors.Ink) {
    $c = New-HDPanelCard $Bg
    [void]$c.Stack.Children.Add((New-HDText $Text 13.5 $Color))
    [void]$UI.FlowPanel.Children.Add($c.Outer)
}

function Hide-HDFlow { $UI.FlowOverlay.Visibility = 'Collapsed' }

function Show-HDProgress([string]$Title, [string]$Sub) {
    Hide-HDFlow
    $UI.ScanTitle.Text = $Title
    $UI.ScanSub.Text = $Sub
    $UI.ScanStep.Text = ''
    $UI.ScanProgress.IsIndeterminate = $true
    $UI.ScanOverlay.Visibility = 'Visible'
    $UI.Footer.IsEnabled = $false
}

function Hide-HDProgress {
    $UI.ScanOverlay.Visibility = 'Collapsed'
    $UI.Footer.IsEnabled = $true
}

# ---- 1. confirmation before running

function Show-HDConfirm {
    $items = @($State.Scan.Items | Where-Object { $_.Selectable -and $State.Selection[$_.Id] })
    if (-not $items.Count) { return }
    Show-HDFlow (T 'confirm.title' $items.Count) (T 'confirm.sub')

    $machine = @($items | Where-Object { (Get-HDItemSides $_) -contains 'Machine' })
    Add-HDFlowNote (T 'confirm.backup') $Colors.SlateLight
    Add-HDFlowNote (T 'confirm.uac')
    $policy = @($items | Where-Object { Test-HDItemPolicy $_ })
    if ($policy.Count) { Add-HDFlowNote (T 'confirm.policy' (($policy | ForEach-Object { $_.Title }) -join ', ')) }
    if ($items | Where-Object { $_.Targets | Where-Object { $_.T -eq 'Win32App' } }) { Add-HDFlowNote (T 'note.uninstall') '#FFF6E6' $Colors.Wing }
    if ($State.Scan.OtherUser) { Add-HDFlowNote (T 'reason.otheruser' @($State.Scan.OtherUser.Me, $State.Scan.OtherUser.Desktop)) '#FFF6E6' $Colors.Wing }

    $c = New-HDPanelCard
    foreach ($i in $items) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '0,3,0,3'
        $right = New-Object Windows.Controls.StackPanel
        $right.Orientation = 'Horizontal'; [Windows.Controls.DockPanel]::SetDock($right, 'Right')
        $sides = Get-HDItemSides $i
        $scopeKey = if ($sides.Count -gt 1) { 'confirm.scope.mixed' } elseif ($sides -contains 'Machine') { 'confirm.scope.machine' } else { 'confirm.scope.user' }
        $sc = New-HDText (T $scopeKey) 12 $Colors.Muted
        $sc.VerticalAlignment = 'Center'
        [void]$right.Children.Add($sc)
        [void]$right.Children.Add((New-HDBadge (T "risk.$($i.Risk)") $RiskStyle[$i.Risk].Bg $RiskStyle[$i.Risk].Fg))
        [void]$row.Children.Add($right)
        $t = New-HDText $i.Title 14 $Colors.Ink 'SemiBold'
        $t.VerticalAlignment = 'Center'
        [void]$row.Children.Add($t)
        [void]$c.Stack.Children.Add($row)
        foreach ($w in $i.Warnings) {
            $wt = New-HDText ('(!) ' + $w) 12 $Colors.Wing
            $wt.Margin = '12,0,0,4'
            [void]$c.Stack.Children.Add($wt)
        }
    }
    [void]$UI.FlowPanel.Children.Add($c.Outer)

    $UI.FlowStatus.Text = if ($machine.Count) { T 'confirm.status.uac' $machine.Count } else { T 'confirm.status.user' }
    [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'ui.cancel') { Hide-HDFlow }))
    [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'confirm.go') { Start-HDUiRun } -Primary))
}

# ---- 2. running (worker + user side), shared by apply and undo

function Start-HDUiRun {
    $ids = @($State.Scan.Items | Where-Object { $_.Selectable -and $State.Selection[$_.Id] } | ForEach-Object { $_.Id })
    try { $dir = New-HDRun -Scan $State.Scan -Ids $ids }
    catch { [void][Windows.MessageBox]::Show($Window, (T 'ui.error.run' $_.Exception.Message), (T 'ui.appname'), 'OK', 'Error'); return }
    $State.Run = @{ Kind = 'Apply'; Dir = $dir; Phase = 'Worker'; Answered = 0; Proc = $null; Status = (Join-Path $dir 'machine\status.json') }
    Show-HDProgress (T 'run.title') (T 'run.sub')
    $UI.ScanStep.Text = T 'run.uac'
    $Window.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background)
    $proc = Start-HDWorker @{ Mode = 'Apply'; RunDir = $dir; Lang = $Lang }
    if (-not $proc) {
        Save-HDRunState $dir @{ Worker = 'Cancelled' }
        $ans = [Windows.MessageBox]::Show($Window, (T 'run.uac.cancelled'), (T 'ui.appname'), 'YesNo', 'Warning')
        if ($ans -eq 'Yes') { Start-HDUserSide } else { Complete-HDUiRun -UserSide 'NotRun' }
        return
    }
    $State.Run.Proc = $proc
    $runTimer.Start()
}

function Start-HDUiUndo([object[]]$Selection, [int]$Count) {
    $ans = [Windows.MessageBox]::Show($Window, (T 'undo.confirm' $Count), (T 'ui.appname'), 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    $jobDir = New-HDUndoJob $Selection
    $State.Run = @{ Kind = 'Undo'; Dir = $jobDir; Selection = $Selection; Phase = 'Worker'; Answered = 0; Proc = $null; Status = (Join-Path $jobDir 'status.json') }
    Show-HDProgress (T 'undo.running') (T 'undo.running.sub')
    $Window.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background)
    if (Test-HDUndoNeedsAdmin $Selection) {
        $UI.ScanStep.Text = T 'run.uac'
        $proc = Start-HDWorker @{ Mode = 'Undo'; JobDir = $jobDir; Lang = $Lang }
        if ($proc) { $State.Run.Proc = $proc; $runTimer.Start(); return }
        [void][Windows.MessageBox]::Show($Window, (T 'undo.uac.cancelled'), (T 'ui.appname'), 'OK', 'Warning')
    }
    Start-HDUserSide
}

function Show-HDConsent($RestorePoint) {
    # Returns Enable / Continue / Cancel
    if ($RestorePoint.Status -eq 'Disabled') {
        $ans = [Windows.MessageBox]::Show($Window, (T 'consent.disabled' $RestorePoint.Reason), (T 'consent.title'), 'YesNoCancel', 'Warning')
        switch ($ans) { 'Yes' { return 'Enable' } 'No' { return 'Continue' } default { return 'Cancel' } }
    }
    $ans = [Windows.MessageBox]::Show($Window, (T 'consent.failed' $RestorePoint.Reason), (T 'consent.title'), 'YesNo', 'Warning')
    if ($ans -eq 'Yes') { return 'Continue' }
    return 'Cancel'
}

function Start-HDUserSide {
    $r = $State.Run
    $r.Phase = 'User'
    $UI.ScanStep.Text = T 'run.user'
    $sync = [hashtable]::Synchronized(@{ Text = ''; Done = $false; Error = $null })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
            param($AppDir, $Lang, $sync, $Kind, $Dir, $Selection)
            try {
                foreach ($f in 'Lang', 'Scan', 'Report', 'Backup', 'Safety', 'Apply', 'Undo') { . (Join-Path $AppDir "core\$f.ps1") }
                foreach ($f in Get-ChildItem (Join-Path $AppDir 'handlers') -Filter *.ps1) { . $f.FullName }
                Initialize-HDLang $Lang
                $prog = { param($p) if ($p.Text) { $sync.Text = $p.Text } }
                if ($Kind -eq 'Apply') {
                    $sync.Text = T 'run.rescan'
                    $plan = Read-HDJson (Join-Path $Dir 'plan.json')
                    $scan = Invoke-HDScan
                    $sel = Select-HDPlanItems -Scan $scan -Plan $plan -Side 'User'
                    $refuse = if ($scan.OtherUser) { T 'reason.otheruser' @($scan.OtherUser.Me, $scan.OtherUser.Desktop) } else { '' }
                    $null = Invoke-HDApplySide -RunDir $Dir -Side 'User' -Items $sel.Items -Refused $sel.Refused -RefuseAll $refuse -Progress $prog
                } else {
                    $jobId = Split-Path $Dir -Leaf
                    foreach ($s in $Selection) {
                        $null = Invoke-HDUndoSide -RunDir (Join-Path (Get-HDRunsRoot) $s.RunId) -Side 'User' -ItemIds @($s.Items) -JobId $jobId -Progress $prog
                    }
                }
            } catch { $sync.Error = $_.ToString() + "`n" + $_.ScriptStackTrace }
            $sync.Done = $true
        }).AddArgument($AppDir).AddArgument($Lang).AddArgument($sync).AddArgument($r.Kind).AddArgument($r.Dir).AddArgument($r.Selection)
    $r.User = @{ Sync = $sync; PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
    $runTimer.Start()
}

function Complete-HDUiRun([string]$UserSide = 'Done') {
    $runTimer.Stop()
    $r = $State.Run
    if ($r.User) {
        try { [void]$r.User.PS.EndInvoke($r.User.Handle) } catch {}
        $r.User.PS.Dispose(); $r.User.RS.Dispose()
        if ($r.User.Sync.Error) { [void][Windows.MessageBox]::Show($Window, (T 'ui.error.run' $r.User.Sync.Error), (T 'ui.appname'), 'OK', 'Error') }
    }
    $State.Run = $null
    Hide-HDProgress
    if ($r.Kind -eq 'Apply') {
        Save-HDRunState $r.Dir @{ UserSide = $UserSide; FinishedAt = (Get-Date).ToString('s') }
        Show-HDRunResult (Update-HDManifest $r.Dir)
    } else {
        Show-HDUndoResult (Get-HDUndoJobResult $r.Dir)
    }
}

$runTimer = New-Object Windows.Threading.DispatcherTimer
$runTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$runTimer.Add_Tick({
        $r = $State.Run
        if (-not $r) { $runTimer.Stop(); return }
        if ($r.Phase -eq 'Worker') {
            $s = $null
            try { $s = Read-HDJson $r.Status } catch {}
            if ($s) {
                $UI.ScanStep.Text = switch ($s.Phase) {
                    'Applying' { T 'run.item' @(([int]$s.Done + 1), $s.Total, $s.Text) }
                    'Undoing'  { T 'run.item' @(([int]$s.Done + 1), $s.Total, $s.Text) }
                    default    { $s.Text }
                }
                if ($s.Phase -eq 'NeedConsent' -and [int]$s.Ask -gt $r.Answered) {
                    $runTimer.Stop()
                    $r.Answered = [int]$s.Ask
                    Set-HDConsent -RunDir $r.Dir -Ask $r.Answered -Choice (Show-HDConsent $s.RestorePoint)
                    $runTimer.Start()
                    return
                }
            }
            if (-not (Test-HDProcessExited $r.Proc)) { return }
            $runTimer.Stop()
            if ($r.Kind -eq 'Undo') { Start-HDUserSide; return }
            $phase = if ($s) { [string]$s.Phase } else { '' }
            $ws = switch ($phase) { 'Done' { 'Done' } 'Cancelled' { 'Declined' } default { 'Failed' } }
            Save-HDRunState $r.Dir @{ Worker = $ws }
            if ($ws -eq 'Declined') { Complete-HDUiRun -UserSide 'NotRun'; return }
            if ($ws -eq 'Failed') {
                $msg = if ($s) { $s.Text } else { T 'reason.workerfailed' }
                $ans = [Windows.MessageBox]::Show($Window, (T 'run.worker.failed' $msg), (T 'ui.appname'), 'YesNo', 'Warning')
                if ($ans -ne 'Yes') { Complete-HDUiRun -UserSide 'NotRun'; return }
            }
            Start-HDUserSide
            return
        }
        if ($r.Phase -eq 'User') {
            if ($r.User.Sync.Text) { $UI.ScanStep.Text = $r.User.Sync.Text }
            if ($r.User.Sync.Done) { Complete-HDUiRun }
        }
    })

# ---- 3. result of a run

function Add-HDResultCard($Item, [string]$Result, [object[]]$Reasons, [object[]]$Units, [object[]]$Links) {
    $c = New-HDPanelCard
    $head = New-Object Windows.Controls.DockPanel
    $rs = $ResultStyle[$Result]
    $badge = New-HDBadge (T "result.$Result") $rs.Bg $rs.Fg
    [Windows.Controls.DockPanel]::SetDock($badge, 'Right')
    [void]$head.Children.Add($badge)
    [void]$head.Children.Add((New-HDText $Item.Title 15 $Colors.Ink 'Bold'))
    [void]$c.Stack.Children.Add($head)
    foreach ($r in @($Reasons)) {
        $t = New-HDText $r 12.5 $(if ($Result -eq 'Failed') { $Colors.Wing } else { $Colors.Muted })
        $t.Margin = '0,4,0,0'
        [void]$c.Stack.Children.Add($t)
    }
    foreach ($l in @($Links)) {
        if (-not $l) { continue }
        $b = New-HDButton (T 'undo.store') { param($s, $e) try { Start-Process $s.Tag } catch {} } -Tag $l
        $b.HorizontalAlignment = 'Left'; $b.Margin = '0,8,0,0'
        [void]$c.Stack.Children.Add($b)
    }
    if (@($Units).Count) {
        $exp = New-Object Windows.Controls.Expander
        $exp.Header = T 'run.details'; $exp.Margin = '0,6,0,0'; $exp.FontSize = 12; $exp.Foreground = New-HDBrush $Colors.Navy
        $lines = foreach ($u in @($Units)) {
            '{0}  [{1}]' -f $u.Label, (T "result.$($u.Result)")
            '    {0}: {1}' -f (T 'run.col.before'), (Format-HDState $u.Before)
            if ($u.After) { '    {0}: {1}' -f (T 'run.col.after'), (Format-HDState $u.After) }
            if ($u.Undo) { '    {0}: {1} {2}' -f (T 'run.col.undo'), (T "result.$($u.Undo.Result)"), $u.Undo.Reason }
        }
        $dt = New-HDText (@($lines) -join "`n") 11.5 $Colors.Muted
        $dt.FontFamily = 'Consolas'; $dt.Margin = '18,4,0,0'
        $exp.Content = $dt
        [void]$c.Stack.Children.Add($exp)
    }
    [void]$UI.FlowPanel.Children.Add($c.Outer)
}

function Show-HDRunResult($M) {
    if (-not $M) { Hide-HDFlow; Start-HDScan; return }
    $items = @($M.Items)
    $ok = @($items | Where-Object Result -eq 'Success').Count
    $skip = @($items | Where-Object Result -eq 'Skipped').Count
    $fail = @($items | Where-Object Result -eq 'Failed').Count
    Show-HDFlow (T 'result.title') (T 'result.summary' @($ok, $skip, $fail))
    $rp = $M.RestorePoint
    if ($rp -and $rp.Status -eq 'Created') { Add-HDFlowNote (T 'run.rp.ok' $rp.Sequence) $Colors.SlateLight }
    elseif ($rp) { Add-HDFlowNote (T 'rp.failed' $rp.Reason) '#FFF6E6' $Colors.Wing }
    else { Add-HDFlowNote (T 'run.rp.none') '#FFF6E6' $Colors.Wing }
    if ($items | Where-Object { $_.Restart }) { Add-HDFlowNote (T 'result.restart') }
    foreach ($i in $items) { Add-HDResultCard $i $i.Result $i.Reasons $i.Units }
    $UI.FlowStatus.Text = T 'run.report.folder' $M.Folder
    $folder = $M.Folder
    $b1 = New-HDButton (T 'result.folder') { param($s, $e) Start-Process explorer.exe -ArgumentList ('"{0}"' -f $s.Tag) } -Tag $folder
    $b2 = New-HDButton (T 'result.report') { param($s, $e) Start-Process (Join-Path $s.Tag 'report.html') } -Tag $folder
    [void]$UI.FlowButtons.Children.Add($b1)
    [void]$UI.FlowButtons.Children.Add($b2)
    [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'result.done') { Hide-HDFlow; Start-HDScan } -Primary))
}

# ---- 4. history and undo

function Show-HDUndoScreen {
    $runs = @(Get-HDRunList | Where-Object { @($_.Items | Where-Object { $_.UndoState -ne 'None' }).Count })
    Show-HDFlow (T 'undo.title') (T 'undo.sub')
    $all = @()
    foreach ($m in $runs) {
        $active = @($m.Items | Where-Object { $_.UndoState -in 'Active', 'Partial' })
        if ($active.Count) { $all += @{ RunId = $m.RunId; Items = @('*') } }
        $c = New-HDPanelCard
        $head = New-Object Windows.Controls.DockPanel
        if ($active.Count) {
            $b = New-HDButton (T 'undo.run' $active.Count) { param($s, $e) Start-HDUiUndo @(@{ RunId = $s.Tag.RunId; Items = @('*') }) $s.Tag.Count } -Tag @{ RunId = $m.RunId; Count = $active.Count }
            [Windows.Controls.DockPanel]::SetDock($b, 'Right')
            [void]$head.Children.Add($b)
        }
        $when = try { ([datetime]$m.CreatedAt).ToString('dd MMM yyyy HH:mm') } catch { $m.CreatedAt }
        $ht = New-HDText (T 'undo.run.title' @($when, $m.RunId)) 16 $Colors.Ink 'Bold'
        $ht.VerticalAlignment = 'Center'
        [void]$head.Children.Add($ht)
        [void]$c.Stack.Children.Add($head)
        $rp = $m.RestorePoint
        $rpText = if ($rp -and $rp.Status -eq 'Created') { T 'run.rp.ok' $rp.Sequence } elseif ($rp) { T 'rp.failed' $rp.Reason } else { T 'run.rp.none' }
        $rpt = New-HDText $rpText 12 $Colors.Muted
        $rpt.Margin = '0,2,0,6'
        [void]$c.Stack.Children.Add($rpt)
        foreach ($i in @($m.Items | Where-Object { $_.UndoState -ne 'None' })) {
            $row = New-Object Windows.Controls.DockPanel
            $row.Margin = '0,4,0,4'
            $right = New-Object Windows.Controls.StackPanel
            $right.Orientation = 'Horizontal'; [Windows.Controls.DockPanel]::SetDock($right, 'Right')
            $stColor = if ($i.UndoState -eq 'Undone') { $Colors.Muted } else { $Colors.Navy }
            $st = New-HDText (T "undo.state.$($i.UndoState)") 12 $stColor 'SemiBold'
            $st.VerticalAlignment = 'Center'
            [void]$right.Children.Add($st)
            if ($i.UndoState -in 'Active', 'Partial') {
                $b = New-HDButton (T 'undo.item') { param($s, $e) Start-HDUiUndo @(@{ RunId = $s.Tag.RunId; Items = @($s.Tag.Id) }) 1 } -Tag @{ RunId = $m.RunId; Id = $i.Id }
                $b.Padding = '12,4'
                [void]$right.Children.Add($b)
            }
            [void]$row.Children.Add($right)
            $t = New-HDText $i.Title 14 $Colors.Ink
            $t.VerticalAlignment = 'Center'
            [void]$row.Children.Add($t)
            [void]$c.Stack.Children.Add($row)
        }
        [void]$UI.FlowPanel.Children.Add($c.Outer)
    }
    if (-not $runs.Count) { Add-HDFlowNote (T 'undo.none') $Colors.SlateLight }
    $UI.FlowStatus.Text = T 'undo.folder' (Get-HDRunsRoot)
    [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'ui.close') { Hide-HDFlow }))
    if ($all.Count) {
        $n = @($runs | ForEach-Object { @($_.Items | Where-Object { $_.UndoState -in 'Active', 'Partial' }) }).Count
        [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'undo.all' $n) { param($s, $e) Start-HDUiUndo $s.Tag.Sel $s.Tag.Count } -Primary -Tag @{ Sel = $all; Count = $n }))
    }
}

function Show-HDUndoResult([object[]]$Results) {
    $ok = @($Results | Where-Object Result -eq 'Success').Count
    $skip = @($Results | Where-Object Result -eq 'Skipped').Count
    $fail = @($Results | Where-Object Result -eq 'Failed').Count
    Show-HDFlow (T 'undo.result.title') (T 'result.summary' @($ok, $skip, $fail))
    if ($Results | Where-Object { $_.Restart }) { Add-HDFlowNote (T 'result.restart') }
    foreach ($r in $Results) { Add-HDResultCard $r $r.Result $r.Reasons @() $r.Links }
    if (-not @($Results).Count) { Add-HDFlowNote (T 'undo.nothing') $Colors.SlateLight }
    [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'undo.back') { Show-HDUndoScreen }))
    [void]$UI.FlowButtons.Children.Add((New-HDButton (T 'result.done') { Hide-HDFlow; Start-HDScan } -Primary))
}

# ------------------------------------------------------------------ events

$UI.NavList.Add_SelectionChanged({
        $row = $UI.NavList.SelectedItem
        if ($row -and $State.Scan) { Show-HDCategory $row.Tag }
    })
$UI.ChkShowAll.Add_Click({ if ($State.Scan) { Update-HDNav; Show-HDCategory $State.Category } })
$UI.BtnRescan.Add_Click({ if (-not $State.Job) { Start-HDScan } })
$UI.BtnRun.Add_Click({ if ($State.Scan -and -not $State.Run) { Show-HDConfirm } })
$UI.BtnUndo.Add_Click({ if (-not $State.Run) { Show-HDUndoScreen } })
$Window.Add_Closing({
        param($s, $e)
        if ($State.Run) {
            [void][Windows.MessageBox]::Show($Window, (T 'run.busy'), (T 'ui.appname'), 'OK', 'Information')
            $e.Cancel = $true
        }
    })
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
