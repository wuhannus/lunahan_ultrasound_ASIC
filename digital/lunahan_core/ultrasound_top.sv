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
    output wire                       fault_o          // System fault indicator
);

    //===========================================================
    // Internal signals
    //===========================================================
    wire                            clk_sys;          // 50 MHz system clock
    wire                            pll_locked;
    wire                            rst_sys_n;
    
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
    
    //===========================================================
    // PLL: 16 MHz → 50 MHz
    //===========================================================
    sky130_pll #(
        .REF_FREQ_MHZ(16),
        .OUT_FREQ_MHZ(50)
    ) u_pll (
        .clk_in     (clk_16mhz_i),
        .clk_out    (clk_sys),
        .locked     (pll_locked),
        .rst_n      (rst_n_i)
    );
    
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
        .irq_external_i (irq_tx_done | irq_rx_done | irq_uart_rx | irq_pmu_fault)
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
