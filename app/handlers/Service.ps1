# Handler: one Windows service.
#   Backup  start mode (registry Start + DelayedAutostart) and whether it was running
#   Apply   start mode Disabled (through the service manager), then stop it
#   Undo    old start mode back, start it again if it was running

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

function Set-HDServiceStart {
    # Goes through the service manager (sc.exe config) so the change is live, not only after a reboot.
    # Falls back to the registry for services whose security descriptor refuses the change.
    param([string]$Name, [int]$Start, $Delayed)
    $mode = switch ($Start) { 0 { 'boot' } 1 { 'system' } 2 { if ($Delayed -eq 1) { 'delayed-auto' } else { 'auto' } } 3 { 'demand' } default { 'disabled' } }
    $out = & sc.exe config "$Name" start= $mode 2>&1
    if ($LASTEXITCODE -eq 0) { return $false }
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try {
        Set-HDRegState -Path $key -Name 'Start' -Data $Start -Kind 'DWord'
        if ($null -ne $Delayed) { Set-HDRegState -Path $key -Name 'DelayedAutostart' -Data $Delayed -Kind 'DWord' }
    } catch {
        throw ("sc.exe: {0} / registry: {1}" -f (($out | Out-String).Trim()), $_.Exception.Message)
    }
    return $true   # written to the registry only: active after restart
}

$script:HDHandlers['Service'] = @{
    Side = { param($t) 'Machine' }

    Expand = {
        param($t)
        if (Get-Service -Name $t.Name -ErrorAction SilentlyContinue) {
            @{ Type = 'Service'; Key = "Service:$($t.Name)"; Label = "Service $($t.Name)"; Name = $t.Name }
        }
    }

    Read = {
        param($u)
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($u.Name)"
        $start = Get-HDRegState -Path $key -Name 'Start'
        $delayed = Get-HDRegState -Path $key -Name 'DelayedAutostart'
        $svc = Get-Service -Name $u.Name -ErrorAction SilentlyContinue
        [ordered]@{
            Exists  = [bool]$svc
            Start   = if ($start.Exists) { [int]$start.Data } else { $null }
            Delayed = if ($delayed.Exists) { [int]$delayed.Data } else { $null }
            Status  = if ($svc) { [string]$svc.Status } else { $null }
        }
    }

    IsDone = { param($u, $s) $s.Exists -and $s.Start -eq 4 }

    Backup = { param($u, $before, $dir) $null }

    Apply = {
        param($u, $before, $backup, $dir)
        $restart = Set-HDServiceStart -Name $u.Name -Start 4 -Delayed $null
        $svc = Get-Service -Name $u.Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') {
            try {
                Stop-Service -Name $u.Name -Force -NoWait -ErrorAction Stop
                $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            } catch { $restart = $true }
        }
        if ($restart) { return @{ Restart = $true } }
    }

    Undo = {
        param($u, $before, $backup, $dir)
        if ($null -eq $before.Start) { throw "No recorded start mode for $($u.Name)" }
        $restart = Set-HDServiceStart -Name $u.Name -Start ([int]$before.Start) -Delayed $before.Delayed
        if ($before.Status -eq 'Running') {
            try { Start-Service -Name $u.Name -ErrorAction Stop } catch { $restart = $true }
        }
        if ($restart) { return @{ Restart = $true } }
    }

    IsRestored = {
        param($u, $before, $now)
        if ($now.Start -ne $before.Start) { return $false }
        if ($before.Start -eq 2) { return ([int]$now.Delayed -eq [int]$before.Delayed) }
        return $true
    }
}
