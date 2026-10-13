# Run folders, JSON files, folder permissions and the System Restore point.
#
# Layout of one run (see docs/DESIGN.md section 4):
#   %ProgramData%\HeartnetDebloat\runs\<yyyyMMdd-HHmmss>\
#     plan.json        what the user selected (written by the UI, not trusted by the worker)
#     run.json         how the run went (UI)
#     consent.json     answer to "continue without a restore point?" (UI -> worker)
#     user\            results.json + reg\ + files\  (non-elevated UI process: HKCU, Appx, HKCU startup)
#     machine\         results.json + reg\ + tasks\ + files\ + status.json  (elevated worker)
#     manifest.json    merged view of everything above, rebuilt by Update-HDManifest
#     report.html
# machine\ is created by the elevated worker, owned by Administrators and read-only for Users, so a
# non-admin process cannot plant task XML or registry data that the worker would later restore.

$script:HDAdminsSid = 'S-1-5-32-544'
$script:HDSystemSid = 'S-1-5-18'
$script:HDUsersSid  = 'S-1-5-32-545'

function Get-HDDataRoot { Join-Path $env:ProgramData 'HeartnetDebloat' }
function Get-HDRunsRoot { Join-Path (Get-HDDataRoot) 'runs' }

# ============================================================== JSON

function Save-HDJson {
    param([string]$Path, $Object)
    # Write to a temp file and rename, so a reader polling the file never sees half of it.
    $json = $Object | ConvertTo-Json -Depth 12
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-HDJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Trim()) { return $null }
    return ($text | ConvertFrom-Json)
}

# ============================================================== folders

function New-HDRunDir {
    $root = Get-HDRunsRoot
    [void][IO.Directory]::CreateDirectory($root)
    $id = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $root $id
    $n = 2
    while (Test-Path -LiteralPath $dir) { $dir = Join-Path $root "$id-$n"; $n++ }
    [void][IO.Directory]::CreateDirectory($dir)
    return $dir
}

function Test-HDRunDirPath {
    # The worker only accepts run folders that really are under %ProgramData%\HeartnetDebloat\runs.
    param([string]$Path)
    if (-not $Path) { return $false }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [IO.Path]::GetFullPath((Get-HDRunsRoot)).TrimEnd('\')
    $leaf = Split-Path $full -Leaf
    return ((Split-Path $full -Parent) -ieq $root) -and ($leaf -match '^\d{8}-\d{6}(-\d+)?$') -and (Test-Path -LiteralPath $full)
}

function Get-HDOwnerSid {
    param([string]$Path)
    try { return (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { return $null }
}

function Test-HDAdminOwned {
    param([string]$Path)
    (Get-HDOwnerSid $Path) -in $script:HDAdminsSid, $script:HDSystemSid
}

function New-HDAdminDir {
    # Elevated worker only: a folder that Administrators/SYSTEM can write and Users can only read.
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-HDAdminOwned $Path)) { throw "Folder $Path is not owned by Administrators; refusing to use it." }
        return
    }
    $admins = New-Object Security.Principal.SecurityIdentifier $script:HDAdminsSid
    $system = New-Object Security.Principal.SecurityIdentifier $script:HDSystemSid
    $users  = New-Object Security.Principal.SecurityIdentifier $script:HDUsersSid
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($admins)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule $admins, 'FullControl', $inherit, 'None', 'Allow'))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule $system, 'FullControl', $inherit, 'None', 'Allow'))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule $users, 'ReadAndExecute', $inherit, 'None', 'Allow'))
    [void][IO.Directory]::CreateDirectory($Path, $acl)
}

function Get-HDSafeName {
    param([string]$Text, [int]$Max = 80)
    $s = ([regex]::Replace($Text, '[^A-Za-z0-9._-]+', '_')).Trim('_')
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max) }
    if (-not $s) { $s = 'x' }
    return $s
}

# ============================================================== registry (64-bit view, exact kinds)

function Split-HDRegPath {
    param([string]$Path)
    if ($Path -match '^(HKCU|HKLM):\\(.+)$') {
        $hive = if ($Matches[1] -eq 'HKCU') { [Microsoft.Win32.RegistryHive]::CurrentUser } else { [Microsoft.Win32.RegistryHive]::LocalMachine }
        return @{ Hive = $hive; Sub = $Matches[2].TrimEnd('\'); Native = ($Matches[1] + '\' + $Matches[2].TrimEnd('\')) }
    }
    throw "Unsupported registry path: $Path"
}

function Open-HDRegKey {
    param([string]$Path, [switch]$Write, [switch]$Create)
    $p = Split-HDRegPath $Path
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($p.Hive, [Microsoft.Win32.RegistryView]::Registry64)
    if ($Create) { return $base.CreateSubKey($p.Sub) }
    return $base.OpenSubKey($p.Sub, [bool]$Write)
}

function ConvertTo-HDRegData {
    # Registry value -> something JSON can hold without losing information.
    param($Value, [string]$Kind)
    if ($null -eq $Value) { return $null }
    switch ($Kind) {
        'Binary'      { return (($Value | ForEach-Object { $_.ToString('X2') }) -join ' ') }
        'MultiString' { return [object[]]@($Value) }
        'DWord'       { return [int64][uint32]([BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$Value), 0)) }
        'QWord'       { return [string]$Value }
        default       { return [string]$Value }
    }
}

function ConvertFrom-HDRegData {
    param($Data, [string]$Kind)
    switch ($Kind) {
        # The leading comma keeps PowerShell from unrolling the typed array into object[].
        'Binary'      { if (-not $Data) { return ,([byte[]]@()) }; return ,([byte[]]@(([string]$Data -split ' ') | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })) }
        'MultiString' { return ,([string[]]@($Data)) }
        'DWord'       { return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32][int64]$Data), 0) }
        'QWord'       { return [int64]$Data }
        default       { return [string]$Data }
    }
}

function Get-HDRegState {
    # Exact state of one value: does the key exist, does the value exist, kind and data.
    param([string]$Path, [string]$Name)
    $key = $null
    try { $key = Open-HDRegKey $Path } catch {}
    if (-not $key) { return [ordered]@{ KeyExists = $false; Exists = $false; Kind = $null; Data = $null } }
    try {
        if ($key.GetValueNames() -notcontains $Name) { return [ordered]@{ KeyExists = $true; Exists = $false; Kind = $null; Data = $null } }
        $kind = $key.GetValueKind($Name).ToString()
        $val = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
        return [ordered]@{ KeyExists = $true; Exists = $true; Kind = $kind; Data = (ConvertTo-HDRegData $val $kind) }
    } finally { $key.Close() }
}

function Set-HDRegState {
    param([string]$Path, [string]$Name, $Data, [string]$Kind)
    $key = Open-HDRegKey $Path -Create
    try { $key.SetValue($Name, (ConvertFrom-HDRegData $Data $Kind), [Microsoft.Win32.RegistryValueKind]$Kind) } finally { $key.Close() }
}

function Remove-HDRegValue {
    param([string]$Path, [string]$Name, [switch]$RemoveKeyIfEmpty)
    $key = Open-HDRegKey $Path -Write
    if (-not $key) { return }
    try {
        if ($key.GetValueNames() -contains $Name) { $key.DeleteValue($Name) }
        $empty = ($key.ValueCount -eq 0) -and ($key.SubKeyCount -eq 0)
    } finally { $key.Close() }
    if ($RemoveKeyIfEmpty -and $empty) {
        $p = Split-HDRegPath $Path
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($p.Hive, [Microsoft.Win32.RegistryView]::Registry64)
        try { $base.DeleteSubKey($p.Sub, $false) } catch {}
    }
}

function Test-HDRegDataEqual {
    param($A, $B)
    return ((@($A) | ForEach-Object { [string]$_ }) -join "`n") -eq ((@($B) | ForEach-Object { [string]$_ }) -join "`n")
}

function Export-HDRegKey {
    # Extra safety copy of the whole key (reg export). The manifest holds the exact old value anyway.
    param([string]$Path, [string]$Dir)
    $p = Split-HDRegPath $Path
    $regDir = Join-Path $Dir 'reg'
    [void][IO.Directory]::CreateDirectory($regDir)
    $file = Join-Path $regDir ((Get-HDSafeName $p.Native 120) + '.reg')
    if (Test-Path -LiteralPath $file) { return ('reg\' + (Split-Path $file -Leaf)) }
    $probe = $null
    try { $probe = Open-HDRegKey $Path } catch {}
    if (-not $probe) { return $null }
    $probe.Close()
    $null = & reg.exe export $p.Native $file /y 2>&1
    if ($LASTEXITCODE -eq 0) { return ('reg\' + (Split-Path $file -Leaf)) }
    return $null
}

# ============================================================== System Restore

function Test-HDSystemProtection {
    # $true / $false, or $null when it cannot be determined.
    $pol = Get-HDRegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -Name 'DisableSR'
    if ($pol.Exists -and $pol.Value -eq 1) { return $false }
    try {
        $vol = Get-CimInstance Win32_Volume -Filter ("DriveLetter='{0}'" -f $env:SystemDrive) -ErrorAction Stop | Select-Object -First 1
        $clients = Get-HDRegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -Name '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}'
        if (-not $clients.Exists) { return $false }
        $guid = [regex]::Match([string]$vol.DeviceID, '\{[0-9A-Fa-f-]+\}').Value
        if (-not $guid) { return $null }
        foreach ($c in @($clients.Value)) { if ([string]$c -like "*$guid*") { return $true } }
        return $false
    } catch { return $null }
}

function New-HDRestorePoint {
    # Creates a restore point. Windows allows only one per 24 hours by default
    # (SystemRestorePointCreationFrequency); that limit is lifted for this call only and put back after.
    param([string]$Description)
    $res = [ordered]@{ Status = 'Failed'; Reason = ''; Sequence = $null; At = (Get-Date).ToString('s'); Description = $Description }
    $prot = Test-HDSystemProtection
    if ($prot -eq $false) { $res.Status = 'Disabled'; $res.Reason = T 'rp.disabled' $env:SystemDrive; return $res }

    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqName = 'SystemRestorePointCreationFrequency'
    $old = Get-HDRegState -Path $srKey -Name $freqName
    $res.FrequencyBefore = $old
    try {
        Set-HDRegState -Path $srKey -Name $freqName -Data 0 -Kind 'DWord'
        $last = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.SequenceNumber } | Sort-Object)[-1]
        $warn = $null
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningVariable warn -WarningAction SilentlyContinue
        $new = Get-ComputerRestorePoint -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.SequenceNumber -gt [int]$last -and $_.Description -eq $Description } | Select-Object -First 1
        if ($new) { $res.Status = 'Created'; $res.Sequence = [int]$new.SequenceNumber }
        else { $res.Reason = if ($warn) { ($warn | ForEach-Object { [string]$_ }) -join ' ' } else { T 'rp.notfound' } }
    } catch {
        $res.Reason = $_.Exception.Message
    } finally {
        try {
            if ($old.Exists) { Set-HDRegState -Path $srKey -Name $freqName -Data $old.Data -Kind $old.Kind }
            else { Remove-HDRegValue -Path $srKey -Name $freqName }
        } catch { $res.Reason = ($res.Reason + ' ' + $_.Exception.Message).Trim() }
        $res.FrequencyAfter = Get-HDRegState -Path $srKey -Name $freqName
    }
    if ($res.Status -ne 'Created' -and $prot -eq $null -and -not $res.Reason) { $res.Reason = T 'rp.unknown' }
    return $res
}
