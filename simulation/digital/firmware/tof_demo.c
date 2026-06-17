/*===========================================================
 * lunahan_ultrasound_ASIC — TX/RX/PMMU Controller Driver
 *===========================================================
 * lunahan_v1 RISC-V core firmware for ultrasound ASIC
 *===========================================================
 * Memory-mapped IO base addresses
 */
#define TX_CTRL_BASE     0x20000000
#define RX_CTRL_BASE     0x20000100
#define PMU_CTRL_BASE    0x20000200
#define UART_BASE        0x20000300
#define TIMER_BASE       0x20000700
#define SRAM_BASE        0x10000000

/* TX Controller Registers */
#define TX_CTRL_REG      (*(volatile uint32_t *)(TX_CTRL_BASE + 0x00))
#define TX_FREQ_REG      (*(volatile uint32_t *)(TX_CTRL_BASE + 0x04))
#define TX_PHASE_BASE    (TX_CTRL_BASE + 0x08)
#define TX_STATUS_REG    (*(volatile uint32_t *)(TX_CTRL_BASE + 0x48))

/* RX Controller Registers */
#define RX_CTRL_REG      (*(volatile uint32_t *)(RX_CTRL_BASE + 0x00))
#define RX_THRESH_REG    (*(volatile uint32_t *)(RX_CTRL_BASE + 0x04))
#define RX_TOF_BASE      (RX_CTRL_BASE + 0x08)
#define RX_COUNT_REG     (*(volatile uint32_t *)(RX_CTRL_BASE + 0x48))

/* PMU Controller Registers */
#define PMU_CTRL_REG     (*(volatile uint32_t *)(PMU_CTRL_BASE + 0x00))
#define PMU_STATUS_REG   (*(volatile uint32_t *)(PMU_CTRL_BASE + 0x04))
#define PMU_TEMP_REG     (*(volatile uint32_t *)(PMU_CTRL_BASE + 0x08))

/* UART Registers */
#define UART_DATA_REG    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_STATUS_REG  (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_TX_READY    0x1
#define UART_RX_VALID    0x2

/* Constants */
#define SOUND_SPEED_CM_US   0.0343f   /* 343 m/s ÷ 10000 = 0.0343 cm/100ns */
#define NUM_RX_CHANNELS     64
#define NUM_TX_CHANNELS     16
#define NUM_DIRECTIONS      4
#define TOF_UNIT_NS         100       /* TOF units are in 100 ns */

/* Direction mapping */
typedef enum {
    DIR_FRONT = 0,
    DIR_RIGHT = 1,
    DIR_BACK  = 2,
    DIR_LEFT  = 3
} direction_t;

/* Detection result */
typedef struct {
    uint16_t range_cm;
    uint8_t  confidence;
    uint8_t  direction;
    uint16_t tof_raw;
} detection_result_t;

/*===========================================================
 * Low-level driver functions
 *===========================================================*/

void uart_putc(char c) {
    while (!(UART_STATUS_REG & UART_TX_READY));
    UART_DATA_REG = c;
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

void uart_printf(const char *fmt, ...) {
    /* Simplified: use sprintf to buffer then uart_puts */
    char buf[128];
    __builtin_va_list args;
    __builtin_va_start(args, fmt);
    /* mini-vsprintf implementation */
    __builtin_va_end(args);
    uart_puts(buf);
}

/* Set TX pulse voltage (6-14 Vpp) */
void pmu_set_tx_voltage(float volts) {
    uint8_t code;
    if (volts < 6.0f) code = 0;
    else if (volts > 14.0f) code = 16;
    else code = (uint8_t)((volts - 6.0f) * 2.0f + 0.5f);
    
    PMU_CTRL_REG = code & 0x1F;
    
    /* Wait for PMU to stabilize */
    for (volatile int i = 0; i < 10000; i++);
}

/* Set RX gain (0-63 → -2 to 42 dB) */
void rx_set_gain(uint8_t gain_code) {
    uint32_t ctrl = RX_CTRL_REG;
    ctrl &= ~(0x3F << 1);  /* Clear gain bits */
    ctrl |= (gain_code & 0x3F) << 1;
    RX_CTRL_REG = ctrl;
}

/* Set echo detection threshold (mV) */
void rx_set_threshold(uint16_t mv) {
    RX_THRESH_REG = mv & 0x3FF;
}

/*===========================================================
 * TX: Transmit ultrasound burst
 *===========================================================*/
void ultrasound_tx(direction_t dir, uint8_t pulse_count, float volts) {
    /* Program TX voltage via PMU */
    pmu_set_tx_voltage(volts);
    
    /* Configure TX controller */
    uint32_t tx_ctrl = (1 << 0)                   /* Enable */
                     | ((dir & 0x7) << 1)         /* Direction */
                     | ((pulse_count & 0xF) << 4); /* Pulse count */
    TX_CTRL_REG = tx_ctrl;
    
    /* Set frequency: 4000 = 40 kHz (divisor for 50 MHz clk) */
    TX_FREQ_REG = 4000;
    
    /* Wait for TX to complete (poll status) */
    while (TX_STATUS_REG & 0x1);  /* Busy flag */
}

/*===========================================================
 * RX: Receive echoes and compute TOF
 *===========================================================*/
void ultrasound_rx(direction_t dir, uint8_t gain_code, uint16_t threshold_mv,
                   detection_result_t *results) {
    /* Configure RX */
    rx_set_gain(gain_code);
    rx_set_threshold(threshold_mv);
    
    uint32_t rx_ctrl = (1 << 0)                    /* Enable */
                     | ((gain_code & 0x3F) << 1)   /* Gain */
                     | ((dir & 0x3) << 7);          /* Direction */
    RX_CTRL_REG = rx_ctrl;
    
    /* Wait for RX to complete */
    while (!(RX_COUNT_REG & 0x80000000));  /* Done flag */
    
    /* Read TOF results for all channels */
    uint16_t tof_values[64];
    for (int ch = 0; ch < NUM_RX_CHANNELS; ch++) {
        tof_values[ch] = *(volatile uint16_t *)(RX_TOF_BASE + ch * 4);
    }
    
    /* Process: find earliest echo in each direction group */
    /* Center 4 channels per direction: front=[0..3], right=[16..19], ... */
    uint8_t base_ch = dir * 16;
    uint16_t min_tof = 0xFFFF;
    uint8_t best_ch = 0;
    uint8_t echo_count = 0;
    
    for (int i = 0; i < 16; i++) {
        uint8_t ch = base_ch + i;
        if (tof_values[ch] > 0 && tof_values[ch] < min_tof) {
            min_tof = tof_values[ch];
            best_ch = ch;
        }
        if (tof_values[ch] > 0) echo_count++;
    }
    
    /* Compute distance: d = v_sound × TOF / 2 */
    /* TOF is in 100 ns units; v_sound ≈ 343 m/s = 0.0343 cm/100ns */
    /* d_cm = 0.0343 × TOF_100ns / 2 = 0.01715 × TOF_100ns */
    if (min_tof < 0xFFFF) {
        results->range_cm  = (uint16_t)(min_tof * 0.001715f);
        results->confidence = (echo_count * 100) / 16;
        results->direction  = dir;
        results->tof_raw    = min_tof;
    } else {
        results->range_cm  = 0xFFFF;
        results->confidence = 0;
        results->direction  = dir;
        results->tof_raw    = 0;
    }
    
    /* Disable RX */
    RX_CTRL_REG = 0;
}

/*===========================================================
 * Temperature compensation
 *===========================================================*/
float get_speed_of_sound(void) {
    int8_t temp = PMU_TEMP_REG;  /* °C offset from 25 */
    float t = 25.0f + (float)temp;
    return 331.3f + 0.606f * t;  /* m/s */
}

/*===========================================================
 * Main demo loop: 4-direction scan at 4 fps
 *===========================================================*/
void main(void) {
    detection_result_t results[4];
    
    uart_puts("lunahan_ultrasound_ASIC v1.0\r\n");
    uart_puts("4-direction ultrasound scanner\r\n");
    uart_puts("================================\r\n");
    
    /* Initialize PMU: set TX to 12 Vpp */
    pmu_set_tx_voltage(12.0f);
    
    /* Wait for PMU ready */
    while (!(PMU_STATUS_REG & 0x1));
    uart_puts("PMU: OK\r\n");
    
    /* Self-test: check temperature sensor */
    int8_t temp = PMU_TEMP_REG;
    uart_printf("Die temperature: %d C\r\n", 25 + temp);
    
    /* Main loop: 4 fps = 250 ms per frame */
    while (1) {
        for (int dir = 0; dir < NUM_DIRECTIONS; dir++) {
            /* Transmit: 8 pulses at 12 Vpp */
            ultrasound_tx(dir, 8, 12.0f);
            
            /* Receive: 32.8 dB gain, 50 mV threshold */
            ultrasound_rx(dir, 48, 50, &results[dir]);
        }
        
        /* Report results via UART */
        uart_printf("FRAME: ");
        for (int dir = 0; dir < NUM_DIRECTIONS; dir++) {
            if (results[dir].confidence > 0) {
                uart_printf("%c:%dcm/%d%% ",
                    "FRBL"[dir],
                    results[dir].range_cm,
                    results[dir].confidence);
            } else {
                uart_printf("%c:-- ", "FRBL"[dir]);
            }
        }
        uart_puts("\r\n");
        
        /* Frame timing: 250 ms */
        for (volatile int i = 0; i < 1250000; i++) {
            __asm__ volatile ("nop");
        }
    }
}
