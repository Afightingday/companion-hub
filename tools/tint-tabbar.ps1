# 底栏图标双态生成器（1.8 灰化版 / 1.11 加选中浅绿版）。
# 原件 = 设计稿定稿手绘线条 PNG（Media/art/tabbar/*.png，字节同源勿改）；
# *-off.png：去饱和 75% + 向暖纸色提 18%（未选中灰）；
# *-on.png ：按笔触深浅整体染向浅鼠尾草绿 0x9CB07C（选中亮，
#            五审「墨绿调浅一点的绿」），白色填充保持白、alpha 保笔触。
# 跑法（Windows PowerShell，工程根）：pwsh apps/ios/tools/tint-tabbar.ps1
Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot "..\App\Media\art\tabbar"
$cream = @(245, 244, 239) # 0xF5F4EF
$green = @(156, 176, 124) # 0x9CB07C 浅鼠尾草

function Save-Variant($bytes, $stride, $w, $h, $out) {
    $dst = [System.Drawing.Bitmap]::new($w, $h, 'Format32bppArgb')
    $drect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $ddata = $dst.LockBits($drect, 'WriteOnly', 'Format32bppArgb')
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ddata.Scan0, $bytes.Length)
    $dst.UnlockBits($ddata)
    $dst.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
}

Get-ChildItem $dir -Filter *.png | Where-Object { $_.Name -notmatch '-(off|on)\.png$' } | ForEach-Object {
    $src = [System.Drawing.Bitmap]::new($_.FullName)
    $w = $src.Width; $h = $src.Height
    $rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $data = $src.LockBits($rect, 'ReadOnly', 'Format32bppArgb')
    $stride = $data.Stride
    $orig = [byte[]]::new($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $orig, 0, $orig.Length)
    $src.UnlockBits($data)
    $src.Dispose()

    $off = [byte[]]::new($orig.Length); $on = [byte[]]::new($orig.Length)
    [Array]::Copy($orig, $off, $orig.Length); [Array]::Copy($orig, $on, $orig.Length)

    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            $i = $row + $x * 4
            $b = [double]$orig[$i]; $g = [double]$orig[$i + 1]; $r = [double]$orig[$i + 2]
            $gray = 0.299 * $r + 0.587 * $g + 0.114 * $b
            # off：去饱和 + 暖纸提亮
            $r2 = 0.25 * $r + 0.75 * $gray; $g2 = 0.25 * $g + 0.75 * $gray; $b2 = 0.25 * $b + 0.75 * $gray
            $off[$i]     = [byte][Math]::Round([Math]::Min(255, $b2 * 0.82 + $cream[2] * 0.18))
            $off[$i + 1] = [byte][Math]::Round([Math]::Min(255, $g2 * 0.82 + $cream[1] * 0.18))
            $off[$i + 2] = [byte][Math]::Round([Math]::Min(255, $r2 * 0.82 + $cream[0] * 0.18))
            # on：按笔触深浅（暗=浓）染向浅绿，白填充保持白
            $t = 1.0 - $gray / 255.0
            $on[$i]     = [byte][Math]::Round(255 * (1 - $t) + $green[2] * $t)
            $on[$i + 1] = [byte][Math]::Round(255 * (1 - $t) + $green[1] * $t)
            $on[$i + 2] = [byte][Math]::Round(255 * (1 - $t) + $green[0] * $t)
        }
    }

    Save-Variant $off $stride $w $h (Join-Path $dir ($_.BaseName + "-off.png"))
    Save-Variant $on  $stride $w $h (Join-Path $dir ($_.BaseName + "-on.png"))
    Write-Output ("{0} -> -off / -on" -f $_.Name)
}
