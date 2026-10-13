# Apply engine: plan -> backup -> apply -> verify, one side (User or Machine) at a time.
#
# Privilege split (docs/DESIGN.md section 4):
#   User side    HKCU values, Appx, HKCU startup. Runs in the normal, non-elevated UI process, so it
#                changes the account of the person at the PC (not the account of whoever typed the
#                admin password).
#   Machine side HKLM values, services, tasks, devices, programs, HKLM startup, ProgramData leftovers.
#                Runs in app\Worker.ps1 (elevated, one UAC prompt). The worker only takes item ids
#                from plan.json and rebuilds every target from the catalog and its own scan.
#
# Each catalog target is expanded by its handler (app\handlers) into concrete units. For every unit:
#   Before = Read  ->  already done? skip  ->  Backup  ->  (results saved)  ->  Apply  ->  After = Read
#   -> success only if IsDone(After), i.e. the same detection as the scan confirms the change.

$script:HDUnitResults = 'Success', 'Skipped', 'Failed'

function Get-HDHandler {
    param([string]$Type)
    $h = $script:HDHandlers[$Type]
    if (-not $h) { throw "No handler for target type '$Type'" }
    return $h
}

function Get-HDTargetSide {
    param($Target)
    return [string](& (Get-HDHandler $Target.T).Side $Target)
}

function Get-HDItemSides {
    param($Item)
    return @($Item.Targets | ForEach-Object { Get-HDTargetSide $_ } | Sort-Object -Unique)
}

function Test-HDItemPolicy {
    param($Item)
    return [bool](@($Item.Targets) | Where-Object { $_.T -eq 'Reg' -and $_.Path -like '*\Policies\*' })
}

function Get-HDCurrentSid { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }

function Test-HDElevated {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================== plan

function New-HDRun {
    param($Scan, [string[]]$Ids)
    $items = @($Scan.Items | Where-Object { $Ids -contains $_.Id -and $_.Selectable })
    if (-not $items.Count) { throw 'Nothing selected.' }
    $dir = New-HDRunDir
    $plan = [ordered]@{
        App       = 'Heartnet Debloat'
        Version   = $Scan.Version
        RunId     = (Split-Path $dir -Leaf)
        CreatedAt = (Get-Date).ToString('s')
        Lang      = $script:HDLang
        User      = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
        UserSid   = Get-HDCurrentSid
        Machine   = $Scan.Machine
        Items     = [object[]]@(foreach ($i in $items) {
                [ordered]@{
                    Id = $i.Id; Title = $i.Title; Category = $i.Category; Risk = $i.Risk
                    Sides = [object[]]@(Get-HDItemSides $i); Policy = (Test-HDItemPolicy $i)
                    Notes = [object[]]@($i.Notes); Warnings = [object[]]@($i.Warnings)
                }
            })
    }
    Save-HDJson -Path (Join-Path $dir 'plan.json') -Object $plan
    return $dir
}

# Matches plan ids with a fresh scan. Returns @{ Items = items to run; Refused = @{ id = reason } }.
function Select-HDPlanItems {
    param($Scan, $Plan, [string]$Side)
    $run = New-Object System.Collections.Generic.List[object]
    $refused = [ordered]@{}
    foreach ($p in @($Plan.Items)) {
        if (@($p.Sides) -notcontains $Side) { continue }
        $id = [string]$p.Id
        if ($id -notmatch '^[A-Za-z0-9._-]+$') { continue }
        $i = @($Scan.Items | Where-Object { $_.Id -eq $id }) | Select-Object -First 1
        if (-not $i) { $refused[$id] = T 'reason.gone'; continue }
        if ($i.Kind -ne 'Action') { $refused[$id] = T 'reason.notaction'; continue }
        if ($i.State -eq 'Blocked') { $refused[$id] = T 'reason.blocked' (@($i.Warnings) -join ' '); continue }
        $run.Add($i)
    }
    return @{ Items = $run.ToArray(); Refused = $refused }
}

# ============================================================== one side

function Invoke-HDApplySide {
    param(
        [string]$RunDir,
        [ValidateSet('User', 'Machine')][string]$Side,
        [object[]]$Items,
        $Refused = @{},
        [string]$RefuseAll,          # reason to skip everything (e.g. elevated as another account)
        $Header = @{},
        [scriptblock]$Progress = {}
    )
    $dir = Join-Path $RunDir $Side.ToLower()
    [void][IO.Directory]::CreateDirectory($dir)
    $file = Join-Path $dir 'results.json'
    $results = [ordered]@{
        Side = $Side; Account = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME); Sid = (Get-HDCurrentSid); Elevated = (Test-HDElevated)
        StartedAt = (Get-Date).ToString('s'); FinishedAt = $null
        Items = New-Object System.Collections.ArrayList
    }
    foreach ($k in $Header.Keys) { $results[$k] = $Header[$k] }
    $save = { Save-HDJson -Path $file -Object $results }

    foreach ($id in $Refused.Keys) { [void]$results.Items.Add([ordered]@{ Id = $id; Title = $id; Refused = $Refused[$id]; Units = [object[]]@() }) }

    $n = 0
    foreach ($item in $Items) {
        $n++
        & $Progress @{ Done = $n - 1; Total = $Items.Count; Text = $item.Title }
        $entry = [ordered]@{ Id = $item.Id; Title = $item.Title; Refused = $null; Units = New-Object System.Collections.ArrayList }
        [void]$results.Items.Add($entry)
        if ($RefuseAll) { $entry.Refused = $RefuseAll; & $save; continue }

        foreach ($t in @($item.Targets)) {
            if ((Get-HDTargetSide $t) -ne $Side) { continue }
            $h = Get-HDHandler $t.T
            $units = @()
            try { $units = @(& $h.Expand $t | Where-Object { $_ }) }
            catch { [void]$entry.Units.Add([ordered]@{ Key = "$($t.T):?"; Type = $t.T; Label = $t.T; Result = 'Failed'; Reason = (T 'reason.error' $_.Exception.Message) }); continue }

            foreach ($unit in $units) {
                $u = [ordered]@{ Key = $unit.Key; Type = $unit.Type; Label = $unit.Label; Spec = $unit; Before = $null; Backup = $null
                                 After = $null; Attempted = $false; Result = 'Pending'; Reason = ''; Restart = $false }
                [void]$entry.Units.Add($u)
                $why = Test-HDUnitAllowed $unit
                if ($why) { $u.Result = 'Failed'; $u.Reason = $why; continue }
                try {
                    $u.Before = & $h.Read $unit
                    if (& $h.IsDone $unit $u.Before) { $u.Result = 'Skipped'; $u.Reason = T 'reason.already'; continue }
                    $u.Backup = & $h.Backup $unit $u.Before $dir
                    $u.Attempted = $true
                    & $save                      # the backup is on disk before anything changes
                    $out = & $h.Apply $unit $u.Before $u.Backup $dir
                    if ($out -and $out.Restart) { $u.Restart = $true }
                    $u.After = & $h.Read $unit
                    if (& $h.IsDone $unit $u.After) { $u.Result = 'Success' }
                    elseif ($u.Restart) { $u.Result = 'Success'; $u.Reason = T 'reason.restart' }
                    else { $u.Result = 'Failed'; $u.Reason = T 'reason.verify' }
                } catch {
                    $u.Result = 'Failed'; $u.Reason = T 'reason.error' $_.Exception.Message
                    if ($u.Attempted) { try { $u.After = & $h.Read $unit } catch {} }
                }
                & $save
            }
        }
        & $save
    }
    $results.FinishedAt = (Get-Date).ToString('s')
    & $save
    & $Progress @{ Done = $Items.Count; Total = $Items.Count; Text = '' }
    return $results
}

# ============================================================== elevated worker

function Get-HDWorkerArgs {
    param([hashtable]$Params)
    $worker = Join-Path (Split-Path $PSScriptRoot) 'Worker.ps1'
    $a = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $worker
    foreach ($k in $Params.Keys) { $a += ' -{0} "{1}"' -f $k, $Params[$k] }
    return $a
}

# Starts app\Worker.ps1 elevated. Returns the process, or $null when the UAC prompt was declined.
function Start-HDWorker {
    param([hashtable]$Params)
    $sp = @{ FilePath = 'powershell.exe'; ArgumentList = (Get-HDWorkerArgs $Params); PassThru = $true; WindowStyle = 'Hidden' }
    if (-not (Test-HDElevated)) { $sp.Verb = 'RunAs' }
    try { return (Start-Process @sp -ErrorAction Stop) } catch { return $null }
}

function Test-HDProcessExited {
    param($Process)
    try { return $Process.HasExited } catch { return $false }
}

function Set-HDConsent {
    param([string]$RunDir, [int]$Ask, [ValidateSet('Enable', 'Continue', 'Cancel')][string]$Choice)
    Save-HDJson -Path (Join-Path $RunDir 'consent.json') -Object ([ordered]@{ Ask = $Ask; Choice = $Choice; At = (Get-Date).ToString('s') })
}

function Save-HDRunState {
    param([string]$RunDir, [hashtable]$Values)
    $file = Join-Path $RunDir 'run.json'
    $cur = [ordered]@{}
    $old = Read-HDJson $file
    if ($old) { foreach ($p in $old.PSObject.Properties) { $cur[$p.Name] = $p.Value } }
    foreach ($k in $Values.Keys) { $cur[$k] = $Values[$k] }
    Save-HDJson -Path $file -Object $cur
}

# ============================================================== headless (CLI, also used for VM tests)

function Invoke-HDRunHeadless {
    # Same split as the UI: user side here, machine side in the elevated worker.
    param($Scan, [string[]]$Ids, [switch]$AllowNoRestorePoint, [scriptblock]$Log = { param($m) Write-Host $m })
    $dir = New-HDRun -Scan $Scan -Ids $Ids
    & $Log (T 'cli.run.dir' $dir)
    & $Log ('  ' + (T 'metrics.before'))
    Save-HDRunState $dir @{ MetricsBefore = (Get-HDMetrics) }
    $plan = Read-HDJson (Join-Path $dir 'plan.json')
    $proc = Start-HDWorker @{ Mode = 'Apply'; RunDir = $dir; Lang = $script:HDLang }
    $workerState = 'Cancelled'
    if ($proc) {
        $status = Join-Path $dir 'machine\status.json'
        $answered = 0; $last = ''
        while (-not (Test-HDProcessExited $proc)) {
            Start-Sleep -Milliseconds 400
            $s = $null; try { $s = Read-HDJson $status } catch {}
            if (-not $s) { continue }
            $line = '{0} {1}' -f $s.Phase, $s.Text
            if ($line -ne $last) { & $Log ('  [admin] ' + $line); $last = $line }
            if ($s.Phase -eq 'NeedConsent' -and [int]$s.Ask -gt $answered) {
                $answered = [int]$s.Ask
                & $Log ('  ' + (T 'rp.failed' $s.RestorePoint.Reason))
                $choice = if ($AllowNoRestorePoint) { 'Continue' } else { 'Cancel' }
                if (-not $AllowNoRestorePoint -and [Environment]::UserInteractive) {
                    $ans = Read-Host (T 'cli.rp.ask')
                    if ($ans -match '^(y|ya)$') { $choice = 'Continue' }
                }
                Set-HDConsent -RunDir $dir -Ask $answered -Choice $choice
            }
        }
        $s = Read-HDJson $status
        $workerState = switch ($s.Phase) { 'Done' { 'Done' } 'Cancelled' { 'Declined' } default { 'Failed' } }
        if ($workerState -eq 'Failed') { & $Log ('  [admin] ' + $s.Text) }
    }
    Save-HDRunState $dir @{ Worker = $workerState }
    if ($workerState -eq 'Declined' -or ($workerState -eq 'Cancelled' -and -not $AllowNoRestorePoint)) {
        Save-HDRunState $dir @{ UserSide = 'NotRun'; FinishedAt = (Get-Date).ToString('s') }
        return (Update-HDManifest $dir)
    }
    $fresh = Invoke-HDScan
    $sel = Select-HDPlanItems -Scan $fresh -Plan $plan -Side 'User'
    $refuse = if ($fresh.OtherUser) { T 'reason.otheruser' @($fresh.OtherUser.Me, $fresh.OtherUser.Desktop) } else { '' }
    $null = Invoke-HDApplySide -RunDir $dir -Side 'User' -Items $sel.Items -Refused $sel.Refused -RefuseAll $refuse `
        -Progress { param($p) if ($p.Text) { & $Log ('  [user] ' + $p.Text) } }
    & $Log ('  ' + (T 'metrics.after'))
    Save-HDRunState $dir @{ UserSide = 'Done'; FinishedAt = (Get-Date).ToString('s'); MetricsAfter = (Get-HDMetrics) }
    return (Update-HDManifest $dir)
}
