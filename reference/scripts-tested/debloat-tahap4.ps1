# Debloat tahap 4: Microsoft 365/OneNote (uninstall silent) dan Xbox.
# Butuh admin (otomatis minta UAC). Tiap bagian minta konfirmasi (y/n).

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

function Remove-App($name) {
    $p = Get-AppxPackage -Name $name
    if (-not $p) { "  $name tidak ada, dilewati"; return }
    try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; "  Dihapus: $name" }
    catch { "  Gagal: $name ($($_.Exception.Message))" }
}

function Set-Reg($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

# ---------- 1. Microsoft 365 + OneNote (silent) ----------
''
'=== 1. Microsoft 365 dan OneNote (uninstall otomatis, tanpa jendela) ==='
'  - Tutup dulu Word/Excel/Outlook/OneNote kalau terbuka (akan dipaksa tutup).'
'  - Prosesnya bisa 2-10 menit, tunggu sampai muncul tulisan selesai.'
$c2r = 'C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
if (Test-Path $c2r) {
    if (Ask 'Lanjut?') {
        $p = Start-Process -FilePath $c2r -ArgumentList 'scenario=install scenariosubtype=ARP sourcetype=None productstoremove=AllProducts culture=en-us version.16=16.0 DisplayLevel=False forceappshutdown=True' -Wait -PassThru
        "  Exit code: $($p.ExitCode)"
        $left = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Microsoft 365|OneNote' }
        if ($left) { '  Office MASIH terpasang: ' + (($left.DisplayName) -join ', ') }
        else { '  Office berhasil dihapus.' }
    } else { 'Dilewati.' }
} else { '  Office tidak ditemukan, dilewati.' }

# ---------- 2. Xbox ----------
''
'=== 2. Xbox ==='
'  - Hapus aplikasi Xbox, Game Bar, dan overlay Xbox'
'  - Matikan service Xbox Live (login, cloud save, jaringan)'
'  - Matikan Game Bar / Game DVR supaya tidak muncul popup "ms-gamingoverlay"'
'  Game Steam (Valheim, Deadlock) TIDAK terpengaruh.'
'  Yang ikut tidak bisa: game Microsoft Store/Game Pass dan game yang login pakai akun Xbox.'
if (Ask 'Lanjut?') {
    Get-Process -Name 'GameBar','GameBarFTServer','XboxPcApp' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($a in 'Microsoft.GamingApp','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay',
                   'Microsoft.XboxSpeechToTextOverlay','Microsoft.Xbox.TCUI','Microsoft.XboxIdentityProvider') {
        Remove-App $a
    }
    foreach ($s in 'XblAuthManager','XblGameSave','XboxNetApiSvc') { Disable-Svc $s }
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
    '  Game Bar / Game DVR dimatikan.'

    ''
    '  Service XboxGipSvc dipakai untuk controller Xbox (update firmware, Xbox Wireless Adapter).'
    if (Ask '  Kamu TIDAK pakai controller Xbox? Matikan juga XboxGipSvc?') { Disable-Svc 'XboxGipSvc' }
    else { '  XboxGipSvc dibiarkan.' }
} else { 'Dilewati.' }

''
'Selesai. Restart laptop supaya semuanya bersih.'
