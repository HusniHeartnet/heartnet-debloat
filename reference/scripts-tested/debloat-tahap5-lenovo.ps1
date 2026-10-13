# Debloat tahap 5: Lenovo UDC ("NotifyMe") dan Lenovo Vantage.
# Butuh admin (otomatis minta UAC). Tiap bagian minta konfirmasi (y/n).
# TIDAK menyentuh driver tombol Fn (LenovoFnAndFunctionKeys / FnHotkeyUtility) dan aplikasi Lenovo Utility.

$self = $MyInvocation.MyCommand.Path
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Membuka ulang sebagai admin (klik Yes di UAC)...'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$self`""
    return
}

function Ask($q) { (Read-Host "$q (y/n)") -eq 'y' }

function Disable-Svc($name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $s) { "  $name tidak ada, dilewati"; return }
    try {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
        "  Dimatikan: $name"
    } catch { "  Gagal: $name ($($_.Exception.Message))" }
}

function Disable-Tasks($path) {
    Get-ScheduledTask -TaskPath "$path*" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_ | Disable-ScheduledTask -ErrorAction Stop | Out-Null; "  Task dimatikan: $($_.TaskPath)$($_.TaskName)" }
        catch { "  Gagal task: $($_.TaskName)" }
    }
}

$backup = Join-Path (Split-Path $self) ('services-backup-lenovo-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
Get-CimInstance Win32_Service | Where-Object { 'UDCService','LenovoVantageService','ImControllerService' -contains $_.Name } |
    ForEach-Object { '{0}={1}' -f $_.Name, $_.StartMode } | Set-Content $backup

# ---------- 1. Lenovo UDC / NotifyMe ----------
''
'=== 1. Lenovo UDC ("NotifyMe": promo, telemetri, auto-install aplikasi Lenovo) ==='
if (Ask 'Matikan?') {
    Disable-Svc 'UDCService'
    Get-Process -Name 'UDClientService','MessagingPlugin','CoreTelemetryPlugin','AppProvisioningPlugin' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Disable-Tasks '\Lenovo\UDC\'
} else { 'Dilewati.' }

# ---------- 2. Lenovo Vantage ----------
''
'=== 2. Lenovo Vantage (aplikasi + service + jadwal tugas) ==='
'  Pastikan Conservation Mode / setting baterai sudah diatur dulu di Vantage.'
if (Ask 'Uninstall Lenovo Vantage?') {
    Get-Process -Name 'LenovoVantage*','SEGameTool','LenovoVantageService' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $app = Get-AppxPackage -Name 'E046963F.LenovoCompanion'
    if ($app) {
        try { Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop; '  Dihapus: aplikasi Lenovo Vantage' }
        catch { '  Gagal hapus aplikasi Vantage: ' + $_.Exception.Message }
    } else { '  Aplikasi Vantage tidak ada, dilewati' }

    $paths = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $svc = Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'Lenovo Vantage Service' } | Select-Object -First 1
    if ($svc) {
        $exe = ($svc.UninstallString -replace '^"([^"]+)".*$', '$1') -replace '\\\\', '\'
        '  Uninstall: Lenovo Vantage Service (tunggu sebentar)...'
        $p = Start-Process -FilePath $exe -ArgumentList '/SILENT' -Wait -PassThru
        "  Exit code: $($p.ExitCode)"
    } else { '  Lenovo Vantage Service tidak ada, dilewati' }

    Disable-Svc 'LenovoVantageService'
    Disable-Tasks '\Lenovo\Vantage\'
} else { 'Dilewati.' }

# ---------- 3. ImController (System Interface Foundation) ----------
''
'=== 3. Lenovo System Interface Foundation (ImController) ==='
'  Ini "mesin" yang memasang ulang add-in Vantage. Tanpa Vantage tidak dibutuhkan.'
'  Kalau setelah restart ada tombol Fn yang tidak jalan, nyalakan lagi:'
'     Set-Service ImControllerService -StartupType Automatic; Start-Service ImControllerService'
if (Ask 'Matikan ImController?') {
    Disable-Svc 'ImControllerService'
    Disable-Tasks '\Lenovo\ImController\'
} else { 'Dilewati.' }

''
'Selesai. Restart laptop, lalu tes: Fn+Q (mode performa), tombol volume/brightness, Fn+Space (lampu keyboard).'
'Status service lama tersimpan di: ' + $backup
