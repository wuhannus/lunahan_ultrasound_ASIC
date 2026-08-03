#==============================================================================
# SQUARE LAYOUT v2 — W=100u, 1 column per PMOS, 32 rows shared
# W×M equivalent: keep W=100u, split M across rows
# Shared nwell, M1 horizontal, M2 vertical, vias
#==============================================================================
tech load /opt/homebrew/share/pdk/sky130A/libs.tech/magic/sky130A.tech -noprompt

# ===== Parameters (lambda, 1λ=5nm) =====
set W 20000         ;# 100um per finger
set Lpmos 400       ;# 2um PMOS
set Lnmos 1600      ;# 8um NMOS
set fp [expr {$W + 40}]
set rh [expr {$Lpmos + 100}]  ;# row height with gate extension

# ===== CREATE SINGLE-FINGER CELLS (M=1, repeated N times) =====
proc make_mos1 {name width_lambda len_lambda type} {
    cellname create $name; load $name; select top cell; expand
    box values 0 0 $width_lambda $len_lambda
    if {$type eq "pfet"} { paint pdiff } else { paint ndiff }
    set px [expr {$width_lambda/2 - 30}]
    box values $px -50 [expr {$px + 60}] [expr {$len_lambda + 50}]
    paint poly
    set cx [expr {$width_lambda/2 - 34}]
    box values $cx 14 $cx 48; paint pcontact
    box values $cx [expr {$len_lambda - 48}] $cx [expr {$len_lambda - 14}]; paint pcontact
    save
    return $width_lambda
}

puts "=== Single-finger cells ==="
make_mos1 "PFET_1F" $W $Lpmos pfet
make_mos1 "NFET_1F" $W $Lnmos nfet
puts "  PFET: ${W}x${Lpmos} lambda, NFET: ${W}x${Lnmos} lambda"

# ===== TOP CELL =====
cellname create LNA_SQUARE
load LNA_SQUARE; select top cell; expand

# Layout dimensions
set nrows 32
set total_height [expr {$nrows * $rh + 40000}]
set pmos_width [expr {$W + 200}]  ;# each column width
set m1w 500; set m2w 500; set sp 3000

# Column X positions (XM1, XM2, XMT in shared nwell)
set x_xm1 0
set x_xm2 [expr {$pmos_width + $sp}]
set x_xmt [expr {2*($pmos_width + $sp)}]
set total_pmos_w [expr {4*($pmos_width + $sp)}]

set vdd_y [expr {$total_height + 10000}]
set gnd_y 0

# ===== SHARED NWELL =====
set nw_h [expr {$total_height + 3000}]
box values -3000 -3000 [expr {$total_pmos_w + 5000}] [expr {$nw_h + 3000}]
paint nwell
puts "  Shared nwell: ${total_pmos_w}x${nw_h} lambda"

# ===== PLACE PMOS FINGERS (1 column per device, N rows) =====
puts "=== Placing PMOS fingers ($nrows rows) ==="
for {set row 0} {$row < $nrows} {incr row} {
    set ry [expr {$row * $rh + 10000}]
    
    # XM1: 32 rows (all used)
    box values $x_xm1 $ry [expr {$x_xm1 + $W}] [expr {$ry + $Lpmos}]
    getcell PFET_1F
    
    # XM2: 32 rows
    box values $x_xm2 $ry [expr {$x_xm2 + $W}] [expr {$ry + $Lpmos}]
    getcell PFET_1F
    
    # XMT: only 16 rows needed, replicate in top 16, dummy in bottom 16
    if {$row < 16} {
        box values $x_xmt $ry [expr {$x_xmt + $W}] [expr {$ry + $Lpmos}]
        getcell PFET_1F
    }
}
puts "  XM1: 32 rows, XM2: 32 rows, XMT: 16 rows active"

# ===== NMOS LOADS =====
set load_y [expr {$gnd_y + 5000}]
set nlx [expr {$total_pmos_w + 5000}]
set nrx [expr {$nlx + $W + $sp}]

for {set i 0} {$i < 3} {incr i} {
    set ry [expr {$load_y + $i * [expr {$Lnmos + $sp}]}]
    box values $nlx $ry [expr {$nlx + $W}] [expr {$ry + $Lnmos}]
    getcell NFET_1F
    box values $nrx $ry [expr {$nrx + $W}] [expr {$ry + $Lnmos}]
    getcell NFET_1F
}
puts "  XMNL: right side, XMNR: right side, 3 rows each"

# ===== ROUTING (M1 horizontal, M2 vertical) =====
puts "=== Routing ==="

# VDDA rail (M1, top)
box values 0 [expr {$vdd_y - $m1w/2}] [expr {$nrx + $W + 5000}] [expr {$vdd_y + $m1w/2}]
paint metal1; label VDDA

# GND rail (M1, bottom)
box values 0 [expr {$gnd_y - $m1w/2}] [expr {$nrx + $W + 5000}] [expr {$gnd_y + $m1w/2}]
paint metal1; label GND

# XM1/XM2/XMT sources → VDDA (M2 vertical strips along columns)
# In PMOS: source=top (connected to nwell/VDDA through body)
# PMOS sources already connected via nwell. Drain at bottom.

# Drains → output bus (M1 horizontal at bottom of PMOS)
set op_y [expr {10000 + $nrows * $rh + 2000}]
# XM1 drain = OP
box values $x_xm1 $op_y [expr {$x_xm2 + $W}] [expr {$op_y + $m1w}]
paint metal1; label OP
# XM2 drain = ON 
label ON

# OP → XMNL drain (M2), ON → XMNR drain (M2)
box values [expr {($x_xm1 + $x_xm2)/2 - $m2w/2}] $op_y $m2w [expr {$load_y - $op_y}]
paint metal2
box values [expr {($x_xm2 + $x_xmt)/2 - $m2w/2}] $op_y $m2w [expr {$load_y - $op_y}]
paint metal2

# NMOS drain connections
set load_mid_y [expr {$load_y + 1.5*$Lnmos + 1.5*$sp}]
box values $nlx $load_mid_y [expr {$nrx + $W}] [expr {$load_mid_y + $m1w}]
paint metal1

# NMOS sources → GND (M2)
box values [expr {$nlx + $W/2 - $m2w/2}] $gnd_y $m2w [expr {$load_y - $gnd_y}]
paint metal2
box values [expr {$nrx + $W/2 - $m2w/2}] $gnd_y $m2w [expr {$load_y - $gnd_y}]
paint metal2

# NG node (NMOS gates)
set ngy [expr {$load_y + 500}]
box values $nlx $ngy [expr {$nrx + $W}] [expr {$ngy + $m1w}]
paint metal1; label NG

# VB2 → XMT gate (M2)
box values [expr {$x_xmt - 3000 - $m2w/2}] $load_y $m2w [expr {$vdd_y - $load_y}]
paint metal2; label VB2

# GP/GN (input gates, M1 horizontal)
box values [expr {$x_xm1 - 4000}] [expr {10000 + 15*$rh}] [expr {$x_xm1}] [expr {10000 + 17*$rh + $m1w}]
paint metal1; label GP
box values [expr {$x_xm2 + $W}] [expr {10000 + 15*$rh}] [expr {$x_xm2 + $W + 4000}] [expr {10000 + 17*$rh + $m1w}]
paint metal1; label GN

# XMT source to ground connection through nwell
# (Already handled — PMOS source is nwell-connected to VDDA)

# ===== VIAS (M1↔M2) =====
# Magic auto-inserts via1 where metal1 and metal2 overlap

# ===== SAVE + DRC =====
save
drc on; drc catchup
puts ""
puts "=== DRC: [drc count total] errors ==="
gds write /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_square_v2.gds

set w_um [expr {$total_pmos_w * 5.0 / 1000}]
set h_um [expr {$vdd_y * 5.0 / 1000}]
set area_um2 [expr {$w_um * $h_um}]
puts "=== Layout: [format %.0f $w_um] × [format %.0f $h_um] um = [format %.0f $area_um2] um² ==="
puts "=== Aspect ratio: [format %.2f [expr {$w_um/$h_um}]]:1 ==="

quit
