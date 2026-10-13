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

# ------------------------------------------------------------------ result
if ($fail.Count) {
    Write-Host "FAILED ($($fail.Count))" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host ("OK: {0} catalog items, {1} id strings, {2} en strings, {3} source files checked" -f $catalog.Items.Count, $id.Count, $en.Count, $sources.Count) -ForegroundColor Green
