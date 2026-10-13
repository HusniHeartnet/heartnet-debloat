# Debloat tahap 3: Nahimic, Phone Link, Microsoft 365/OneNote, dan service yang tidak dipakai.
# Butuh admin (otomatis minta UAC). Tiap bagian minta konfirmasi (y/n).
# Status service lama disimpan ke services-backup-*.txt untuk dikembalikan nanti.

$self = $MyInvocation.MyCommand.Path
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Membuka ulang sebagai admin (klik Yes di UAC)...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$self`""
    return
}

function Ask($q) { (Read-Host "$q (y/n)") -eq 'y' }

$services = 'NahimicService','Spooler','DiagTrack','MapsBroker'
$backup = Join-Path (Split-Path $self) ('services-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
Get-CimInstance Win32_Service | Where-Object { $services -contains $_.Name } |
    ForEach-Object { '{0}={1}' -f $_.Name, $_.StartMode } | Set-Content $backup

function Disable-Svc($name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $s) { "  $name tidak ada, dilewati"; return }
    try {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
        "  Dimatikan: $name"
    } catch { "  Gagal: $name ($($_.Exception.Message))" }
}

function Remove-App($name) {
    $p = Get-AppxPackage -Name $name
    if (-not $p) { "  $name tidak ada, dilewati"; return }
    try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; "  Dihapus: $name" }
    catch { "  Gagal: $name ($($_.Exception.Message))" }
}

# ---------- 1. Nahimic ----------
''
'=== 1. Nahimic (audio enhancer Lenovo) ==='
'  - Matikan NahimicService dan hapus aplikasi Nahimic'
'  - Driver audio TIDAK dihapus, speaker/headset tetap normal (efek "enhancer" saja yang hilang)'
if (Ask 'Lanjut?') {
    Disable-Svc 'NahimicService'
    Get-Process -Name 'Nahimic3','nahimicNotifSys' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-App 'A-Volute.Nahimic'
} else { 'Dilewati.' }

# ---------- 2. Phone Link ----------
''
'=== 2. Phone Link ==='
'  - Hapus Phone Link dan Cross Device'
if (Ask 'Lanjut?') {
    Get-Process -Name 'PhoneExperienceHost','CrossDeviceService','CrossDeviceResume' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-App 'Microsoft.YourPhone'
    Remove-App 'MicrosoftWindows.CrossDevice'
} else { 'Dilewati.' }

# ---------- 3. Microsoft 365 + OneNote ----------
''
'=== 3. Microsoft 365 dan OneNote ==='
'  - Menjalankan uninstaller resmi Office. Akan muncul jendela konfirmasi: klik Uninstall.'
'  - Office online (office.com, Word/Excel di browser) tetap bisa dipakai.'
$c2r = 'C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
if (Test-Path $c2r) {
    if (Ask 'Lanjut?') {
        foreach ($prod in 'O365HomePremRetail.16_en-us_x-none','OneNoteFreeRetail.16_en-us_x-none') {
            "  Uninstall: $prod"
            Start-Process -FilePath $c2r -ArgumentList "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=$prod culture=en-us version.16=16.0" -Wait
        }
    } else { 'Dilewati.' }
} else { '  Office tidak ditemukan, dilewati.' }

# ---------- 4. Service yang tidak dipakai ----------
''
'=== 4. Service yang akan dimatikan ==='
'  - Spooler     : Print Spooler (printer). "Microsoft Print to PDF" ikut mati;'
'                  "Save as PDF" di Chrome/Opera tetap jalan.'
'  - DiagTrack   : telemetri Microsoft'
'  - MapsBroker  : Downloaded Maps Manager (aplikasi Maps sudah dihapus)'
if (Ask 'Lanjut?') {
    Disable-Svc 'Spooler'
    Disable-Svc 'DiagTrack'
    Disable-Svc 'MapsBroker'
} else { 'Dilewati.' }

''
'Selesai. Restart laptop supaya semuanya bersih.'
'Status service lama tersimpan di: ' + $backup
'Contoh mengembalikan printer: Set-Service Spooler -StartupType Automatic; Start-Service Spooler'
