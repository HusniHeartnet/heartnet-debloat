<p align="center"><img src="app/assets/mascot.png" width="180" alt="Maskot Heartnet Debloat"></p>

<h1 align="center">Heartnet Debloat</h1>
<p align="center"><b>Periksa dulu, bereskan kemudian.</b><br>Debloat Windows 10/11 yang jujur: scan dulu, jelaskan, baru kamu yang memilih.</p>

---

> **Status: versi 0.2 (uji coba).** Scan, backup, jalankan, dan undo sudah ada, tapi baru diuji terbatas.
> Pakai di PC yang datanya sudah aman, dan laporkan kalau ada item yang gagal (kirim folder backup-nya, lihat di bawah).

## Kenapa beda dari tool debloat lain

- **Audit dulu.** Yang ditampilkan hanya yang benar-benar ada di PC kamu. Tiap item punya penjelasan bahasa sehari-hari, tingkat risiko, dan untung-ruginya.
- **Keamanan tidak disentuh.** Defender, Windows Update, Memory Integrity/VBS, dan Hyper-V hanya ditampilkan sebagai info, tidak pernah dimatikan.
- **Mendeteksi masalah yang terlewat tool lain**, misalnya:
  - Folder Desktop/Documents kamu ada di OneDrive, tapi OneDrive dimatikan, jadi backup berhenti diam-diam.
  - Windows Update atau Defender dimatikan lewat policy oleh tool lain.
  - Jadwal tugas telemetri yang aktif lagi setelah update Windows.
- **Nama persis, bukan pola.** Tidak ada regex longgar yang bisa ikut mengenai service lain. Ada tes otomatis yang menolak katalog kalau menyentuh daftar "jangan disentuh".
- **Backup lengkap + undo per item.** Restore point, nilai registry lama, status service, XML jadwal tugas, dan file yang dipindah (bukan dihapus). Undo bisa per item atau semuanya.
- **Hasil jujur + sebelum/sesudah.** Tiap item dicek ulang setelah diubah (berhasil / dilewati / gagal + alasan). RAM, CPU, jumlah proses, service, startup, dan jadwal tugas diukur sebelum dan sesudah, dan bisa diukur ulang setelah restart.
- **Tidak ada tweak placebo.** Tidak ada "RAM booster", tweak Nagle, timer bcdedit, atau janji FPS naik drastis. Daftarnya ada di dalam app.

## Cara pakai

Tidak perlu install. Syarat: Windows 10/11 (Windows PowerShell 5.1 sudah bawaan).

1. Download repo ini (**Code > Download ZIP**), lalu **extract** dulu (jangan dijalankan dari dalam ZIP).
2. Double-click **`Start-HeartnetDebloat.cmd`**. Kalau muncul "Windows protected your PC", klik **More info > Run anyway**.
3. Tunggu scan selesai (hanya membaca). Lihat hasilnya per kategori. Item risiko **Rendah** sudah dicentang. **Opsional** dan **Eksperimen** tidak dicentang: baca penjelasannya dulu.
4. Klik **Backup & jalankan**, cek daftar di layar konfirmasi, lalu **Backup & jalankan sekarang**. Windows minta izin admin sekali (UAC).
   - Kalau System Protection mati, app menawarkan untuk menyalakannya supaya restore point bisa dibuat (pilih **Yes**).
   - Setting akun (aplikasi bawaan, iklan, startup) dikerjakan **tanpa** admin supaya yang berubah memang akun kamu. Jangan pakai "Scan sebagai admin" kalau mau menjalankan perubahan dari akun lain.
5. Layar hasil menampilkan tiap item (berhasil / dilewati / gagal + alasan) dan tabel **sebelum vs sesudah**.
6. **Restart**, buka app lagi, **Riwayat & undo > Ukur ulang sekarang** untuk melihat efek setelah restart.
7. Mau mengembalikan? **Riwayat & undo** > **Undo** per item, per run, atau **Undo semuanya**.

Semua catatan backup ada di `C:\ProgramData\HeartnetDebloatuns\<tanggal-jam>\` (`manifest.json` berisi nilai sebelum/sesudah tiap target, `report.html` laporannya). Kalau ada yang gagal, kirim folder itu.

Mode command line (tanpa jendela):

```
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Cli -Html laporan.html -Json laporan.json
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Apply default            (item yang dicentang default)
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Apply tel.tasks,ads.cdm
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -ListRuns
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Measure latest           (ukur ulang, mis. setelah restart)
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Undo latest              (atau: all, <runId>, <runId>:<itemId>)
```

## Isi repo

| Path | Isi |
|---|---|
| `app/catalog/items.psd1` | Katalog item: **data saja**, mudah diaudit |
| `app/catalog/protected.psd1` | Daftar yang tidak boleh disentuh |
| `app/core/Scan.ps1` | Engine scan (read-only) |
| `app/core/Apply.ps1`, `Undo.ps1`, `Backup.ps1`, `Safety.ps1`, `Metrics.ps1` | Backup, jalankan + cek ulang, undo, restore point, cek "jangan disentuh", ukur sebelum/sesudah |
| `app/handlers/` | Satu file per jenis target (registry, service, task, startup, appx, program, Bluetooth, folder): backup / ubah / undo |
| `app/Worker.ps1` | Bagian yang butuh admin (dijalankan lewat satu UAC) |
| `app/lang/` | Teks Indonesia (utama) dan Inggris |
| `app/Main.ps1`, `app/ui/` | Aplikasi WPF |
| `tests/Test-Catalog.ps1` | Tes statis: katalog, teks, encoding, sintaks, handler, safety |
| `tests/Test-Engine.ps1` | Tes engine backup/jalankan/undo dengan handler palsu (tidak mengubah PC) |
| `docs/DESIGN.md` | Design doc |
| `reference/scripts-tested/` | Script asli yang jadi dasar katalog (hardcoded untuk satu laptop; **jangan dijalankan di PC lain**) |

## English

Heartnet Debloat is an audit-first Windows 10/11 debloater. It scans what actually exists on your PC, explains each finding with its risk and trade-off, and never touches security features. Version 0.2 (testing) adds backup, apply with verify-after, before/after measurements, and undo per item or for everything. The UI is in Indonesian first; English UI strings are available with `-Lang en`, and item texts are being translated.

## Lisensi

Kode: [MIT](LICENSE). Maskot kucing (`assets/`, `app/assets/`) **tidak** termasuk lisensi MIT. Lihat [NOTICE](NOTICE).
