# Heartnet Debloat - elevated worker. Started by the UI (or -Cli) through one UAC prompt.
#   -Mode Apply -RunDir <runs\id>   restore point, then the machine-scope part of plan.json
#   -Mode Undo  -JobDir <undo\id>   undo the machine-scope part of the runs listed in the job
# It never touches per-user things (HKCU, Appx, HKCU startup): those belong to the account at the
# desktop and are done by the non-elevated UI process.
# plan.json is written by a non-admin process, so only item ids are taken from it. Targets come
# from this app's catalog and a fresh scan; backups are kept in machine\ (Administrators only).

param(
    [ValidateSet('Apply', 'Undo')][string]$Mode,
    [string]$RunDir,
    [string]$JobDir,
    [ValidateSet('id', 'en')][string]$Lang = 'id'
)

$ErrorActionPreference = 'Stop'
$AppDir = $PSScriptRoot
foreach ($f in 'Lang', 'Scan', 'Backup', 'Safety', 'Apply', 'Undo', 'Report', 'Metrics') { . (Join-Path $AppDir "core\$f.ps1") }
foreach ($f in Get-ChildItem (Join-Path $AppDir 'handlers') -Filter *.ps1) { . $f.FullName }
Initialize-HDLang $Lang

if (-not (Test-HDElevated)) { exit 2 }

$script:StatusFile = $null
$script:StatusAsk = 0
function Set-WorkerStatus {
    param([string]$Phase, [string]$Text = '', $Extra = @{})
    $o = [ordered]@{ Phase = $Phase; Text = $Text; Ask = $script:StatusAsk; At = (Get-Date).ToString('s'); Pid = $PID }
    foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] }
    Save-HDJson -Path $script:StatusFile -Object $o
}

function Wait-WorkerConsent {
    # Asks the UI (through status.json) and waits for consent.json with the same question number.
    param($RestorePoint)
    $script:StatusAsk++
    Set-WorkerStatus 'NeedConsent' $RestorePoint.Reason @{ RestorePoint = $RestorePoint }
    $file = Join-Path $RunDir 'consent.json'
    $until = (Get-Date).AddMinutes(30)
    while ((Get-Date) -lt $until) {
        Start-Sleep -Milliseconds 400
        $c = $null
        try { $c = Read-HDJson $file } catch {}
        if ($c -and [int]$c.Ask -eq $script:StatusAsk) { return [string]$c.Choice }
    }
    return 'Cancel'
}

# ------------------------------------------------------------------ apply
if ($Mode -eq 'Apply') {
    if (-not (Test-HDRunDirPath $RunDir)) { exit 3 }
    $RunDir = [IO.Path]::GetFullPath($RunDir)
    $mdir = Join-Path $RunDir 'machine'
    New-HDAdminDir $mdir
    $script:StatusFile = Join-Path $mdir 'status.json'
    try {
        $plan = Read-HDJson (Join-Path $RunDir 'plan.json')
        if (-not $plan) { throw 'plan.json missing' }

        # 1. restore point (before anything changes, user side included)
        Set-WorkerStatus 'RestorePoint' (T 'run.rp')
        $rp = New-HDRestorePoint -Description ('Heartnet Debloat ' + (Split-Path $RunDir -Leaf))
        while ($rp.Status -ne 'Created') {
            $choice = Wait-WorkerConsent $rp
            if ($choice -eq 'Enable' -and $rp.Status -eq 'Disabled') {
                Set-WorkerStatus 'RestorePoint' (T 'run.rp.enable')
                try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop } catch {}
                $rp = New-HDRestorePoint -Description ('Heartnet Debloat ' + (Split-Path $RunDir -Leaf))
                $rp.ProtectionEnabledByApp = $true
                continue
            }
            if ($choice -eq 'Continue') { $rp.Consent = 'ContinueWithout'; break }
            Save-HDJson -Path (Join-Path $mdir 'results.json') -Object ([ordered]@{
                    Side = 'Machine'; Cancelled = $true; RestorePoint = $rp; Items = [object[]]@() })
            Set-WorkerStatus 'Cancelled' (T 'reason.cancelled')
            exit 0
        }

        # 2. machine-scope items, re-derived from a fresh scan
        Set-WorkerStatus 'Scanning' (T 'run.rescan')
        $scan = Invoke-HDScan
        $sel = Select-HDPlanItems -Scan $scan -Plan $plan -Side 'Machine'
        $null = Invoke-HDApplySide -RunDir $RunDir -Side 'Machine' -Items $sel.Items -Refused $sel.Refused -Header @{ RestorePoint = $rp } `
            -Progress { param($p) Set-WorkerStatus 'Applying' $p.Text @{ Done = $p.Done; Total = $p.Total } }
        Set-WorkerStatus 'Done'
        exit 0
    } catch {
        $msg = $_.Exception.Message + ' ' + $_.ScriptStackTrace
        try { Add-Content -LiteralPath (Join-Path $mdir 'worker.log') -Value ((Get-Date).ToString('s') + ' ' + $msg) } catch {}
        Set-WorkerStatus 'Error' $_.Exception.Message
        exit 1
    }
}

# ------------------------------------------------------------------ undo
if ($Mode -eq 'Undo') {
    $root = [IO.Path]::GetFullPath((Join-Path (Get-HDDataRoot) 'undo')).TrimEnd('\')
    $JobDir = [IO.Path]::GetFullPath($JobDir).TrimEnd('\')
    if ((Split-Path $JobDir -Parent) -ine $root -or (Split-Path $JobDir -Leaf) -notmatch '^\d{8}-\d{6}(-\d+)?$') { exit 3 }
    $script:StatusFile = Join-Path $JobDir 'status.json'
    try {
        $job = Read-HDJson (Join-Path $JobDir 'plan.json')
        $jobId = Split-Path $JobDir -Leaf
        foreach ($s in @($job.Runs)) {
            $runDir = Join-Path (Get-HDRunsRoot) ([string]$s.RunId)
            if (-not (Test-HDRunDirPath $runDir)) { continue }
            $ids = @($s.Items | Where-Object { [string]$_ -match '^(\*|[A-Za-z0-9._-]+)$' })
            $null = Invoke-HDUndoSide -RunDir $runDir -Side 'Machine' -ItemIds $ids -JobId $jobId `
                -Progress { param($p) Set-WorkerStatus 'Undoing' $p.Text @{ Done = $p.Done; Total = $p.Total } }
        }
        Set-WorkerStatus 'Done'
        exit 0
    } catch {
        Set-WorkerStatus 'Error' ($_.Exception.Message + ' ' + $_.ScriptStackTrace)
        exit 1
    }
}
exit 4
