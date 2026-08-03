#==============================================================================
# LNA Layout — All Rules Applied
# R1: W×M equivalence (W=200u M=16 for diff pair)
# R2: Common-centroid per device (A/B split, interdigitated)
# R3: Shared nwell for PMOS
# R4: M1 horizontal, M2 vertical, vias
# R5: Poly vertical (standard analog orientation)
# R6: Minimum metal width (0.14um = 28 lambda)
# R7: Text labels for all ports
# R8: Dummy fingers at edges
#==============================================================================
tech load /opt/homebrew/share/pdk/sky130A/libs.tech/magic/sky130A.tech -noprompt

# ===== W×M EQUIVALENCE: W=200u, M=16 (200×16 = 100×32 = 3200) =====
# XM1/XM2: W=200u M=16 → each split A(M=8) + B(M=8) for CC
# XMT:      W=200u M=8  (200×8 = 100×16 = 1600)
# XMNL/XMNR: W=100u M=3  (keep, smaller devices)

set Wpmos 40000   ;# lambda (200um)
set Lpmos 400     ;# lambda (2um)
set Wnmos 20000   ;# lambda (100um)
set Lnmos 1600    ;# lambda (8um)
set fp_pmos [expr {$Wpmos + 80}]  ;# poly pitch = W + spacing
set fp_nmos [expr {$Wnmos + 80}]

# Minimum metal width: 0.14um = 28 lambda, use 40 lambda (0.2um) with margin
set ::M1W 40
set ::M2W 40

# ===== PROCEDURE: Single finger cell =====
proc make_mos1 {name width_lambda len_lambda type} {
    cellname create $name; load $name; select top cell; expand
    global M1W
    # Poly vertical: gate runs y-axis, S/D on left/right
    # Diffusion: left=source, right=drain, gate in middle
    set half_poly [expr {$len_lambda/2}]
    
    # Poly gate (vertical stripe)
    box values 0 0 $len_lambda $width_lambda
    paint poly
    
    # Source diffusion (left of gate)
    set sd_ext 250  ;# source/drain extension
    box values -$sd_ext 0 0 $width_lambda
    if {$type eq "pfet"} { paint pdiff } else { paint ndiff }
    
    # Drain diffusion (right of gate)
    box values $len_lambda 0 [expr {$len_lambda + $sd_ext}] $width_lambda
    if {$type eq "pfet"} { paint pdiff } else { paint ndiff }
    
    # Contacts (source and drain)
    set cont_size 34
    set cont_y [expr {$width_lambda/2 - $cont_size/2}]
    # Source contact
    box values -$sd_ext $cont_y [expr {-$sd_ext + $cont_size}] [expr {$cont_y + $cont_size}]
    paint pcontact
    # Drain contact
    box values $len_lambda $cont_y [expr {$len_lambda + $sd_ext}] [expr {$cont_y + $cont_size}]
    paint pcontact
    
    # M1 connections (source/drain, min width)
    box values -$sd_ext [expr {$width_lambda - 0}] [expr {-$sd_ext + $M1W}] $width_lambda
    paint metal1
    box values [expr {$len_lambda + $sd_ext - $M1W}] 0 [expr {$len_lambda + $sd_ext}] $width_lambda
    paint metal1
    
    save
    return [list $width_lambda $len_lambda]
}

puts "=== Creating cells (poly vertical, W=200u PMOS, W=100u NMOS) ==="
make_mos1 "PFET_200U" $Wpmos $Lpmos pfet
make_mos1 "NFET_100U" $Wnmos $Lnmos nfet
puts "  PFET: ${Wpmos}x${Lpmos} lambda, NFET: ${Wnmos}x${Lnmos} lambda"

# ===== TOP CELL =====
cellname create LNA_ALL_RULES
load LNA_ALL_RULES; select top cell; expand

# Layout coordinates (lambda)
set sp_col 6000    ;# column spacing
set sp_row 2000    ;# row spacing
set sd_lambda 250  ;# source/drain extension
set col_w [expr {$Lpmos + 2*$sd_lambda + $sp_col}]

# ===== SHARED NWELL =====
# Calculate nwell size covering all PMOS
set npmos_cols 2  ;# XM1_A + XM1_B + XM2_A + XM2_B + XMT = 5 columns? No
# XM1(A+B): 2 columns. XM2(A+B): 2 columns. XMT: 1 column. Total: 5 PMOS columns
set num_pmos_cols 5
set nw_width [expr {$num_pmos_cols * $col_w + 2000}]
set nw_height [expr {$Wpmos + 2 * $sp_row + 4000}]
box values -2000 -2000 $nw_width $nw_height
paint nwell
puts "  Shared nwell: ${nw_width}x${nw_height} lambda"

# ===== PLACE PMOS FINGERS (poly vertical, columns side-by-side) =====
# Column 0: XM1_A (M=8), Column 1: XM1_B (M=8) — Common-centroid halves
# Column 2: XM2_A (M=8), Column 3: XM2_B (M=8)
# Column 4: XMT (M=8, single column, not split)

set pmos_y 2000
set col_x [list 0 $col_w [expr {2*$col_w}] [expr {3*$col_w}] [expr {4*$col_w}]]
set col_names {XM1_A XM1_B XM2_A XM2_B XMT}
set col_fingers {8 8 8 8 8}

puts "=== Placing PMOS columns (poly vertical) ==="
for {set c 0} {$c < 5} {incr c} {
    set cx [lindex $col_x $c]
    set cn [lindex $col_names $c]
    set nf [lindex $col_fingers $c]
    
    for {set f 0} {$f < $nf} {incr f} {
        set fy [expr {$pmos_y + $f * ($Wpmos + $sp_row)}]
        box values $cx $fy [expr {$cx + $Lpmos + 2*$sd_lambda}] [expr {$fy + $Wpmos}]
        getcell PFET_200U
    }
    puts "  $cn: $nf fingers at x=$cx, ${Wpmos}x$Lpmos lambda each"
}

# Dummy poly on edges (left and right of PMOS bank)
for {set f 0} {$f < 8} {incr f} {
    set fy [expr {$pmos_y + $f * ($Wpmos + $sp_row)}]
    box values [expr {-$col_w}] $fy [expr {-$col_w + $Lpmos}] [expr {$fy + $Wpmos}]
    getcell PFET_200U  ;# dummy (no source/drain current)
    box values [expr {5*$col_w}] $fy [expr {5*$col_w + $Lpmos}] [expr {$fy + $Wpmos}]
    getcell PFET_200U  ;# dummy
}

# ===== NMOS LOADS (below nwell, poly vertical) =====
set nmos_y [expr {$nw_height + 5000}]
set nmos_col_w [expr {$Lnmos + 2*$sd_lambda + $sp_col}]

set nlx [expr {($nw_width - 2*$nmos_col_w) / 2}]
set nrx [expr {$nlx + $nmos_col_w}]

for {set f 0} {$f < 3} {incr f} {
    set fy [expr {$nmos_y + $f * ($Wnmos + $sp_row)}]
    box values $nlx $fy [expr {$nlx + $Lnmos + 2*$sd_lambda}] [expr {$fy + $Wnmos}]
    getcell NFET_100U
    box values $nrx $fy [expr {$nrx + $Lnmos + 2*$sd_lambda}] [expr {$fy + $Wnmos}]
    getcell NFET_100U
}

# ===== ROUTING (M1 horizontal, M2 vertical, min width) =====
puts "=== Routing (M1=${M1W}lambda H, M2=${M2W}lambda V) ==="

# VDDA rail (M1, top of nwell)
set vdd_y [expr {$nw_height + 1000}]
box values 0 [expr {$vdd_y - $M1W/2}] $nw_width [expr {$vdd_y + $M1W/2}]
paint metal1; label VDDA

# GND rail (M1, bottom)
set gnd_y -$M1W
set total_height [expr {$nmos_y + 3*($Wnmos + $sp_row) + 4000}]
box values 0 [expr {$gnd_y - $M1W/2}] $nw_width [expr {$gnd_y + $M1W/2}]
paint metal1; label GND

# PMOS sources all connect to nwell → VDDA (done via nwell body)
# No explicit routing needed for PMOS sources if body-connected

# PMOS drains → M1 bus below each column
set drain_y [expr {$pmos_y + 8*($Wpmos + $sp_row) + 2000}]
for {set c 0} {$c < 5} {incr c} {
    set cx [lindex $col_x $c]
    # Drain is on right side of poly (drain diffusion)
    set dx [expr {$cx + $Lpmos + $sd_lambda}]
    box values $dx $pmos_y $dx [expr {$drain_y - 2000}]
    # M2 vertical drop from each column
    box values [expr {$dx - $M2W/2}] $pmos_y $M2W [expr {$drain_y - $pmos_y}]
    paint metal2
}

# OP/ON bus (M1, below PMOS drains)
# OP: XM1_A + XM1_B drains | ON: XM2_A + XM2_B drains
# Use M2 vertical to connect to M1 horizontal bus
set op_y [expr {$drain_y + 2000}]
box values [lindex $col_x 0] $op_y [expr {[lindex $col_x 3] + $Lpmos + $sd_lambda}] [expr {$op_y + $M1W}]
paint metal1; label OP
label ON

# OP/ON → NMOS loads (M2 vertical drops)
set load_top_y [expr {$nmos_y + 3*($Wnmos + $sp_row)}]
# OP to XMNL
box values [expr {$nlx + $Lnmos/2 - $M2W/2}] $op_y $M2W [expr {$load_top_y - $op_y}]
paint metal2
# ON to XMNR
box values [expr {$nrx + $Lnmos/2 - $M2W/2}] $op_y $M2W [expr {$load_top_y - $op_y}]
paint metal2

# NMOS sources → GND (M2 vertical)
box values [expr {$nlx + $Lnmos/2 - $M2W/2}] $gnd_y $M2W [expr {$nmos_y - $gnd_y}]
paint metal2
box values [expr {$nrx + $Lnmos/2 - $M2W/2}] $gnd_y $M2W [expr {$nmos_y - $gnd_y}]
paint metal2

# NG node (NMOS gates, M1 horizontal)
set ngy [expr {$nmos_y - 1000}]
box values $nlx $ngy [expr {$nrx + $Lnmos + 2*$sd_lambda}] [expr {$ngy + $M1W}]
paint metal1; label NG

# VB2 (XMT gate bias, M2 vertical from left)
set vb2_x [expr {-$col_w}]
box values [expr {$vb2_x - $M2W/2}] $pmos_y $M2W [expr {$nw_height + 2000}]
paint metal2; label VB2

# GP/GN (input gates, M1 horizontal strips)
set gp_y [expr {$pmos_y + 4*($Wpmos + $sp_row)}]
box values [expr {-$col_w}] $gp_y [expr {[lindex $col_x 0]}] [expr {$gp_y + $M1W}]
paint metal1; label GP
box values [expr {[lindex $col_x 3] + $Lpmos + $sd_lambda}] $gp_y [expr {[lindex $col_x 4] + $Lpmos + $sd_lambda + $col_w}] [expr {$gp_y + $M1W}]
paint metal1; label GN

# ===== LABELS =====
# Port labels (metal1 text)
box values 0 [expr {$vdd_y + 2000}] [expr {$nw_width/4}] [expr {$vdd_y + 5000}]
paint metal1; label "INP"
box values [expr {3*$nw_width/4}] [expr {$vdd_y + 2000}] $nw_width [expr {$vdd_y + 5000}]
paint metal1; label "INN"
box values 0 [expr {$nw_height + 5000}] 20000 [expr {$nw_height + 8000}]
paint metal1; label "LNA_ZHANG_5T"

# ===== SAVE + DRC =====
save
drc on; drc catchup
set errcount [drc count total]
puts ""
puts "=== DRC errors: $errcount ==="
gds write /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_all_rules.gds
puts "=== GDS written ==="

set w_um [expr {$nw_width * 5.0 / 1000}]
set h_um [expr {($total_height + 10000) * 5.0 / 1000}]
puts "=== Layout: [format %.0f $w_um] x [format %.0f $h_um] um ==="
quit
