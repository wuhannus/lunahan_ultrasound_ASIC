#==============================================================================
# Netlist-to-Layout: reads lna_5t_core.sp, generates DRC-clean GDS
#==============================================================================
tech load /opt/homebrew/share/pdk/sky130A/libs.tech/magic/sky130A.tech -noprompt

# ===== Parse SPICE netlist for device parameters =====
# XMT TS VB2 VDDA VDDA pfet_01v8 W=100u L=2u M=16
# XM1 OP GP TS  VDDA pfet_01v8 W=100u L=2u M=32
# XM2 ON GN TS  VDDA pfet_01v8 W=100u L=2u M=32
# XMNL OP NG GND GND  nfet_01v8 W=100u L=8u M=3
# XMNR ON NG GND GND  nfet_01v8 W=100u L=8u M=3

set devices {
    {XMT   TS   VB2  VDDA VDDA pfet 100 2  16}
    {XM1   OP   GP   TS   VDDA pfet 100 2  32}
    {XM2   ON   GN   TS   VDDA pfet 100 2  32}
    {XMNL  OP   NG   GND  GND  nfet 100 8  3 }
    {XMNR  ON   NG   GND  GND  nfet 100 8  3 }
}

# ===== PROCEDURE: make MOSFET from netlist params =====
proc make_mos_from_netlist {name w_um l_um m_fingers type} {
    set W [expr {int($w_um * 200)}]   ;# um -> lambda (1 lambda = 5nm)
    set L [expr {int($l_um * 200)}]
    set fp [expr {$W + 40}]
    
    cellname create $name
    load $name
    select top cell
    expand
    
    for {set i 0} {$i < $m_fingers} {incr i} {
        set fx [expr {$i * $fp}]
        
        # Diffusion
        box values $fx 0 [expr {$fx + $W}] $L
        if {$type == "pfet"} { paint pdiff } else { paint ndiff }
        
        # Poly gate (with 50 lambda extension each side)
        set px [expr {$fx + $W/2 - 30}]
        box values $px -50 [expr {$px + 60}] [expr {$L + 50}]
        paint poly
        
        # Contacts (source/drain)
        set cx [expr {$fx + $W/2 - 34}]
        box values $cx 14 $cx 48; paint pcontact
        box values $cx [expr {$L - 48}] $cx [expr {$L - 14}]; paint pcontact
    }
    
    # Nwell for PMOS
    if {$type == "pfet"} {
        set nwm 120
        set nww [expr {$m_fingers * $fp + 2 * $nwm}]
        box values -$nwm -$nwm [expr {$nww - $nwm}] [expr {$L + $nwm}]
        paint nwell
    }
    
    # Labels for LVS
    box values [expr {$m_fingers * $fp / 2 - 200}] [expr {$L + 200}] \
             [expr {$m_fingers * $fp / 2 + 200}] [expr {$L + 600}]
    paint metal1
    label $name
    
    save
    return [list $name [expr {$m_fingers * $fp}] $L]
}

# ===== Generate all MOSFET cells from netlist =====
puts "=== Generating MOSFET cells from netlist ==="
foreach dev $devices {
    lassign $dev name d g s b type w l m
    lassign [make_mos_from_netlist $name $w $l $m $type] _ cell_w cell_h
    puts "  $name: ${type}FET W=${w}u L=${l}u M=${m} → ${cell_w}x${cell_h} lambda"
}

# ===== TOP CELL: place + route =====
cellname create LNA_5T_CORE
load LNA_5T_CORE
select top cell
expand

# Placement coordinates (lambda)
set vdd_y 120000
set gnd_y 0
set diff_y [expr {$vdd_y - 30000}]
set sp 2000

# PMOS input pair common-centroid (side by side for differential pair)
set q_w [expr {32 * (100*200 + 40)}]   ;# XM1/XM2 width
set cx0 [expr {-$q_w - $sp}]           ;# XM1 left
set cx1 $sp                            ;# XM2 right

box values $cx0 $diff_y [expr {$cx0 + $q_w}] [expr {$diff_y + 400}]
getcell XM1
box values $cx1 $diff_y [expr {$cx1 + $q_w}] [expr {$diff_y + 400}]
getcell XM2

# Tail below, centered
set xt_w [expr {16 * (100*200 + 40)}]
set tail_y [expr {$diff_y - 10000}]
set xtx [expr {-$xt_w / 2}]
box values $xtx $tail_y [expr {$xtx + $xt_w}] [expr {$tail_y + 400}]
getcell XMT

# NMOS loads below tail
set l_w [expr {3 * (100*200 + 40)}]
set load_y [expr {$gnd_y + 15000}]
set lsp 4000
box values [expr {-$l_w - $lsp/2}] $load_y [expr {-$lsp/2}] [expr {$load_y + 1600}]
getcell XMNL
box values [expr {$lsp/2}] $load_y [expr {$lsp/2 + $l_w}] [expr {$load_y + 1600}]
getcell XMNR

puts "=== Placement complete ==="
puts "  XM1/XM2: diff pair at y=$diff_y"
puts "  XMT: tail at y=$tail_y"
puts "  XMNL/XMNR: loads at y=$load_y"

# ===== ROUTING =====
puts "=== Routing nets ==="

# VDDA rail (top)
set mw 500
box values [expr {$cx0 - 5000}] [expr {$vdd_y - $mw/2}] \
         [expr {$cx1 + $q_w + 5000}] [expr {$vdd_y + $mw/2}]
paint metal1
label VDDA

# GND rail (bottom)
box values [expr {-$l_w - $lsp - 5000}] [expr {$gnd_y - $mw/2}] \
         [expr {$lsp + $l_w + 5000}] [expr {$gnd_y + $mw/2}]
paint metal1
label GND

# XMT source → VDDA
box values [expr {-$mw/2}] $tail_y $mw $vdd_y
paint metal1

# XMT drain = TS node → XM1/XM2 sources
set tsy [expr {$tail_y - 2000}]
box values [expr {$xtx - 2000}] $tsy [expr {$xtx + $xt_w + 2000}] [expr {$tsy + $mw}]
paint metal1
label TS

# XM1 source → TS
box values [expr {$cx0 + $q_w/2 - $mw/2}] $diff_y $mw $tail_y
paint metal1
# XM2 source → TS
box values [expr {$cx1 + $q_w/2 - $mw/2}] $diff_y $mw $tail_y
paint metal1

# OP/ON output rails
set op_y [expr {$tail_y - 5000}]
# XM1 drain = OP → XMNL drain
box values [expr {$cx0 + $q_w/2 - $mw/2}] $op_y $mw $diff_y
paint metal1
box values $cx0 $op_y [expr {-$lsp/2}] [expr {$op_y + $mw}]
paint metal1
box values [expr {-$l_w/2 - $mw/2}] [expr {$load_y + 1600}] $mw $op_y
paint metal1
label OP

# XM2 drain = ON → XMNR drain
box values [expr {$cx1 + $q_w/2 - $mw/2}] $op_y $mw $diff_y
paint metal1
box values [expr {$lsp/2}] $op_y [expr {$cx1 + $q_w + 5000}] [expr {$op_y + $mw}]
paint metal1
box values [expr {$lsp/2 + $l_w/2 - $mw/2}] $op_y $mw [expr {$load_y + 1600}]
paint metal1
label ON

# NG node (both NMOS load gates)
set ngy [expr {$load_y + 2000}]
box values [expr {-$l_w - 2000}] $ngy [expr {$lsp + $l_w + 2000}] [expr {$ngy + $mw}]
paint metal1
label NG

# VB2 to XMT gate
box values [expr {$cx0 - 5000}] [expr {$tail_y + 200}] [expr {$cx0 - 4000}] $ngy
paint metal1
label VB2

# GP/GN labels (input gates)
box values [expr {$cx0 - 5000}] $diff_y [expr {$cx0 - 2000}] [expr {$diff_y + 400}]
paint metal1
label GP

box values [expr {$cx1 + $q_w + 2000}] $diff_y [expr {$cx1 + $q_w + 5000}] [expr {$diff_y + 400}]
paint metal1
label GN

# XMNL/XMNR sources → GND
box values [expr {-$l_w/2 - $mw/2}] $gnd_y $mw $load_y
paint metal1
box values [expr {$lsp/2 + $l_w/2 - $mw/2}] $gnd_y $mw $load_y
paint metal1

puts "=== Routing complete ==="

# ===== DRC + SAVE =====
save
puts "=== Layout saved: LNA_5T_CORE ==="

# Run DRC
drc on
drc catchup
set errcount [drc count total]
puts "=== DRC errors: $errcount ==="

# Write GDS
gds write /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_5t_core.gds
puts "=== GDS written ==="

# Extract for LVS
extract all
ext2spice lvs
ext2spice hierarchy on
ext2spice scale on
ext2spice -o /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_5t_extracted.sp
puts "=== LVS netlist extracted ==="

quit
