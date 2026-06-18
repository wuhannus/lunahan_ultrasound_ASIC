//===========================================================
// lunahan_ultrasound_ASIC — Beamform Delay Table SRAM
//===========================================================
// 96 KB delay table: 65,536 entries × 12 bits
// Organized as 32K × 24 bits (2 delays per word)
// Stored in sky130 SRAM macro
//===========================================================

module beamform_delay_sram #(
    parameter DATA_WIDTH = 24,
    parameter ADDR_WIDTH = 15      // 32K addresses
) (
    input  wire                         clk_i,
    input  wire [ADDR_WIDTH-1:0]        addr_i,
    input  wire                         rd_en_i,
    output reg  [DATA_WIDTH-1:0]        rd_data_o,
    output reg                          rd_valid_o,
    input  wire                         wr_en_i,
    input  wire [DATA_WIDTH-1:0]        wr_data_i
);

    //===========================================================
    // SRAM array (behavioral model for simulation;
    // replaced by sky130_sram macro in physical design)
    //===========================================================
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    
    // Read: 1-cycle latency
    always @(posedge clk_i) begin
        if (rd_en_i) begin
            rd_data_o  <= mem[addr_i];
            rd_valid_o <= 1'b1;
        end else begin
            rd_valid_o <= 1'b0;
        end
        
        if (wr_en_i) begin
            mem[addr_i] <= wr_data_i;
        end
    end

endmodule
