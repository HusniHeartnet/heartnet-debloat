# Read-only scan engine. Nothing in this file writes to the system: it only reads
# the registry, services, scheduled tasks, packages, devices and files.
# The same detection is used again after every change (verify-after, see core\Apply.ps1).

$script:HDVersion = '0.2.0-dev'

# ============================================================== small readers

function Get-HDRegValue {
    param([string]$Path, [string]$Name)
    $none = [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    try { $key = Get-Item -LiteralPath $Path -ErrorAction Stop } catch { return $none }
    if ($key.GetValueNames() -notcontains $Name) { return $none }
    [pscustomobject]@{
        Exists = $true
        Value  = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
        Kind   = $key.GetValueKind($Name).ToString()
    }
}

function Format-HDRegData {
    param($Value)
    if ($null -eq $Value) { return (T 'detail.reg.missing') }
    if ($Value -is [byte[]]) { return (($Value | ForEach-Object { $_.ToString('X2') }) -join ' ') }
    return [string]$Value
}

function Get-HDExePath {
    param([string]$Command)
    if (-not $Command) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { return $c.Substring(1, $end - 1) }
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd))(\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ($c -split ' ')[0]
}

function Get-HDPublisher {
    param([string]$ExePath)
    if (-not $ExePath) { return $null }
    try { return (Get-Item -LiteralPath $ExePath -ErrorAction Stop).VersionInfo.CompanyName } catch { return $null }
}

function Get-HDVendor {
    param([string]$Manufacturer)
    switch -Regex ($Manufacturer) {
        '^LENOVO'               { return 'LENOVO' }
        '^(HP|Hewlett)'         { return 'HP' }
        '^Dell'                 { return 'DELL' }
        '^ASUS'                 { return 'ASUS' }
        '^Acer'                 { return 'ACER' }
        '^(Micro-Star|MSI)'     { return 'MSI' }
        default                 { return 'OTHER' }
    }
}

# ============================================================== context (facts about this PC)

function Get-HDStartupEntries {
    $list = New-Object System.Collections.Generic.List[object]
    $sa = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $regSources = @(
        @{ Src = 'HKCU Run';          Scope = 'User';    Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';              Approved = "HKCU:\$sa\Run" }
        @{ Src = 'HKLM Run';          Scope = 'Machine'; Run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';              Approved = "HKLM:\$sa\Run" }
        @{ Src = 'HKLM Run (32-bit)'; Scope = 'Machine'; Run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';  Approved = "HKLM:\$sa\Run32" }
    )
    foreach ($s in $regSources) {
        try { $key = Get-Item -LiteralPath $s.Run -ErrorAction Stop } catch { continue }
        foreach ($name in $key.GetValueNames()) {
            if (-not $name) { continue }
            $cmd = [string]$key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
            $list.Add((New-HDStartupEntry -Source $s -Name $name -Command $cmd))
        }
    }
    $folderSources = @(
        @{ Src = 'Startup folder (user)'; Scope = 'User';    Dir = [Environment]::GetFolderPath('Startup');       Approved = "HKCU:\$sa\StartupFolder" }
        @{ Src = 'Startup folder (all)';  Scope = 'Machine'; Dir = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$sa\StartupFolder" }
    )
    $shell = $null
    foreach ($s in $folderSources) {
        if (-not $s.Dir -or -not (Test-Path -LiteralPath $s.Dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $s.Dir -File -ErrorAction SilentlyContinue) {
            if ($f.Name -eq 'desktop.ini') { continue }
            $cmd = $f.FullName
            if ($f.Extension -eq '.lnk') {
                try {
                    if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                    $lnk = $shell.CreateShortcut($f.FullName)
                    $cmd = ('"{0}" {1}' -f $lnk.TargetPath, $lnk.Arguments).Trim()
                } catch {}
            }
            $list.Add((New-HDStartupEntry -Source $s -Name $f.Name -Command $cmd))
        }
    }
    return $list
}

function New-HDStartupEntry {
    param($Source, [string]$Name, [string]$Command)
    $approved = Get-HDRegValue -Path $Source.Approved -Name $Name
    $disabled = $false
    if ($approved.Exists -and $approved.Value -is [byte[]] -and $approved.Value.Length -gt 0) {
        $disabled = ($approved.Value[0] -band 1) -eq 1
    }
    $exe = Get-HDExePath $Command
    [pscustomobject]@{
        Name         = $Name
        Command      = $Command
        Exe          = $exe
        Publisher    = Get-HDPublisher $exe
        Source       = $Source.Src
        Scope        = $Source.Scope
        ApprovedPath = $Source.Approved
        Disabled     = $disabled
    }
}

function Get-HDOneDriveInfo {
    $roots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)
    try {
        Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction Stop | ForEach-Object {
            $roots += (Get-HDRegValue -Path $_.PSPath -Name 'UserFolder').Value
        }
    } catch {}
    $roots = @($roots | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Sort-Object -Unique)

    $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $folders = [ordered]@{
        'Desktop'                                = 'Desktop'
        'Personal'                               = 'Documents'
        'My Pictures'                            = 'Pictures'
        'My Music'                               = 'Music'
        'My Video'                               = 'Videos'
        '{374DE290-123F-4565-9164-39C4925E467B}' = 'Downloads'
    }
    $kfm = @()
    foreach ($name in $folders.Keys) {
        $v = Get-HDRegValue -Path $usf -Name $name
        if (-not $v.Exists) { continue }
        $path = [Environment]::ExpandEnvironmentVariables([string]$v.Value)
        foreach ($r in $roots) {
            if ($path.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase) -or $path -ieq $r) { $kfm += $folders[$name]; break }
        }
    }
    $exe = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    [pscustomobject]@{
        Installed   = [bool]$exe
        Running     = [bool](Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)
        Roots       = $roots
        KfmFolders  = $kfm
    }
}

function Get-HDPrinters {
    $virtualPorts = @('PORTPROMPT:', 'nul:', 'SHRFAX:', 'XPSPort:')
    $virtualNames = @('Microsoft Print to PDF', 'Microsoft XPS Document Writer', 'Fax', 'OneNote (Desktop)',
                      'OneNote for Windows 10', 'Send To OneNote 2016', 'Send To OneNote 2013', 'OneNote')
    $physical = @()
    foreach ($k in Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' -ErrorAction SilentlyContinue) {
        $port = (Get-HDRegValue -Path $k.PSPath -Name 'Port').Value
        if ($virtualNames -contains $k.PSChildName -or $virtualPorts -contains $port) { continue }
        $physical += $k.PSChildName
    }
    foreach ($k in Get-ChildItem 'HKCU:\Printers\Connections' -ErrorAction SilentlyContinue) {
        $physical += ($k.PSChildName -replace ',', '\')
    }
    return $physical
}

function Get-HDBluetooth {
    $all = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
    # The radio is the bus-enumerated device (USB\, PCI\, ...). Paired devices and protocol
    # enumerators live under BTH*\ or SWD\. Matching by instance-id prefix works for every vendor
    # (MediaTek, Intel, Realtek, Qualcomm) unlike matching the word "Adapter" in the name.
    $radios = @($all | Where-Object { $_.InstanceId -notmatch '^(BTH|BTHENUM|BTHLE|BTHLEDEVICE|SWD)\\' })
    $macs = @{}
    foreach ($d in $all) {
        $m = [regex]::Match($d.InstanceId, 'DEV_([0-9A-F]{12})', 'IgnoreCase')
        if ($m.Success) { $macs[$m.Groups[1].Value.ToUpper()] = $true }
    }
    foreach ($k in Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices' -ErrorAction SilentlyContinue) {
        $macs[$k.PSChildName.ToUpper()] = $true
    }
    [pscustomobject]@{ Radios = $radios; PairedCount = $macs.Count }
}

function Get-HDSystemDiskType {
    try {
        $letter = $env:SystemDrive.TrimEnd(':')
        $part = Get-Partition -DriveLetter $letter -ErrorAction Stop
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq [string]$part.DiskNumber } | Select-Object -First 1
        if ($pd) { return [string]$pd.MediaType }
    } catch {}
    return 'Unknown'
}

function Get-HDArpEntries {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($r in $roots) {
        foreach ($k in Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.DisplayName) { continue }
            $type = 'Interactive'
            if ($p.PSObject.Properties['Inno Setup: App Path']) { $type = 'Inno' }
            elseif ($p.WindowsInstaller -eq 1) { $type = 'MSI' }
            elseif ($p.QuietUninstallString) { $type = 'Quiet' }
            $list.Add([pscustomobject]@{
                DisplayName     = [string]$p.DisplayName
                DisplayVersion  = [string]$p.DisplayVersion
                Publisher       = [string]$p.Publisher
                UninstallString = [string]$p.UninstallString
                QuietUninstallString = [string]$p.QuietUninstallString
                InstallerType   = $type
                SystemComponent = ($p.SystemComponent -eq 1)
                Key             = $k.Name
            })
        }
    }
    return $list
}

function Get-HDContext {
    param([scriptblock]$Progress = {})
    $ctx = @{}

    & $Progress 'system'
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ctx.Manufacturer   = ([string]$cs.Manufacturer).Trim()
    $ctx.Model          = ([string]$cs.Model).Trim()
    $ctx.IsLaptop       = ($cs.PCSystemType -eq 2)
    $ctx.OS             = [string]$os.Caption
    $ctx.DisplayVersion = [string]$cv.DisplayVersion
    $ctx.Build          = '{0}.{1}' -f $cv.CurrentBuild, $cv.UBR
    $ctx.Vendor         = Get-HDVendor $ctx.Manufacturer
    $ctx.IsAdmin        = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $ctx.UserName       = [Environment]::UserName
    # When elevated with a different admin account, HKCU/Appx/startup belong to that account, not to the
    # person sitting at the PC. Detect it by comparing with the owner of explorer.exe in this session.
    $ctx.OtherUser = $null
    if ($ctx.IsAdmin) {
        try {
            $me = [Security.Principal.WindowsIdentity]::GetCurrent()
            $session = (Get-Process -Id $PID).SessionId
            $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$session" | Select-Object -First 1
            if ($exp) {
                $sid = (Invoke-CimMethod -InputObject $exp -MethodName GetOwnerSid).Sid
                if ($sid -and $sid -ne $me.User.Value) {
                    $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner
                    $ctx.OtherUser = @{ Me = $me.Name; Desktop = ('{0}\{1}' -f $o.Domain, $o.User) }
                }
            }
        } catch {}
    }

    & $Progress 'apps'
    $ctx.Appx = @{}
    foreach ($p in Get-AppxPackage -ErrorAction SilentlyContinue) { $ctx.Appx[$p.Name] = $p }

    & $Progress 'services'
    $ctx.Services = @{}
    foreach ($s in Get-Service -ErrorAction SilentlyContinue) { $ctx.Services[$s.Name] = $s }

    & $Progress 'tasks'
    $ctx.Tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskPath, TaskName, State)

    & $Progress 'programs'
    $ctx.Arp = Get-HDArpEntries

    & $Progress 'startup'
    $ctx.Startup = Get-HDStartupEntries

    & $Progress 'onedrive'
    $ctx.OneDrive = Get-HDOneDriveInfo

    & $Progress 'hardware'
    $ctx.Printers  = @(Get-HDPrinters)
    $ctx.Bluetooth = Get-HDBluetooth
    $ctx.DiskType  = Get-HDSystemDiskType
    $ctx.XboxDevices = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Xbox' } | Select-Object -ExpandProperty FriendlyName -Unique)
    $ctx.EdgeInstalled = (Test-Path (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')) -or
                         (Test-Path (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'))
    $hib = Get-HDRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled'
    $ctx.HibernateAvailable = (-not $hib.Exists) -or ($hib.Value -ne 0)

    return $ctx
}

# ============================================================== targets, requirements, guards

function Get-HDTargetStatus {
    param($Target, $Ctx)
    $r = [pscustomobject]@{ Type = $Target.T; Found = $false; Done = $false; Lines = @(); Anchor = ($Target.T -ne 'Reg'); Policy = $false; Scope = 'Machine' }
    switch ($Target.T) {
        'Appx' {
            $r.Scope = 'User'
            $p = $Ctx.Appx[$Target.Name]
            if ($p) { $r.Found = $true; $r.Lines = @(T 'detail.appx' @($Target.Name, $p.Version)) }
        }
        'Service' {
            $s = $Ctx.Services[$Target.Name]
            if ($s) {
                $r.Found = $true
                $r.Done = ([string]$s.StartType -eq 'Disabled')
                $r.Lines = @(T 'detail.svc' @($Target.Name, $s.StartType, $s.Status))
            }
        }
        'Task' {
            $m = @($Ctx.Tasks | Where-Object {
                    ((-not $Target.Path) -or $_.TaskPath.StartsWith($Target.Path, [StringComparison]::OrdinalIgnoreCase)) -and
                    ((-not $Target.Name) -or $_.TaskName -ieq $Target.Name) })
            if ($m.Count -gt 0) {
                $r.Found = $true
                $r.Done = -not ($m | Where-Object { [string]$_.State -ne 'Disabled' })
                $r.Lines = @($m | ForEach-Object { T 'detail.task' @(($_.TaskPath + $_.TaskName), $_.State) })
            }
        }
        'Reg' {
            if ($Target.Path -like 'HKCU:*') { $r.Scope = 'User' }
            $r.Policy = $Target.Path -like '*\Policies\*'
            $cur = Get-HDRegValue -Path $Target.Path -Name $Target.Name
            $r.Found = $true
            $r.Done = $cur.Exists -and ([string]$cur.Value -eq [string]$Target.Value)
            $short = $Target.Path -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\'
            $r.Lines = @(T 'detail.reg' @($short, $Target.Name, (Format-HDRegData $cur.Value), $Target.Value))
        }
        'Win32App' {
            $a = $Ctx.Arp | Where-Object { $_.DisplayName -ieq $Target.DisplayName } | Select-Object -First 1
            if ($a) { $r.Found = $true; $r.Lines = @(T 'detail.win32' @($a.DisplayName, $a.DisplayVersion, $a.InstallerType)) }
        }
        'BtRadio' {
            $radios = $Ctx.Bluetooth.Radios
            if ($radios.Count -gt 0) {
                $r.Found = $true
                $r.Done = -not ($radios | Where-Object { $_.ConfigManagerErrorCode -ne 22 })
                $r.Lines = @($radios | ForEach-Object { T 'detail.bt' @($_.FriendlyName, $_.Status) })
            }
        }
        'Startup' {
            $e = $Target.Entry
            $r.Scope = $e.Scope
            $r.Found = $true
            $r.Done = $e.Disabled
            $r.Lines = @(T 'detail.startup' $e.Command)
            if ($e.Publisher) { $r.Lines += T 'detail.startup.pub' $e.Publisher }
            $r.Lines += T 'detail.startup.src' $e.Source
        }
        'Path' {
            $p = [Environment]::ExpandEnvironmentVariables($Target.Path)
            if (Test-Path -LiteralPath $p) { $r.Found = $true; $r.Lines = @($p) }
        }
    }
    return $r
}

function Test-HDRequirement {
    param([string]$Req, $Ctx)
    if ($Req -like 'Vendor:*') { return $Ctx.Vendor -eq $Req.Substring(7) }
    switch ($Req) {
        'EdgeInstalled'      { return [bool]$Ctx.EdgeInstalled }
        'HibernateAvailable' { return [bool]$Ctx.HibernateAvailable }
    }
    throw "Unknown requirement: $Req"
}

# Returns $null when the guard does not trigger, otherwise @{ Level = 'Block'|'Warn'; Message = ... }
function Get-HDGuard {
    param([string]$Guard, $Ctx)
    switch ($Guard) {
        'PhysicalPrinter' { if ($Ctx.Printers.Count) { return @{ Level = 'Block'; Message = (T 'guard.PhysicalPrinter' ($Ctx.Printers -join ', ')) } } }
        'SystemDiskHdd'   {
            if ($Ctx.DiskType -eq 'HDD') { return @{ Level = 'Warn'; Message = (T 'guard.SystemDiskHdd') } }
            if ($Ctx.DiskType -notin 'SSD', 'SCM') { return @{ Level = 'Warn'; Message = (T 'guard.SystemDiskUnknown') } }
        }
        'BtPairedDevices' { if ($Ctx.Bluetooth.PairedCount -gt 0) { return @{ Level = 'Warn'; Message = (T 'guard.BtPairedDevices' $Ctx.Bluetooth.PairedCount) } } }
        'XboxGames'       { if ($Ctx.Appx['Microsoft.GamingServices']) { return @{ Level = 'Warn'; Message = (T 'guard.XboxGames') } } }
        'XboxController'  { if ($Ctx.XboxDevices.Count) { return @{ Level = 'Warn'; Message = (T 'guard.XboxController' ($Ctx.XboxDevices -join ', ')) } } }
        'OneDriveKfm'     { if ($Ctx.OneDrive.KfmFolders.Count) { return @{ Level = 'Block'; Message = (T 'guard.OneDriveKfm' ($Ctx.OneDrive.KfmFolders -join '/')) } } }
        default           { throw "Unknown guard: $Guard" }
    }
    return $null
}

# ============================================================== item results

function New-HDItem {
    param(
        [string]$Id, [string]$Category, [string]$Risk, [string]$State = 'Info', [string]$Kind = 'Action',
        [object[]]$TitleArgs, [object[]]$DescArgs, [object[]]$TradeoffArgs, [string]$TextKey,
        [string[]]$Details = @(), [string[]]$Warnings = @(), [string[]]$Notes = @(),
        [string]$Scope = '', [object[]]$Targets = @(), [bool]$Checked = $false
    )
    if (-not $TextKey) { $TextKey = $Id }
    $selectable = ($Kind -eq 'Action') -and ($State -eq 'Applicable' -or $State -eq 'Partial')
    [pscustomobject]@{
        Id         = $Id
        Category   = $Category
        Kind       = $Kind
        Risk       = $Risk
        State      = $State
        Selectable = $selectable
        Checked    = $Checked -and $selectable
        Title      = T "$TextKey.title" $TitleArgs
        Desc       = T "$TextKey.desc" $DescArgs
        Tradeoff   = T "$TextKey.tradeoff" $TradeoffArgs
        Details    = @($Details)
        Warnings   = @($Warnings)
        Notes      = @($Notes)
        Scope      = $Scope
        Targets    = @($Targets)
    }
}

function Resolve-HDItem {
    param($Def, $Ctx, [string]$Category, [string]$Id, [object[]]$TitleArgs, [string]$TextKey)
    if (-not $Category) { $Category = $Def.Cat }
    if (-not $Id) { $Id = $Def.Id }
    foreach ($req in @($Def.Requires)) {
        if ($req -and -not (Test-HDRequirement $req $Ctx)) {
            return New-HDItem -Id $Id -Category $Category -Risk $Def.Risk -State 'NotPresent' -TitleArgs $TitleArgs -TextKey $TextKey -Targets $Def.Targets
        }
    }
    $status = @(foreach ($t in $Def.Targets) { Get-HDTargetStatus $t $Ctx })
    $anchors = @($status | Where-Object { $_.Anchor })
    $present = @($status | Where-Object { $_.Found })
    $details = @($present | ForEach-Object { $_.Lines })
    $scopes = @($present | ForEach-Object { $_.Scope } | Sort-Object -Unique)
    $scope = if ($scopes.Count -gt 1) { 'Mixed' } elseif ($scopes.Count -eq 1) { $scopes[0] } else { '' }

    if (($anchors.Count -gt 0 -and -not ($anchors | Where-Object { $_.Found })) -or $present.Count -eq 0) {
        return New-HDItem -Id $Id -Category $Category -Risk $Def.Risk -State 'NotPresent' -TitleArgs $TitleArgs -TextKey $TextKey -Targets $Def.Targets
    }
    $doneCount = @($present | Where-Object { $_.Done }).Count
    $state = if ($doneCount -eq $present.Count) { 'Done' } elseif ($doneCount -gt 0) { 'Partial' } else { 'Applicable' }

    $warnings = @(); $blocked = $false
    foreach ($g in @($Def.Guards)) {
        if (-not $g) { continue }
        $res = Get-HDGuard $g $Ctx
        if ($res) { $warnings += $res.Message; if ($res.Level -eq 'Block') { $blocked = $true } }
    }
    if ($blocked -and $state -ne 'Done') { $state = 'Blocked' }

    $notes = @()
    if ($present | Where-Object { $_.Policy }) { $notes += T 'note.policy' }
    if ($present | Where-Object { $_.Type -eq 'Win32App' }) { $notes += T 'note.uninstall' }
    if ($present | Where-Object { $_.Type -eq 'Appx' }) { $notes += T 'note.appx' }

    $checked = ($Def.Risk -eq 'Low') -and ($warnings.Count -eq 0)
    New-HDItem -Id $Id -Category $Category -Risk $Def.Risk -State $state -TitleArgs $TitleArgs -TextKey $TextKey `
        -Details $details -Warnings $warnings -Notes $notes -Scope $scope -Targets $Def.Targets -Checked $checked
}

# ============================================================== dynamic items

function Get-HDStartupItems {
    param($Ctx)
    foreach ($e in $Ctx.Startup) {
        $slug = ([regex]::Replace($e.Name, '[^A-Za-z0-9]+', '-')).Trim('-').ToLower()
        $id = 'startup.{0}.{1}' -f ($e.Source -replace '[^A-Za-z0-9]', '').ToLower(), $slug
        $def = @{ Risk = 'Optional'; Targets = @(@{ T = 'Startup'; Entry = $e; Name = $e.Name; ApprovedPath = $e.ApprovedPath }) }
        $textKey = 'startup.generic'; $titleArgs = @($e.Name)

        $leaf = if ($e.Exe) { Split-Path $e.Exe -Leaf } else { '' }
        $isProtected = ($Ctx.Protected.StartupExe -contains $leaf) -or
                       ($e.Exe -and ($e.Exe -like "$env:SystemRoot\System32\*" -or $e.Exe -like '*\DriverStore\FileRepository\*'))
        $isOneDrive = $leaf -ieq 'OneDrive.exe'
        if ($isProtected) {
            $item = Resolve-HDItem -Def $def -Ctx $Ctx -Category 'startup' -Id $id -TitleArgs $titleArgs -TextKey $textKey
            $item.Desc = T 'startup.generic.desc' $e.Name
            if ($item.State -ne 'Done') { $item.State = 'Blocked'; $item.Selectable = $false; $item.Checked = $false }
            $item.Warnings = @(T 'guard.ProtectedStartup')
            $item
            continue
        }
        if ($isOneDrive) {
            $def.Guards = @('OneDriveKfm'); $textKey = 'od.startup'; $id = 'od.startup'; $titleArgs = @()
        } elseif ($e.Name -like 'MicrosoftEdgeAutoLaunch_*' -and $e.Exe -and (Split-Path $e.Exe -Leaf) -ieq 'msedge.exe') {
            $def.Risk = 'Low'; $textKey = 'startup.edge'; $titleArgs = @()
        } elseif ($e.Exe -and (Split-Path $e.Exe -Leaf) -ieq 'browser_assistant.exe') {
            $def.Risk = 'Low'; $textKey = 'startup.assistant'
        }
        $item = Resolve-HDItem -Def $def -Ctx $Ctx -Category 'startup' -Id $id -TitleArgs $titleArgs -TextKey $textKey
        if ($textKey -eq 'startup.generic') { $item.Desc = T 'startup.generic.desc' $e.Name }
        $item
    }
}

function Get-HDWarningItems {
    param($Ctx)
    if ($Ctx.OtherUser) {
        New-HDItem -Id 'warn.otheruser' -Category 'warn' -Risk 'Warning' -Kind 'Warning' -DescArgs @($Ctx.OtherUser.Me, $Ctx.OtherUser.Desktop)
    }
    $od = $Ctx.OneDrive
    if ($od.KfmFolders.Count -gt 0 -and -not $od.Running) {
        $entry = $Ctx.Startup | Where-Object { $_.Exe -and (Split-Path $_.Exe -Leaf) -ieq 'OneDrive.exe' } | Select-Object -First 1
        if (-not $entry -or $entry.Disabled) {
            New-HDItem -Id 'warn.kfm' -Category 'warn' -Risk 'Warning' -Kind 'Warning' -DescArgs @(($od.KfmFolders -join '/')) `
                -Details @($od.Roots | ForEach-Object { "OneDrive: $_" })
        }
    }
    $wuPol = Get-HDRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate'
    if ($wuPol.Exists -and $wuPol.Value -eq 1) { New-HDItem -Id 'warn.wupolicy' -Category 'warn' -Risk 'Warning' -Kind 'Warning' }
    $wu = $Ctx.Services['wuauserv']
    if ($wu -and [string]$wu.StartType -eq 'Disabled') { New-HDItem -Id 'warn.wusvc' -Category 'warn' -Risk 'Warning' -Kind 'Warning' }
    $d1 = Get-HDRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware'
    $d2 = Get-HDRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableRealtimeMonitoring'
    if (($d1.Exists -and $d1.Value -eq 1) -or ($d2.Exists -and $d2.Value -eq 1)) { New-HDItem -Id 'warn.defpolicy' -Category 'warn' -Risk 'Warning' -Kind 'Warning' }
}

function Get-HDOemInfoItems {
    param($Ctx, $Catalog)
    # Microsoft 365 / Office Click-to-Run: guidance only
    $c2r = Get-HDRegValue -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -Name 'ProductReleaseIds'
    if ($c2r.Exists -and $c2r.Value) {
        $arp = @($Ctx.Arp | Where-Object { $_.DisplayName -like 'Microsoft 365*' -or $_.DisplayName -like 'Microsoft Office*' -or $_.DisplayName -like 'Microsoft OneNote*' } | ForEach-Object { $_.DisplayName })
        New-HDItem -Id 'office.c2r' -Category 'oem' -Risk 'Info' -Kind 'Info' -DescArgs @(($c2r.Value -replace ',', ', ')) -Details $arp
    }

    # Pre-installed antivirus: installed => guidance; uninstalled but leftovers => cleanup item
    foreach ($av in 'McAfee', 'Norton') {
        $installed = @($Ctx.Arp | Where-Object { $_.DisplayName -like "$av*" })
        if ($installed.Count) {
            New-HDItem -Id "av.$($av.ToLower()).installed" -TextKey 'av.installed' -Category 'oem' -Risk 'Info' -Kind 'Info' `
                -TitleArgs @($av) -Details @($installed | ForEach-Object { $_.DisplayName })
        } elseif ($av -eq 'McAfee') {
            $def = @{ Risk = 'Low'; Targets = @(
                    @{ T = 'Task'; Path = '\McAfee\'; Mode = 'Remove' }
                    @{ T = 'Path'; Path = '%ProgramData%\McAfee'; Mode = 'Move' }) }
            $item = Resolve-HDItem -Def $def -Ctx $Ctx -Category 'oem' -Id 'av.mcafee.leftovers'
            if ($item.State -ne 'NotPresent') {
                # Leftovers are removed, not disabled, so "Disabled" tasks still count as work to do.
                $item.State = 'Applicable'; $item.Selectable = $true; $item.Checked = $true
            }
            $item
        }
    }

    # Everything else from the manufacturer: info only, no tested rules yet
    $pubRegex = @{ LENOVO = '^Lenovo'; HP = '^(HP|Hewlett)'; DELL = '^Dell'; ASUS = '^ASUS'; ACER = '^Acer'; MSI = '^(Micro-Star|MSI)' }[$Ctx.Vendor]
    if ($pubRegex) {
        $covered = @($Catalog.Items | ForEach-Object { $_.Targets } | Where-Object { $_.T -eq 'Win32App' } | ForEach-Object { $_.DisplayName })
        $names = @($Ctx.Arp | Where-Object { $_.Publisher -match $pubRegex -and -not $_.SystemComponent -and $covered -notcontains $_.DisplayName } |
                   ForEach-Object { $_.DisplayName }) +
                 @($Ctx.Appx.Values | Where-Object { $_.Publisher -match ($pubRegex -replace '\^', 'CN=') } | ForEach-Object { $_.Name })
        $names = @($names | Sort-Object -Unique)
        if ($names.Count) {
            New-HDItem -Id 'oem.inventory' -Category 'oem' -Risk 'Info' -Kind 'Info' -TitleArgs @($Ctx.Manufacturer) `
                -DescArgs @($Ctx.Manufacturer, ($names -join ', '))
        }
    }

    # Browsers that keep running in the background
    $browsers = @()
    if ($Ctx.Arp | Where-Object { $_.DisplayName -ieq 'Google Chrome' }) { $browsers += 'Google Chrome' }
    if ($Ctx.Arp | Where-Object { $_.DisplayName -like 'Opera*' }) { $browsers += 'Opera' }
    if ($Ctx.Arp | Where-Object { $_.DisplayName -like 'Brave*' }) { $browsers += 'Brave' }
    if ($browsers.Count) { New-HDItem -Id 'sys.browserbg' -Category 'system' -Risk 'Info' -Kind 'Info' -DescArgs @(($browsers -join ', ')) }
}

function Get-HDSecurityItems {
    param($Ctx)
    $on = T 'value.on'; $off = T 'value.off'; $unk = T 'value.unknown'
    function OnOff($b) { if ($null -eq $b) { $unk } elseif ($b) { $on } else { $off } }

    # Defender / antivirus
    $desc = $null
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $desc = T 'value.defender' @((OnOff ($mp.AMServiceEnabled -and $mp.AntivirusEnabled)), (OnOff $mp.RealTimeProtectionEnabled), (OnOff $mp.IsTamperProtected))
    } catch {}
    try {
        $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $_.displayName })
        if ($avs.Count) { $line = T 'value.av.other' ($avs -join ', '); $desc = if ($desc) { "$desc $line" } else { $line } }
    } catch {}
    if (-not $desc) { $desc = $unk }
    New-HDItem -Id 'sec.defender' -Category 'security' -Risk 'Info' -Kind 'Info' -DescArgs @($desc)

    # Firewall
    try {
        $fw = (Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object { '{0}: {1}' -f $_.Name, (OnOff ([bool]$_.Enabled)) }) -join ', '
    } catch { $fw = $unk }
    New-HDItem -Id 'sec.firewall' -Category 'security' -Risk 'Info' -Kind 'Info' -DescArgs @($fw)

    # VBS / Memory Integrity
    $dg = $null
    try { $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop } catch {}
    $hvciReg = Get-HDRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled'
    $hvci = if ($dg -and (@($dg.SecurityServicesRunning) -contains 2)) { T 'value.running' } elseif ($hvciReg.Exists -and $hvciReg.Value -eq 1) { $on } else { $off }
    New-HDItem -Id 'sec.hvci' -Category 'security' -Risk 'Info' -Kind 'Info' -DescArgs @($hvci)
    $vbs = if ($dg) { T ('value.vbs.' + [int]$dg.VirtualizationBasedSecurityStatus) } else { $unk }
    New-HDItem -Id 'sec.vbs' -Category 'security' -Risk 'Info' -Kind 'Info' -DescArgs @($vbs)

    foreach ($pair in @(@('sec.wu', 'wuauserv'), @('sec.search', 'WSearch'))) {
        $s = $Ctx.Services[$pair[1]]
        $d = if ($s) { '{0} ({1}, {2})' -f $pair[1], $s.StartType, $s.Status } else { T 'value.none' }
        New-HDItem -Id $pair[0] -Category 'security' -Risk 'Info' -Kind 'Info' -DescArgs @($d)
    }

    # Virtualization features that other apps depend on
    $names = @{ 'Microsoft-Hyper-V-All' = 'Hyper-V'; 'VirtualMachinePlatform' = 'Virtual Machine Platform'; 'Microsoft-Windows-Subsystem-Linux' = 'WSL';
                'HypervisorPlatform' = 'Windows Hypervisor Platform'; 'Containers-DisposableClientVM' = 'Windows Sandbox' }
    $enabled = @()
    try {
        foreach ($f in Get-CimInstance Win32_OptionalFeature -ErrorAction Stop | Where-Object { $names.ContainsKey($_.Name) -and $_.InstallState -eq 1 }) { $enabled += $names[$f.Name] }
    } catch {}
    $vm = if ($enabled.Count) { ($enabled | Sort-Object) -join ', ' } else { T 'value.none' }
    New-HDItem -Id 'sec.hyperv' -Category 'security' -Risk 'Info' -Kind 'Info' -DescArgs @($vm)
}

function Get-HDNotDoneItems {
    foreach ($i in 1..8) { New-HDItem -Id "notdone.$i" -Category 'notdone' -Risk 'Info' -Kind 'Info' }
}

# ============================================================== entry point

function Invoke-HDScan {
    param([scriptblock]$Progress = {})
    $root = Split-Path $PSScriptRoot
    $catalog = Import-PowerShellDataFile (Join-Path $root 'catalog\items.psd1')
    $ctx = Get-HDContext -Progress $Progress
    $ctx.Protected = Import-PowerShellDataFile (Join-Path $root 'catalog\protected.psd1')

    & $Progress 'catalog'
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($def in $catalog.Items) { $items.Add((Resolve-HDItem -Def $def -Ctx $ctx)) }
    foreach ($i in Get-HDStartupItems $ctx) { $items.Add($i) }
    foreach ($i in Get-HDWarningItems $ctx) { $items.Add($i) }
    foreach ($i in Get-HDOemInfoItems $ctx $catalog) { $items.Add($i) }
    & $Progress 'security'
    foreach ($i in Get-HDSecurityItems $ctx) { $items.Add($i) }
    foreach ($i in Get-HDNotDoneItems) { $items.Add($i) }

    [pscustomobject]@{
        App       = 'Heartnet Debloat'
        Version   = $script:HDVersion
        ScannedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Machine   = [pscustomobject]@{
            Manufacturer = $ctx.Manufacturer; Model = $ctx.Model; Vendor = $ctx.Vendor; IsLaptop = $ctx.IsLaptop
            OS = $ctx.OS; DisplayVersion = $ctx.DisplayVersion; Build = $ctx.Build; IsAdmin = $ctx.IsAdmin; DiskType = $ctx.DiskType
        }
        Items     = $items.ToArray()
        OtherUser = $ctx.OtherUser
    }
}
