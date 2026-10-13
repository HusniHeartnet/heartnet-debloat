# Handler: one scheduled task.
#   Backup  Export-ScheduledTask XML (machine\tasks\) + old state
#   Apply   Mode 'Disable' (built-in tasks): disable.  Mode 'Remove' (leftovers): unregister.
#   Undo    enable again / register again from the exported XML

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

$script:HDHandlers['Task'] = @{
    Side = { param($t) 'Machine' }

    Expand = {
        param($t)
        $mode = if ($t.Mode) { [string]$t.Mode } else { 'Disable' }
        # Same matching as the scan: Path is a folder prefix, Name is exact.
        foreach ($x in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
                    ((-not $t.Path) -or $_.TaskPath.StartsWith($t.Path, [StringComparison]::OrdinalIgnoreCase)) -and
                    ((-not $t.Name) -or $_.TaskName -ieq $t.Name) })) {
            @{ Type = 'Task'; Key = "Task:$($x.TaskPath)$($x.TaskName)"; Label = "Task $($x.TaskPath)$($x.TaskName)"
               TaskPath = $x.TaskPath; TaskName = $x.TaskName; Mode = $mode }
        }
    }

    Read = {
        param($u)
        $x = Get-ScheduledTask -TaskPath $u.TaskPath -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -eq $u.TaskName } | Select-Object -First 1
        [ordered]@{ Exists = [bool]$x; State = if ($x) { [string]$x.State } else { $null } }
    }

    IsDone = {
        param($u, $s)
        if ($u.Mode -eq 'Remove') { return (-not $s.Exists) }
        return ($s.Exists -and $s.State -eq 'Disabled')
    }

    Backup = {
        param($u, $before, $dir)
        $tdir = Join-Path $dir 'tasks'
        [void][IO.Directory]::CreateDirectory($tdir)
        $name = (Get-HDSafeName ($u.TaskPath + $u.TaskName) 150) + '.xml'
        try {
            $xml = Export-ScheduledTask -TaskPath $u.TaskPath -TaskName $u.TaskName -ErrorAction Stop
            [IO.File]::WriteAllText((Join-Path $tdir $name), $xml, (New-Object System.Text.UnicodeEncoding $false, $true))
            return @{ Xml = "tasks\$name" }
        } catch {
            # Without the XML a removed task cannot come back, so removing is not allowed then.
            if ($u.Mode -eq 'Remove') { throw }
            return @{ Xml = $null; ExportError = $_.Exception.Message }
        }
    }

    Apply = {
        param($u, $before, $backup, $dir)
        if ($u.Mode -eq 'Remove') {
            Unregister-ScheduledTask -TaskPath $u.TaskPath -TaskName $u.TaskName -Confirm:$false -ErrorAction Stop
        } else {
            $null = Disable-ScheduledTask -TaskPath $u.TaskPath -TaskName $u.TaskName -ErrorAction Stop
        }
    }

    Undo = {
        param($u, $before, $backup, $dir)
        $now = Get-ScheduledTask -TaskPath $u.TaskPath -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -eq $u.TaskName } | Select-Object -First 1
        if (-not $now) {
            if (-not $backup.Xml) { throw "No exported XML for $($u.TaskPath)$($u.TaskName)" }
            $xml = [IO.File]::ReadAllText((Join-Path $dir $backup.Xml))
            $null = Register-ScheduledTask -Xml $xml -TaskPath $u.TaskPath -TaskName $u.TaskName -ErrorAction Stop
            $now = Get-ScheduledTask -TaskPath $u.TaskPath -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -eq $u.TaskName } | Select-Object -First 1
        }
        if ($now -and $before.State -ne 'Disabled' -and [string]$now.State -eq 'Disabled') {
            $null = Enable-ScheduledTask -TaskPath $u.TaskPath -TaskName $u.TaskName -ErrorAction Stop
        }
    }

    IsRestored = {
        param($u, $before, $now)
        if (-not $now.Exists) { return $false }
        return (($before.State -eq 'Disabled') -eq ($now.State -eq 'Disabled'))
    }
}
