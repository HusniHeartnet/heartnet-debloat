# Handler: one registry value.
#   Backup  exact old state (key exists?, value exists?, kind, data) + reg export of the key
#   Apply   set the catalog value
#   Undo    write the old value back with its old kind, or delete it if it did not exist
#           (and delete the key too if this run created it and it is empty again)
#
# Every handler is a set of script blocks with the same parameters (see core\Apply.ps1):
#   Side($target)                      'User' | 'Machine' for a catalog target, before expansion
#   Expand($target)                    concrete units (hashtables with Type, Key, Label + own fields)
#   Read($unit)                        current state, JSON-safe
#   IsDone($unit, $state)              $true when the state already is what the catalog wants
#   Backup($unit, $before, $dir)       extra backup files, returns a hashtable (or $null)
#   Apply($unit, $before, $backup, $dir)   change it; may return @{ Restart = $true }
#   Undo($unit, $before, $backup, $dir)    restore $before; may return @{ Manual = text; Link = url }
#   IsRestored($unit, $before, $now)   $true when $now matches $before again

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

$script:HDHandlers['Reg'] = @{
    Side = { param($t) if ($t.Path -like 'HKCU:*') { 'User' } else { 'Machine' } }

    Expand = {
        param($t)
        $short = $t.Path -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\'
        @{ Type = 'Reg'; Key = "Reg:$($t.Path)\$($t.Name)"; Label = "$short\$($t.Name)"
           Path = $t.Path; Name = $t.Name; Value = $t.Value; Kind = $t.Kind }
    }

    Read = { param($u) Get-HDRegState -Path $u.Path -Name $u.Name }

    IsDone = { param($u, $s) $s.Exists -and ([string]$s.Data -eq [string]$u.Value) }

    Backup = { param($u, $before, $dir) @{ Export = (Export-HDRegKey -Path $u.Path -Dir $dir) } }

    Apply = {
        param($u, $before, $backup, $dir)
        Set-HDRegState -Path $u.Path -Name $u.Name -Data $u.Value -Kind $u.Kind
        # Service start values are read by the service manager at boot.
        if ($u.Path -match '\\CurrentControlSet\\Services\\') { return @{ Restart = $true } }
    }

    Undo = {
        param($u, $before, $backup, $dir)
        if ($before.Exists) {
            Set-HDRegState -Path $u.Path -Name $u.Name -Data $before.Data -Kind $before.Kind
        } else {
            Remove-HDRegValue -Path $u.Path -Name $u.Name -RemoveKeyIfEmpty:(-not $before.KeyExists)
        }
        if ($u.Path -match '\\CurrentControlSet\\Services\\') { return @{ Restart = $true } }
    }

    IsRestored = {
        param($u, $before, $now)
        if (-not $before.Exists) { return (-not $now.Exists) }
        return ($now.Exists -and $now.Kind -eq $before.Kind -and (Test-HDRegDataEqual $now.Data $before.Data))
    }
}
