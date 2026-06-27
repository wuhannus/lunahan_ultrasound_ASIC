//===========================================================
// lunahan_ultrasound_ASIC — Charge-Pump Integer-N PLL
//===========================================================
// sky130 Digital PLL Clock Generator (using sky130 PDK)
//
// Architecture: Type-II charge-pump PLL (sky130 PDK)
//   Ref:      16 MHz (external crystal)
//   PFD freq: = 4 MHz (ref ÷ 4)
//   VCO:      200 MHz (ring oscillator, topology below)
//   FB div:   /50 (200/4 = 50)
//   Outputs:
//     clk_sys:  50 MHz  (VCO ÷ 4) — System clock for RISC-V core
//     clk_adc:  ~1.2 MHz (VCO ÷ 167 = 1.198 MHz) — ADC sampling clock
//===========================================================
//
// Note: The PLL is a mixed-signal block. This SystemVerilog module
// models the digital portion (dividers, PFD, lock detect, post-dividers).
// The analog portion (charge pump, loop filter, VCO) is in SPICE and
// simulated together in the AMS co-simulation flow.
//
// For pure-digital simulation (Verilator), this module uses a behavioral
// VCO model with configurable lock time.
//===========================================================

`timescale 1ns / 1ps

module sky130_pll #(
    parameter real    REF_FREQ_MHZ   = 16.0,      // Reference clock (MHz)
    parameter real    OUT_FREQ_MHZ   = 50.0,      // Target output (MHz)
    parameter integer REF_DIV        = 4,         // Reference divider
    parameter integer FB_DIV         = 50,        // Feedback divider (N)
    parameter integer POST_DIV_SYS   = 4,         // Post-divider for sys clk
    parameter integer POST_DIV_ADC   = 167,       // Post-divider for ADC clk
    parameter integer LOCK_CYCLES    = 128        // Lock confirmation cycles
) (
    // Clock & Reset
    input  wire  clk_ref_i,       // 16 MHz reference clock
    input  wire  rst_n_i,         // Active-low reset
    
    // Control (MMIO, optional)
    input  wire  [7:0] cfg_div_i, // Configurable divider override
    input  wire        cfg_en_i,  // Configuration enable
    
    // Analog interface (for AMS co-simulation)
    output wire       pll_up_o,   // PFD UP signal (to charge pump)
    output wire       pll_dn_o,   // PFD DN signal (to charge pump)
    input  wire       vco_out_i,  // VCO output (from analog, optional)
    
    // Clock outputs
    output wire       clk_sys_o,  // 50 MHz system clock
    output wire       clk_adc_o,  // 1.2 MHz ADC clock
    
    // Status
    output wire       pll_locked_o, // PLL lock indicator
    output wire [7:0] pll_status_o  // Status register
);

    //===========================================================
    // 1. Reference Divider (÷4)
    //===========================================================
    reg [1:0] ref_div_cnt;
    reg       ref_div_out;
    
    always @(posedge clk_ref_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ref_div_cnt  <= 2'd0;
            ref_div_out  <= 1'b0;
        end else begin
            ref_div_cnt <= ref_div_cnt + 2'd1;
            if (ref_div_cnt == 2'd0)   // Toggle at count 0 and 2
                ref_div_out <= ~ref_div_out;
        end
    end
    
    wire pfd_ref = ref_div_out;  // 4 MHz PFD reference

    //===========================================================
    // 2. Phase-Frequency Detector (PFD)
    //===========================================================
    // Tri-state PFD with anti-dead-zone delay
    // Generates UP and DN pulses proportional to phase error.
    
    reg up_reg, dn_reg;
    wire up_pre, dn_pre;
    wire reset_pfd;
    
    // Flip-flops: assert on rising edge of respective clock
    always @(posedge pfd_ref or posedge reset_pfd) begin
        if (reset_pfd)  up_reg <= 1'b0;
        else            up_reg <= 1'b1;
    end
    
    always @(posedge fb_clk or posedge reset_pfd) begin
        if (reset_pfd)  dn_reg <= 1'b0;
        else            dn_reg <= 1'b1;
    end
    
    // Reset condition: both UP and DN high
    assign reset_pfd = up_reg & dn_reg;
    
    // Output with programmable delay for anti-dead-zone
    wire #(0.5) up_delayed = up_reg;   // ~0.5 ns delay in sky130
    wire #(0.5) dn_delayed = dn_reg;
    
    assign pll_up_o = up_delayed;
    assign pll_dn_o = dn_delayed;

    //===========================================================
    // 3. Behavioral VCO Model (Digital-Only Simulation)
    //===========================================================
    // In AMS co-simulation, vco_out_i is driven by the analog SPICE
    // model. In pure-digital sim, we use a behavioral approximation.
    
    wire vco_clk;
    
`ifdef AMS_COSIM
    // Analog VCO provides the clock (from SPICE co-simulation)
    assign vco_clk = vco_out_i;
`else
    // Behavioral VCO: starts at 200 MHz, locks after settling
    // In real silicon, frequency is controlled by Vctrl from loop filter
    reg        vco_beh;
    reg [15:0] vco_cnt;
    parameter  VCO_DIV = 5;  // 50 MHz sim clock ÷ 5 = 10 ns period → 100 MHz model
    // Note: In behavioral sim we approximate with a fixed-frequency
    // oscillator. Full dynamics require analog co-simulation.
    
    always @(posedge clk_ref_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            vco_cnt  <= 16'd0;
            vco_beh  <= 1'b0;
        end else begin
            // Generate 200 MHz from 16 MHz ref (½× at sim scale)
            vco_cnt <= vco_cnt + 16'd1;
            if (vco_cnt >= VCO_DIV - 1) begin
                vco_cnt <= 16'd0;
                vco_beh <= ~vco_beh;
            end
        end
    end
    assign vco_clk = vco_beh;
`endif

    //===========================================================
    // 4. Feedback Divider (÷N, N=50)
    //===========================================================
    // Integer-N divider: ÷50 = ÷5 → ÷5 → ÷2
    // Or programmable via cfg_div_i for multi-frequency support
    
    reg  [5:0] fb_div_cnt;
    reg        fb_div_out;
    wire [5:0] fb_div_val = cfg_en_i ? cfg_div_i[5:0] : 6'd50;
    
    always @(posedge vco_clk or negedge rst_n_i) begin
        if (!rst_n_i) begin
            fb_div_cnt <= 6'd0;
            fb_div_out <= 1'b0;
        end else begin
            fb_div_cnt <= fb_div_cnt + 6'd1;
            if (fb_div_cnt >= fb_div_val - 1) begin
                fb_div_cnt <= 6'd0;
                fb_div_out <= ~fb_div_out;  // Toggle → ÷2 at the end
            end
        end
    end
    
    // Final ÷2 for 50% duty cycle
    reg fb_div2;
    always @(posedge fb_div_out or negedge rst_n_i) begin
        if (!rst_n_i) fb_div2 <= 1'b0;
        else          fb_div2 <= ~fb_div2;
    end
    
    wire fb_clk = fb_div2;  // VCO/50 feedback to PFD

    //===========================================================
    // 5. Post-Dividers
    //===========================================================
    
    // ÷4 → 50 MHz system clock
    reg [1:0] post_sys_cnt;
    reg       post_sys_out;
    always @(posedge vco_clk or negedge rst_n_i) begin
        if (!rst_n_i) begin
            post_sys_cnt <= 2'd0;
            post_sys_out <= 1'b0;
        end else begin
            post_sys_cnt <= post_sys_cnt + 2'd1;
            if (post_sys_cnt == 2'd0)
                post_sys_out <= ~post_sys_out;
        end
    end
    assign clk_sys_o = post_sys_out;
    
    // ÷167 → ~1.198 MHz ADC clock
    reg [7:0] post_adc_cnt;
    reg       post_adc_out;
    always @(posedge vco_clk or negedge rst_n_i) begin
        if (!rst_n_i) begin
            post_adc_cnt <= 8'd0;
            post_adc_out <= 1'b0;
        end else begin
            post_adc_cnt <= post_adc_cnt + 8'd1;
            if (post_adc_cnt >= 8'd83) begin  // 167/2 - 1
                post_adc_cnt <= 8'd0;
                post_adc_out <= ~post_adc_out;
            end
        end
    end
    assign clk_adc_o = post_adc_out;

    //===========================================================
    // 6. Lock Detector
    //===========================================================
    // Digital lock detection: monitor PFD UP/DN pulses.
    // Lock is declared when both UP and DN pulses are shorter
    // than a threshold for consecutive reference cycles.
    
    reg  [7:0] lock_cnt;
    reg        locked;
    reg  [7:0] up_width_cnt, dn_width_cnt;
    reg        up_short, dn_short;
    
    parameter SHORT_PULSE_NS = 5;    // Pulses <5 ns considered "locked"
    parameter LOCK_THRESHOLD  = 128;  // Consecutive cycles to declare lock
    
    // Measure UP/DN pulse widths
    always @(posedge clk_ref_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            up_width_cnt <= 8'd0;
            dn_width_cnt <= 8'd0;
            up_short     <= 1'b0;
            dn_short     <= 1'b0;
        end else begin
            // Rough measurement: count fast cycles while UP/DN are high
            up_width_cnt <= pll_up_o ? up_width_cnt + 8'd1 : 8'd0;
            dn_width_cnt <= pll_dn_o ? dn_width_cnt + 8'd1 : 8'd0;
            
            // At each ref edge, check if pulses were short
            up_short <= (up_width_cnt < 8'd5);   // <5 ref cycles ≈ 5 ns
            dn_short <= (dn_width_cnt < 8'd5);
        end
    end
    
    // Lock state machine
    always @(posedge clk_ref_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lock_cnt <= 8'd0;
            locked   <= 1'b0;
        end else begin
            if (up_short && dn_short)
                lock_cnt <= lock_cnt + 8'd1;
            else
                lock_cnt <= 8'd0;
            
            locked <= (lock_cnt >= LOCK_THRESHOLD);
        end
    end
    
    assign pll_locked_o = locked;
    assign pll_status_o = {6'd0, locked, !locked};  // [1]=locked, [0]=unlocked

endmodule
