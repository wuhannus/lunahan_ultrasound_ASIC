//===========================================================
// lunahan_ultrasound_ASIC — TX Controller
//===========================================================
// Beamforming pulse generator for 16-channel TX array
//===========================================================

module tx_controller #(
    parameter NUM_CHANNELS = 16,
    parameter PHASE_WIDTH  = 8,   // 1.25° resolution
    parameter PULSE_MAX    = 16
) (
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    
    // AXI4-Lite slave interface (MMIO)
    input  wire [31:0]                  s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [31:0]                  s_axi_wdata,
    input  wire [3:0]                   s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [31:0]                  s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    output wire [31:0]                  s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,
    
    // TX output signals
    output wire [NUM_CHANNELS-1:0]      tx_pulse_o,
    output wire [NUM_CHANNELS-1:0]      tx_polarity_o,
    output wire [3:0]                   tx_direction_o,
    output wire                         tx_done_o
);

    //===========================================================
    // Register Map
    //===========================================================
    // 0x00: TX_CTRL    [0]=enable, [3:1]=direction, [7:4]=pulse_count
    // 0x04: TX_FREQ    [15:0] = frequency / 10 Hz (e.g., 4000 for 40 kHz)
    // 0x08-0x44: TX_PHASE[0..15]  [7:0] = phase delay (1.25° per step)
    // 0x48: TX_STATUS  [0]=busy, [15:8]=current pulse
    
    reg             tx_enable;
    reg [2:0]       tx_direction;
    reg [3:0]       tx_pulse_count;
    reg [15:0]      tx_freq_div;  // clk_freq / (2 * tx_freq)
    reg [7:0]       tx_phase [0:NUM_CHANNELS-1];
    
    // State machine
    reg [2:0]       state;
    reg [4:0]       pulse_idx;
    reg [15:0]      cycle_counter;
    reg [7:0]       phase_counter;
    
    localparam S_IDLE   = 3'd0;
    localparam S_PULSE  = 3'd1;
    localparam S_WAIT   = 3'd2;
    localparam S_DONE   = 3'd3;
    
    //===========================================================
    // AXI Register Interface (simplified)
    //===========================================================
    // (Full AXI implementation uses standard handshake)
    
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_enable       <= 1'b0;
            tx_direction    <= 3'd0;
            tx_pulse_count  <= 4'd8;
            tx_freq_div     <= 16'd625;  // 50MHz / (2*40kHz) = 625
        end else if (s_axi_awvalid && s_axi_wvalid) begin
            case (s_axi_awaddr[7:0])
                8'h00: begin
                    tx_enable       <= s_axi_wdata[0];
                    tx_direction    <= s_axi_wdata[3:1];
                    tx_pulse_count  <= s_axi_wdata[7:4];
                end
                8'h04: tx_freq_div <= s_axi_wdata[15:0];
            endcase
        end
    end
    
    //===========================================================
    // Pulse Generation State Machine
    //===========================================================
    
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state           <= S_IDLE;
            pulse_idx       <= 5'd0;
            cycle_counter   <= 16'd0;
            phase_counter   <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (tx_enable) begin
                        state       <= S_PULSE;
                        pulse_idx   <= 5'd0;
                        cycle_counter <= 16'd0;
                        phase_counter <= 8'd0;
                    end
                end
                
                S_PULSE: begin
                    if (cycle_counter < tx_freq_div) begin
                        cycle_counter <= cycle_counter + 16'd1;
                    end else begin
                        cycle_counter <= 16'd0;
                        phase_counter <= phase_counter + 8'd1;
                        
                        // One complete cycle = 2 × tx_freq_div clock cycles
                        if (phase_counter == 8'd1) begin
                            pulse_idx <= pulse_idx + 5'd1;
                            if (pulse_idx >= tx_pulse_count) begin
                                state <= S_WAIT;
                            end
                        end
                    end
                end
                
                S_WAIT: begin
                    // Wait for remaining echoes + guard time
                    if (cycle_counter < 16'd50000) begin  // ~1 ms wait
                        cycle_counter <= cycle_counter + 16'd1;
                    end else begin
                        state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    tx_enable <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    //===========================================================
    // Output Generation with Phase Delays (Beamforming)
    //===========================================================
    
    genvar ch;
    generate
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : gen_tx_channel
            reg ch_pulse;
            reg [7:0] ch_phase_acc;
            
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    ch_pulse        <= 1'b0;
                    ch_phase_acc    <= 8'd0;
                end else if (state == S_PULSE) begin
                    // Accumulate phase
                    ch_phase_acc <= ch_phase_acc + 8'd1;
                    
                    // Generate 40 kHz square wave with phase offset
                    if (ch_phase_acc < (tx_phase[ch] + 8'd128)) begin
                        ch_pulse <= 1'b1;  // High phase
                    end else begin
                        ch_pulse <= 1'b0;  // Low phase
                    end
                    
                    // Reset at end of cycle
                    if (ch_phase_acc == 8'd255)
                        ch_phase_acc <= 8'd0;
                        
                end else begin
                    ch_pulse    <= 1'b0;
                    ch_phase_acc <= 8'd0;
                end
            end
            
            assign tx_pulse_o[ch]    = ch_pulse;
            assign tx_polarity_o[ch] = 1'b0;  // Single-ended mode
        end
    endgenerate
    
    assign tx_direction_o = {1'b0, tx_direction};
    assign tx_done_o = (state == S_DONE);

endmodule
