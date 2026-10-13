# Static checks for the catalog, language files and sources. No system access.
# Run: powershell -ExecutionPolicy Bypass -File tests\Test-Catalog.ps1   (exit code 1 on failure)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$app = Join-Path $root 'app'
$fail = New-Object System.Collections.Generic.List[string]
function Fail([string]$m) { $fail.Add($m) }

$catalog   = Import-PowerShellDataFile (Join-Path $app 'catalog\items.psd1')
$protected = Import-PowerShellDataFile (Join-Path $app 'catalog\protected.psd1')
$id        = Import-PowerShellDataFile (Join-Path $app 'lang\id.psd1')
$en        = Import-PowerShellDataFile (Join-Path $app 'lang\en.psd1')

$cats    = 'apps', 'ads', 'startup', 'oem', 'xbox', 'privacy', 'system'
$risks   = 'Low', 'Optional', 'Experimental'
$types   = 'Appx', 'Service', 'Task', 'Reg', 'Win32App', 'BtRadio'
$reqs    = 'EdgeInstalled', 'HibernateAvailable'
$guards  = 'PhysicalPrinter', 'SystemDiskHdd', 'BtPairedDevices', 'XboxGames', 'XboxController', 'OneDriveKfm'
$wild    = '[\*\?\[\]]'

# ------------------------------------------------------------------ catalog
$seen = @{}
foreach ($i in $catalog.Items) {
    $tag = "item '$($i.Id)'"
    if (-not $i.Id) { Fail 'item without Id'; continue }
    if ($seen[$i.Id]) { Fail "$tag duplicated" }; $seen[$i.Id] = $true
    if ($cats -notcontains $i.Cat) { Fail "$tag has unknown category '$($i.Cat)'" }
    if ($risks -notcontains $i.Risk) { Fail "$tag has unknown risk '$($i.Risk)'" }
    foreach ($r in @($i.Requires)) { if ($r -and $r -notlike 'Vendor:*' -and $reqs -notcontains $r) { Fail "$tag has unknown requirement '$r'" } }
    foreach ($g in @($i.Guards)) { if ($g -and $guards -notcontains $g) { Fail "$tag has unknown guard '$g'" } }
    if (-not $i.Targets -or @($i.Targets).Count -eq 0) { Fail "$tag has no targets" }
    foreach ($k in 'title', 'desc', 'tradeoff') { if (-not $id.ContainsKey("$($i.Id).$k")) { Fail "$tag is missing text '$($i.Id).$k'" } }

    foreach ($t in @($i.Targets)) {
        if ($types -notcontains $t.T) { Fail "$tag has unknown target type '$($t.T)'"; continue }
        foreach ($field in 'Name', 'DisplayName', 'Path') {
            if ($t[$field] -and $t[$field] -match $wild) { Fail "$tag target $field '$($t[$field])' contains a wildcard; names must be exact" }
        }
        switch ($t.T) {
            'Service' {
                if ($protected.Services -contains $t.Name) { Fail "$tag targets PROTECTED service '$($t.Name)'" }
            }
            'Appx' {
                if ($protected.Appx -contains $t.Name) { Fail "$tag targets PROTECTED app '$($t.Name)'" }
            }
            'Task' {
                if (-not $t.Path -and -not $t.Name) { Fail "$tag task target needs Path and/or Name" }
                if ($t.Path -and ($t.Path[0] -ne '\' -or $t.Path[-1] -ne '\')) { Fail "$tag task path '$($t.Path)' must start and end with '\'" }
                foreach ($p in $protected.TaskPaths) {
                    if ($t.Path -and ($t.Path.StartsWith($p, 'OrdinalIgnoreCase') -or $p.StartsWith($t.Path, 'OrdinalIgnoreCase'))) {
                        Fail "$tag task path '$($t.Path)' overlaps PROTECTED '$p'"
                    }
                }
            }
            'Reg' {
                if ($t.Path -notmatch '^HK(CU|LM):\\') { Fail "$tag registry path must start with HKCU:\ or HKLM:\" }
                if ($null -eq $t.Value -or -not $t.Kind) { Fail "$tag registry target needs Value and Kind" }
                foreach ($p in $protected.RegPathPrefixes) { if ($t.Path.StartsWith($p, 'OrdinalIgnoreCase')) { Fail "$tag writes under PROTECTED '$p'" } }
                # Services can only be touched through the Service target (and its protected list)
                if ($t.Path -match '\\Services\\([^\\]+)') {
                    $svc = $Matches[1]
                    if ($protected.Services | Where-Object { $_ -ieq $svc }) { Fail "$tag edits PROTECTED service key '$svc'" }
                }
            }
        }
    }
}

# Service names must never be loose patterns: catch the old "bth" mistake (it also matched webthreatdefsvc).
foreach ($p in $protected.Services) {
    foreach ($i in $catalog.Items) {
        foreach ($t in @($i.Targets)) {
            if ($t.T -eq 'Service' -and $t.Name -ne $p -and $p -like "*$($t.Name)*" -and $t.Name.Length -lt 6) {
                Fail "item '$($i.Id)' service '$($t.Name)' is short and is part of protected '$p'; double-check it is an exact name"
            }
        }
    }
}

# ------------------------------------------------------------------ language
foreach ($k in $en.Keys) { if (-not $id.ContainsKey($k)) { Fail "en.psd1 key '$k' is not in id.psd1" } }

# Every literal key used with T '...' in the sources must exist
$dynamic = @('startup.generic', 'startup.edge', 'startup.assistant', 'od.startup', 'warn.kfm', 'warn.otheruser', 'warn.wupolicy',
             'warn.wusvc', 'warn.defpolicy', 'office.c2r', 'av.installed', 'av.mcafee.leftovers', 'oem.inventory', 'sys.browserbg',
             'sec.defender', 'sec.firewall', 'sec.hvci', 'sec.vbs', 'sec.wu', 'sec.search', 'sec.hyperv') + (1..8 | ForEach-Object { "notdone.$_" })
foreach ($d in $dynamic) { foreach ($k in 'title', 'desc', 'tradeoff') { if ($d -notlike 'notdone.*' -or $k -ne 'tradeoff') { if (-not $id.ContainsKey("$d.$k")) { Fail "missing text '$d.$k'" } } } }
foreach ($c in $cats + 'warn', 'security', 'notdone') { if (-not $id.ContainsKey("cat.$c")) { Fail "missing text 'cat.$c'" } }
foreach ($r in $risks + 'Info', 'Warning') { if (-not $id.ContainsKey("risk.$r")) { Fail "missing text 'risk.$r'" } }
foreach ($g in $guards + 'ProtectedStartup', 'SystemDiskUnknown') { if (-not $id.ContainsKey("guard.$g")) { Fail "missing text 'guard.$g'" } }

$sources = Get-ChildItem $app -Recurse -Include *.ps1
foreach ($f in $sources) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($m in [regex]::Matches($text, "\bT\s+'([a-z][\w.]*[\w])'")) {
        $key = $m.Groups[1].Value
        if (-not $id.ContainsKey($key)) { Fail "$($f.Name) uses missing text '$key'" }
    }
}

# ------------------------------------------------------------------ sources
foreach ($f in Get-ChildItem $root -Recurse -Include *.ps1, *.psd1, *.xaml, *.cmd | Where-Object { $_.FullName -notlike '*\reference\*' }) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $bom -and ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1)) {
        Fail "$($f.Name) has non-ASCII characters but no UTF-8 BOM (PowerShell 5.1 would misread it)"
    }
    if ($f.Extension -eq '.ps1') {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
        foreach ($e in $errors) { Fail "$($f.Name):$($e.Extent.StartLineNumber) $($e.Message)" }
    }
}
try { [void][xml](Get-Content (Join-Path $app 'ui\MainWindow.xaml') -Raw) } catch { Fail "MainWindow.xaml is not valid XML: $_" }

# ------------------------------------------------------------------ handlers (backup / apply / undo)
# Load the code without running anything that touches the system.
foreach ($f in 'Lang', 'Scan', 'Backup', 'Safety', 'Apply', 'Undo', 'Report', 'Metrics') { . (Join-Path $app "core\$f.ps1") }
foreach ($f in Get-ChildItem (Join-Path $app 'handlers') -Filter *.ps1) { . $f.FullName }
Initialize-HDLang 'id'

$blocks = 'Side', 'Expand', 'Read', 'IsDone', 'Backup', 'Apply', 'Undo', 'IsRestored'
foreach ($t in $types + 'Startup', 'Path') {
    $h = $script:HDHandlers[$t]
    if (-not $h) { Fail "no handler for target type '$t'"; continue }
    foreach ($b in $blocks) { if ($h[$b] -isnot [scriptblock]) { Fail "handler '$t' has no '$b' script block" } }
}
foreach ($i in $catalog.Items) {
    foreach ($t in @($i.Targets)) {
        if ($t.T -eq 'Task' -and $t.Mode -and $t.Mode -notin 'Disable', 'Remove') { Fail "item '$($i.Id)' task Mode '$($t.Mode)' must be Disable or Remove" }
        if ($t.T -eq 'Reg' -and $t.Kind -and -not [enum]::IsDefined([Microsoft.Win32.RegistryValueKind], [string]$t.Kind)) { Fail "item '$($i.Id)' has unknown registry Kind '$($t.Kind)'" }
        # The run-time safety check must agree with the static one: every catalog target is allowed.
        $unit = switch ($t.T) {
            'Service'  { @{ Type = 'Service'; Name = $t.Name } }
            'Appx'     { @{ Type = 'Appx'; Name = $t.Name } }
            'Reg'      { & $script:HDHandlers['Reg'].Expand $t }
            'Task'     { @{ Type = 'Task'; TaskPath = $(if ($t.Path) { $t.Path } else { '\' }); TaskName = $t.Name } }
            default    { $null }
        }
        if ($unit) { $why = Test-HDUnitAllowed $unit; if ($why) { Fail "item '$($i.Id)' is refused at run time: $why" } }
    }
}
foreach ($k in 'confirm.scope.user', 'confirm.scope.machine', 'confirm.scope.mixed') { if (-not $id.ContainsKey($k)) { Fail "missing text '$k'" } }
foreach ($r in 'Success', 'Skipped', 'Failed', 'Pending') { if (-not $id.ContainsKey("result.$r")) { Fail "missing text 'result.$r'" } }
foreach ($s in 'Active', 'Undone', 'Partial', 'None') { if (-not $id.ContainsKey("undo.state.$s")) { Fail "missing text 'undo.state.$s'" } }

# Safety: protected things are refused at run time.
$refuse = @(
    @{ Type = 'Service'; Name = 'WinDefend' }, @{ Type = 'Service'; Name = 'wuauserv' }
    @{ Type = 'Task'; TaskPath = '\Microsoft\Windows\WindowsUpdate\'; TaskName = 'Scheduled Start' }
    @{ Type = 'Appx'; Name = 'Microsoft.WindowsStore' }
    @{ Type = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableAntiSpyware' }
    @{ Type = 'Reg'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend'; Name = 'Start' }
    @{ Type = 'Path'; Path = $env:ProgramData }, @{ Type = 'Path'; Path = "$env:SystemRoot\System32\drivers" }, @{ Type = 'Path'; Path = 'C:\' }
    @{ Type = 'Startup'; Name = 'SecurityHealth'; Command = '%windir%\system32\SecurityHealthSystray.exe' }
    @{ Type = 'BtRadio'; InstanceId = 'BTHENUM\{0000110B-0000-1000-8000-00805F9B34FB}' }
)
foreach ($u in $refuse) { if (-not (Test-HDUnitAllowed $u)) { Fail "safety check lets through $($u.Type) $($u.Name)$($u.Path)$($u.TaskName)$($u.InstanceId)" } }
if (Test-HDUnitAllowed @{ Type = 'Path'; Path = "$env:ProgramData\McAfee" }) { Fail 'safety check refuses %ProgramData%\McAfee' }

# Registry data survives the trip through JSON exactly (undo depends on it).
$cases = @(
    @{ Kind = 'DWord'; Value = [int32]0 }, @{ Kind = 'DWord'; Value = [int32]-1 }, @{ Kind = 'DWord'; Value = [int32]4 }
    @{ Kind = 'QWord'; Value = [int64]::MaxValue }, @{ Kind = 'String'; Value = 'a "b" c' }
    @{ Kind = 'ExpandString'; Value = '%SystemRoot%\x.exe' }, @{ Kind = 'MultiString'; Value = [string[]]@('one', 'two') }
    @{ Kind = 'Binary'; Value = [byte[]]@(3, 0, 0, 0, 255, 16) }
)
foreach ($c in $cases) {
    $data = ConvertTo-HDRegData $c.Value $c.Kind
    $back = ConvertFrom-HDRegData ((@{ D = $data } | ConvertTo-Json -Depth 4 | ConvertFrom-Json).D) $c.Kind
    if (((@($back) | ForEach-Object { [string]$_ }) -join ',') -ne ((@($c.Value) | ForEach-Object { [string]$_ }) -join ',') -or $back.GetType() -ne $c.Value.GetType()) {
        Fail "registry $($c.Kind) value '$($c.Value)' does not survive JSON (got '$back' $($back.GetType().Name))"
    }
}

# Before/after rows: one per measurement, lower is better.
$ma = [pscustomobject]@{ RamUsedMB = 1000; CommitMB = 2000; CpuPct = 3.5; Processes = 200; ServicesRunning = 100; StartupEnabled = 3; TasksActive = 200 }
$mbx = [pscustomobject]@{ RamUsedMB = 900; CommitMB = 2100; CpuPct = 2; Processes = 190; ServicesRunning = 95; StartupEnabled = 0; TasksActive = 190 }
$rows = @(Get-HDMetricRows $ma $mbx)
if ($rows.Count -ne 7) { Fail "metric rows: expected 7, got $($rows.Count)" }
if (@($rows | Where-Object { $_.Better }).Count -ne 6) { Fail 'metric rows: 6 of 7 should be better' }
foreach ($r in $rows) { if (-not (Test-HDText "metric.$($r.Key)")) { Fail "missing text 'metric.$($r.Key)'" } }

# Item result logic
$r = Get-HDItemResult -Units @(@{ Label = 'a'; Result = 'Success' }, @{ Label = 'b'; Result = 'Skipped'; Reason = 'x' })
if ($r.Result -ne 'Success') { Fail "item result: Success+Skipped should be Success, got $($r.Result)" }
$r = Get-HDItemResult -Units @(@{ Label = 'a'; Result = 'Success' }, @{ Label = 'b'; Result = 'Failed'; Reason = 'x' })
if ($r.Result -ne 'Failed') { Fail "item result: Success+Failed should be Failed, got $($r.Result)" }
$r = Get-HDItemResult -Units @() -MissingReasons @('no admin')
if ($r.Result -ne 'Skipped' -or $r.Reasons -notcontains 'no admin') { Fail 'item result: no units should be Skipped with the reason' }

# ------------------------------------------------------------------ result
if ($fail.Count) {
    Write-Host "FAILED ($($fail.Count))" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host ("OK: {0} catalog items, {1} id strings, {2} en strings, {3} source files checked" -f $catalog.Items.Count, $id.Count, $en.Count, $sources.Count) -ForegroundColor Green
