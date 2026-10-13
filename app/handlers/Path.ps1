# Handler: a leftover file or folder. Never deleted: it is MOVED into the run folder.
#   Backup  original path; the moved copy itself is the backup (<side>\files\<n>)
#   Apply   move into the backup folder
#   Undo    move back (refused if something new already exists at the original path)

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

function Move-HDItem {
    param([string]$From, [string]$To)
    [void][IO.Directory]::CreateDirectory((Split-Path $To -Parent))
    if ([IO.Path]::GetPathRoot($From) -ieq [IO.Path]::GetPathRoot($To)) {
        Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop
    } else {
        # Different drive: copy, then remove the original only after the copy succeeded.
        Copy-Item -LiteralPath $From -Destination $To -Recurse -Force -ErrorAction Stop
        Remove-Item -LiteralPath $From -Recurse -Force -ErrorAction Stop
    }
}

$script:HDHandlers['Path'] = @{
    Side = {
        param($t)
        $p = [Environment]::ExpandEnvironmentVariables($t.Path)
        if ($p.StartsWith($env:USERPROFILE + '\', [StringComparison]::OrdinalIgnoreCase)) { 'User' } else { 'Machine' }
    }

    Expand = {
        param($t)
        $p = [Environment]::ExpandEnvironmentVariables($t.Path)
        if (Test-Path -LiteralPath $p) { @{ Type = 'Path'; Key = "Path:$p"; Label = $p; Path = $p; Mode = 'Move' } }
    }

    Read = { param($u) [ordered]@{ Exists = (Test-Path -LiteralPath $u.Path) } }

    IsDone = { param($u, $s) -not $s.Exists }

    Backup = {
        param($u, $before, $dir)
        $n = 1
        do { $rel = 'files\{0}\{1}' -f $n, (Split-Path $u.Path -Leaf); $n++ } while (Test-Path -LiteralPath (Join-Path $dir $rel))
        @{ Moved = $rel }
    }

    Apply = { param($u, $before, $backup, $dir) Move-HDItem -From $u.Path -To (Join-Path $dir $backup.Moved) }

    Undo = {
        param($u, $before, $backup, $dir)
        if (Test-Path -LiteralPath $u.Path) { throw (T 'reason.pathexists' $u.Path) }
        Move-HDItem -From (Join-Path $dir $backup.Moved) -To $u.Path
    }

    IsRestored = { param($u, $before, $now) [bool]$now.Exists }
}
