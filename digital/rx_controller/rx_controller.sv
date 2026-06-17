//===========================================================
// lunahan_ultrasound_ASIC — RX Controller
//===========================================================
// ADC data acquisition + Time-of-Flight computation
//===========================================================

module rx_controller #(
    parameter NUM_CHANNELS = 64,
    parameter ADC_WIDTH    = 10,
    parameter TOF_WIDTH    = 16   // in 100 ns units, max range ~11.2 km
) (
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    
    // AXI4-Lite slave interface
    input  wire [31:0]                  s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [31:0]                  s_axi_wdata,
    // ... (remaining AXI signals)
    output wire [31:0]                  s_axi_rdata,
    
    // ADC Interface
    input  wire [ADC_WIDTH-1:0]         adc_data_i,      // ADC parallel data
    input  wire [NUM_CHANNELS-1:0]      adc_eoc_i,       // End of conversion
    output reg  [5:0]                   adc_channel_o,   // Channel select (0-63)
    output reg                          adc_start_o,     // Start conversion
    
    // Status
    output wire                         rx_done_o,
    output wire                         echo_detected_o
);

    //===========================================================
    // Configuration registers
    //===========================================================
    reg             rx_enable;
    reg [5:0]       rx_gain_code;       // 0-63 → -2 to 42 dB
    reg [1:0]       rx_direction;
    reg [9:0]       rx_threshold;       // Detection threshold (mV)
    
    //===========================================================
    // ADC Channel Sequencer (round-robin across 64 channels)
    //===========================================================
    reg [5:0]       current_channel;
    reg [3:0]       conv_cycle;         // 10 conversion cycles per channel
    reg [15:0]      sample_counter;
    reg [ADC_WIDTH-1:0] adc_buffer [0:63];  // Latest sample per channel
    
    parameter MAX_SAMPLES = 1024;  // Samples per frame per channel
    
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            current_channel <= 6'd0;
            conv_cycle      <= 4'd0;
            sample_counter  <= 16'd0;
            adc_start_o     <= 1'b0;
        end else if (rx_enable) begin
            // Channel sequencing
            if (!adc_start_o) begin
                adc_channel_o   <= current_channel;
                adc_start_o     <= 1'b1;
            end
            
            // Wait for conversion complete
            if (adc_eoc_i[current_channel]) begin
                adc_start_o     <= 1'b0;
                adc_buffer[current_channel] <= adc_data_i;
                
                conv_cycle <= conv_cycle + 4'd1;
                if (conv_cycle == 4'd10) begin  // 10 cycles per conversion
                    conv_cycle <= 4'd0;
                    current_channel <= current_channel + 6'd1;
                    
                    if (current_channel == 6'd63) begin
                        sample_counter <= sample_counter + 16'd1;
                        if (sample_counter >= MAX_SAMPLES) begin
                            rx_enable <= 1'b0;
                        end
                    end
                end
            end
        end
    end
    
    //===========================================================
    // Time-of-Flight Computation
    //===========================================================
    reg [TOF_WIDTH-1:0] tof_register [0:NUM_CHANNELS-1];
    reg [NUM_CHANNELS-1:0] echo_detected;
    
    // Echo detection: threshold crossing on rising edge
    genvar ch;
    generate
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : gen_tof
            reg prev_above_threshold;
            
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    tof_register[ch]        <= {TOF_WIDTH{1'b0}};
                    echo_detected[ch]       <= 1'b0;
                    prev_above_threshold    <= 1'b0;
                end else if (rx_enable && adc_eoc_i[ch]) begin
                    // Check for threshold crossing
                    if (adc_data_i > rx_threshold && !prev_above_threshold) begin
                        // Rising edge: record TOF
                        tof_register[ch]  <= sample_counter * (TOF_WIDTH)'(100);  // 100 ns units
                        echo_detected[ch] <= 1'b1;
                    end
                    prev_above_threshold <= (adc_data_i > rx_threshold);
                end
            end
        end
    endgenerate
    
    assign echo_detected_o = |echo_detected;
    assign rx_done_o = (sample_counter >= MAX_SAMPLES);
    
    //===========================================================
    // AXI Read: TOF data accessible via register map
    //===========================================================
    // 0x08-0x44: TOF register per channel (16-bit each)

endmodule
