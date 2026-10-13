# Hapus aplikasi bawaan Windows yang tidak dipakai (hanya untuk user ini, tidak butuh admin).
# Semua aplikasi di bawah bisa dipasang lagi dari Microsoft Store kalau nanti dibutuhkan.
# Hapus baris aplikasi yang MASIH kamu pakai sebelum menjalankan script ini.

$apps = @(
    'Clipchamp.Clipchamp'                        # editor video Microsoft
    'Microsoft.BingNews'                         # Berita
    'Microsoft.BingWeather'                      # Cuaca
    'Microsoft.BingSearch'                       # Bing Search
    'Microsoft.Copilot'                          # Copilot
    'Microsoft.GetHelp'                          # Get Help
    'Microsoft.MicrosoftOfficeHub'               # Microsoft 365 hub (bukan Office-nya)
    'Microsoft.MicrosoftSolitaireCollection'     # Solitaire
    'Microsoft.OutlookForWindows'                # Outlook baru
    'Microsoft.People'                           # People
    'Microsoft.PowerAutomateDesktop'             # Power Automate
    'Microsoft.Todos'                            # To Do
    'Microsoft.Windows.DevHome'                  # Dev Home
    'Microsoft.WindowsFeedbackHub'               # Feedback Hub
    'Microsoft.WindowsMaps'                      # Maps
    'Microsoft.ZuneVideo'                        # Films & TV
    'MicrosoftCorporationII.MicrosoftFamily'     # Family Safety
    'MicrosoftCorporationII.QuickAssist'         # Quick Assist
    'MicrosoftTeams'                             # Teams (lama)
    'MSTeams'                                    # Teams (baru)
    'MicrosoftWindows.Client.WebExperience'      # Widgets
)

$found = foreach ($a in $apps) { Get-AppxPackage -Name $a }
if (-not $found) { 'Tidak ada aplikasi dari daftar yang terpasang.'; return }

'Aplikasi yang akan dihapus:'
$found | ForEach-Object { '  - ' + $_.Name }
$ok = Read-Host 'Lanjut hapus? (y/n)'
if ($ok -ne 'y') { 'Dibatalkan.'; return }

foreach ($p in $found) {
    try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; 'Dihapus: ' + $p.Name }
    catch { 'Gagal: ' + $p.Name + ' (' + $_.Exception.Message + ')' }
}
'Selesai.'
