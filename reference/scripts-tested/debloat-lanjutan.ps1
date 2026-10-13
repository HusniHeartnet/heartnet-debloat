# Debloat lanjutan: aplikasi Lenovo yang tidak penting, setting iklan/saran Windows, dan startup.
# Tiap bagian minta konfirmasi (y/n). Setting registry dibackup dulu ke folder backup-registry-*.
# Tidak menyentuh: Lenovo Vantage, Lenovo Utility, Overwolf, CapCut, Opera GX, Chrome, Defender, Windows Update.

function Ask($q) { (Read-Host "$q (y/n)") -eq 'y' }

function Set-Reg($path, $name, $value, $type = 'DWord') {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}

# ---------- 1. Uninstall aplikasi Lenovo yang tidak penting ----------
''
'=== 1. Aplikasi Lenovo yang akan di-uninstall ==='
$lenovo = @(
    @{ Name = 'Lenovo Now';          Exe = 'C:\Program Files (x86)\Lenovo\LenovoNow\unins000.exe';             Args = '/SILENT' }
    @{ Name = 'Lenovo AvatarMaster'; Exe = 'C:\Program Files\Lenovo\Lenovo AvatarMaster\unins000.exe';        Args = '/SILENT' }
    @{ Name = 'Legion Arena';        Exe = 'C:\Program Files (x86)\Lenovo\Legion Arena\Uninstall.exe';         Args = '' }
) | Where-Object { Test-Path $_.Exe }

if ($lenovo) {
    $lenovo | ForEach-Object { '  - ' + $_.Name }
    'Windows akan meminta izin admin (UAC) untuk tiap aplikasi. Legion Arena memakai uninstaller biasa, klik saja sampai selesai.'
    if (Ask 'Uninstall aplikasi di atas?') {
        foreach ($a in $lenovo) {
            'Uninstall: ' + $a.Name
            try {
                if ($a.Args) { Start-Process -FilePath $a.Exe -ArgumentList $a.Args -Wait -ErrorAction Stop }
                else         { Start-Process -FilePath $a.Exe -Wait -ErrorAction Stop }
            } catch { '  Gagal/dibatalkan: ' + $_.Exception.Message }
        }
    } else { 'Dilewati.' }
} else { 'Tidak ada aplikasi Lenovo dari daftar yang terpasang.' }

# ---------- Backup registry ----------
$backup = Join-Path $PSScriptRoot ('backup-registry-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$keys = @(
    'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
    'HKCU\Software\Policies\Microsoft\Windows\Explorer'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
)
$n = 0
foreach ($k in $keys) {
    $n++
    reg export $k (Join-Path $backup ("{0:D2}.reg" -f $n)) /y 2>$null | Out-Null
}

# ---------- 2. Setting Windows: iklan, saran, pencarian web, perekaman latar ----------
''
'=== 2. Setting Windows yang akan diubah ==='
'  - Matikan iklan/saran di Start, Settings, lock screen, dan notifikasi tips'
'  - Cegah Windows memasang aplikasi promosi diam-diam (supaya Clipchamp dkk. tidak balik lagi)'
'  - Matikan rekomendasi/promosi di Start menu dan iklan OneDrive di File Explorer'
'  - Matikan "Tailored experiences" (iklan berdasarkan data diagnostik)'
'  - Matikan hasil web Bing dan "search highlights" di pencarian Start'
'  - Matikan Xbox Game Bar "Record what happened" (perekaman latar belakang saat main game)'
if (Ask 'Terapkan setting di atas?') {
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($v in 'SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled',
                   'PreInstalledAppsEnabled','OemPreInstalledAppsEnabled','RotatingLockScreenOverlayEnabled',
                   'SubscribedContent-310093Enabled','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled',
                   'SubscribedContent-353696Enabled') {
        Set-Reg $cdm $v 0
    }
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'Start_IrisRecommendations' 0
    Set-Reg $adv 'ShowSyncProviderNotifications' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    $search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
    Set-Reg $search 'IsDynamicSearchBoxEnabled' 0
    Set-Reg $search 'IsMSACloudSearchEnabled' 0
    Set-Reg $search 'IsAADCloudSearchEnabled' 0
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
    'Setting diterapkan.'
} else { 'Dilewati.' }

# ---------- 3. Matikan aplikasi yang ikut jalan saat startup ----------
''
'=== 3. Startup yang akan dimatikan (aplikasinya tetap ada, hanya tidak auto-start) ==='
$startup = @(
    'MicrosoftEdgeAutoLaunch_A765AF1E2244409368913F8CD63AA76E'   # Edge buka sendiri di belakang
    'Opera GX Browser Assistant'                                 # asisten Opera, bukan browsernya
    # Hapus tanda # di depan baris berikut kalau mau ikut dimatikan:
    # 'Spotify'
    # 'NeatDM'
    # 'OneDrive'
)
$startup | ForEach-Object { '  - ' + $_ }
if (Ask 'Matikan startup di atas?') {
    $sa = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    $disabled = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
    foreach ($s in $startup) { Set-Reg $sa $s $disabled 'Binary'; 'Dimatikan: ' + $s }
} else { 'Dilewati.' }

''
'Selesai. Restart laptop supaya semua perubahan berlaku.'
'Backup registry ada di: ' + $backup
'Untuk membatalkan setting: klik dua kali file .reg di folder backup itu.'
