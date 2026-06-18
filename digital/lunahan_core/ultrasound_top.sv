//===========================================================
// lunahan_ultrasound_ASIC — Top-Level System Integration
//===========================================================
// Integrates: lunahan_v1 RISC-V core + TX/RX/PMU controllers
//             + AXI4-Lite interconnect + memory + peripherals
//===========================================================

`timescale 1ns / 1ps

module ultrasound_asic_top #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter NUM_RX_CHANNELS = 64,
    parameter NUM_TX_CHANNELS = 16
) (
    // Clock and Reset
    input  wire                     clk_16mhz_i,      // 16 MHz external crystal
    input  wire                     rst_n_i,          // Active-low reset
    
    // TX Interface (to analog UERTX drivers)
    output wire [NUM_TX_CHANNELS-1:0] tx_pulse_o,    // Pulse enable per channel
    output wire [NUM_TX_CHANNELS-1:0] tx_polarity_o, // Polarity control
    output wire [3:0]                 tx_direction_o, // Which direction array
    
    // RX Interface (from analog ADCs)
    input  wire [NUM_RX_CHANNELS-1:0] adc_eoc_i,     // ADC end-of-conversion
    input  wire [9:0]                 adc_data_i,     // ADC data bus (time-multiplexed)
    output wire [5:0]                 adc_channel_o,  // ADC channel select (0-63)
    output wire                       adc_start_o,    // ADC start conversion
    
    // PMU Interface (SPI to analog PMU)
    output wire                       pmu_spi_sck_o,
    output wire                       pmu_spi_mosi_o,
    input  wire                       pmu_spi_miso_i,
    output wire                       pmu_spi_cs_n_o,
    
    // UART (Host communication)
    output wire                       uart_tx_o,
    input  wire                       uart_rx_i,
    
    // SPI (External configuration/debug)
    input  wire                       ext_spi_sck_i,
    input  wire                       ext_spi_mosi_i,
    output wire                       ext_spi_miso_o,
    input  wire                       ext_spi_cs_n_i,
    
    // GPIO
    inout  wire [15:0]                gpio_io,
    
    // Status
    output wire                       system_ready_o,  // PLL locked + PMU ready
    output wire                       fault_o,         // System fault indicator
    
    // PLL analog interface (for AMS co-sim; NC in pure-digital flow)
    output wire                       pll_up_o,        // PFD UP → charge pump
    output wire                       pll_dn_o,        // PFD DN → charge pump
    input  wire                       vco_in_i,        // VCO output from analog
    
    // Beamforming output (voxel intensity stream)
    output wire [15:0]                voxel_intensity_o,
    output wire [15:0]                voxel_addr_o,
    output wire                       voxel_valid_o
);

    //===========================================================
    // Internal signals
    //===========================================================
    wire                            clk_sys;          // 50 MHz system clock
    wire                            clk_adc;          // 1.2 MHz ADC clock
    wire                            pll_locked;
    wire                            rst_sys_n;
    wire                            pll_up, pll_dn;   // PFD outputs
    wire                            vco_clk;          // VCO feedback clock
    
    // AXI4-Lite master (from core)
    wire [AXI_ADDR_WIDTH-1:0]       m_axi_awaddr;
    wire                            m_axi_awvalid;
    wire                            m_axi_awready;
    wire [AXI_DATA_WIDTH-1:0]       m_axi_wdata;
    wire [3:0]                      m_axi_wstrb;
    wire                            m_axi_wvalid;
    wire                            m_axi_wready;
    wire [1:0]                      m_axi_bresp;
    wire                            m_axi_bvalid;
    wire                            m_axi_bready;
    wire [AXI_ADDR_WIDTH-1:0]       m_axi_araddr;
    wire                            m_axi_arvalid;
    wire                            m_axi_arready;
    wire [AXI_DATA_WIDTH-1:0]       m_axi_rdata;
    wire [1:0]                      m_axi_rresp;
    wire                            m_axi_rvalid;
    wire                            m_axi_rready;
    
    // AXI slaves (to memory/peripherals)
    wire [AXI_ADDR_WIDTH-1:0]       sram_awaddr;
    wire                            sram_awvalid;
    wire                            sram_awready;
    // ... (multiple slave interfaces)
    
    // Interrupt lines
    wire                            irq_timer;
    wire                            irq_tx_done;
    wire                            irq_rx_done;
    wire                            irq_uart_rx;
    wire                            irq_pmu_fault;
    wire                            irq_bf_done;       // Beamforming frame complete
    
    // PV-RXBF interface wires
    wire [15:0]                     bf_voxel_intensity;
    wire [15:0]                     bf_voxel_addr;
    wire                            bf_voxel_valid;
    wire                            bf_done;
    wire                            bf_busy;
    wire [11:0]                     bf_dtbl_addr;
    wire                            bf_dtbl_rd_en;
    wire [11:0]                     bf_dtbl_data;
    wire                            bf_dtbl_valid;
    
    //===========================================================
    // PLL: 16 MHz → 50 MHz + 1.2 MHz (gf180mcu open PDK)
    //===========================================================
    // Architecture: Type-II charge-pump integer-N PLL
    //   PFD: 4 MHz (ref ÷ 4)
    //   VCO: 200 MHz ring oscillator
    //   FB: ÷50, Post-dividers: ÷4 (50 MHz), ÷167 (1.2 MHz)
    //   See: afe/pll/pll_tb.sp for analog simulation
    //        docs/pll_design_summary.md for full design details
    //===========================================================
    gf180_pll #(
        .REF_FREQ_MHZ(16),
        .OUT_FREQ_MHZ(50),
        .REF_DIV(4),
        .FB_DIV(50),
        .POST_DIV_SYS(4),
        .POST_DIV_ADC(167)
    ) u_pll (
        .clk_ref_i   (clk_16mhz_i),
        .rst_n_i     (rst_n_i),
        .cfg_div_i   (8'd0),
        .cfg_en_i    (1'b0),
        .pll_up_o    (pll_up),
        .pll_dn_o    (pll_dn),
        .vco_out_i   (vco_in_i),         // From analog VCO (AMS co-sim)
        .clk_sys_o   (clk_sys),
        .clk_adc_o   (clk_adc),
        .pll_locked_o(pll_locked),
        .pll_status_o()
    );
    
    // Route PLL analog interface to chip-level ports
    assign pll_up_o = pll_up;
    assign pll_dn_o = pll_dn;
    
    // Reset synchronizer
    sync_reset u_rst_sync (
        .clk        (clk_sys),
        .rst_n_async(rst_n_i & pll_locked),
        .rst_n_sync (rst_sys_n)
    );
    
    //===========================================================
    // lunahan_v1 RISC-V Core (RV32IMC, 5-stage)
    //===========================================================
    lunahan_core #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_core (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        
        // Instruction bus (AXI4-Lite)
        .i_axi_awaddr   (m_axi_awaddr),
        .i_axi_awvalid  (m_axi_awvalid),
        .i_axi_awready  (m_axi_awready),
        // ... (remaining AXI signals)
        
        // Interrupts
        .irq_timer_i    (irq_timer),
        .irq_software_i (1'b0),
        .irq_external_i (irq_tx_done | irq_rx_done | irq_uart_rx | irq_pmu_fault | irq_bf_done)
    );
    
    //===========================================================
    // AXI4-Lite Interconnect (1 master → N slaves)
    //===========================================================
    axi_interconnect #(
        .NUM_SLAVES(8),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        // Address map
        .S0_BASE(32'h0000_0000),  // Boot ROM / I-Cache
        .S0_MASK(32'hFFFF_F000),
        .S1_BASE(32'h1000_0000),  // SRAM
        .S1_MASK(32'hFFFF_8000),
        .S2_BASE(32'h2000_0000),  // TX Controller
        .S2_MASK(32'hFFFFFF00),
        .S3_BASE(32'h2000_0100),  // RX Controller
        .S3_MASK(32'hFFFFFF00),
        .S4_BASE(32'h2000_0200),  // PMU Controller
        .S4_MASK(32'hFFFFFF00),
        .S5_BASE(32'h2000_0300),  // UART
        .S5_MASK(32'hFFFFFF00),
        .S6_BASE(32'h2000_0500),  // SPI Slave
        .S6_MASK(32'hFFFFFF00),
        .S7_BASE(32'h2000_0700)   // System Timer
    ) u_interconnect (
        // ... (AXI routing)
    );
    
    //===========================================================
    // Peripherals
    //===========================================================
    
    // --- TX Controller ---
    tx_controller #(
        .NUM_CHANNELS(NUM_TX_CHANNELS)
    ) u_tx_ctrl (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        // AXI slave
        .s_axi_awaddr   (tx_awaddr),
        // ...
        // TX outputs
        .tx_pulse_o     (tx_pulse_o),
        .tx_polarity_o  (tx_polarity_o),
        .tx_direction_o (tx_direction_o),
        .tx_done_o      (irq_tx_done)
    );
    
    // --- RX Controller ---
    rx_controller #(
        .NUM_CHANNELS(NUM_RX_CHANNELS),
        .ADC_WIDTH(10)
    ) u_rx_ctrl (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        // AXI slave
        // ...
        // ADC interface
        .adc_data_i     (adc_data_i),
        .adc_eoc_i      (adc_eoc_i),
        .adc_channel_o  (adc_channel_o),
        .adc_start_o    (adc_start_o),
        .rx_done_o      (irq_rx_done)
    );
    
    // --- PMU Controller ---
    pmu_controller u_pmu_ctrl (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        // AXI slave
        // ...
        // SPI to PMU analog
        .spi_sck_o      (pmu_spi_sck_o),
        .spi_mosi_o     (pmu_spi_mosi_o),
        .spi_miso_i     (pmu_spi_miso_i),
        .spi_cs_n_o     (pmu_spi_cs_n_o),
        .fault_o        (irq_pmu_fault)
    );
    
    // --- UART ---
    uart_16550 #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE(115200)
    ) u_uart (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        .tx_o           (uart_tx_o),
        .rx_i           (uart_rx_i),
        .irq_o          (irq_uart_rx)
    );
    
    // --- System Timer (1 ms tick) ---
    system_timer u_timer (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        .tick_o         (irq_timer)
    );
    
    // --- GPIO ---
    gpio_controller u_gpio (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        .gpio_io        (gpio_io)
    );
    
    //===========================================================
    // PV-RXBF — Per-Voxel RX Beamfocusing (JSSC 2022)
    //===========================================================
    // On-chip delay-and-sum beamformer for 64-channel 8×8 array.
    // 32×32 voxel grid, ~10 M Focal Points/s, 24 fps imaging.
    // See: L. Wu et al., JSSC Vol.57 No.11, Nov. 2022.
    //===========================================================
    pv_rx_beamfocusing #(
        .NUM_CHANNELS(64),
        .ADC_WIDTH(10),
        .BEAMF_WIDTH(16),
        .SAMPLE_DEPTH(4096),
        .VOXEL_GRID_X(32),
        .VOXEL_GRID_Y(32)
    ) u_pv_rxbf (
        .clk_i           (clk_sys),
        .rst_n_i         (rst_sys_n),
        
        // AXI4-Lite slave
        .s_axi_awaddr    (bf_awaddr),
        .s_axi_awvalid   (bf_awvalid),
        .s_axi_awready   (bf_awready),
        .s_axi_wdata     (bf_wdata),
        .s_axi_wstrb     (bf_wstrb),
        .s_axi_wvalid    (bf_wvalid),
        .s_axi_wready    (bf_wready),
        .s_axi_bresp     (),
        .s_axi_bvalid    (),
        .s_axi_bready    (1'b1),
        .s_axi_araddr    (bf_araddr),
        .s_axi_arvalid   (bf_arvalid),
        .s_axi_arready   (bf_arready),
        .s_axi_rdata     (bf_rdata),
        .s_axi_rresp     (),
        .s_axi_rvalid    (),
        .s_axi_rready    (1'b1),
        
        // ADC sample input (from RX controller)
        .adc_data_i      (adc_data_i),
        .adc_channel_i   (adc_channel_o),
        .adc_valid_i     (|adc_eoc_i),
        
        // Beamformed output
        .voxel_intensity_o(bf_voxel_intensity),
        .voxel_addr_o    (bf_voxel_addr),
        .voxel_valid_o   (bf_voxel_valid),
        
        // Delay table SRAM
        .dtbl_addr_o     (bf_dtbl_addr),
        .dtbl_rd_en_o    (bf_dtbl_rd_en),
        .dtbl_data_i     (bf_dtbl_data),
        .dtbl_valid_i    (bf_dtbl_valid),
        
        // Control/Status
        .bf_done_o       (bf_done),
        .bf_busy_o       (bf_busy),
        .bf_start_i      (bf_start)
    );
    
    // Delay table SRAM (96 KB = 65536 × 12 bits → 32K × 24 bits)
    beamform_delay_sram #(
        .DATA_WIDTH(24),
        .ADDR_WIDTH(15)
    ) u_bf_delay_sram (
        .clk_i           (clk_sys),
        .addr_i          (bf_dtbl_addr),
        .rd_en_i         (bf_dtbl_rd_en),
        .rd_data_o       (bf_dtbl_data),
        .rd_valid_o      (bf_dtbl_valid),
        .wr_en_i         (1'b0),        // Delay table pre-loaded via AXI
        .wr_data_i       (24'd0)
    );
    
    // Route beamforming outputs to chip-level ports
    assign voxel_intensity_o = bf_voxel_intensity;
    assign voxel_addr_o      = bf_voxel_addr;
    assign voxel_valid_o     = bf_voxel_valid;
    assign irq_bf_done       = bf_done;
    
    //===========================================================
    // SRAM (32 KB)
    //===========================================================
    sky130_sram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(13),  // 32 KB = 8192 × 32-bit
        .NUM_WORDS(8192)
    ) u_sram (
        .clk_i          (clk_sys),
        .rst_n_i        (rst_sys_n),
        // AXI slave interface
        // ...
    );
    
    //===========================================================
    // Status outputs
    //===========================================================
    assign system_ready_o = pll_locked && !irq_pmu_fault;
    assign fault_o = irq_pmu_fault;

endmodule
