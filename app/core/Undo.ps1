# Undo engine, merged run manifest and the list of past runs.
#
# Undo is derived from the recorded backup only: for every unit that was attempted, the handler of
# its type gets the unit spec, the recorded "Before" state and the backup files, and restores them.
# Nothing is written per item. After undo the unit is read again and only counts as restored when the
# state matches "Before" (verify-after, same as apply).

function Get-HDUndoRecords {
    # All undo records of one side of one run, newest last.
    param([string]$SideDir)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $SideDir -Filter 'undo-*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $r = $null
        try { $r = Read-HDJson $f.FullName } catch {}
        if ($r) { foreach ($u in @($r.Units)) { if ($u) { $list.Add($u) } } }
    }
    return $list
}

function Read-HDSideResults {
    param([string]$RunDir, [string]$Side)
    $dir = Join-Path $RunDir $Side.ToLower()
    $file = Join-Path $dir 'results.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    # Machine data is only trusted when it was written by the elevated worker.
    if ($Side -eq 'Machine' -and -not ((Test-HDAdminOwned $dir) -and (Test-HDAdminOwned $file))) { return $null }
    return (Read-HDJson $file)
}

function Invoke-HDUndoSide {
    param(
        [string]$RunDir,
        [ValidateSet('User', 'Machine')][string]$Side,
        [string[]]$ItemIds = @('*'),
        [string]$JobId = (Get-Date -Format 'yyyyMMdd-HHmmss'),
        [scriptblock]$Progress = {}
    )
    $dir = Join-Path $RunDir $Side.ToLower()
    $res = Read-HDSideResults $RunDir $Side
    if (-not $res) { return $null }
    $undone = @{}
    foreach ($r in Get-HDUndoRecords $dir) { if ($r.Result -eq 'Success') { $undone["$($r.Item)|$($r.Key)"] = $true } }

    $rec = [ordered]@{ Side = $Side; JobId = $JobId; At = (Get-Date).ToString('s'); Account = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
                       Units = New-Object System.Collections.ArrayList }
    # Per-user changes may only be undone by the same account that made them.
    $foreign = ($Side -eq 'User') -and ($res.Sid -ne (Get-HDCurrentSid))
    $file = Join-Path $dir ("undo-$JobId.json")

    $todo = @(foreach ($item in @($res.Items)) {
            if ($ItemIds -notcontains '*' -and $ItemIds -notcontains $item.Id) { continue }
            foreach ($u in @($item.Units)) { if ($u -and $u.Attempted -and -not $undone["$($item.Id)|$($u.Key)"]) { @{ Item = $item; Unit = $u } } }
        })
    # Reverse order: last change first.
    [array]::Reverse($todo)
    $n = 0
    foreach ($t in $todo) {
        $n++
        $u = $t.Unit
        & $Progress @{ Done = $n - 1; Total = $todo.Count; Text = $u.Label }
        $r = [ordered]@{ Item = $t.Item.Id; Title = $t.Item.Title; Key = $u.Key; Label = $u.Label; Result = 'Failed'; Reason = ''; After = $null; Restart = $false; Link = $null }
        [void]$rec.Units.Add($r)
        if ($foreign) { $r.Result = 'Skipped'; $r.Reason = T 'reason.otheraccount' $res.Account; continue }
        $why = Test-HDUnitAllowed $u.Spec
        if ($why) { $r.Reason = $why; continue }
        try {
            $h = Get-HDHandler $u.Type
            $out = & $h.Undo $u.Spec $u.Before $u.Backup $dir
            if ($out -and $out.Restart) { $r.Restart = $true }
            $r.After = & $h.Read $u.Spec
            if ($out -and $out.Manual) { $r.Result = 'Skipped'; $r.Reason = $out.Manual; $r.Link = $out.Link }
            elseif (& $h.IsRestored $u.Spec $u.Before $r.After) { $r.Result = 'Success' }
            elseif ($r.Restart) { $r.Result = 'Success'; $r.Reason = T 'reason.restart' }
            else { $r.Reason = T 'reason.verify.undo' }
        } catch { $r.Reason = T 'reason.error' $_.Exception.Message }
        Save-HDJson -Path $file -Object $rec
    }
    if ($rec.Units.Count) { Save-HDJson -Path $file -Object $rec }
    & $Progress @{ Done = $todo.Count; Total = $todo.Count; Text = '' }
    return $rec
}

# ============================================================== merged manifest

function Get-HDItemResult {
    # Success / Skipped / Failed for a whole item from its units.
    param([object[]]$Units, [string[]]$MissingReasons)
    $failed = @($Units | Where-Object { $_.Result -eq 'Failed' -or $_.Result -eq 'Pending' })
    $ok = @($Units | Where-Object { $_.Result -eq 'Success' })
    $reasons = New-Object System.Collections.Generic.List[string]
    foreach ($u in $Units) {
        if ($u.Result -ne 'Success' -and $u.Reason) {
            $line = '{0}: {1}' -f $u.Label, $u.Reason
            if ($u.Result -eq 'Pending') { $line = '{0}: {1}' -f $u.Label, (T 'reason.interrupted') }
            if (-not $reasons.Contains($line)) { $reasons.Add($line) }
        }
    }
    foreach ($m in $MissingReasons) { if ($m -and -not $reasons.Contains($m)) { $reasons.Add($m) } }
    $result = if ($failed.Count) { 'Failed' } elseif ($ok.Count) { 'Success' } else { 'Skipped' }
    if ($result -eq 'Skipped' -and -not $reasons.Count) { $reasons.Add((T 'reason.nothing')) }
    return @{ Result = $result; Reasons = [object[]]$reasons.ToArray() }
}

function Get-HDRunManifest {
    param([string]$RunDir)
    $plan = Read-HDJson (Join-Path $RunDir 'plan.json')
    if (-not $plan) { return $null }
    $run = Read-HDJson (Join-Path $RunDir 'run.json')
    $sides = @{ User = (Read-HDSideResults $RunDir 'User'); Machine = (Read-HDSideResults $RunDir 'Machine') }
    $undo = @{}
    foreach ($s in 'User', 'Machine') {
        if (-not $sides[$s]) { continue }
        foreach ($r in Get-HDUndoRecords (Join-Path $RunDir $s.ToLower())) { $undo["$s|$($r.Item)|$($r.Key)"] = $r }
    }
    $workerState = if ($run) { [string]$run.Worker } else { '' }

    $items = foreach ($p in @($plan.Items)) {
        $units = New-Object System.Collections.Generic.List[object]
        $missing = @()
        foreach ($s in @($p.Sides)) {
            $res = $sides[$s]
            $entry = if ($res) { @($res.Items | Where-Object { $_.Id -eq $p.Id }) | Select-Object -First 1 } else { $null }
            if (-not $entry) {
                $missing += switch ("$s/$workerState") {
                    'Machine/Cancelled' { T 'reason.noadmin' }
                    'Machine/Declined'  { T 'reason.cancelled' }
                    'Machine/Failed'    { T 'reason.workerfailed' }
                    default             { if ($run -and $run.UserSide -eq 'NotRun') { T 'reason.cancelled' } elseif ($run.FinishedAt) { T 'reason.nothing' } else { T 'reason.notrun' } }
                }
                continue
            }
            if ($entry.Refused) { $missing += $entry.Refused }
            foreach ($u in @($entry.Units)) {
                if (-not $u) { continue }
                $un = $undo["$s|$($p.Id)|$($u.Key)"]
                $units.Add([ordered]@{
                        Side = $s; Key = $u.Key; Type = $u.Type; Label = $u.Label; Spec = $u.Spec
                        Before = $u.Before; Backup = $u.Backup; After = $u.After; Attempted = [bool]$u.Attempted
                        Result = $u.Result; Reason = $u.Reason; Restart = [bool]$u.Restart
                        Undo = if ($un) { [ordered]@{ At = $un.At; JobId = $un.JobId; Result = $un.Result; Reason = $un.Reason; After = $un.After; Link = $un.Link } } else { $null }
                    })
            }
        }
        $r = Get-HDItemResult -Units $units.ToArray() -MissingReasons $missing
        $attempted = @($units | Where-Object { $_.Attempted })
        $restored = @($attempted | Where-Object { $_.Undo -and $_.Undo.Result -eq 'Success' })
        $undoState = if (-not $attempted.Count) { 'None' } elseif ($restored.Count -eq $attempted.Count) { 'Undone' } elseif ($restored.Count) { 'Partial' } else { 'Active' }
        [ordered]@{
            Id = $p.Id; Title = $p.Title; Category = $p.Category; Risk = $p.Risk; Sides = [object[]]@($p.Sides); Policy = [bool]$p.Policy
            Result = $r.Result; Reasons = $r.Reasons; Restart = [bool]($units | Where-Object { $_.Restart -and $_.Result -eq 'Success' })
            UndoState = $undoState; Units = [object[]]$units.ToArray()
        }
    }
    [ordered]@{
        App = $plan.App; Version = $plan.Version; RunId = $plan.RunId; CreatedAt = $plan.CreatedAt; User = $plan.User; Machine = $plan.Machine
        Folder = $RunDir; Run = $run
        Metrics = [ordered]@{
            Before = if ($run) { $run.MetricsBefore } else { $null }
            After  = if ($run) { $run.MetricsAfter } else { $null }
            Later  = if ($run) { $run.MetricsLater } else { $null }
        }
        RestorePoint = if ($sides.Machine) { $sides.Machine.RestorePoint } else { $null }
        Items = [object[]]@($items)
    }
}

function Update-HDManifest {
    # Rebuilds manifest.json + report.html from the part files. Returns the manifest.
    param([string]$RunDir)
    $m = Get-HDRunManifest $RunDir
    if (-not $m) { return $null }
    try {
        Save-HDJson -Path (Join-Path $RunDir 'manifest.json') -Object $m
        Export-HDRunReport -Manifest $m -Path (Join-Path $RunDir 'report.html')
    } catch {}
    return $m
}

function Get-HDRunList {
    # Past runs, newest first, with their manifest (read-only, nothing is rewritten here).
    $root = Get-HDRunsRoot
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{8}-\d{6}(-\d+)?$' } | Sort-Object Name -Descending)) {
        $m = $null
        try { $m = Get-HDRunManifest $d.FullName } catch {}
        if ($m) { $m }
    }
}

# ============================================================== undo jobs (several runs/items at once)

function New-HDUndoJob {
    # $Selection: list of @{ RunId = '...'; Items = @('id', ...) or @('*') }
    param([object[]]$Selection)
    $root = Join-Path (Get-HDDataRoot) 'undo'
    [void][IO.Directory]::CreateDirectory($root)
    $id = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $root $id
    $n = 2
    while (Test-Path -LiteralPath $dir) { $dir = Join-Path $root "$id-$n"; $n++ }
    [void][IO.Directory]::CreateDirectory($dir)
    $job = [ordered]@{ JobId = (Split-Path $dir -Leaf); CreatedAt = (Get-Date).ToString('s')
                       Runs = [object[]]@($Selection | ForEach-Object { [ordered]@{ RunId = $_.RunId; Items = [object[]]@($_.Items) } }) }
    Save-HDJson -Path (Join-Path $dir 'plan.json') -Object $job
    return $dir
}

function Test-HDUndoNeedsAdmin {
    param([object[]]$Selection)
    foreach ($s in $Selection) {
        $res = Read-HDSideResults (Join-Path (Get-HDRunsRoot) $s.RunId) 'Machine'
        if (-not $res) { continue }
        foreach ($i in @($res.Items)) {
            if (@($s.Items) -notcontains '*' -and @($s.Items) -notcontains $i.Id) { continue }
            if (@($i.Units) | Where-Object { $_ -and $_.Attempted }) { return $true }
        }
    }
    return $false
}

function Get-HDUndoJobResult {
    # Per item results of one undo job, read back from the runs it touched.
    param([string]$JobDir)
    $job = Read-HDJson (Join-Path $JobDir 'plan.json')
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($job.Runs)) {
        $runDir = Join-Path (Get-HDRunsRoot) $s.RunId
        $m = Update-HDManifest $runDir
        if (-not $m) { continue }
        foreach ($i in @($m.Items)) {
            if (@($s.Items) -notcontains '*' -and @($s.Items) -notcontains $i.Id) { continue }
            $units = @($i.Units | Where-Object { $_.Undo -and $_.Undo.JobId -eq $job.JobId })
            if (-not $units.Count) { continue }
            $fake = @($units | ForEach-Object { [ordered]@{ Label = $_.Label; Result = $_.Undo.Result; Reason = $_.Undo.Reason } })
            $r = Get-HDItemResult -Units $fake
            $out.Add([ordered]@{ RunId = $s.RunId; Id = $i.Id; Title = $i.Title; Result = $r.Result; Reasons = $r.Reasons
                                 Links = [object[]]@($units | Where-Object { $_.Undo.Link } | ForEach-Object { $_.Undo.Link })
                                 Restart = [bool]($units | Where-Object { $_.Undo.Restart }) })
        }
    }
    return $out.ToArray()
}

function Invoke-HDUndoHeadless {
    param([object[]]$Selection, [scriptblock]$Log = { param($m) Write-Host $m })
    $jobDir = New-HDUndoJob $Selection
    $jobId = Split-Path $jobDir -Leaf
    if (Test-HDUndoNeedsAdmin $Selection) {
        $proc = Start-HDWorker @{ Mode = 'Undo'; JobDir = $jobDir; Lang = $script:HDLang }
        if ($proc) {
            $last = ''
            while (-not (Test-HDProcessExited $proc)) {
                Start-Sleep -Milliseconds 400
                $s = $null; try { $s = Read-HDJson (Join-Path $jobDir 'status.json') } catch {}
                if ($s) { $line = '{0} {1}' -f $s.Phase, $s.Text; if ($line -ne $last) { & $Log ('  [admin] ' + $line); $last = $line } }
            }
        } else { & $Log ('  ' + (T 'reason.noadmin')) }
    }
    foreach ($s in $Selection) {
        $null = Invoke-HDUndoSide -RunDir (Join-Path (Get-HDRunsRoot) $s.RunId) -Side 'User' -ItemIds @($s.Items) -JobId $jobId `
            -Progress { param($p) if ($p.Text) { & $Log ('  [user] ' + $p.Text) } }
    }
    return (Get-HDUndoJobResult $jobDir)
}
