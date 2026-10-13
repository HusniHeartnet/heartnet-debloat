# Handler: one Store/built-in app (Appx), current user only.
#   Backup  package full name, family name (= Store id), version, install folder
#   Apply   Remove-AppxPackage for this user (not deprovisioned, other users keep it)
#   Undo    Add-AppxPackage -Register from the install folder while Windows still has the files
#           (always the case for apps that are provisioned for new users). Otherwise: Store link.

if (-not $script:HDHandlers) { $script:HDHandlers = @{} }

$script:HDHandlers['Appx'] = @{
    Side = { param($t) 'User' }

    Expand = {
        param($t)
        if (Get-AppxPackage -Name $t.Name -ErrorAction SilentlyContinue) {
            @{ Type = 'Appx'; Key = "Appx:$($t.Name)"; Label = "App $($t.Name)"; Name = $t.Name }
        }
    }

    Read = {
        param($u)
        $pk = @(Get-AppxPackage -Name $u.Name -ErrorAction SilentlyContinue | ForEach-Object {
                [ordered]@{ FullName = $_.PackageFullName; Family = $_.PackageFamilyName; Version = [string]$_.Version; Location = $_.InstallLocation }
            })
        [ordered]@{ Installed = ($pk.Count -gt 0); Packages = [object[]]$pk }
    }

    IsDone = { param($u, $s) -not $s.Installed }

    Backup = { param($u, $before, $dir) $null }

    Apply = {
        param($u, $before, $backup, $dir)
        foreach ($p in @($before.Packages)) { Remove-AppxPackage -Package $p.FullName -ErrorAction Stop }
    }

    Undo = {
        param($u, $before, $backup, $dir)
        if (Get-AppxPackage -Name $u.Name -ErrorAction SilentlyContinue) { return }
        $family = $null
        foreach ($p in @($before.Packages)) {
            $family = $p.Family
            $manifest = if ($p.Location) { Join-Path $p.Location 'AppxManifest.xml' } else { $null }
            if ($manifest -and (Test-Path -LiteralPath $manifest)) {
                Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
            }
        }
        if (-not (Get-AppxPackage -Name $u.Name -ErrorAction SilentlyContinue)) {
            return @{ Manual = (T 'reason.manual.appx' $u.Name); Link = "ms-windows-store://pdp/?PFN=$family" }
        }
    }

    IsRestored = { param($u, $before, $now) [bool]$now.Installed }
}
