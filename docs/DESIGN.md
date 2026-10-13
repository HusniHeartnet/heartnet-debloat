# Heartnet Debloat: Design Doc (v0.2)

Status: **disetujui (2026-10-13)**.

Keputusan:
- **PowerShell 5.1 + WPF**
- **open source** (kode MIT, maskot tidak termasuk; lihat NOTICE), dirilis di GitHub
- Office cukup panduan + link resmi
- maskot kucing (bagian 7)

Sumber: 8 script di `reference/scripts-tested/` (sudah teruji di Lenovo LOQ 83JC).
Script itu hanya referensi. Aplikasinya **generik**: semua item dideteksi dulu di PC yang sedang dipakai.

## 1. Prinsip

1. **Audit dulu.** Scan hanya membaca, tidak mengubah apa pun. User melihat apa yang benar-benar ada di PC-nya, dengan
   penjelasan bahasa sehari-hari, tingkat risiko, dan untung-ruginya.
2. **User yang memilih.** Item aman sudah dicentang. Item opsional/eksperimen tidak dicentang.
   Item keamanan (Defender, Memory Integrity/VBS, Windows Update) hanya **ditampilkan sebagai info** dan tidak pernah dimatikan.
3. **Backup otomatis sebelum mengubah apa pun.** Restore point, nilai registry lama, start-mode service,
   XML scheduled task, dan file yang **dipindah** (bukan dihapus).
4. **Hasil per item jujur:** berhasil / dilewati / gagal + alasan. Sukses baru diklaim setelah dicek ulang (verify-after).
5. **Undo per item atau semuanya**, dari catatan backup.
6. **Jujur soal efek.** Debloat mengurangi lonjakan proses di background, pemakaian RAM, dan waktu boot.
   FPS rata-rata biasanya tidak banyak berubah. Tidak ada "RAM booster" atau tweak placebo.

## 2. Alur

```
SCAN (read-only, tanpa admin) → PILIH (checklist) → BACKUP (otomatis) → JALANKAN (laporan per item) → UNDO (kapan saja)
```

## 3. Pilihan teknologi (perlu persetujuan)

| | **PowerShell 5.1 + WPF** (rekomendasi) | C# / .NET single-file exe |
|---|---|---|
| Install | Tidak perlu. PS 5.1 dan WPF sudah ada di semua Windows 10/11 | Tidak perlu (.NET Framework 4.8) atau ~70 MB kalau self-contained |
| Bisa diaudit | **Ya, kode bisa langsung dibaca.** Penting untuk tool yang mengubah sistem | Harus percaya pada binary (kecuali source dibuka + build reproducible) |
| Antivirus / SmartScreen | Script `.ps1` relatif aman. Pola `irm \| iex` sering dicurigai, jadi distribusi pakai zip | exe tanpa tanda tangan dari dev baru sering kena SmartScreen/AV heuristic |
| UI | Cukup bagus (XAML). Agak lambat di startup | Lebih mulus, lebih fleksibel |
| Contoh nyata | Chris Titus WinUtil | O&O ShutUp10++ |

**Rekomendasi: PowerShell 5.1 + WPF.** Alasannya:

- Untuk tool debloat, kepercayaan adalah fitur utama. User (atau temannya yang ngerti) bisa membaca persis apa yang dilakukan.
- Logikanya sama dengan script yang sudah teruji.

Distribusi: zip berisi `Start-HeartnetDebloat.cmd` (double-click). Nanti `.ps1` bisa ditandatangani (Authenticode) kalau sudah ada sertifikat.

## 4. Arsitektur

```
HeartnetDebloat/
  Start-HeartnetDebloat.cmd      launcher (powershell -ExecutionPolicy Bypass -File app\Main.ps1)
  app/
    Main.ps1                     jendela WPF (ui/MainWindow.xaml)
    core/   Scan, Backup, Apply, Undo, Report, Safety, Lang
    handlers/                    satu file per jenis aksi (lihat tabel di bawah): detect / backup / apply / verify / undo
    catalog/*.psd1               DATA item: id, kategori, target persis, risiko, default, kunci teks, guard
    probes/*.ps1                 deteksi khusus: vendor OEM, OneDrive KFM, printer, Bluetooth, SSD/HDD, Hyper-V, dll.
    lang/id.psd1, en.psd1        semua teks UI dan penjelasan (Indonesia dulu, Inggris menyusul)
  tests/                         Pester: validasi katalog, cek bentrok dengan daftar "jangan disentuh"
Data backup: %ProgramData%\HeartnetDebloat\runs\<yyyyMMdd-HHmmss>\  manifest.json, reg\, tasks\, files\, report.html
```

**Katalog = data, handler = kode generik.** Undo diturunkan dari jenis aksi, bukan ditulis ulang per item, jadi semua item otomatis punya undo.

| Handler | Backup sebelum ubah | Aksi | Undo |
|---|---|---|---|
| `RegValue` | nilai lama persis (ada/tidak, tipe, data) di manifest + `reg export` key sebagai cadangan | set nilai | tulis ulang nilai lama, atau hapus kalau dulu tidak ada |
| `Service` | StartType + status lama (untuk service template: nilai `Start` registry) | stop + Disabled | kembalikan StartType, start kalau dulu jalan |
| `ScheduledTask` | `Export-ScheduledTask` XML | disable (task bawaan) / unregister (task sisa) | enable / register ulang dari XML |
| `StartupEntry` | byte StartupApproved lama | set "disabled" di StartupApproved (entry Run tidak dihapus) | kembalikan byte lama / hapus kalau dulu tidak ada |
| `Appx` | nama paket + PackageFamilyName + ID Store | `Remove-AppxPackage` (user ini) | `Add-AppxPackage -Register` kalau paket provisioned masih ada, kalau tidak → tombol buka Store |
| `Win32Uninstall` | entri ARP (DisplayName, UninstallString, tipe installer) | uninstaller resmi (Inno `/SILENT`, MSI `/x /qb`, lainnya interaktif) | tidak otomatis → link download resmi. **Tidak pernah dicentang default** |
| `PnpDevice` | InstanceId + status | `Disable-PnpDevice` (hanya device itu) | `Enable-PnpDevice` |
| `FileMove` | path asli | pindah ke folder backup (bukan hapus) | pindah balik |

**Pemisahan hak akses (penting).**

- Scan berjalan **tanpa admin**.
- Saat "Jalankan", item **scope user** (HKCU, Appx) dikerjakan oleh proses UI yang tidak elevated. Item **scope machine** (HKLM, service, task, device) dikerjakan oleh worker elevated (UAC sekali) yang membaca file rencana JSON.
- Ini mencegah bug klasik: kalau admin-nya akun lain, HKCU di proses elevated adalah HKCU **akun admin**, bukan milik user.

## 5. Katalog item

Kode risiko:

- **R** = rendah, dicentang default
- **O** = opsional, tidak dicentang
- **E** = eksperimen, tidak dicentang + peringatan ekstra
- **i** = info saja, tidak ada aksi

Semua target dicocokkan dengan **nama persis**. Satu-satunya pola adalah prefix Edge (lihat C), dan itu juga diverifikasi lewat path exe-nya.

### A. Aplikasi bawaan (Appx, user ini)
Deteksi: `Get-AppxPackage -Name <persis>`. Undo: Store (atau register ulang).

| Default | Paket |
|---|---|
| R | Clipchamp.Clipchamp, Microsoft.BingNews, Microsoft.BingWeather, Microsoft.BingSearch, Microsoft.GetHelp, Microsoft.MicrosoftOfficeHub, Microsoft.MicrosoftSolitaireCollection, Microsoft.People, Microsoft.PowerAutomateDesktop, Microsoft.Windows.DevHome, Microsoft.WindowsFeedbackHub, Microsoft.WindowsMaps, Microsoft.ZuneVideo, Microsoft.MixedReality.Portal, MicrosoftWindows.Client.WebExperience (Widgets), C27EB4BA.DropboxOEM, microsoft.windowscommunicationsapps (Mail & Calendar, sudah dipensiunkan Microsoft) |
| O | Microsoft.Copilot, Microsoft.OutlookForWindows, Microsoft.Todos, MicrosoftCorporationII.MicrosoftFamily, MicrosoftCorporationII.QuickAssist, MicrosoftTeams, MSTeams, Microsoft.Whiteboard, Microsoft.MicrosoftJournal, Phone Link (Microsoft.YourPhone + MicrosoftWindows.CrossDevice) |

Penjelasan untuk tiap aplikasi berisi apa fungsinya dan "kalau kamu pakai X, jangan dicentang".
Hapus untuk semua user (deprovision) **tidak** masuk v1.

### B. Iklan & saran Windows (HKCU, semua R)
| ID | Isi |
|---|---|
| `ads.cdm` | 13 nilai ContentDeliveryManager: saran di Start/Settings/lock screen, tips, **pemasangan diam-diam aplikasi promosi** (supaya Clipchamp dkk. tidak kembali) |
| `ads.start` | Rekomendasi di Start (`Start_IrisRecommendations`) + iklan OneDrive di Explorer (`ShowSyncProviderNotifications`) |
| `ads.tailored` | Tailored experiences + "Finish setting up your device" (Scoobe) |
| `ads.search` | Hasil web Bing + search highlights. Termasuk satu **policy** HKCU, jadi ada catatan "managed by your organization" |

### C. Aplikasi startup
- Deteksi: Run HKCU/HKLM (+WOW6432Node), folder Startup user & common, status StartupApproved. Semua entri ditampilkan dengan nama, path, dan publisher.
- R hanya untuk sampah yang dikenal:
  - `MicrosoftEdgeAutoLaunch_*`: suffix-nya beda per user, jadi dicocokkan pakai prefix **dan** target harus `msedge.exe`
  - asisten browser (mis. "Opera GX Browser Assistant")
- Entri lain O, dengan penjelasan "aplikasinya tetap ada, hanya tidak auto-start".
- OneDrive: lihat guard K.

### D. Software OEM
Vendor dideteksi lewat `Win32_ComputerSystem.Manufacturer`. Targetnya nama service/task/appx/ARP yang persis.

| ID | Deteksi | Aksi | Risiko |
|---|---|---|---|
| `oem.lenovo.udc` | service `UDCService`, task `\Lenovo\UDC\*` | disable service + task | R |
| `oem.lenovo.vantage` | appx `E046963F.LenovoCompanion`, ARP "Lenovo Vantage Service", service `LenovoVantageService`, task `\Lenovo\Vantage\*` | hapus app, uninstall service, disable service + task | O. Catatan: atur Conservation Mode/baterai dulu. Bisa dipasang lagi dari Store |
| `oem.lenovo.imcontroller` | service `ImControllerService`, task `\Lenovo\ImController\*` | disable | E. Di beberapa model tombol Fn bisa terpengaruh, jadi ada instruksi tes Fn+Q/volume/brightness |
| `oem.lenovo.extras` | ARP persis: Lenovo Now, Lenovo AvatarMaster, Legion Arena | uninstaller resmi | O (uninstall tidak bisa di-undo otomatis) |
| `oem.other.*` | ASUS / HP / Dell / Acer / MSI: dideteksi lalu ditampilkan sebagai **i "belum diverifikasi"** | (belum ada) | Diaktifkan per vendor setelah diuji di unit asli/VM |

**Tidak pernah disentuh:** driver Fn/hotkey (LenovoFnAndFunctionKeys, FnHotkeyUtility, Lenovo Utility), Armoury Crate/MSI Center bagian kontrol kipas, driver/service audio, GPU, dan chipset.

### E. Audio enhancer Nahimic (Lenovo, MSI, Dell/Alienware, dll.)
`audio.nahimic` (O): service `NahimicService` + task **`NahimicTask32` dan `NahimicTask64`** + appx `A-Volute.Nahimic`.
Driver/APO audio **tidak disentuh**. Speaker tetap normal, hanya efek enhancer yang hilang.

### F. Sisa antivirus pra-instal (McAfee, Norton)
- `av.leftovers` (R): produk **sudah tidak ada di ARP**, tapi masih ada folder task `\McAfee\` atau `C:\ProgramData\McAfee`. Task diekspor lalu di-unregister, folder dipindah ke backup.
- Kalau produknya **masih terpasang**: i. Arahkan ke uninstall lewat Settings atau tool resmi vendor (MCPR / Norton Remove & Reinstall).

### G. Microsoft 365 / Office pra-instal (Click-to-Run)
- Deteksi: `HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration` → `ProductReleaseIds` (beda-beda tiap PC) + ARP.
- `office.c2r` = **i + panduan**: tombol membuka Settings > Apps dan link resmi `aka.ms/SaRA-OfficeUninstallFromPC`.
- Tidak di-automasi di v1. Di laptop asli, cara ARP maupun `DisplayLevel=False productstoremove=AllProducts` gagal (17002 / 30038).

### H. Xbox
| ID | Isi | Risiko |
|---|---|---|
| `xbox.bgrecord` | Matikan "Record what happened" (`HistoricalCaptureEnabled=0`) | R |
| `xbox.all` | Appx GamingApp, XboxGamingOverlay, XboxGameOverlay, XboxSpeechToTextOverlay, Xbox.TCUI, XboxIdentityProvider + service XblAuthManager, XblGameSave, XboxNetApiSvc + Game Bar/DVR off | O. Guard: kalau ada `Microsoft.GamingServices` / game Store, ada peringatan keras: "game Game Pass/Store/yang login Xbox tidak akan jalan. Steam aman" |
| `xbox.gip` | Service `XboxGipSvc` (controller Xbox) | O, ditanya terpisah. Guard: kalau ada controller/adapter Xbox terdeteksi → jangan |
| | XboxGameCallableUI | i: komponen sistem, tidak bisa dihapus |

### I. Telemetri & privasi
| ID | Isi | Risiko |
|---|---|---|
| `tel.services` | `DiagTrack` + `dmwappushservice` → Disabled | R |
| `tel.level` | Policy `AllowTelemetry=1` (Required/minimum) + `DoNotShowFeedbackNotifications=1` | R + catatan "managed by your organization" |
| `tel.tasks` | 8 task persis: MareBackup, CEIP Consolidator, UsbCeip, DiskDiagnosticDataCollector, Siuf DmClient(+OnScenarioDownload), WER QueueReporting, Autochk Proxy | R |
| `tel.wer` | Windows Error Reporting off | R |
| `tel.input` | Pengumpulan data ketikan/tulisan tangan off | R |
| `tel.activity` | Activity history (policy) off | R |
| `tel.feedback` | Pertanyaan feedback off | R |
| `tel.speech` | Daftar bahasa tidak dibagikan ke situs + online speech recognition off | R. Catatan: voice typing online ikut mati |

### J. Sistem & performa
| ID | Isi | Risiko / guard |
|---|---|---|
| `sys.deliveryopt` | Policy `DODownloadMode=0`: update tidak di-upload ke PC lain. Windows Update tetap normal | R |
| `sys.edgebg` | Policy Edge `StartupBoostEnabled=0`, `BackgroundModeEnabled=0` (hanya kalau Edge ada) | R + catatan "managed" |
| `sys.mapsbroker` | Service `MapsBroker` off | R |
| `sys.spooler` | Print Spooler off. "Microsoft Print to PDF" ikut mati, "Save as PDF" di browser tetap jalan | O. Guard: printer fisik terdeteksi (dibaca dari registry, karena WMI gagal kalau Spooler mati) → diblokir |
| `sys.sysmain` | SysMain off | E. Guard: disk sistem HDD → disarankan jangan |
| `sys.bgapps` | Policy `LetAppsRunInBackground=2` (hanya aplikasi Store). Discord/Steam/Chrome tidak terpengaruh | E. Notifikasi aplikasi Store bisa telat |
| `sys.faststartup` | `HiberbootEnabled=0`: shutdown bersih, boot ~3-5 detik lebih lama | O |
| `sys.bluetooth` | Disable **hanya adapter radio** (device class Bluetooth dengan service `BTHUSB`/radio, bukan cocok nama "Adapter"). Service `bthserv`/`BTAGService`/`BthAvctpSvc` → Disabled. Template `BluetoothUserService` `Start=4` | E. Guard: ada perangkat ter-pair → peringatan keras. Penjelasan: adapter yang dimatikan memang tampil "Error / CM_PROB_DISABLED", itu normal |
| `sys.browserbg` | Chrome/Opera "Continue running background apps" | i + panduan |

### K. OneDrive (guard Known Folder Move)
- Deteksi KFM: `HKCU\...\Explorer\User Shell Folders` (Desktop, Personal, My Pictures, dll.) mengarah ke dalam `%OneDrive%`.
- `od.startup` (O): disable startup OneDrive. **Diblokir kalau KFM aktif**, dengan penjelasan "Desktop/Documents/Pictures kamu ada di OneDrive. Kalau OneDrive mati, backup berhenti diam-diam".
- Temuan khusus: **KFM aktif + startup OneDrive sudah mati** → tampil sebagai ⚠ "file kamu tidak ter-backup". Kondisi ini ada di laptop ini sekarang.
- Uninstall OneDrive: tidak ada di v1. Nanti pun tidak boleh selama KFM aktif.

### L. Info saja (tidak pernah diubah)
- Defender (real-time, Tamper Protection), Firewall, Memory Integrity (HVCI), VBS, Windows Update.
- Hyper-V / Virtual Machine Platform / WSL dan siapa yang memakainya (mis. aplikasi Claude, Docker). Pesannya: "jangan dimatikan".
- Windows Search: disebut saja, tidak diubah kecuali nanti user opt-in.

### Tweak yang sengaja TIDAK ada (ditampilkan di app supaya user tahu)
- Nagle/TCPNoDelay, timer `bcdedit`, mematikan IPv6
- Ultimate Performance di laptop
- Mematikan Defender/Windows Update/Hyper-V
- "RAM booster"/pembersih RAM
- Hapus driver audio/GPU, sentuh VPN/Tailscale

## 6. Safety check (dari pengalaman di laptop asli)
1. **Nama persis.** Pola `bth` dulu sempat kena `webthreatdefsvc`. Setiap target katalog divalidasi terhadap daftar "jangan disentuh" lewat tes otomatis.
2. **Guard OneDrive KFM** (bagian K).
3. **Pemberitahuan policy.** Setiap item yang menulis ke `...\Policies\...` diberi label, dan sebelum dijalankan muncul ringkasan "Settings/Edge akan menampilkan *managed by your organization*, itu normal".
4. **Verify-after.** Setelah aksi, deteksi dijalankan ulang. Kalau masih terdeteksi → "gagal" + penjelasan + langkah resmi. Ini pelajaran dari Office.
5. **Restore point.**
   - Cek dulu System Protection di C:.
   - Batas 1 restore point per 24 jam di-bypass sementara (`SystemRestorePointCreationFrequency`), lalu dikembalikan.
   - Kalau gagal → user diberi tahu dan harus setuju dulu sebelum lanjut. Backup per item tetap ada.
6. **Konteks user** (bagian 4): item HKCU/Appx tidak dikerjakan oleh proses elevated.
7. **Uninstaller.**
   - Tipe installer dideteksi.
   - Kalau perlu klik manual, user diberi tahu. UAC juga dijelaskan.
   - Hasilnya diverifikasi lewat ARP.
8. **Cek hardware.** Printer, perangkat Bluetooth ter-pair, controller Xbox, SSD vs HDD, laptop vs desktop.
9. **Tidak menghapus file.** Hanya dipindah ke backup. Uninstall adalah satu-satunya aksi destruktif, dan selalu opt-in.
10. **Pending reboot** dideteksi. Laporan akhir menyebut item mana yang butuh restart.

## 7. Identitas visual & maskot

Maskot: kucing abu-biru berkacamata bundar, bertopi tinggi, berkalung, dengan satu sayap kelelawar.
File asli: `assets/mascot-original.jpg`.

Karakternya pas dengan prinsip "audit dulu":

- **Kacamata** = teliti, memeriksa dulu sebelum bertindak.
- **Topi tinggi** = rapi dan sopan, bukan tool "hajar semua".
- **Sayap kelelawar** = berani masuk ke sudut gelap Windows (service, task, telemetri) lalu membereskannya.

**Palet** (diambil dari gambar):

| Token | Warna | Dipakai untuk |
|---|---|---|
| `ink` | `#2E1E1F` | outline tebal, teks utama |
| `plum` | `#3E263C` | header/sidebar (warna topi) |
| `plum-light` | `#6A2D4E` | tombol utama, aksen (pita topi) |
| `wing` | `#761D31` | badge **Eksperimen**, tombol bahaya |
| `slate` | `#708DAB` | badge **Rendah**, link, progress (bulu biru) |
| `paper` | `#ECF6F7` | latar kartu (bulu putih) |
| `amber` | `#E3A33B` | badge **Opsional**, peringatan (mata) |
| `blush` | `#C47B84` | aksen kecil, hover (telinga) |

**Gaya UI.** Mengikuti gaya stiker di gambar:

- kartu putih dengan **outline gelap tebal (2 px)** dan sudut membulat
- bayangan datar (bukan blur)
- font tebal untuk judul
- tema gelap (plum) dan tema terang (paper)

**Maskot di app:**

| Tempat | Versi maskot |
|---|---|
| Ikon app | kepala + topi |
| Header | maskot kecil |
| Saat scan | "kucing memeriksa", kacamata berkilau |
| Hasil | maskot + ringkasan, contoh: "Ketemu 23 hal yang bisa dibereskan, 2 yang perlu kamu cek dulu" |
| Panel peringatan (mis. OneDrive KFM) | maskot dengan ekspresi serius |

Bahan yang masih perlu dibuat dari gambar ini:

- PNG transparan (latarnya sekarang putih)
- `.ico` multi-size
- varian ekspresi (bisa dibuat belakangan; MVP cukup pakai satu gambar)

## 8. Temuan saat membangun MVP scan (2026-10-13)

1. **Tanpa admin, sebagian scheduled task tidak terlihat.** Contoh: 1 dari 2 task `\Lenovo\UDC\` dan semua task `\Lenovo\ImController\`. Karena itu:
   - Scan tetap bisa jalan tanpa admin.
   - UI menampilkan alasannya dan tombol **Scan sebagai admin** (tetap read-only).
2. **Admin akun lain.** Kalau proses elevated dijalankan oleh akun admin yang berbeda dari pemilik `explorer.exe`, scan menampilkan peringatan `warn.otheruser`.
3. **Printer.** `Win32_Printer` error kalau Spooler mati. Deteksi printer dibaca dari `HKLM\...\Control\Print\Printers` + `HKCU\Printers\Connections`.
4. **Jenis disk.** `Get-PhysicalDisk` butuh admin. Kalau jenis disk tidak diketahui, item SysMain diberi peringatan, bukan diam saja.
5. **Radio Bluetooth.** Dideteksi lewat prefix InstanceId (USB\, PCI\, bukan BTH*\ atau SWD\), bukan dari kata "Adapter". Nama adapter Intel tidak mengandung "Adapter".
6. **Entri startup yang diproteksi.** Exe di `System32`/`DriverStore`, ditambah daftar `StartupExe` (SecurityHealth, Realtek, dll.), tetap ditampilkan tapi diblokir.
7. **Task telemetri aktif lagi.** Di laptop referensi, 8 task telemetri yang dimatikan di tahap 6 sekarang berstatus **Ready** lagi. Mungkin di-enable ulang oleh Windows, mungkin dulu gagal tanpa ketahuan. Ini bukti kenapa verify-after dan scan ulang penting.
8. **Bug PS 5.1:** `ConvertTo-JSON` membungkus array jadi `{value, Count}`. Export memakai hashtable + `[object[]]`.

## 9. Rencana kerja
1. ~~Design doc disetujui.~~ Selesai.
2. ~~**MVP Scan**~~ Selesai (v0.1.0-scan):
   - engine scan + katalog (deteksi saja) + probe
   - jendela WPF: daftar per kategori, badge risiko, penjelasan, checkbox default, panel peringatan (KFM dll.), panel info keamanan
   - export laporan JSON/HTML
   - Tombol Jalankan/Undo masih nonaktif
3. Backup + Apply + Undo per handler. Dites di **Windows Sandbox / VM Hyper-V** (Sandbox belum aktif di PC ini, Hyper-V sudah), bukan di laptop utama.
4. Bahasa Inggris, vendor OEM lain, signing, rilis.

## 10. Pertanyaan terbuka
1. Nama maskot?
2. Hak pakai gambar maskot: sudah dipastikan aman untuk dirilis publik?
