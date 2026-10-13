# Last line of defence before any change: every concrete unit (one service, one task, one registry
# value, ...) is checked against catalog\protected.psd1 right before it is applied or undone.
# tests\Test-Catalog.ps1 already checks the catalog statically; this catches anything that slips
# through at run time (dynamic startup entries, task folders that expand to more tasks, edited files).

function Get-HDProtected {
    if (-not $script:HDProtected) {
        $script:HDProtected = Import-PowerShellDataFile (Join-Path (Split-Path $PSScriptRoot) 'catalog\protected.psd1')
    }
    return $script:HDProtected
}

# Returns $null when the unit may be changed, otherwise the reason (text) why not.
function Test-HDUnitAllowed {
    param($Unit)
    $p = Get-HDProtected
    switch ($Unit.Type) {
        'Service' {
            if ($p.Services | Where-Object { $_ -ieq $Unit.Name }) { return (T 'reason.protected' $Unit.Name) }
        }
        'Task' {
            foreach ($tp in $p.TaskPaths) { if (([string]$Unit.TaskPath).StartsWith($tp, [StringComparison]::OrdinalIgnoreCase)) { return (T 'reason.protected' ($Unit.TaskPath + $Unit.TaskName)) } }
        }
        'Appx' {
            if ($p.Appx | Where-Object { $_ -ieq $Unit.Name }) { return (T 'reason.protected' $Unit.Name) }
        }
        'Reg' {
            foreach ($rp in $p.RegPathPrefixes) { if (([string]$Unit.Path).StartsWith($rp, [StringComparison]::OrdinalIgnoreCase)) { return (T 'reason.protected' $Unit.Path) } }
            if ($Unit.Path -match '\\Services\\([^\\]+)') {
                $svc = $Matches[1]
                if ($p.Services | Where-Object { $_ -ieq $svc }) { return (T 'reason.protected' $svc) }
            }
        }
        'Startup' {
            $exe = Get-HDExePath $Unit.Command
            $leaf = if ($exe) { Split-Path $exe -Leaf } else { '' }
            if (($p.StartupExe -contains $leaf) -or ($exe -and ($exe -like "$env:SystemRoot\System32\*" -or $exe -like '*\DriverStore\FileRepository\*'))) {
                return (T 'reason.protected' $Unit.Name)
            }
        }
        'Path' {
            $full = [IO.Path]::GetFullPath([string]$Unit.Path).TrimEnd('\')
            $roots = @($env:SystemDrive, $env:SystemRoot, $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)},
                       $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, (Split-Path $env:USERPROFILE)) |
                Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
            # Never a root folder itself, never inside Windows, always at least two levels deep.
            if (($roots | Where-Object { $_ -ieq $full }) -or
                $full.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
                ($full.Split('\').Count -lt 3)) {
                return (T 'reason.protected' $full)
            }
        }
        'BtRadio' {
            if ([string]$Unit.InstanceId -match '^(BTH|BTHENUM|BTHLE|BTHLEDEVICE|SWD)\\') { return (T 'reason.protected' $Unit.InstanceId) }
        }
    }
    return $null
}
