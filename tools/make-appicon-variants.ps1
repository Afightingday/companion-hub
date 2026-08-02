# App 图标三枚生成器（1.15 起：默认也走深底白字，九审祐祐拍板
# 「tinted 预览这个好好看，默认我也就要这个了」）。
# 源 = tools/appicon-master.png（浅色定稿：祐字水墨+藏笑脸压米白纸底，
# 1024²）。字形 alpha 从它按亮度键出（米白纸底≈lum244 → 全透，浓墨≤95
# → 全实，渐变带保笔触水墨感），然后：
#   AppIcon1024.png       ：白字形压墨玉底 #262A24（默认外观，1024 不透明）
#   AppIcon1024-dark.png  ：白字形透明底（深色外观，系统垫深色玻璃）
#   AppIcon1024-tinted.png：白字形灰度透明底（色调外观，系统按用户色调染）
# 深色曾是浅鼠尾草字形，1.15 统一白字形——三种外观一个脸。
# 美术重导出＝换 master 后重跑本脚本。
# 跑法（工程根）：pwsh apps/ios/tools/make-appicon-variants.ps1
Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot "..\App\Assets.xcassets\AppIcon.appiconset"
$srcPath = Join-Path $PSScriptRoot "appicon-master.png"
$inkBg = @(38, 42, 36) # #262A24 墨玉底（九审预览同款，所见即所得）
$lumHi = 240.0  # 亮过此值=纯纸底，全透
$lumLo = 95.0   # 暗过此值=浓墨，全实

function Save-Png($bytes, $w, $h, $fmt, $out) {
    $dst = [System.Drawing.Bitmap]::new($w, $h, $fmt)
    $drect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $ddata = $dst.LockBits($drect, 'WriteOnly', $fmt)
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ddata.Scan0, $bytes.Length)
    $dst.UnlockBits($ddata)
    $dst.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
}

$src = [System.Drawing.Bitmap]::new($srcPath)
$w = $src.Width; $h = $src.Height
$rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
$data = $src.LockBits($rect, 'ReadOnly', 'Format32bppArgb')
$stride = $data.Stride
$orig = [byte[]]::new($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $orig, 0, $orig.Length)
$src.UnlockBits($data)
$src.Dispose()

$glyph = [byte[]]::new($orig.Length)           # 32bpp：白字形+alpha（dark/tinted 共用）
$flatStride = $w * 3 + ((4 - ($w * 3) % 4) % 4) # 24bpp 行对齐
$flat = [byte[]]::new($flatStride * $h)         # 24bpp：白字形压墨玉底（默认）
$span = $lumHi - $lumLo

for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride
    $frow = $y * $flatStride
    for ($x = 0; $x -lt $w; $x++) {
        $i = $row + $x * 4
        $b = [double]$orig[$i]; $g = [double]$orig[$i + 1]; $r = [double]$orig[$i + 2]
        $lum = 0.299 * $r + 0.587 * $g + 0.114 * $b
        $t = [Math]::Min(1, [Math]::Max(0, ($lumHi - $lum) / $span)) # 0=纸底 1=浓墨
        # 透明底白字形
        $glyph[$i] = 255; $glyph[$i + 1] = 255; $glyph[$i + 2] = 255
        $glyph[$i + 3] = [byte][Math]::Round(255 * $t)
        # 墨玉底实拍平：white*t + bg*(1-t)
        $fi = $frow + $x * 3
        $flat[$fi]     = [byte][Math]::Round(255 * $t + $inkBg[2] * (1 - $t))
        $flat[$fi + 1] = [byte][Math]::Round(255 * $t + $inkBg[1] * (1 - $t))
        $flat[$fi + 2] = [byte][Math]::Round(255 * $t + $inkBg[0] * (1 - $t))
    }
}

Save-Png $flat  $w $h 'Format24bppRgb'  (Join-Path $dir "AppIcon1024.png")
Save-Png $glyph $w $h 'Format32bppArgb' (Join-Path $dir "AppIcon1024-dark.png")
Save-Png $glyph $w $h 'Format32bppArgb' (Join-Path $dir "AppIcon1024-tinted.png")
Write-Output "appicon-master.png ($w x $h) -> 默认(墨玉白字) / -dark / -tinted"
