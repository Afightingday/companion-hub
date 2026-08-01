# 底栏图标「未选中态」灰化版生成器（2026-08-01 第 1.8 批）。
# 原件 = 设计稿定稿手绘线条 PNG（Media/art/tabbar/*.png，字节同源勿改）；
# 本脚本逐像素生成 *-off.png：去饱和 75% + 向暖纸色提 18%，alpha 原样保留，
# 笔触浓淡不丢。选中态用原件原色——系统「未选中灰、选中彩」的语感。
# 跑法（Windows PowerShell，工程根）：pwsh apps/ios/tools/tint-tabbar.ps1
Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot "..\App\Media\art\tabbar"
$cream = @(245, 244, 239) # 0xF5F4EF

Get-ChildItem $dir -Filter *.png | Where-Object { $_.Name -notmatch '-off\.png$' } | ForEach-Object {
    $src = [System.Drawing.Bitmap]::new($_.FullName)
    $w = $src.Width; $h = $src.Height
    $rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $data = $src.LockBits($rect, 'ReadOnly', 'Format32bppArgb')
    $bytes = [byte[]]::new($data.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $src.UnlockBits($data)

    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $data.Stride
        for ($x = 0; $x -lt $w; $x++) {
            $i = $row + $x * 4
            $b = [double]$bytes[$i]; $g = [double]$bytes[$i + 1]; $r = [double]$bytes[$i + 2]
            $gray = 0.299 * $r + 0.587 * $g + 0.114 * $b
            $r2 = 0.25 * $r + 0.75 * $gray; $g2 = 0.25 * $g + 0.75 * $gray; $b2 = 0.25 * $b + 0.75 * $gray
            $bytes[$i]     = [byte][Math]::Round([Math]::Min(255, $b2 * 0.82 + $cream[2] * 0.18))
            $bytes[$i + 1] = [byte][Math]::Round([Math]::Min(255, $g2 * 0.82 + $cream[1] * 0.18))
            $bytes[$i + 2] = [byte][Math]::Round([Math]::Min(255, $r2 * 0.82 + $cream[0] * 0.18))
        }
    }

    $dst = [System.Drawing.Bitmap]::new($w, $h, 'Format32bppArgb')
    $drect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $ddata = $dst.LockBits($drect, 'WriteOnly', 'Format32bppArgb')
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ddata.Scan0, $bytes.Length)
    $dst.UnlockBits($ddata)

    $out = Join-Path $dir ($_.BaseName + "-off.png")
    $dst.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $src.Dispose(); $dst.Dispose()
    Write-Output ("{0} -> {1}" -f $_.Name, (Split-Path $out -Leaf))
}
