# Handler: the Bluetooth radio device(s) only (not paired devices, not protocol enumerators).
#   Backup  InstanceId + status + problem code
#   Apply   Disable-PnpDevice on that InstanceId
#   Undo    Enable-PnpDevice if it was enabled before

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

$script:HDHandlers['BtRadio'] = @{
    Side = { param($t) 'Machine' }

    Expand = {
        param($t)
        # Same rule as the scan (core\Scan.ps1, Get-HDBluetooth): bus-enumerated devices of class Bluetooth.
        foreach ($d in @((Get-HDBluetooth).Radios)) {
            @{ Type = 'BtRadio'; Key = "BtRadio:$($d.InstanceId)"; Label = "Bluetooth $($d.FriendlyName)"
               InstanceId = $d.InstanceId; FriendlyName = $d.FriendlyName }
        }
    }

    Read = {
        param($u)
        $d = Get-PnpDevice -InstanceId $u.InstanceId -ErrorAction SilentlyContinue
        [ordered]@{ Exists = [bool]$d; Status = if ($d) { [string]$d.Status } else { $null }; Problem = if ($d) { [int]$d.ConfigManagerErrorCode } else { $null } }
    }

    IsDone = { param($u, $s) $s.Exists -and $s.Problem -eq 22 }

    Backup = { param($u, $before, $dir) $null }

    Apply = {
        param($u, $before, $backup, $dir)
        Disable-PnpDevice -InstanceId $u.InstanceId -Confirm:$false -ErrorAction Stop
    }

    Undo = {
        param($u, $before, $backup, $dir)
        if ($before.Problem -ne 22) { Enable-PnpDevice -InstanceId $u.InstanceId -Confirm:$false -ErrorAction Stop }
    }

    IsRestored = { param($u, $before, $now) $now.Exists -and (($now.Problem -eq 22) -eq ($before.Problem -eq 22)) }
}
