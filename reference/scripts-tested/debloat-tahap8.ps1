# Debloat tahap 8 (eksperimen): SysMain, background apps, Fast Startup, Bluetooth.
# Butuh admin (otomatis minta UAC). Tiap bagian minta konfirmasi (y/n).
# Status lama dibackup ke folder backup-tahap8-*, berisi juga file CARA-MENGEMBALIKAN.txt.

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

function Disable-Svc($name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $s) { "  $name tidak ada, dilewati"; return }
    try {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
        "  Dimatikan: $name"
    } catch { "  Gagal: $name ($($_.Exception.Message))" }
}

$backup = Join-Path (Split-Path $self) ('backup-tahap8-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Get-CimInstance Win32_Service | Where-Object { 'SysMain','bthserv','BTAGService','BthAvctpSvc' -contains $_.Name } |
    ForEach-Object { '{0}={1}' -f $_.Name, $_.StartMode } | Set-Content (Join-Path $backup 'services.txt')
reg export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' (Join-Path $backup 'appprivacy.reg') /y 2>$null | Out-Null
reg export 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' (Join-Path $backup 'power.reg') /y 2>$null | Out-Null

@'
CARA MENGEMBALIKAN (jalankan di PowerShell sebagai admin, pilih yang perlu saja):

SysMain:
  Set-Service SysMain -StartupType Automatic; Start-Service SysMain

Background apps:
  Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name LetAppsRunInBackground

Fast Startup:
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 1

Bluetooth:
  Get-PnpDevice -Class Bluetooth | Where-Object FriendlyName -match 'Adapter' | Enable-PnpDevice -Confirm:$false
  Set-Service bthserv -StartupType Manual; Set-Service BTAGService -StartupType Manual; Set-Service BthAvctpSvc -StartupType Manual
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\BluetoothUserService' -Name Start -Value 3
  (lalu restart)
'@ | Set-Content (Join-Path $backup 'CARA-MENGEMBALIKAN.txt')

# ---------- 1. SysMain ----------
''
'=== 1. SysMain ==='
'  Windows berhenti memuat aplikasi ke RAM di latar belakang.'
'  Aplikasi yang jarang dibuka mungkin sedikit lebih lambat terbuka (di SSD NVMe hampir tidak terasa).'
if (Ask 'Matikan?') { Disable-Svc 'SysMain' } else { 'Dilewati.' }

# ---------- 2. Background apps ----------
''
'=== 2. Background apps (aplikasi Microsoft Store) ==='
'  Aplikasi Store tidak boleh jalan di latar belakang.'
'  Discord, Spotify, Steam, Opera, Chrome TIDAK terpengaruh (bukan aplikasi Store).'
'  Efek samping: notifikasi dari aplikasi Store bisa telat.'
if (Ask 'Matikan?') {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
    '  Background apps Store dimatikan'
} else { 'Dilewati.' }

# ---------- 3. Fast Startup ----------
''
'=== 3. Fast Startup ==='
'  Shutdown jadi "bersih" (driver & Windows benar-benar dimuat ulang). Booting ~3-5 detik lebih lama.'
if (Ask 'Matikan?') {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    '  Fast Startup dimatikan'
} else { 'Dilewati.' }

# ---------- 4. Bluetooth ----------
''
'=== 4. Bluetooth ==='
'  Matikan adapter Bluetooth MediaTek + semua service Bluetooth.'
'  Wi-Fi TIDAK terpengaruh. Headset/mouse/controller Bluetooth tidak bisa dipakai sampai dikembalikan.'
if (Ask 'Matikan?') {
    Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Adapter' -and $_.Status -eq 'OK' } | ForEach-Object {
        try { Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction Stop; '  Adapter dimatikan: ' + $_.FriendlyName }
        catch { '  Gagal mematikan adapter: ' + $_.FriendlyName }
    }
    foreach ($s in 'BTAGService','BthAvctpSvc','bthserv') { Disable-Svc $s }
    Get-Service -Name 'BluetoothUserService_*' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\BluetoothUserService' 'Start' 4
    '  Dimatikan: BluetoothUserService'
} else { 'Dilewati.' }

''
'Selesai. Restart laptop (pakai Restart, bukan Shut down) supaya semuanya berlaku.'
'Backup & cara mengembalikan ada di: ' + $backup
