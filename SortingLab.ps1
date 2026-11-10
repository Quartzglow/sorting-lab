#requires -Version 5.1
<#
    SORTING LAB - a console sorting visualizer
    Run:  powershell -ExecutionPolicy Bypass -File .\SortingLab.ps1
    Best in Windows Terminal (UTF-8 + truecolor).
#>

param([switch]$SelfTest, [switch]$RenderTest, [switch]$AnimTest)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- terminal ---
try {
    if (-not ('VT' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VT {
    [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetConsoleMode(IntPtr h, uint m);
    public static void Enable() {
        IntPtr h = GetStdHandle(-11);
        uint m;
        if (GetConsoleMode(h, out m)) { SetConsoleMode(h, m | 0x0004); }
    }
}
'@
    }
    [VT]::Enable()
} catch { }

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

$script:Esc    = [char]27
$script:Bg     = "$($script:Esc)[48;2;6;6;10m"
$script:Reset  = "$($script:Esc)[0m"
$script:EL     = "$($script:Esc)[K"
$script:ED     = "$($script:Esc)[J"
$script:White  = "$($script:Esc)[1m$($script:Esc)[38;2;255;255;255m"
$script:CursorOff = "$($script:Esc)[?25l"
$script:CursorOn  = "$($script:Esc)[?25h"

# glyphs built from code points so the .ps1 file stays pure ASCII
$script:FULL  = [string][char]0x2588
$script:BLK   = $script:FULL + $script:FULL
$script:SHADE = [string][char]0x2591
$script:PART  = @('', [char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588)

# ----------------------------------------------------------------- palette ---
# gradient: 0 = bottom (yellow) ... 1 = top (deep violet)
$script:Stops = @(
    @(255, 238, 158),
    @(255, 201,  94),
    @(255, 152,  74),
    @(245,  92, 104),
    @(213,  45, 134),
    @(150,  40, 170),
    @( 84,  22, 122),
    @( 38,  11,  66)
)

function Get-GradColor([double]$t) {
    if ($t -lt 0) { $t = 0.0 }
    if ($t -gt 1) { $t = 1.0 }
    $n = $script:Stops.Count - 1
    $x = $t * $n
    $i = [int][Math]::Floor($x)
    if ($i -ge $n) { $i = $n - 1 }
    $f = $x - $i
    $a = $script:Stops[$i]
    $b = $script:Stops[$i + 1]
    return @(
        [int][Math]::Round($a[0] + ($b[0] - $a[0]) * $f),
        [int][Math]::Round($a[1] + ($b[1] - $a[1]) * $f),
        [int][Math]::Round($a[2] + ($b[2] - $a[2]) * $f)
    )
}

function New-Fg([int]$r, [int]$g, [int]$b) {
    return $script:Esc + '[38;2;' + $r + ';' + $g + ';' + $b + 'm'
}

function New-Bg([int]$r, [int]$g, [int]$b) {
    return $script:Esc + '[48;2;' + $r + ';' + $g + ';' + $b + 'm'
}

function Get-GradText([string]$text) {
    $chars = $text.ToCharArray()
    $n = $chars.Length
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        $t = if ($n -le 1) { 0.5 } else { $i / [double]($n - 1) }
        $c = Get-GradColor (1.0 - $t)
        $null = $sb.Append($script:Esc).Append('[1;38;2;').Append($c[0]).Append(';').Append($c[1]).Append(';').Append($c[2]).Append('m').Append($chars[$i])
    }
    $null = $sb.Append($script:Reset)
    return $sb.ToString()
}

$script:AlgoNames = @('Bubble Sort', 'Insertion Sort', 'Selection Sort', 'Quick Sort', 'Merge Sort', 'Heap Sort')
$script:VisNames  = @('Gradient Grid', 'Vertical Bars', 'Horizontal Bars', 'Dot Matrix')

# ------------------------------------------------------------------ render ---
function Get-WinSize {
    if ($script:TestW) { return @([int]$script:TestW, [int]$script:TestH) }
    $w = 120
    $h = 34
    try { $w = [Console]::WindowWidth } catch { }
    try { $h = [Console]::WindowHeight } catch { }
    if ($w -lt 30) { $w = 30 }
    if ($h -lt 12) { $h = 12 }
    return @([int]$w, [int]$h)
}

function Write-Frame([string]$s) {
    if ($null -ne $script:Capture) { $null = $script:Capture.Append($s) }
    else { [Console]::Out.Write($s) }
}

function Update-Palette([int]$hd, [int]$n) {
    if (-not $script:RowFg -or $script:RowFg.Count -ne ($hd + 1)) {
        $script:RowFg = New-Object string[] ($hd + 1)
        for ($r = 1; $r -le $hd; $r++) {
            $t = if ($hd -le 1) { 0.0 } else { ($r - 1) / [double]($hd - 1) }
            $c = Get-GradColor $t
            $script:RowFg[$r] = New-Fg $c[0] $c[1] $c[2]
        }
    }
    if (-not $script:ValFg -or $script:ValFg.Count -ne ($n + 1)) {
        $script:ValFg = New-Object string[] ($n + 1)
        for ($v = 1; $v -le $n; $v++) {
            $t = if ($n -le 1) { 0.0 } else { ($v - 1) / [double]($n - 1) }
            $c = Get-GradColor $t
            $script:ValFg[$v] = New-Fg $c[0] $c[1] $c[2]
        }
    }
}

function Render {
    $sz = Get-WinSize
    $W = $sz[0]
    $H = $sz[1]
    $hd = $H - 7
    if ($hd -lt 6) { $hd = 6 }
    $script:Hdraw = $hd
    $N = $script:N
    $A = $script:A
    $hi1 = $script:Hi1
    $hi2 = $script:Hi2

    Update-Palette $hd $N

    $hts = New-Object int[] $N
    for ($c = 0; $c -lt $N; $c++) {
        $v = [int][Math]::Round((0.12 + 0.88 * $A[$c] / [double]$N) * $hd)
        if ($v -lt 1) { $v = 1 }
        if ($v -gt $hd) { $v = $hd }
        $hts[$c] = $v
    }

    $sb = New-Object System.Text.StringBuilder 16384
    $null = $sb.Append("$($script:Esc)[H")

    # ---- top caption (array size)
    $lbl = [string]$N
    $pad = [Math]::Max(0, [int](($W - $lbl.Length) / 2))
    $null = $sb.Append($script:Bg).Append(' ' * $pad)
    $null = $sb.Append((New-Fg 96 96 112)).Append($lbl).Append($script:EL).Append($script:Reset).Append("`r`n")

    # ---- title
    $title = $script:SortName
    $pad = [Math]::Max(0, [int](($W - $title.Length) / 2))
    $null = $sb.Append($script:Bg).Append(' ' * $pad)
    $null = $sb.Append("$($script:Esc)[1m").Append((New-Fg 246 246 252)).Append($title)
    $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")

    # ---- spacer
    $null = $sb.Append($script:Bg).Append($script:EL).Append($script:Reset).Append("`r`n")

    # ---- visualization
    if ($script:Mode -eq 0) {
        # Gradient Grid
        $cellW = 3
        if (($N * 3 - 1) -gt ($W - 2)) { $cellW = 2 }
        $drawN = $N
        $maxCols = [int][Math]::Floor(($W - 2) / $cellW)
        if ($drawN -gt $maxCols) { $drawN = $maxCols }
        $rowW = $drawN * $cellW - 1
        $pad = [Math]::Max(0, [int](($W - $rowW) / 2))
        $sep = if ($cellW -eq 3) { ' ' } else { '' }
        for ($r = $hd; $r -ge 1; $r--) {
            $fg = $script:RowFg[$r]
            $null = $sb.Append($script:Bg).Append(' ' * $pad).Append($fg)
            for ($c = 0; $c -lt $drawN; $c++) {
                if ($hts[$c] -ge $r) {
                    if ($c -eq $hi1 -or $c -eq $hi2) {
                        $null = $sb.Append($script:White).Append($script:BLK).Append($fg)
                    } else {
                        $null = $sb.Append($script:BLK)
                    }
                } else {
                    $null = $sb.Append('  ')
                }
                if ($sep -and $c -lt ($drawN - 1)) { $null = $sb.Append($sep) }
            }
            $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")
        }
    }
    elseif ($script:Mode -eq 1) {
        # Vertical Bars
        $blocks = $script:PART
        $uArr = New-Object int[] $N
        for ($c = 0; $c -lt $N; $c++) {
            $uArr[$c] = [int][Math]::Round((0.12 + 0.88 * $A[$c] / [double]$N) * $hd * 8)
            if ($uArr[$c] -lt 1) { $uArr[$c] = 1 }
        }
        $drawN = $N
        $maxCols = [int][Math]::Floor(($W - 2) / 3)
        if ($drawN -gt $maxCols) { $drawN = $maxCols }
        $pad = [Math]::Max(0, [int](($W - ($drawN * 3 - 1)) / 2))
        for ($r = $hd; $r -ge 1; $r--) {
            $null = $sb.Append($script:Bg).Append(' ' * $pad)
            $lo = ($r - 1) * 8
            for ($c = 0; $c -lt $drawN; $c++) {
                $u = $uArr[$c]
                if ($u -gt $lo) {
                    $k = $u - $lo
                    if ($k -gt 8) { $k = 8 }
                    $fg = if ($c -eq $hi1 -or $c -eq $hi2) { $script:White } else { $script:ValFg[$A[$c]] }
                    $null = $sb.Append($fg).Append($blocks[$k]).Append($blocks[$k])
                } else {
                    $null = $sb.Append('  ')
                }
                if ($c -lt ($drawN - 1)) { $null = $sb.Append(' ') }
            }
            $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")
        }
    }
    elseif ($script:Mode -eq 2) {
        # Horizontal Bars (several panels if there are more values than rows)
        $panels = [int][Math]::Ceiling($N / [double]$hd)
        $per = [int][Math]::Ceiling($N / [double]$panels)
        $top = [int][Math]::Floor(($hd - $per) / 2)
        $gap = 4
        $panelW = [int][Math]::Floor(($W - 4 - ($panels - 1) * $gap) / $panels)
        if ($panelW -lt 10) { $panelW = 10 }
        $totalW = $panels * $panelW + ($panels - 1) * $gap
        $pad = [Math]::Max(0, [int](($W - $totalW) / 2))
        for ($row = 0; $row -lt $hd; $row++) {
            $r = $row - $top
            if ($r -lt 0 -or $r -ge $per) {
                $null = $sb.Append($script:Bg).Append($script:EL).Append($script:Reset).Append("`r`n")
                continue
            }
            $null = $sb.Append($script:Bg).Append(' ' * $pad)
            for ($p = 0; $p -lt $panels; $p++) {
                $idx = $p * $per + $r
                if ($idx -lt $N) {
                    $v = $A[$idx]
                    $len = [int][Math]::Round((0.12 + 0.88 * $v / [double]$N) * ($panelW - 2))
                    if ($len -lt 1) { $len = 1 }
                    $fg = if ($idx -eq $hi1 -or $idx -eq $hi2) { $script:White } else { $script:ValFg[$v] }
                    $null = $sb.Append($fg).Append($script:FULL * $len).Append(' ' * ($panelW - $len))
                } else {
                    $null = $sb.Append(' ' * $panelW)
                }
                if ($p -lt ($panels - 1)) { $null = $sb.Append(' ' * $gap) }
            }
            $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")
        }
    }
    else {
        # Dot Matrix
        $drawN = $N
        $maxCols = [int][Math]::Floor(($W - 2) / 3)
        if ($drawN -gt $maxCols) { $drawN = $maxCols }
        $pad = [Math]::Max(0, [int](($W - ($drawN * 3 - 1)) / 2))
        for ($r = $hd; $r -ge 1; $r--) {
            $null = $sb.Append($script:Bg).Append(' ' * $pad)
            for ($c = 0; $c -lt $drawN; $c++) {
                if ($hts[$c] -eq $r) {
                    $fg = if ($c -eq $hi1 -or $c -eq $hi2) { $script:White } else { $script:ValFg[$A[$c]] }
                    $null = $sb.Append($fg).Append($script:BLK)
                } else {
                    $null = $sb.Append('  ')
                }
                if ($c -lt ($drawN - 1)) { $null = $sb.Append(' ') }
            }
            $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")
        }
    }

    # ---- spacer
    $null = $sb.Append($script:Bg).Append($script:EL).Append($script:Reset).Append("`r`n")

    # ---- operation counter
    $opsStr = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:N0}', [long]$script:Ops) + ' operations'
    $pad = [Math]::Max(0, [int](($W - $opsStr.Length) / 2))
    $null = $sb.Append($script:Bg).Append(' ' * $pad)
    $null = $sb.Append((New-Fg 190 190 205)).Append($opsStr)
    $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")

    # ---- bottom hint
    if ($script:Done) {
        $hint = 'DONE  -  R: reshuffle   M: menu   Q: quit'
        $hintColor = New-Fg 140 220 150
    }
    elseif ($script:Paused) {
        $hint = 'PAUSED  -  SPACE to resume   M menu   Q quit'
        $hintColor = New-Fg 255 200 90
    }
    else {
        $hint = 'SPACE pause - 1-4 visual - +/- speed - R reshuffle - M menu - Q quit'
        $hintColor = New-Fg 78 78 92
    }
    if ($hint.Length -le ($W - 2)) {
        $pad = [Math]::Max(0, [int](($W - $hint.Length) / 2))
        $null = $sb.Append($script:Bg).Append(' ' * $pad)
        $null = $sb.Append($hintColor).Append($hint)
        $null = $sb.Append($script:EL).Append($script:Reset)
    }

    $null = $sb.Append($script:ED)
    Write-Frame $sb.ToString()
}

# ------------------------------------------------------------------- sorts ---
function Update-StepEvery {
    $n = [double]$script:N
    $est = switch ($script:SortId) {
        0 { $n * $n }
        1 { $n * $n / 2.0 }
        2 { $n * $n / 2.0 }
        3 { $n * [Math]::Log($n, 2) * 2.0 }
        4 { $n * [Math]::Log($n, 2) * 3.0 }
        5 { $n * [Math]::Log($n, 2) * 3.0 }
        default { $n * $n }
    }
    $frames = 1500.0 / [double]$script:Speed
    if ($frames -gt 1200.0) { $frames = 1200.0 }
    $se = [int][Math]::Round($est / $frames)
    if ($se -lt 1) { $se = 1 }
    $script:StepEvery = $se
    $script:FrameDelay = [int][Math]::Round((10 - $script:Speed) * 2.5)
    if ($script:FrameDelay -lt 0) { $script:FrameDelay = 0 }
}

function New-ShuffledArray([int]$n) {
    $a = New-Object int[] $n
    for ($i = 0; $i -lt $n; $i++) { $a[$i] = $i + 1 }
    for ($i = $n - 1; $i -gt 0; $i--) {
        $j = $script:Rng.Next(0, $i + 1)
        $t = $a[$i]; $a[$i] = $a[$j]; $a[$j] = $t
    }
    return , $a
}

function Step {
    $script:Ops++
    if ($script:Abort) { throw [System.OperationCanceledException]::new() }
    if ($script:Ops -ge $script:NextRender) {
        $script:NextRender = $script:Ops + $script:StepEvery
        Invoke-Frame
    }
}

function Handle-Keys {
    while ($true) {
        $has = $false
        try { $has = [Console]::KeyAvailable } catch { return }
        if (-not $has) { return }
        $k = [Console]::ReadKey($true)
        $kc = $k.KeyChar
        $key = $k.Key
        if ($key -eq [ConsoleKey]::Spacebar) {
            $script:Paused = -not $script:Paused
            continue
        }
        if ($key -eq [ConsoleKey]::Escape) {
            $script:Action = 'menu'; $script:Abort = $true; return
        }
        $c = [char]::ToLowerInvariant($kc)
        if ($c -eq 'q') { $script:Action = 'quit';    $script:Abort = $true; return }
        if ($c -eq 'm') { $script:Action = 'menu';    $script:Abort = $true; return }
        if ($c -eq 'r') { $script:Action = 'restart'; $script:Abort = $true; return }
        if ($c -eq '+' -or $c -eq '=') {
            if ($script:Speed -lt 10) { $script:Speed++; Update-StepEvery }
            continue
        }
        if ($c -eq '-' -or $c -eq '_') {
            if ($script:Speed -gt 1) { $script:Speed--; Update-StepEvery }
            continue
        }
        if ($kc -ge [char]'1' -and $kc -le [char]'4') {
            $script:Mode = ([int][char]$kc) - 49
            Render
        }
    }
}

function Invoke-Frame {
    while ($true) {
        Handle-Keys
        if ($script:Abort) { throw [System.OperationCanceledException]::new() }
        Render
        if (-not $script:Paused) {
            if ($script:FrameDelay -gt 0) { Start-Sleep -Milliseconds $script:FrameDelay }
            break
        }
        Start-Sleep -Milliseconds 40
    }
}

function Sort-Bubble {
    $a = $script:A
    $n = $a.Length
    for ($i = 0; $i -lt $n - 1; $i++) {
        $swapped = $false
        $lim = $n - 1 - $i
        for ($j = 0; $j -lt $lim; $j++) {
            $script:Hi1 = $j
            $script:Hi2 = $j + 1
            Step
            if ($a[$j] -gt $a[$j + 1]) {
                $t = $a[$j]; $a[$j] = $a[$j + 1]; $a[$j + 1] = $t
                $script:Swaps++
                Step
                $swapped = $true
            }
        }
        if (-not $swapped) { break }
    }
}

function Sort-Insertion {
    $a = $script:A
    $n = $a.Length
    for ($i = 1; $i -lt $n; $i++) {
        $key = $a[$i]
        $j = $i - 1
        while ($j -ge 0) {
            $script:Hi1 = $j
            $script:Hi2 = $i
            Step
            if ($a[$j] -gt $key) {
                $a[$j + 1] = $a[$j]
                $script:Swaps++
                $script:Hi1 = $j + 1
                Step
                $j--
            }
            else { break }
        }
        if (($j + 1) -ne $i) {
            $a[$j + 1] = $key
            $script:Hi1 = $j + 1
            Step
        }
    }
}

function Sort-Selection {
    $a = $script:A
    $n = $a.Length
    for ($i = 0; $i -lt $n - 1; $i++) {
        $min = $i
        for ($j = $i + 1; $j -lt $n; $j++) {
            $script:Hi1 = $j
            $script:Hi2 = $min
            Step
            if ($a[$j] -lt $a[$min]) { $min = $j }
        }
        if ($min -ne $i) {
            $t = $a[$i]; $a[$i] = $a[$min]; $a[$min] = $t
            $script:Swaps++
            $script:Hi1 = $i
            $script:Hi2 = $min
            Step
        }
    }
}

function Sort-Quick {
    Quick-Range 0 ($script:A.Length - 1)
}

function Quick-Range([int]$lo, [int]$hi) {
    if ($lo -ge $hi) { return }
    $a = $script:A
    $pivot = $a[$hi]
    $i = $lo
    for ($j = $lo; $j -lt $hi; $j++) {
        $script:Hi1 = $j
        $script:Hi2 = $hi
        Step
        if ($a[$j] -lt $pivot) {
            if ($i -ne $j) {
                $t = $a[$i]; $a[$i] = $a[$j]; $a[$j] = $t
                $script:Swaps++
                Step
            }
            $i++
        }
    }
    if ($i -ne $hi) {
        $t = $a[$i]; $a[$i] = $a[$hi]; $a[$hi] = $t
        $script:Swaps++
        $script:Hi1 = $i
        $script:Hi2 = $hi
        Step
    }
    Quick-Range $lo ($i - 1)
    Quick-Range ($i + 1) $hi
}

function Sort-Merge {
    $n = $script:A.Length
    $tmp = New-Object int[] $n
    Merge-Range 0 ($n - 1) $tmp
}

function Merge-Range([int]$lo, [int]$hi, $tmp) {
    if ($lo -ge $hi) { return }
    $mid = [int][Math]::Floor(($lo + $hi) / 2)
    Merge-Range $lo $mid $tmp
    Merge-Range ($mid + 1) $hi $tmp
    $a = $script:A
    for ($k = $lo; $k -le $hi; $k++) { $tmp[$k] = $a[$k] }
    $i = $lo
    $j = $mid + 1
    for ($k = $lo; $k -le $hi; $k++) {
        if ($i -gt $mid) {
            $a[$k] = $tmp[$j]; $j++
        }
        elseif ($j -gt $hi) {
            $a[$k] = $tmp[$i]; $i++
        }
        else {
            $script:Hi1 = $i
            $script:Hi2 = $j
            Step
            if ($tmp[$i] -le $tmp[$j]) { $a[$k] = $tmp[$i]; $i++ }
            else { $a[$k] = $tmp[$j]; $j++ }
        }
        $script:Hi1 = $k
        $script:Hi2 = -1
        Step
    }
}

function Sort-Heap {
    $n = $script:A.Length
    for ($i = [int][Math]::Floor($n / 2) - 1; $i -ge 0; $i--) { Sift-Down $i ($n - 1) }
    for ($end = $n - 1; $end -gt 0; $end--) {
        $a = $script:A
        $t = $a[0]; $a[0] = $a[$end]; $a[$end] = $t
        $script:Swaps++
        $script:Hi1 = 0
        $script:Hi2 = $end
        Step
        Sift-Down 0 ($end - 1)
    }
}

function Sift-Down([int]$root, [int]$end) {
    $a = $script:A
    while ($true) {
        $child = 2 * $root + 1
        if ($child -gt $end) { break }
        if (($child + 1) -le $end) {
            $script:Hi1 = $child
            $script:Hi2 = $child + 1
            Step
            if ($a[$child] -lt $a[$child + 1]) { $child++ }
        }
        $script:Hi1 = $root
        $script:Hi2 = $child
        Step
        if ($a[$root] -lt $a[$child]) {
            $t = $a[$root]; $a[$root] = $a[$child]; $a[$child] = $t
            $script:Swaps++
            Step
            $root = $child
        }
        else { break }
    }
}

function Invoke-Sort {
    switch ($script:SortId) {
        0 { Sort-Bubble }
        1 { Sort-Insertion }
        2 { Sort-Selection }
        3 { Sort-Quick }
        4 { Sort-Merge }
        5 { Sort-Heap }
    }
}

# -------------------------------------------------------------------- menu ---
function Add-MenuRow {
    param($Sb, [string]$Label, [string]$Value, [bool]$Selected, [int]$Left, [int]$BoxW)
    $accent = New-Fg 255 122 89
    $dim    = New-Fg 120 120 140
    $valCol = New-Fg 200 200 215
    $white  = "$($script:Esc)[1m" + (New-Fg 245 245 252)
    $bgSel  = New-Bg 30 16 38
    $marker = if ($Selected) { '> ' } else { '  ' }
    $labelTxt = $Label.PadRight(15)
    $contentLen = 2 + $labelTxt.Length + $Value.Length
    $padRight = [Math]::Max(0, $BoxW - $contentLen)
    if ($Selected) {
        $null = $Sb.Append($bgSel).Append(' ' * $Left).Append($accent).Append($marker)
        $null = $Sb.Append($white).Append($labelTxt).Append($Value)
        $null = $Sb.Append($bgSel).Append(' ' * $padRight)
    }
    else {
        $null = $Sb.Append($script:Bg).Append(' ' * $Left).Append($dim).Append($marker)
        $null = $Sb.Append($labelTxt).Append($valCol).Append($Value)
        $null = $Sb.Append($script:Bg).Append(' ' * $padRight)
    }
    $null = $Sb.Append($script:Bg).Append($script:EL).Append($script:Reset).Append("`r`n")
}

function Draw-Menu {
    $sz = Get-WinSize
    $W = $sz[0]
    $H = $sz[1]
    if ($W -lt 46) { $W = 46 }
    if ($H -lt 18) { $H = 18 }

    $m = $script:Menu
    $sb = New-Object System.Text.StringBuilder 8192
    $null = $sb.Append("$($script:Esc)[2J$($script:Esc)[H")

    $blank = $script:Bg + $script:EL + $script:Reset + "`r`n"
    $top = [Math]::Max(1, [int](($H - 19) / 2))
    for ($i = 0; $i -lt $top; $i++) { $null = $sb.Append($blank) }

    $spaced = ((('SORTING LAB').ToCharArray()) -join ' ')
    $gt = Get-GradText $spaced
    $pad = [Math]::Max(0, [int](($W - $spaced.Length) / 2))
    $null = $sb.Append($script:Bg).Append(' ' * $pad).Append($gt)
    $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")

    $sub = 'console sorting visualizer'
    $pad = [Math]::Max(0, [int](($W - $sub.Length) / 2))
    $null = $sb.Append($script:Bg).Append(' ' * $pad).Append((New-Fg 105 105 125)).Append($sub)
    $null = $sb.Append($script:EL).Append($script:Reset).Append("`r`n")

    $null = $sb.Append($blank)
    $null = $sb.Append($blank)

    $boxW = 50
    $left = [Math]::Max(0, [int](($W - $boxW) / 2))
    $bar = ($script:FULL * $m.Speed) + ($script:SHADE * (10 - $m.Speed))

    Add-MenuRow $sb 'ALGORITHM'     ("< " + $script:AlgoNames[$m.Algo] + " >") ($m.Row -eq 0) $left $boxW
    Add-MenuRow $sb 'VISUALIZATION' ("< " + $script:VisNames[$m.Vis] + " >")  ($m.Row -eq 1) $left $boxW
    Add-MenuRow $sb 'SPEED'         ("< " + $bar + " >")                      ($m.Row -eq 2) $left $boxW

    $null = $sb.Append($blank)

    $startText = '  >  START SORTING  '
    $pad = [Math]::Max(0, [int](($W - $startText.Length) / 2))
    if ($m.Row -eq 3) {
        $null = $sb.Append($script:Bg).Append(' ' * $pad)
        $null = $sb.Append((New-Bg 255 122 89)).Append("$($script:Esc)[1m").Append((New-Fg 24 12 12)).Append($startText)
    }
    else {
        $null = $sb.Append($script:Bg).Append(' ' * $pad)
        $null = $sb.Append("$($script:Esc)[1m").Append((New-Fg 230 120 95)).Append($startText)
    }
    $null = $sb.Append($script:Bg).Append($script:EL).Append($script:Reset).Append("`r`n")

    $null = $sb.Append($blank)

    $foot = 'UP/DOWN  select     LEFT/RIGHT  change     ENTER  start     Q  quit'
    $pad = [Math]::Max(0, [int](($W - $foot.Length) / 2))
    $null = $sb.Append($script:Bg).Append(' ' * $pad).Append((New-Fg 78 78 94)).Append($foot)
    $null = $sb.Append($script:EL).Append($script:Reset)

    Write-Frame $sb.ToString()
}

function Show-Menu {
    $script:Menu = @{ Row = 0; Algo = 3; Vis = 0; Speed = 5 }
    while ($true) {
        Draw-Menu
        $k = [Console]::ReadKey($true)
        $key = $k.Key
        $ch = [char]::ToLowerInvariant($k.KeyChar)

        if ($key -eq [ConsoleKey]::UpArrow)   { $script:Menu.Row = ($script:Menu.Row + 3) % 4; continue }
        if ($key -eq [ConsoleKey]::DownArrow) { $script:Menu.Row = ($script:Menu.Row + 1) % 4; continue }
        if ($key -eq [ConsoleKey]::Enter)     { break }
        if ($key -eq [ConsoleKey]::Escape)    { return $null }
        if ($ch -eq 'q')                      { return $null }

        if ($key -eq [ConsoleKey]::LeftArrow -or $key -eq [ConsoleKey]::RightArrow) {
            $d = if ($key -eq [ConsoleKey]::LeftArrow) { -1 } else { 1 }
            switch ($script:Menu.Row) {
                0 { $script:Menu.Algo  = ($script:Menu.Algo + $d + 6) % 6 }
                1 { $script:Menu.Vis   = ($script:Menu.Vis + $d + 4) % 4 }
                2 { $script:Menu.Speed = [Math]::Min(10, [Math]::Max(1, $script:Menu.Speed + $d)) }
            }
        }
    }
    return @{ Sort = $script:Menu.Algo; Vis = $script:Menu.Vis; Speed = $script:Menu.Speed }
}

# --------------------------------------------------------------------- run ---
function Run-Sort($cfg) {
    $script:SortId   = $cfg.Sort
    $script:SortName = $script:AlgoNames[$cfg.Sort]
    $script:Mode     = $cfg.Vis
    $script:Speed    = $cfg.Speed
    $script:Done     = $false
    $script:Paused   = $false
    $script:Rng      = [System.Random]::new()

    $sz = Get-WinSize
    $W = $sz[0]
    $N = [int][Math]::Floor(($W - 4) / 3)
    if ($N -lt 12) { $N = 12 }
    if ($N -gt 72) { $N = 72 }
    $script:N = $N
    $script:A = New-ShuffledArray $N

    Update-StepEvery

    while ($true) {
        for ($i = $N - 1; $i -gt 0; $i--) {
            $j = $script:Rng.Next(0, $i + 1)
            $t = $script:A[$i]; $script:A[$i] = $script:A[$j]; $script:A[$j] = $t
        }
        $script:Ops = 0
        $script:Swaps = 0
        $script:Hi1 = -1
        $script:Hi2 = -1
        $script:Abort = $false
        $script:Action = ''
        $script:Done = $false
        $script:Paused = $false
        $script:NextRender = 0

        try { Invoke-Sort }
        catch [System.OperationCanceledException] { }

        if ($script:Action -eq 'restart') { continue }
        if ($script:Action -eq 'quit')    { return 'quit' }
        if ($script:Action -eq 'menu')    { return 'menu' }

        $script:Done = $true
        $script:Hi1 = -1
        $script:Hi2 = -1
        Render

        $again = $false
        while (-not $again) {
            $k = [Console]::ReadKey($true)
            $ch = [char]::ToLowerInvariant($k.KeyChar)
            if ($k.Key -eq [ConsoleKey]::Escape) { return 'menu' }
            if ($ch -eq 'q') { return 'quit' }
            if ($ch -eq 'm') { return 'menu' }
            if ($ch -eq 'r') { $again = $true; break }
            if ($ch -eq '1' -or $ch -eq '2' -or $ch -eq '3' -or $ch -eq '4') {
                $script:Mode = ([int][char]$ch) - 49
                Render
            }
            if ($ch -eq '+' -or $ch -eq '=' -or $ch -eq '-' -or $ch -eq '_') {
                if ($ch -eq '+' -or $ch -eq '=') { if ($script:Speed -lt 10) { $script:Speed++ } }
                else { if ($script:Speed -gt 1) { $script:Speed-- } }
                Update-StepEvery
            }
        }
    }
}

# ----------------------------------------------------------------- selftest ---
function Invoke-SelfTest {
    $script:Rng = [System.Random]::new(42)
    $script:Speed = 5
    $script:NextRender = [int]::MaxValue
    $script:Abort = $false
    $script:Paused = $false
    $script:Hi1 = -1
    $script:Hi2 = -1
    $allOk = $true
    for ($s = 0; $s -lt 6; $s++) {
        $script:SortId = $s
        $bad = $false
        foreach ($n in @(1, 2, 3, 5, 17, 40, 71)) {
            $script:N = $n
            $script:A = New-ShuffledArray $n
            Update-StepEvery
            $script:Ops = 0
            $script:Swaps = 0
            Invoke-Sort
            for ($i = 1; $i -lt $n; $i++) {
                if ($script:A[$i - 1] -gt $script:A[$i]) { $bad = $true }
            }
        }
        if ($bad) {
            $allOk = $false
            Write-Host ("{0,-16} FAILED" -f $script:AlgoNames[$s]) -ForegroundColor Red
        }
        else {
            Write-Host ("{0,-16} ok" -f $script:AlgoNames[$s]) -ForegroundColor Green
        }
    }
    if ($allOk) { Write-Host 'ALL TESTS PASSED' -ForegroundColor Green }
    else { Write-Host 'TESTS FAILED' -ForegroundColor Red }
}

# -------------------------------------------------------------------- main ---
if ($SelfTest) {
    Invoke-SelfTest
    return
}

if ($AnimTest) {
    $script:TestW = 120
    $script:TestH = 40
    $script:Rng = [System.Random]::new(3)
    $script:N = 34
    $script:A = New-ShuffledArray 34
    $script:SortId = 3
    $script:SortName = 'Quick Sort'
    $script:Mode = 0
    $script:Ops = 0
    $script:Swaps = 0
    $script:Hi1 = -1
    $script:Hi2 = -1
    $script:Done = $false
    $script:Paused = $false
    $script:Speed = 10
    $script:Abort = $false
    $script:Action = ''
    $script:NextRender = 0
    $script:Capture = New-Object System.Text.StringBuilder
    Update-StepEvery
    $script:FrameDelay = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Invoke-Sort
    $sw.Stop()
    $sorted = $true
    for ($i = 1; $i -lt $script:N; $i++) {
        if ($script:A[$i - 1] -gt $script:A[$i]) { $sorted = $false }
    }
    Write-Host ("anim: sorted=$sorted ops=$($script:Ops) time=$($sw.ElapsedMilliseconds)ms bytes=$($script:Capture.Length)")
    return
}

if ($RenderTest) {
    $script:TestW = 120
    $script:TestH = 40
    $script:Rng = [System.Random]::new(7)
    $script:N = 34
    $script:A = New-ShuffledArray 34
    $script:SortId = 3
    $script:SortName = 'Quick Sort'
    $script:Ops = 14773
    $script:Swaps = 0
    $script:Hi1 = 5
    $script:Hi2 = 6
    $script:Done = $false
    $script:Paused = $false
    $script:Speed = 5
    $script:Capture = New-Object System.Text.StringBuilder
    for ($m = 0; $m -lt 4; $m++) {
        $script:Mode = $m
        Render
    }
    $script:Menu = @{ Row = 1; Algo = 3; Vis = 0; Speed = 5 }
    Draw-Menu
    $out = Join-Path ([IO.Path]::GetTempPath()) 'sortinglab-render.txt'
    [IO.File]::WriteAllText($out, $script:Capture.ToString(), [Text.UTF8Encoding]::new($false))
    $script:Capture = New-Object System.Text.StringBuilder
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 100; $i++) {
        $script:Mode = $i % 4
        Render
    }
    $sw.Stop()
    Write-Host ("render avg: {0:N2} ms" -f ($sw.Elapsed.TotalMilliseconds / 100.0))
    return
}

try {
    try { [Console]::CursorVisible = $false } catch { }
    [Console]::Write($script:CursorOff)
    while ($true) {
        $cfg = Show-Menu
        if ($null -eq $cfg) { break }
        $res = Run-Sort $cfg
        if ($res -eq 'quit') { break }
    }
}
finally {
    try { [Console]::CursorVisible = $true } catch { }
    [Console]::Write("$($script:Reset)$($script:CursorOn)$($script:Esc)[2J$($script:Esc)[H")
}

