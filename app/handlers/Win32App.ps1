# Handler: one desktop program from Add/Remove Programs (exact DisplayName).
#   Backup  the ARP entry (name, version, uninstall command, installer type)
#   Apply   the program's own uninstaller: MSI /x /qb, Inno /SILENT, QuietUninstallString, otherwise
#           the normal (interactive) uninstaller, where the user may have to click through
#   Undo    not automatic: the program has to be installed again from the official site
# Never checked by default (catalog risk is Optional).

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

function Split-HDCommand {
    # "C:\x\unins000.exe" /foo  ->  @('C:\x\unins000.exe', '/foo')
    param([string]$Command)
    $c = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    $exe = Get-HDExePath $c
    $rest = ''
    if ($c.StartsWith('"')) { $rest = $c.Substring([Math]::Min($c.Length, $exe.Length + 2)) }
    elseif ($c.Length -gt $exe.Length) { $rest = $c.Substring($exe.Length) }
    return @($exe, $rest.Trim())
}

function Get-HDUninstallCommand {
    param($Entry)
    $u = [string]$Entry.UninstallString
    if ($Entry.InstallerType -eq 'MSI') {
        $code = [regex]::Match(($Entry.Key + ' ' + $u), '\{[0-9A-Fa-f-]{36}\}').Value
        if ($code) { return @("$env:SystemRoot\System32\msiexec.exe", "/x $code /qb /norestart") }
    }
    if ($Entry.InstallerType -eq 'Inno' -and $u) {
        $p = Split-HDCommand $u
        return @($p[0], ($p[1] + ' /SILENT /SUPPRESSMSGBOXES /NORESTART').Trim())
    }
    if ($Entry.QuietUninstallString) { return (Split-HDCommand $Entry.QuietUninstallString) }
    if ($u) { return (Split-HDCommand $u) }
    return $null
}

$script:HDHandlers['Win32App'] = @{
    Side = { param($t) 'Machine' }

    Expand = {
        param($t)
        if (Get-HDArpEntries | Where-Object { $_.DisplayName -ieq $t.DisplayName }) {
            @{ Type = 'Win32App'; Key = "Win32App:$($t.DisplayName)"; Label = "Program $($t.DisplayName)"; DisplayName = $t.DisplayName }
        }
    }

    Read = {
        param($u)
        $e = @(Get-HDArpEntries | Where-Object { $_.DisplayName -ieq $u.DisplayName } | ForEach-Object {
                [ordered]@{ DisplayName = $_.DisplayName; Version = $_.DisplayVersion; Publisher = $_.Publisher; InstallerType = $_.InstallerType
                            UninstallString = $_.UninstallString; QuietUninstallString = $_.QuietUninstallString; Key = $_.Key }
            })
        [ordered]@{ Installed = ($e.Count -gt 0); Entries = [object[]]$e }
    }

    IsDone = { param($u, $s) -not $s.Installed }

    Backup = { param($u, $before, $dir) $null }

    Apply = {
        param($u, $before, $backup, $dir)
        foreach ($e in @($before.Entries)) {
            $cmd = Get-HDUninstallCommand $e
            if (-not $cmd -or -not $cmd[0]) { throw "No uninstall command for $($e.DisplayName)" }
            $sp = @{ FilePath = $cmd[0]; Wait = $true; PassThru = $true }
            if ($cmd[1]) { $sp.ArgumentList = $cmd[1] }
            $proc = Start-Process @sp
            # Many uninstallers hand over to a copy of themselves and exit early: wait for the ARP entry.
            $until = (Get-Date).AddSeconds(120)
            while ((Get-Date) -lt $until -and (Get-HDArpEntries | Where-Object { $_.DisplayName -ieq $u.DisplayName })) { Start-Sleep -Seconds 2 }
            if ($proc.ExitCode -in 1641, 3010) { return @{ Restart = $true } }
        }
    }

    Undo = {
        param($u, $before, $backup, $dir)
        if (Get-HDArpEntries | Where-Object { $_.DisplayName -ieq $u.DisplayName }) { return }
        return @{ Manual = (T 'reason.manual.win32' $u.DisplayName); Link = $null }
    }

    IsRestored = { param($u, $before, $now) [bool]$now.Installed }
}
