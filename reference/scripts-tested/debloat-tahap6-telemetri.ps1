# Debloat tahap 6: sisa telemetri Windows.
# Butuh admin (otomatis minta UAC). Satu konfirmasi (y/n) di awal.
# Registry dibackup dulu ke folder backup-telemetri-*; daftar task yang dimatikan juga disimpan di sana.

$self = $MyInvocation.MyCommand.Path
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Membuka ulang sebagai admin (klik Yes di UAC)...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$self`""
    return
}

function Set-Reg($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

''
'=== Yang akan diubah ==='
'  1. Data diagnostik diturunkan ke level minimum ("Required")'
'  2. Service dmwappushservice (pendukung telemetri) dimatikan'
'  3. Jadwal tugas pengumpul data dimatikan (CEIP, Disk Diagnostic, Feedback, Error Reporting, dll.)'
'  4. Kirim laporan error ke Microsoft dimatikan'
'  5. Pengumpulan data ketikan & tulisan tangan dimatikan'
'  6. Riwayat aktivitas (Activity history) dimatikan'
'  7. Pertanyaan feedback Windows dimatikan'
'  8. Daftar bahasa tidak dibagikan ke website, online speech recognition dimatikan'
''
'  Catatan: di Settings > Privacy akan muncul tulisan "Some settings are managed by your organization".'
'  Itu normal, karena level telemetri dikunci lewat policy. Bukan berarti laptop dikendalikan pihak lain.'
''
if ((Read-Host 'Lanjut? (y/n)') -ne 'y') { 'Dibatalkan.'; return }

# ---------- Backup ----------
$backup = Join-Path (Split-Path $self) ('backup-telemetri-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$keys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'
    'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
    'HKCU\Software\Microsoft\Siuf\Rules'
    'HKCU\Software\Microsoft\InputPersonalization'
    'HKCU\Software\Microsoft\Input\TIPC'
    'HKCU\Software\Microsoft\Personalization\Settings'
    'HKCU\Control Panel\International\User Profile'
    'HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'
)
$n = 0
foreach ($k in $keys) { $n++; reg export $k (Join-Path $backup ("{0:D2}.reg" -f $n)) /y 2>$null | Out-Null }
"dmwappushservice=" + (Get-CimInstance Win32_Service -Filter "Name='dmwappushservice'").StartMode | Set-Content (Join-Path $backup 'services.txt')

# ---------- 1. Level data diagnostik ----------
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
'[1] Data diagnostik: Required (minimum)'

# ---------- 2. Service ----------
Stop-Service dmwappushservice -Force -ErrorAction SilentlyContinue
Set-Service dmwappushservice -StartupType Disabled -ErrorAction SilentlyContinue
'[2] dmwappushservice dimatikan'

# ---------- 3. Scheduled tasks ----------
$tasks = @(
    @('\Microsoft\Windows\Application Experience\', 'MareBackup')
    @('\Microsoft\Windows\Customer Experience Improvement Program\', 'Consolidator')
    @('\Microsoft\Windows\Customer Experience Improvement Program\', 'UsbCeip')
    @('\Microsoft\Windows\DiskDiagnostic\', 'Microsoft-Windows-DiskDiagnosticDataCollector')
    @('\Microsoft\Windows\Feedback\Siuf\', 'DmClient')
    @('\Microsoft\Windows\Feedback\Siuf\', 'DmClientOnScenarioDownload')
    @('\Microsoft\Windows\Windows Error Reporting\', 'QueueReporting')
    @('\Microsoft\Windows\Autochk\', 'Proxy')
)
$done = @()
foreach ($t in $tasks) {
    try { Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction Stop | Out-Null; $done += ($t[0] + $t[1]); '[3] Task dimatikan: ' + $t[1] }
    catch { '[3] Task dilewati: ' + $t[1] }
}
$done | Set-Content (Join-Path $backup 'tasks-disabled.txt')

# ---------- 4. Error reporting ----------
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
'[4] Laporan error ke Microsoft dimatikan'

# ---------- 5. Ketikan & tulisan tangan ----------
Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
Set-Reg 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0
Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
'[5] Pengumpulan data ketikan & tulisan tangan dimatikan'

# ---------- 6. Activity history ----------
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
'[6] Activity history dimatikan'

# ---------- 7. Feedback ----------
Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
'[7] Pertanyaan feedback dimatikan'

# ---------- 8. Bahasa & speech ----------
Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
'[8] Daftar bahasa & online speech dimatikan'

''
'Selesai. Restart laptop supaya semuanya berlaku.'
'Backup ada di: ' + $backup
