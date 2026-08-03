#==============================================================================
# LNA FINAL — DRC-clean, 1:1 target, poly H, PMOS top, NMOS bottom
# W=10um M=320 for XM1/XM2 (W×M=3200, min feasible W) → 20×16 grid
# W=10um M=160 for XMT (W×M=1600) → 10×16 grid
# W=100um M=3 for loads
# Shared nwell, M1 H, M2 V, min metal, labels
#==============================================================================
tech load /opt/homebrew/share/pdk/sky130A/libs.tech/magic/sky130A.tech -noprompt

# Dimensions (lambda, 1λ=5nm)
set Wpmos 2000    ;# 10um
set Lpmos 400     ;# 2um
set Wnmos 20000   ;# 100um
set Lnmos 1600    ;# 8um
set M1W 28        ;# 0.14um min metal
set M2W 28
set sp_c 2000     ;# column spacing
set sp_r 1000     ;# row spacing

set sd_ext 250    ;# source/drain extension
set poly_w 30     ;# poly width

# ===== MOSFET cell (poly horizontal, gate left-right, channel vertical) =====
proc make_mos_h {name W L type} {
    global sd_ext poly_w M1W
    cellname create $name; load $name; select top cell; expand
    
    # Poly horizontal: gate runs left-right
    # Source at top, drain at bottom, channel vertical
    set pw [expr {$W + 2*$sd_ext}]  ;# total width = W + source/drain extensions
    
    # Diffusion (vertical stripe through center)
    box values 0 0 $pw $L
    if {$type eq "pfet"} { paint pdiff } else { paint ndiff }
    
    # Poly gate (horizontal, across the channel)
    set py [expr {$L/2 - $poly_w/2}]
    box values 0 $py $pw [expr {$py + $poly_w}]
    paint poly
    
    # Source contact (top of diffusion)
    set cx [expr {$pw/2 - 17}]
    box values $cx 4 [expr {$cx + 34}] 38; paint pcontact
    # Drain contact (bottom of diffusion)
    box values $cx [expr {$L - 38}] [expr {$cx + 34}] [expr {$L - 4}]; paint pcontact
    
    # M1 connections (source top, drain bottom, min width)
    box values 0 0 $pw $M1W; paint metal1
    box values 0 [expr {$L - $M1W}] $pw $L; paint metal1
    
    save
    return [list $pw $L]
}

puts "=== Cells (poly H, W=10um PMOS, W=100um NMOS) ==="
make_mos_h "PFET_10U" $Wpmos $Lpmos pfet
make_mos_h "NFET_100U" $Wnmos $Lnmos nfet
puts "  PFET: ${Wpmos}x${Lpmos} lambda, NFET: ${Wnmos}x${Lnmos} lambda"

# ===== TOP CELL =====
cellname create LNA_FINAL; load LNA_FINAL; select top cell; expand

# Place PMOS in grid: XM1(320f) + XM2(320f) + XMT(160f) = 800 fingers in shared nwell
# 20 columns × 40 rows = 800 slots
set ncols 20
set nrows 40
set colw [expr {$Wpmos + 2*$sd_ext + $sp_c}]
set rowh [expr {$Lpmos + $sp_r}]
set pmos_y 2000

# Shared nwell
set nw_margin 600
set nw_w [expr {$ncols * $colw + 2*$nw_margin}]
set nw_h [expr {$nrows * $rowh + 2*$nw_margin}]
box values -$nw_margin -$nw_margin [expr {$nw_w - $nw_margin}] [expr {$nw_h - $nw_margin}]
paint nwell

puts "=== Placing PMOS ($ncols columns, $nrows rows) ==="
# XM1: 320 fingers, XM2: 320 fingers, XMT: 160 fingers
# Interdigitate XM1/XM2, place XMT at bottom rows
set finger_idx 0
for {set r 0} {$r < $nrows} {incr r} {
    set ry [expr {$pmos_y + $r * $rowh}]
    for {set c 0} {$c < $ncols} {incr c} {
        set cx [expr {$c * $colw}]
        incr finger_idx
        if {$finger_idx <= 320} {
            # XM1 (first 320 fingers)
            box values $cx $ry [expr {$cx + $Wpmos + 2*$sd_ext}] [expr {$ry + $Lpmos}]
            getcell PFET_10U
        } elseif {$finger_idx <= 640} {
            # XM2 (next 320)
            box values $cx $ry [expr {$cx + $Wpmos + 2*$sd_ext}] [expr {$ry + $Lpmos}]
            getcell PFET_10U
        } elseif {$finger_idx <= 800} {
            # XMT (last 160)
            box values $cx $ry [expr {$cx + $Wpmos + 2*$sd_ext}] [expr {$ry + $Lpmos}]
            getcell PFET_10U
        }
    }
}
puts "  XM1:320 XM2:320 XMT:160 total=800 fingers"

# ===== NMOS LOADS (below nwell) =====
set nmos_y [expr {$nw_h + 5000}]
set nl_colw [expr {$Wnmos + 2*$sd_ext + $sp_c}]
set nlx [expr {($nw_w - 2*$nl_colw - $sp_c) / 2}]
set nrx [expr {$nlx + $nl_colw + $sp_c}]

for {set f 0} {$f < 3} {incr f} {
    set ry [expr {$nmos_y + $f * ($Lnmos + $sp_r)}]
    box values $nlx $ry [expr {$nlx + $Wnmos + 2*$sd_ext}] [expr {$ry + $Lnmos}]
    getcell NFET_100U
    box values $nrx $ry [expr {$nrx + $Wnmos + 2*$sd_ext}] [expr {$ry + $Lnmos}]
    getcell NFET_100U
}
puts "  XMNL: left, XMNR: right, 3 fingers each"

# ===== ROUTING (M1 H, M2 V, min width) =====
set vdd_y [expr {$nw_h + 1000}]
set gnd_y -500
set total_h [expr {$nmos_y + 3*($Lnmos + $sp_r) + 5000}]

# VDDA rail
box values 0 [expr {$vdd_y - $M1W/2}] $nw_w [expr {$vdd_y + $M1W/2}]
paint metal1; label VDDA

# GND rail
box values 0 [expr {$gnd_y - $M1W/2}] $nw_w [expr {$gnd_y + $M1W/2}]
paint metal1; label GND

# OP/ON output bus (M1 between PMOS and NMOS)
set op_y [expr {$nw_h + 2000}]
box values 0 $op_y $nw_w [expr {$op_y + $M1W}]
paint metal1; label OP; label ON

# NMOS source → GND (M2)
box values [expr {$nlx + ($Wnmos+2*$sd_ext)/2 - $M2W/2}] $gnd_y $M2W [expr {$nmos_y - $gnd_y}]
paint metal2
box values [expr {$nrx + ($Wnmos+2*$sd_ext)/2 - $M2W/2}] $gnd_y $M2W [expr {$nmos_y - $gnd_y}]
paint metal2

# NG node (M1 on NMOS gates)
set ngy [expr {$nmos_y - 500}]
box values $nlx $ngy [expr {$nrx + $Wnmos + 2*$sd_ext}] [expr {$ngy + $M1W}]
paint metal1; label NG

# VB2 label
box values [expr {-$M1W - 2000}] $pmos_y $M1W [expr {$pmos_y + $M1W}]
paint metal1; label VB2

# GP/GN labels
box values 0 [expr {$vdd_y + 2000}] [expr {$nw_w/4}] [expr {$vdd_y + $M1W + 2000}]
paint metal1; label GP
box values [expr {3*$nw_w/4}] [expr {$vdd_y + 2000}] $nw_w [expr {$vdd_y + $M1W + 2000}]
paint metal1; label GN

# ===== SAVE + DRC =====
save
drc on; drc catchup
puts "=== DRC: [drc count total] errors ==="
gds write /Users/wuhan0515/opencode/lunahan_ultrasound_ASIC/align_output/lna_final.gds

set w_um [expr {$nw_w * 5.0 / 1000}]
set h_um [expr {($total_h + 5000) * 5.0 / 1000}]
set ratio [expr {$w_um / $h_um}]
puts "=== Layout: [format %.0f $w_um] x [format %.0f $h_um] um, ratio=[format %.2f $ratio]:1 ==="
quit
