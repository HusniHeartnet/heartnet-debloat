# Handler: one startup entry (Run key or Startup folder), switched off the same way Task Manager does it.
#   Backup  old StartupApproved bytes (or "no value")
#   Apply   StartupApproved = 03 00 00 00 + time stamp. The Run value / shortcut itself is NOT removed.
#   Undo    old bytes back, or delete the StartupApproved value if there was none

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

$script:HDHandlers['Startup'] = @{
    Side = { param($t) if ($t.Entry.Scope -eq 'User') { 'User' } else { 'Machine' } }

    Expand = {
        param($t)
        $e = $t.Entry
        @{ Type = 'Startup'; Key = "Startup:$($e.ApprovedPath)\$($e.Name)"; Label = "$($e.Source): $($e.Name)"
           Name = $e.Name; ApprovedPath = $e.ApprovedPath; Source = $e.Source; Command = $e.Command; Scope = $e.Scope }
    }

    Read = { param($u) Get-HDRegState -Path $u.ApprovedPath -Name $u.Name }

    IsDone = {
        param($u, $s)
        if (-not $s.Exists -or $s.Kind -ne 'Binary' -or -not $s.Data) { return $false }
        $first = [Convert]::ToByte((([string]$s.Data) -split ' ')[0], 16)
        return (($first -band 1) -eq 1)
    }

    Backup = { param($u, $before, $dir) @{ Export = (Export-HDRegKey -Path $u.ApprovedPath -Dir $dir) } }

    Apply = {
        param($u, $before, $backup, $dir)
        $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()))
        $hex = ($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
        Set-HDRegState -Path $u.ApprovedPath -Name $u.Name -Data $hex -Kind 'Binary'
    }

    Undo = {
        param($u, $before, $backup, $dir)
        if ($before.Exists) { Set-HDRegState -Path $u.ApprovedPath -Name $u.Name -Data $before.Data -Kind $before.Kind }
        else { Remove-HDRegValue -Path $u.ApprovedPath -Name $u.Name }
    }

    IsRestored = {
        param($u, $before, $now)
        if (-not $before.Exists) { return (-not $now.Exists) }
        return ($now.Exists -and (Test-HDRegDataEqual $now.Data $before.Data))
    }
}
