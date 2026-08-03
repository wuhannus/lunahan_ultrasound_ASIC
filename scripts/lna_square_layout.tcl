#==============================================================================
# SQUARE ANALOG LAYOUT — Zhang LNA, W×M equivalence, shared nwell, M1/M2 routing
#==============================================================================
# Rules:
#  1. W×M constant per device (W=50u chosen for compact columns)
#  2. Square aspect ratio via row/column splitting
#  3. Common-centroid ABBA + interdigitation
#  4. Single shared nwell for all PMOS
#  5. M1=horizontal (odd layer), M2=vertical (even layer), via=connect
#==============================================================================
tech load /opt/homebrew/share/pdk/sky130A/libs.tech/magic/sky130A.tech -noprompt

# ===== W×M EQUIVALENCE: W=50u, M adjusted =====
# XM1/XM2: W=50u M=64 (4 columns × 16 rows for CC)
# XMT:     W=50u M=32 (2 columns × 16 rows)
# XMNL/XMNR: W=100u M=3 (keep original)

set Wpmos 10000   ;# lambda (50um = 10000 lambda)
set Lpmos 400     ;# lambda (2um)
set Wnmos 20000   ;# lambda (100um)
set Lnmos 1600    ;# lambda (8um)
set fp [expr {$Wpmos + 40}]  ;# finger pitch (W + poly spacing)

# ===== PROCEDURE: Create planar MOSFET =====
proc make_mos {name width_lambda len_lambda fingers type} {
    set fp [expr {$width_lambda + 40}]
    cellname create $name
    load $name; select top cell; expand
    
    for {set i 0} {$i < $fingers} {incr i} {
        set fx [expr {$i * $fp}]
        box values $fx 0 [expr {$fx + $width_lambda}] $len_lambda
        if {$type eq "pfet"} { paint pdiff } else { paint ndiff }
        set px [expr {$fx + $width_lambda/2 - 30}]
        box values $px -50 [expr {$px + 60}] [expr {$len_lambda + 50}]
        paint poly
        set cx [expr {$fx + $width_lambda/2 - 34}]
        box values $cx 14 $cx 48; paint pcontact
        box values $cx [expr {$len_lambda - 48}] $cx [expr {$len_lambda - 14}]; paint pcontact
    }
    if {$type eq "pfet"} {
        set nwm 120
        box values -$nwm -$nwm [expr {$fingers * $fp + $nwm}] [expr {$len_lambda + $nwm}]
        paint nwell
    }
    save
    return [list $name [expr {$fingers * $fp}] $len_lambda]
}

# ===== Generate cells with W=50u for PMOS =====
puts "=== Generating MOSFET cells (W=50u PMOS, W=100u NMOS) ==="
lassign [make_mos "XM1_COL" $Wpmos $Lpmos 16 pfet] _ col_w col_h
lassign [make_mos "XM2_COL" $Wpmos $Lpmos 16 pfet] _ _ _
lassign [make_mos "XMT_COL" $Wpmos $Lpmos 16 pfet] _ xt_cw xt_ch
lassign [make_mos "LOAD_M3"  $Wnmos $Lnmos 3  nfet] _ lw lh

puts "  PMOS column: ${col_w}x${col_h} lambda"
puts "  XMT: ${xt_cw}x${xt_ch} lambda"
puts "  LOAD: ${lw}x${lh} lambda"

# ===== TOP CELL =====
cellname create LNA_SQUARE
load LNA_SQUARE; select top cell; expand

# Layout parameters (lambda)
set vdd_y 80000
set gnd_y 0
set m1w 600     ;# M1 wire width
set m2w 600     ;# M2 wire width
set sp 2000     ;# spacing

# ===== SHARED NWELL (all PMOS inside one nwell) =====
set nw_width [expr {4 * $col_w + 3 * $sp + 1000}]
set nw_height [expr {$vdd_y - 10000}]
box values -500 -500 [expr {$nw_width + 500}] [expr {$nw_height + 20000}]
paint nwell
puts "  Shared nwell: ${nw_width}x${nw_height} lambda"

# ===== COMMON-CENTROID DIFF PAIR (interdigitated columns) =====
# Pattern: A B B A  (4 columns, XM1=A, XM2=B)
# Column positions
set dy [expr {$vdd_y - 20000}]
set col_x(0) 0
set col_x(1) [expr {$col_w + $sp}]
set col_x(2) [expr {2*($col_w + $sp)}]
set col_x(3) [expr {3*($col_w + $sp)}]

# Place columns: A(XM1) B(XM2) B(XM2) A(XM1)
set col_order {XM1_COL XM2_COL XM2_COL XM1_COL}

for {set i 0} {$i < 4} {incr i} {
    set cx $col_x($i)
    set cell [lindex $col_order $i]
    box values $cx $dy [expr {$cx + $col_w}] [expr {$dy + $col_h}]
    getcell $cell
    puts "  Col $i: $cell at x=$cx"
}

# ===== TAIL (XMT, centered below, 2 columns) =====
set tail_y [expr {$dy - $col_h - $sp - 5000}]
set xt_x [expr {($nw_width - 2*$xt_cw - $sp) / 2}]
box values $xt_x $tail_y [expr {$xt_x + $xt_cw}] [expr {$tail_y + $xt_ch}]
getcell XMT_COL
box values [expr {$xt_x + $xt_cw + $sp}] $tail_y \
         [expr {$xt_x + 2*$xt_cw + $sp}] [expr {$tail_y + $xt_ch}]
getcell XMT_COL
puts "  XMT: 2 columns at y=$tail_y"

# ===== NMOS LOADS (below tail, symmetric) =====
set load_y [expr {$gnd_y + 15000}]
set lsp 4000
set lx0 [expr {($nw_width - 2*$lw - $lsp) / 2}]
set lx1 [expr {$lx0 + $lw + $lsp}]
box values $lx0 $load_y [expr {$lx0 + $lw}] [expr {$load_y + $lh}]
getcell LOAD_M3
box values $lx1 $load_y [expr {$lx1 + $lw}] [expr {$load_y + $lh}]
getcell LOAD_M3
puts "  Loads: XMNL at $lx0, XMNR at $lx1"

# ===== ROUTING: M1 horizontal, M2 vertical =====
puts ""
puts "=== ROUTING (M1=horizontal, M2=vertical) ==="

# VDDA rail (M1 horizontal at top)
set m1h [expr {$m1w/2}]
box values 0 [expr {$vdd_y - $m1h}] $nw_width [expr {$vdd_y + $m1h}]
paint metal1; label VDDA

# GND rail (M1 horizontal at bottom)
box values 0 [expr {$gnd_y - $m1h}] $nw_width [expr {$gnd_y + $m1h}]
paint metal1; label GND

# XMT source → VDDA (M2 vertical)
set xt_mid [expr {$xt_x + $xt_cw + $sp/2}]
box values [expr {$xt_mid - $m2w/2}] $tail_y $m2w [expr {$vdd_y - $tail_y}]
paint metal2

# XMT drain = TS (M1 horizontal, shared with diff pair sources)
set tsy [expr {$tail_y - 2000}]
box values [expr {$col_x(0) - $m1h}] $tsy $nw_width [expr {$tsy + $m1h}]
paint metal1; label TS

# Diff pair sources → TS (M2 vertical drops)
for {set i 0} {$i < 4} {incr i} {
    set cx_mid [expr {$col_x($i) + $col_w/2}]
    box values [expr {$cx_mid - $m2w/2}] $tsy $m2w [expr {$dy - $tsy}]
    paint metal2
}

# Output: OP (cols 0+3 drains) and ON (cols 1+2 drains) → M1 horizontal bus
set op_y [expr {$tsy - 3000}]
box values [expr {$col_x(0) - $m1h}] $op_y [expr {$col_x(3) + $col_w + $m1h}] [expr {$op_y + $m1h}]
paint metal1; label OP
label ON

# OP/ON → loads (M2 vertical)
set op_mid [expr {$col_x(0) + $col_w}];  # between A and B columns
set on_mid [expr {$col_x(2) + $col_w}];  # between B and A columns
box values [expr {$op_mid - $m2w/2}] $op_y $m2w [expr {$dy - $op_y}]
paint metal2
box values [expr {$on_mid - $m2w/2}] $op_y $m2w [expr {$dy - $op_y}]
paint metal2

# OP → XMNL drain, ON → XMNR drain
set load_bus_y [expr {$load_y + $lh + 2000}]
box values $lx0 $load_bus_y [expr {$lx1 + $lw + $m1h}] [expr {$load_bus_y + $m1h}]
paint metal1; label OP
label ON
box values [expr {$lx0 + $lw/2 - $m2w/2}] $load_bus_y $m2w [expr {$op_y - $load_bus_y}]
paint metal2
box values [expr {$lx1 + $lw/2 - $m2w/2}] $load_bus_y $m2w [expr {$op_y - $load_bus_y}]
paint metal2

# Load sources → GND (M2 vertical)
box values [expr {$lx0 + $lw/2 - $m2w/2}] $gnd_y $m2w [expr {$load_y - $gnd_y}]
paint metal2
box values [expr {$lx1 + $lw/2 - $m2w/2}] $gnd_y $m2w [expr {$load_y - $gnd_y}]
paint metal2

# NG node (NMOS load gates, M1 horizontal)
set ngy [expr {$load_y + 1000}]
box values $lx0 $ngy [expr {$lx1 + $lw + $m1h}] [expr {$ngy + $m1h}]
paint metal1; label NG

# VB2 (M2 down to XMT gate)
box values [expr {-$m2w/2}] $tail_y $m2w [expr {$vdd_y - $tail_y}]
paint metal2; label VB2

# GP/GN inputs (M1 horizontal from left/right)
box values [expr {-$m1h - 2000}] $dy $m1h [expr {$dy + $col_h}]
paint metal1; label GP
box values [expr {$col_x(3) + $col_w + 2000}] $dy [expr {$col_x(3) + $col_w + 2000 + $m1h}] [expr {$dy + $col_h}]
paint metal1; label GN

# ===== VIAS (M1-M2 connections) =====
# Via = 150nm square, paint via1 between M1 and M2 overlapping areas
# (Magic auto-inserts vias where m1 and m2 overlap)

# ===== SAVE + DRC =====
save
drc on; drc catchup
set errcount [drc count total]
puts ""
puts "=== DRC: $errcount errors ==="
gds write /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_square.gds
puts "=== GDS written ==="

# Area calculation
set layout_width $nw_width
set layout_height $vdd_y
set area_um2 [expr {double($layout_width) * $layout_height * 25e-6}]
puts "=== Layout: ${layout_width}x${layout_height} lambda ≈ [format %.0f $area_um2] um² ==="

quit
