# Before/after measurements: what is running in the background and how much RAM/CPU it uses.
# Read-only. Numbers are measured the same way every time and saved in run.json, so a run can be
# compared right after cleaning up and again later (after a restart, which is when the effect shows).
# RAM and CPU move by themselves from minute to minute; process/service/startup/task counts do not.

function Get-HDMetrics {
    param([int]$Samples = 5)
    $ram = New-Object System.Collections.Generic.List[double]
    $cpu = New-Object System.Collections.Generic.List[double]
    $os = $null
    for ($i = 0; $i -lt $Samples; $i++) {
        if ($i) { Start-Sleep -Seconds 1 }
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $ram.Add(([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1024)
        } catch {}
        try {
            $load = @(Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object { [double]$_.LoadPercentage })
            if ($load.Count) { $cpu.Add(($load | Measure-Object -Average).Average) }
        } catch {}
    }
    $avg = { param($l) if ($l.Count) { [math]::Round((($l | Measure-Object -Average).Average), 1) } else { $null } }
    $commit = $null
    try { $commit = [math]::Round(([double]$os.TotalVirtualMemorySize - [double]$os.FreeVirtualMemory) / 1024) } catch {}
    [ordered]@{
        At              = (Get-Date).ToString('s')
        UptimeMin       = if ($os) { [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes } else { $null }
        RamTotalMB      = if ($os) { [int]([double]$os.TotalVisibleMemorySize / 1024) } else { $null }
        RamUsedMB       = [int](& $avg $ram)
        CommitMB        = $commit
        CpuPct          = & $avg $cpu
        Processes       = @(Get-Process -ErrorAction SilentlyContinue).Count
        ServicesRunning = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count
        StartupEnabled  = @(Get-HDStartupEntries | Where-Object { -not $_.Disabled }).Count
        TasksActive     = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { [string]$_.State -ne 'Disabled' }).Count
        Elevated        = (Test-HDElevated)
    }
}

# Rows for display: label, value A, value B, difference (B - A). Lower is better for all of them.
function Get-HDMetricRows {
    param($A, $B)
    $defs = @(
        @{ Key = 'RamUsedMB';       Unit = 'MB' }
        @{ Key = 'CommitMB';        Unit = 'MB' }
        @{ Key = 'CpuPct';          Unit = '%' }
        @{ Key = 'Processes';       Unit = '' }
        @{ Key = 'ServicesRunning'; Unit = '' }
        @{ Key = 'StartupEnabled';  Unit = '' }
        @{ Key = 'TasksActive';     Unit = '' }
    )
    foreach ($d in $defs) {
        $va = if ($A) { $A.($d.Key) } else { $null }
        $vb = if ($B) { $B.($d.Key) } else { $null }
        if ($null -eq $va -and $null -eq $vb) { continue }
        $fmt = {
            param($v)
            if ($null -eq $v) { '-' } elseif ($d.Unit -eq '%') { '{0:0.0} %' -f [double]$v } elseif ($d.Unit) { '{0:N0} {1}' -f [double]$v, $d.Unit } else { '{0:N0}' -f [double]$v }
        }
        $delta = ''
        if ($null -ne $va -and $null -ne $vb) {
            $x = [double]$vb - [double]$va
            $num = if ($d.Unit -eq '%') { '{0:+0.0;-0.0;0}' -f $x } else { '{0:+#,0;-#,0;0}' -f $x }
            $delta = $num + $(if ($d.Unit -and $x -ne 0) { ' ' + $d.Unit } else { '' })
        }
        [ordered]@{ Key = $d.Key; Label = (T "metric.$($d.Key)"); A = (& $fmt $va); B = (& $fmt $vb); Delta = $delta; Better = ($null -ne $va -and $null -ne $vb -and [double]$vb -lt [double]$va) }
    }
}
