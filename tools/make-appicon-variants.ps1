# App 图标 dark / tinted 变体生成器（1.13 起，治「色调模式雾白」）。
# 主屏开深色/色调/透明外观时，iOS 只有平面浅底图标可用就自动生成一版
# ——浅底大块被算成主体，出来是雾白色板（b23 真机实证）。按 iOS 18 规范
# 给 appiconset 补两枚透明底变体，系统才会像原生 App 一样把字形排进玻璃底：
#   AppIcon1024-dark.png  ：字形染浅鼠尾草绿 0x9CB07C（系统垫深色玻璃）
#   AppIcon1024-tinted.png：字形纯白灰度（系统按用户色调染色）
# alpha 从定稿 AppIcon1024.png 按亮度键出（米白纸底≈lum244 → 全透，
# 浓墨≤95 → 全实），笔触深浅化作半透明，水墨质感得以保留。
# 定稿换图（AppIcon1024.png 重导出）必须重跑本脚本。
# 跑法（工程根）：pwsh apps/ios/tools/make-appicon-variants.ps1
Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot "..\App\Assets.xcassets\AppIcon.appiconset"
$srcPath = Join-Path $dir "AppIcon1024.png"
$green = @(156, 176, 124) # 0x9CB07C 浅鼠尾草（与底栏选中态同源）
$lumHi = 240.0  # 亮过此值=纯纸底，全透
$lumLo = 95.0   # 暗过此值=浓墨，全实

function Save-Variant($bytes, $w, $h, $out) {
    $dst = [System.Drawing.Bitmap]::new($w, $h, 'Format32bppArgb')
    $drect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $ddata = $dst.LockBits($drect, 'WriteOnly', 'Format32bppArgb')
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

$dark = [byte[]]::new($orig.Length)
$tint = [byte[]]::new($orig.Length)
$span = $lumHi - $lumLo

for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride
    for ($x = 0; $x -lt $w; $x++) {
        $i = $row + $x * 4
        $b = [double]$orig[$i]; $g = [double]$orig[$i + 1]; $r = [double]$orig[$i + 2]
        $lum = 0.299 * $r + 0.587 * $g + 0.114 * $b
        $a = [byte][Math]::Round(255 * [Math]::Min(1, [Math]::Max(0, ($lumHi - $lum) / $span)))
        # dark：浅鼠尾草字形
        $dark[$i]     = [byte]$green[2]
        $dark[$i + 1] = [byte]$green[1]
        $dark[$i + 2] = [byte]$green[0]
        $dark[$i + 3] = $a
        # tinted：纯白灰度字形（系统拿去按用户色调染）
        $tint[$i] = 255; $tint[$i + 1] = 255; $tint[$i + 2] = 255
        $tint[$i + 3] = $a
    }
}

Save-Variant $dark $w $h (Join-Path $dir "AppIcon1024-dark.png")
Save-Variant $tint $w $h (Join-Path $dir "AppIcon1024-tinted.png")
Write-Output "AppIcon1024.png ($w x $h) -> -dark / -tinted"
