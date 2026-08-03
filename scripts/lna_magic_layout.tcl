# LNA Layout Script for Magic VLSI — sky130
# Follows the same parameterized-cell approach as SKILL code
# Key parameters (matching SKILL style): ypitch, nfwid, pfwid, length, finger

tech load /opt/homebrew/share/pdk/sky130A/libs.tech/magic/sky130A.tech -noprompt

# ===== PARAMETERS (SKILL-style) =====
set ypitch 8.0;       # vertical pitch in lambda (lambda=5nm for sky130, so 8=40nm)
set len_lambda 400;   # channel length in lambda (400*5nm=2um)
set nfwid 20000;      # NMOS finger width in lambda (20000*5nm=100um)
set pfwid 20000;      # PMOS finger width in lambda
set finger_m1 8;      # M1 quadrant fingers
set finger_xt 16;     # XMT tail fingers  
set finger_load 3;    # Load fingers
set space_lambda 100; # spacing in lambda

# ===== PROCEDURE: Create MOSFET cell =====
proc make_mos {name width_lambda len_lambda fingers is_pmos} {
    global ypitch
    # Select the cell (create if not exists)
    if {[catch {cellname exists $name}]} {
        cellname create $name
    }
    load $name
    select top cell
    expand
    
    set fp [expr {$width_lambda + 100}]; # finger pitch with spacing
    
    for {set i 0} {$i < $fingers} {incr i} {
        set fx [expr {$i * $fp}]
        
        # Diffusion
        if {$is_pmos} {
            box values $fx 0 [expr {$fx + $width_lambda}] $len_lambda
            paint pdiff
        } else {
            box values $fx 0 [expr {$fx + $width_lambda}] $len_lambda
            paint ndiff
        }
        
        # Poly gate
        set poly_x [expr {$fx + $width_lambda/2 - 30}]
        box values $poly_x -50 [expr {$poly_x + 60}] [expr {$len_lambda + 50}]
        paint poly
        
        # Contacts (source/drain)
        set cont_x [expr {$fx + $width_lambda/2 - 34}]
        box values $cont_x 14 $cont_x 48
        paint pcontact
        box values $cont_x [expr {$len_lambda - 48}] $cont_x [expr {$len_lambda - 14}]
        paint pcontact
    }
    
    # Nwell for PMOS
    if {$is_pmos} {
        set nw_margin 120
        set nw_width [expr {$fingers * $fp + 2 * $nw_margin}]
        box values -$nw_margin -$nw_margin [expr {$nw_width - $nw_margin}] [expr {$len_lambda + $nw_margin}]
        paint nwell
    }
    
    save
    return [list $name [expr {$fingers * $fp}] $len_lambda]
}

puts "=== Creating MOSFET cells ==="

# Create all transistor cells
lassign [make_mos "XM1_Q8_PMOS" $pfwid $len_lambda 8 1] _ q_w q_h
lassign [make_mos "XM2_Q8_PMOS" $pfwid $len_lambda 8 1] _ _ _
lassign [make_mos "XMT_M16_PMOS" $pfwid $len_lambda 16 1] _ xt_w xt_h
lassign [make_mos "LOAD_M3_NMOS" $nfwid $len_lambda 3 0] _ l_w l_h

puts "  XM1 quadrant: ${q_w}x${q_h} lambda"
puts "  XMT tail: ${xt_w}x${xt_h} lambda"
puts "  LOAD: ${l_w}x${l_h} lambda"

# ===== TOP CELL =====
cellname create LNA_ZHANG_SKILL
load LNA_ZHANG_SKILL
select top cell
expand

# Place VDD/GND rails
set vdd_y 120000
set gnd_y 0
box values -100000 $gnd_y 100000 [expr {$gnd_y + 1000}]
paint metal1
box values -100000 [expr {$vdd_y - 1000}] 100000 $vdd_y
paint metal1

# ===== COMMON-CENTROID PLACEMENT (ABBA 2x2) =====
set dy0 [expr {$vdd_y - 30000}]
set sp 2000
set cx_l [expr {-$q_w - $sp}]
set cx_r $sp
set dy1 [expr {$dy0 - $q_h - $sp}]

# Row 1: A(XM1_L) | B(XM2_L)
box values $cx_l $dy0 [expr {$cx_l + $q_w}] [expr {$dy0 + $q_h}]
getcell XM1_Q8_PMOS
box values $cx_r $dy0 [expr {$cx_r + $q_w}] [expr {$dy0 + $q_h}]
getcell XM2_Q8_PMOS

# Row 2: B(XM2_R) | A(XM1_R)
box values $cx_l $dy1 [expr {$cx_l + $q_w}] [expr {$dy1 + $q_h}]
getcell XM2_Q8_PMOS
box values $cx_r $dy1 [expr {$cx_r + $q_w}] [expr {$dy1 + $q_h}]
getcell XM1_Q8_PMOS

puts "  CC placement: ABBA 2x2 at y=${dy0} to ${dy1}"

# ===== TAIL PLACEMENT =====
set dby [expr {$dy1 - 5000}]
set xtx [expr {-$xt_w / 2}]
box values $xtx $dby [expr {$xtx + $xt_w}] [expr {$dby + $xt_h}]
getcell XMT_M16_PMOS
puts "  Tail at ($xtx, $dby)"

# ===== LOAD PLACEMENT =====
set ly [expr {$gnd_y + 15000}]
set lsp 4000
box values [expr {-$l_w - $lsp/2}] $ly [expr {-$lsp/2}] [expr {$ly + $l_h}]
getcell LOAD_M3_NMOS
box values [expr {$lsp/2}] $ly [expr {$lsp/2 + $l_w}] [expr {$ly + $l_h}]
getcell LOAD_M3_NMOS
puts "  Loads at y=${ly}"

# ===== ROUTING (simple metal1 connections) =====
# TS node (tail drain)
set tsy [expr {$dby - 2000}]
box values [expr {$xtx - 2000}] $tsy [expr {$xtx + $xt_w + 2000}] [expr {$tsy + 500}]
paint metal1

# Tail source to VDDA
box values -250 $dby [expr {$dby + $xt_h}] [expr {$xt_h + 250}] $vdd_y
paint metal1

# Diff pair sources to TS
box values [expr {$cx_l + $q_w/2 - 250}] $dy1 500 [expr {$dy1 + $q_h}]
paint metal1
box values [expr {$cx_r + $q_w/2 - 250}] $dy1 500 [expr {$dy1 + $q_h}]
paint metal1

# Output routing (simplified)
set midy [expr {$dby - 4000}]
box values [expr {$cx_l - 1000}] $midy [expr {$cx_r + $q_w + 1000}] [expr {$midy + 500}]
paint metal1

# Load connections
box values [expr {-$l_w/2 - 250}] $ly [expr {-$l_w/2 + 250}] [expr {$ly + $l_h}]
paint metal1
box values [expr {$lsp/2 + $l_w/2 - 250}] $ly [expr {$lsp/2 + $l_w/2 + 250}] [expr {$ly + $l_h}]
paint metal1

# Labels
box values -80000 [expr {$vdd_y + 3000}] -50000 [expr {$vdd_y + 8000}]
paint metal1
label VDDA

box values -80000 [expr {$gnd_y - 8000}] -50000 [expr {$gnd_y - 3000}]
paint metal1
label GND

save
puts "=== Layout saved: LNA_ZHANG_SKILL ==="

# Write GDS
gds write /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_magic_skill.gds
puts "GDS written"

quit
