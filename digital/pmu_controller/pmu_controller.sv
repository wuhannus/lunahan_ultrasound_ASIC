//===========================================================
// lunahan_ultrasound_ASIC — PMU Controller
//===========================================================
// SPI master for communicating with analog Power Management Unit
//===========================================================

module pmu_controller (
    input  wire         clk_i,
    input  wire         rst_n_i,
    
    // AXI4-Lite slave
    input  wire [31:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [31:0]  s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,
    
    // SPI to PMU analog
    output reg          spi_sck_o,
    output reg          spi_mosi_o,
    input  wire         spi_miso_i,
    output reg          spi_cs_n_o,
    
    // Status
    output reg          fault_o,
    input  wire         pmu_ready_i,    // From analog PMU
    input  wire [7:0]   temp_sensor_i,  // On-die temperature
    input  wire [7:0]   current_mon_i   // Current monitor
);

    //===========================================================
    // Register Map
    //===========================================================
    // 0x00: PMU_CTRL    [4:0] = TX voltage code (0-16 → 6-14V)
    // 0x04: PMU_STATUS  [0]=ready, [1]=overcurrent, [2]=overtemp, [3]=uvlo
    // 0x08: PMU_TEMP    [7:0] = temperature offset from 25°C
    // 0x0C: PMU_CURRENT [7:0] = current × 2 mA
    
    reg [4:0]   tx_voltage_code;
    reg         tx_voltage_dirty;  // Set when new code written
    
    // AXI write handling
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_voltage_code <= 5'd12;  // Default: 12V = 12 Vpp
            tx_voltage_dirty <= 1'b1;
        end else if (s_axi_awvalid && s_axi_wvalid) begin
            case (s_axi_awaddr[7:0])
                8'h00: begin
                    tx_voltage_code <= s_axi_wdata[4:0];
                    tx_voltage_dirty <= 1'b1;
                end
            endcase
        end
    end
    
    // AXI read handling
    reg [31:0] read_data;
    always @(*) begin
        case (s_axi_araddr[7:0])
            8'h00: read_data = {27'd0, tx_voltage_code};
            8'h04: read_data = {28'd0, pmu_ready_i, fault_o, 2'b0};
            8'h08: read_data = {24'd0, temp_sensor_i};
            8'h0C: read_data = {24'd0, current_mon_i};
            default: read_data = 32'd0;
        endcase
    end
    assign s_axi_rdata = read_data;
    
    //===========================================================
    // SPI Master FSM (Mode 0: CPOL=0, CPHA=0)
    //===========================================================
    // SPI frame: 16 bits = [7 cmd] [5 voltage_code] [4 reserved]
    // CMD: 0x01 = Write TX voltage
    
    parameter S_IDLE   = 3'd0;
    parameter S_START  = 3'd1;
    parameter S_SHIFT  = 3'd2;
    parameter S_STOP   = 3'd3;
    
    reg [2:0]   spi_state;
    reg [4:0]   bit_count;
    reg [15:0]  shift_reg;
    reg [7:0]   clk_div;
    
    // Clock divider: 50 MHz → ~5 MHz SPI clock (div by 10)
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            spi_state   <= S_IDLE;
            bit_count   <= 5'd0;
            clk_div     <= 8'd0;
            spi_cs_n_o  <= 1'b1;
            spi_sck_o   <= 1'b0;
            spi_mosi_o  <= 1'b0;
            fault_o     <= 1'b0;
        end else begin
            case (spi_state)
                S_IDLE: begin
                    if (tx_voltage_dirty) begin
                        // Prepare SPI frame: CMD=0x01, DATA=voltage code
                        shift_reg <= {8'h01, tx_voltage_code, 3'd0};
                        bit_count <= 5'd15;
                        clk_div   <= 8'd0;
                        spi_state <= S_START;
                        tx_voltage_dirty <= 1'b0;
                    end
                    
                    // Monitor for faults
                    if (current_mon_i > 8'd200)  // >400 mA
                        fault_o <= 1'b1;
                end
                
                S_START: begin
                    spi_cs_n_o <= 1'b0;  // Assert CS
                    spi_state  <= S_SHIFT;
                    clk_div    <= 8'd0;
                end
                
                S_SHIFT: begin
                    // Generate SPI clock (div by 5 for 5 MHz)
                    if (clk_div < 8'd4) begin
                        clk_div <= clk_div + 8'd1;
                    end else begin
                        clk_div <= 8'd0;
                        
                        if (spi_sck_o) begin
                            // Falling edge: output next bit
                            spi_mosi_o <= shift_reg[15];
                            shift_reg  <= {shift_reg[14:0], 1'b0};
                            
                            if (bit_count == 5'd0) begin
                                spi_state <= S_STOP;
                            end else begin
                                bit_count <= bit_count - 5'd1;
                            end
                        end
                        
                        spi_sck_o <= ~spi_sck_o;
                    end
                end
                
                S_STOP: begin
                    spi_sck_o  <= 1'b0;
                    spi_cs_n_o <= 1'b1;  // De-assert CS
                    spi_state  <= S_IDLE;
                end
            endcase
        end
    end

endmodule
