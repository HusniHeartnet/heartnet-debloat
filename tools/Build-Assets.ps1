# Builds app\assets\mascot.png (transparent) and app\assets\icon.ico from assets\mascot-original.jpg.
# Removes the white background with a flood fill from the image border, so the white fur inside the
# dark outline stays white. Run: powershell -ExecutionPolicy Bypass -File tools\Build-Assets.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$src = Join-Path $root 'assets\mascot-original.jpg'
$outDir = Join-Path $root 'app\assets'
New-Item -ItemType Directory -Force $outDir | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class HDMask {
    // Flood-fills near-white pixels connected to the border and makes them transparent.
    // Pixels next to the filled area get partial alpha based on how white they are (anti-aliasing).
    public static Bitmap RemoveBackground(Bitmap input, int threshold) {
        int w = input.Width, h = input.Height;
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp)) { g.DrawImage(input, 0, 0, w, h); }
        Rectangle rect = new Rectangle(0, 0, w, h);
        BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        byte[] px = new byte[data.Stride * h];
        Marshal.Copy(data.Scan0, px, 0, px.Length);
        bool[] bg = new bool[w * h];
        Queue<int> q = new Queue<int>();
        Func<int, bool> white = i => { int o = (i / w) * data.Stride + (i % w) * 4; return px[o] >= threshold && px[o + 1] >= threshold && px[o + 2] >= threshold; };
        for (int x = 0; x < w; x++) { q.Enqueue(x); q.Enqueue((h - 1) * w + x); }
        for (int y = 0; y < h; y++) { q.Enqueue(y * w); q.Enqueue(y * w + w - 1); }
        while (q.Count > 0) {
            int i = q.Dequeue();
            if (bg[i] || !white(i)) continue;
            bg[i] = true;
            int x = i % w, y = i / w;
            if (x > 0) q.Enqueue(i - 1); if (x < w - 1) q.Enqueue(i + 1);
            if (y > 0) q.Enqueue(i - w); if (y < h - 1) q.Enqueue(i + w);
        }
        for (int i = 0; i < w * h; i++) {
            int o = (i / w) * data.Stride + (i % w) * 4;
            if (bg[i]) { px[o + 3] = 0; continue; }
            int x = i % w, y = i / w;
            bool edge = (x > 0 && bg[i - 1]) || (x < w - 1 && bg[i + 1]) || (y > 0 && bg[i - w]) || (y < h - 1 && bg[i + w]);
            if (edge) {
                int lum = Math.Min(px[o], Math.Min(px[o + 1], px[o + 2]));
                int a = 255 - Math.Max(0, (lum - 120) * 255 / 135);
                px[o + 3] = (byte)Math.Max(0, Math.Min(255, a));
            }
        }
        Marshal.Copy(px, 0, data.Scan0, px.Length);
        bmp.UnlockBits(data);
        return bmp;
    }

    public static Rectangle Bounds(Bitmap bmp) {
        int minX = bmp.Width, minY = bmp.Height, maxX = 0, maxY = 0;
        for (int y = 0; y < bmp.Height; y++) for (int x = 0; x < bmp.Width; x++) {
            if (bmp.GetPixel(x, y).A > 16) { if (x < minX) minX = x; if (y < minY) minY = y; if (x > maxX) maxX = x; if (y > maxY) maxY = y; }
        }
        return new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
    }
}
'@

function Save-Square([System.Drawing.Bitmap]$img, [System.Drawing.Rectangle]$crop, [int]$size, [string]$path) {
    $side = [Math]::Max($crop.Width, $crop.Height)
    $pad = [int]($side * 0.04)
    $side += 2 * $pad
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $scale = $size / $side
    $dw = $crop.Width * $scale; $dh = $crop.Height * $scale
    $dest = New-Object System.Drawing.RectangleF ((($size - $dw) / 2), (($size - $dh) / 2), $dw, $dh)
    $g.DrawImage($img, $dest, $crop, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    if ($path) { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) }
    return $bmp
}

$orig = [System.Drawing.Bitmap]::FromFile($src)
$clean = [HDMask]::RemoveBackground($orig, 232)
$bounds = [HDMask]::Bounds($clean)
"Mascot bounds: $bounds"

(Save-Square $clean $bounds 512 (Join-Path $outDir 'mascot.png')).Dispose()

# Icon: head + hat only (top ~58% of the figure), so it stays readable at 16-32 px.
$head = New-Object System.Drawing.Rectangle $bounds.X, $bounds.Y, ([int]($bounds.Width * 0.80)), ([int]($bounds.Height * 0.58))
$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $b = Save-Square $clean $head $s $null
    $ms = New-Object IO.MemoryStream
    $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    , $ms.ToArray()
}
(Save-Square $clean $head 256 (Join-Path $outDir 'icon-256.png')).Dispose()

# ICO with PNG-compressed entries (supported since Windows Vista)
$ico = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter $ico
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $pngs[$i].Length
    $bw.Write([byte]($s % 256)); $bw.Write([byte]($s % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
    $offset += $len
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $outDir 'icon.ico'), $ico.ToArray())
$clean.Dispose(); $orig.Dispose()
Get-ChildItem $outDir | Select-Object Name, Length
