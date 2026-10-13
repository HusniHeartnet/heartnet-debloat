# Debloat tahap 7: sisa McAfee, task Nahimic & SoftLanding, aplikasi bawaan sisa,
# Delivery Optimization (upload P2P), dan Edge Startup Boost/background.
# Butuh admin (otomatis minta UAC). Tiap bagian minta konfirmasi (y/n).
# Semua dibackup ke folder backup-tahap7-* (task XML, registry, file McAfee dipindah ke sana).

$self = $MyInvocation.MyCommand.Path
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Membuka ulang sebagai admin (klik Yes di UAC)...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$self`""
    return
}

function Ask($q) { (Read-Host "$q (y/n)") -eq 'y' }

function Set-Reg($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

$backup = Join-Path (Split-Path $self) ('backup-tahap7-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null

function Save-TaskXml($task) {
    $file = Join-Path $backup ('task-' + ($task.TaskPath.Trim('\') -replace '[\\/:*?"<>|]', '_') + '-' + ($task.TaskName -replace '[\\/:*?"<>|]', '_') + '.xml')
    Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath | Set-Content -Path $file -Encoding Unicode
}

# ---------- 1. Sisa McAfee ----------
''
'=== 1. Sisa McAfee (program sudah tidak ada, tapi 3 jadwal tugas + 2 file masih tertinggal) ==='
if (Ask 'Bersihkan?') {
    Get-ScheduledTask -TaskPath '\McAfee\*' -ErrorAction SilentlyContinue | ForEach-Object {
        Save-TaskXml $_
        try { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction Stop; '  Task dihapus: ' + $_.TaskName }
        catch { '  Gagal: ' + $_.TaskName }
    }
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    foreach ($f in '\McAfee\WPS', '\McAfee') { try { $svc.GetFolder('\').DeleteFolder($f.TrimStart('\'), 0) } catch {} }
    if (Test-Path 'C:\ProgramData\McAfee') {
        Move-Item 'C:\ProgramData\McAfee' (Join-Path $backup 'ProgramData-McAfee') -Force
        '  Folder C:\ProgramData\McAfee dipindah ke backup'
    }
} else { 'Dilewati.' }

# ---------- 2. Task Nahimic & SoftLanding ----------
''
'=== 2. Jadwal tugas Nahimic (terlewat di tahap 3) dan SoftLanding (promo/tips Windows) ==='
if (Ask 'Matikan?') {
    $tasks = @(Get-ScheduledTask -TaskName 'NahimicTask32','NahimicTask64' -ErrorAction SilentlyContinue) +
             @(Get-ScheduledTask -TaskPath '\SoftLanding\*' -ErrorAction SilentlyContinue)
    foreach ($t in $tasks) {
        Save-TaskXml $t
        try { $t | Disable-ScheduledTask -ErrorAction Stop | Out-Null; '  Task dimatikan: ' + $t.TaskName }
        catch { '  Gagal: ' + $t.TaskName }
    }
} else { 'Dilewati.' }

# ---------- 3. Aplikasi bawaan sisa ----------
''
'=== 3. Aplikasi yang akan dihapus ==='
$apps = 'C27EB4BA.DropboxOEM','microsoft.windowscommunicationsapps','Microsoft.MixedReality.Portal','Microsoft.Whiteboard','Microsoft.MicrosoftJournal'
'  - Dropbox (promo OEM), Mail & Calendar, Mixed Reality Portal, Whiteboard, Journal'
if (Ask 'Hapus?') {
    foreach ($a in $apps) {
        $p = Get-AppxPackage -Name $a
        if (-not $p) { "  $a tidak ada, dilewati"; continue }
        try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; "  Dihapus: $a" }
        catch { "  Gagal: $a ($($_.Exception.Message))" }
    }
} else { 'Dilewati.' }

# ---------- 4. Delivery Optimization ----------
''
'=== 4. Delivery Optimization ==='
'  Windows berhenti meng-upload update ke PC lain (hemat upload, ping game lebih stabil).'
'  Windows Update tetap jalan normal, download langsung dari server Microsoft.'
if (Ask 'Matikan berbagi update?') {
    reg export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' (Join-Path $backup 'deliveryoptimization.reg') /y 2>$null | Out-Null
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    '  Delivery Optimization: HTTP only (tanpa P2P)'
} else { 'Dilewati.' }

# ---------- 5. Edge ----------
''
'=== 5. Microsoft Edge: Startup Boost dan jalan di background ==='
'  Edge tidak lagi dimuat diam-diam saat booting dan benar-benar berhenti saat ditutup.'
'  (Di edge://settings akan muncul "Managed by your organization" - itu normal.)'
if (Ask 'Matikan?') {
    reg export 'HKLM\SOFTWARE\Policies\Microsoft\Edge' (Join-Path $backup 'edge.reg') /y 2>$null | Out-Null
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
    '  Edge Startup Boost & background mode dimatikan'
} else { 'Dilewati.' }

''
'Selesai. Restart laptop supaya semuanya berlaku.'
'Backup ada di: ' + $backup
''
'TIDAK termasuk di script ini (perlu kamu lakukan sendiri):'
'  - OneDrive: Desktop/Documents/Pictures masih di folder OneDrive dan sinkron sedang mati.'
'  - Microsoft 365 / OneNote: pakai tool resmi Microsoft (aka.ms/SaRA-OfficeUninstallFromPC).'
'  - Chrome & Opera GX: matikan "Continue running background apps" di setting browser.'
