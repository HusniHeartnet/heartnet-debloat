<p align="center"><img src="app/assets/mascot.png" width="180" alt="Maskot Heartnet Debloat"></p>

<h1 align="center">Heartnet Debloat</h1>
<p align="center"><b>Periksa dulu, bereskan kemudian.</b><br>Debloat Windows 10/11 yang jujur: scan dulu, jelaskan, baru kamu yang memilih.</p>

---

> **Status: versi scan (MVP).** Versi ini **hanya membaca** dan tidak mengubah apa pun di PC kamu.
> Fitur backup, jalankan, dan undo sedang dikerjakan.

## Kenapa beda dari tool debloat lain

- **Audit dulu.** Yang ditampilkan hanya yang benar-benar ada di PC kamu. Tiap item punya penjelasan bahasa sehari-hari, tingkat risiko, dan untung-ruginya.
- **Keamanan tidak disentuh.** Defender, Windows Update, Memory Integrity/VBS, dan Hyper-V hanya ditampilkan sebagai info, tidak pernah dimatikan.
- **Mendeteksi masalah yang terlewat tool lain**, misalnya:
  - Folder Desktop/Documents kamu ada di OneDrive, tapi OneDrive dimatikan, jadi backup berhenti diam-diam.
  - Windows Update atau Defender dimatikan lewat policy oleh tool lain.
  - Jadwal tugas telemetri yang aktif lagi setelah update Windows.
- **Nama persis, bukan pola.** Tidak ada regex longgar yang bisa ikut mengenai service lain. Ada tes otomatis yang menolak katalog kalau menyentuh daftar "jangan disentuh".
- **Backup lengkap + undo per item.** Ini fitur versi berikutnya: restore point, nilai registry lama, status service, XML jadwal tugas, dan file yang dipindah (bukan dihapus).
- **Tidak ada tweak placebo.** Tidak ada "RAM booster", tweak Nagle, timer bcdedit, atau janji FPS naik drastis. Daftarnya ada di dalam app.

## Cara pakai

1. Download repo ini (Code > Download ZIP), lalu extract.
2. Double-click **`Start-HeartnetDebloat.cmd`**.
3. Lihat hasilnya per kategori. Kalau mau hasil yang lengkap, klik **Scan sebagai admin**: beberapa jadwal tugas sistem/pabrikan baru terlihat dengan admin. Scan-nya tetap hanya membaca.
4. **Simpan laporan** ke HTML/JSON kalau mau dibagikan atau ditanyakan ke orang lain.

Mode command line (tanpa jendela):

```
powershell -ExecutionPolicy Bypass -File app\Main.ps1 -Cli -Html laporan.html -Json laporan.json
```

Syarat: Windows 10/11 dengan Windows PowerShell 5.1 (sudah bawaan). Tidak perlu install apa pun.

## Isi repo

| Path | Isi |
|---|---|
| `app/catalog/items.psd1` | Katalog item: **data saja**, mudah diaudit |
| `app/catalog/protected.psd1` | Daftar yang tidak boleh disentuh |
| `app/core/Scan.ps1` | Engine scan (read-only) |
| `app/lang/` | Teks Indonesia (utama) dan Inggris |
| `app/Main.ps1`, `app/ui/` | Aplikasi WPF |
| `tests/Test-Catalog.ps1` | Tes statis: katalog, teks, encoding, sintaks |
| `docs/DESIGN.md` | Design doc |
| `reference/scripts-tested/` | Script asli yang jadi dasar katalog (hardcoded untuk satu laptop; **jangan dijalankan di PC lain**) |

## English

Heartnet Debloat is an audit-first Windows 10/11 debloater. It scans what actually exists on your PC, explains each finding with its risk and trade-off, and never touches security features. This release is a **read-only scan MVP**. Backup, apply, and undo are in progress. The UI is in Indonesian first; English UI strings are available with `-Lang en`, and item texts are being translated.

## Lisensi

Kode: [MIT](LICENSE). Maskot kucing (`assets/`, `app/assets/`) **tidak** termasuk lisensi MIT. Lihat [NOTICE](NOTICE).
