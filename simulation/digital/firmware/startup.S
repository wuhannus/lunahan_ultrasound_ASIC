# RISC-V startup code for lunahan_v1
# Initializes stack pointer, clears BSS, jumps to main

.section .text.startup
.globl _start
_start:
    # Initialize stack pointer
    la sp, _stack_top

    # Clear BSS section
    la t0, __bss_start__
    la t1, __bss_end__
clear_bss:
    beq t0, t1, done_bss
    sw zero, 0(t0)
    addi t0, t0, 4
    j clear_bss
done_bss:

    # Enable interrupts (set MIE bit in mstatus)
    li t0, 0x1888
    csrw mstatus, t0

    # Jump to main
    call main

    # Infinite loop if main returns
halt:
    wfi
    j halt
