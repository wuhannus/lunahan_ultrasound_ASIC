#===========================================================
# lunahan_ultrasound_ASIC — RISC-V Firmware Linker Script
#===========================================================

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K    /* Boot ROM / I-Cache */
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 32K   /* SRAM */
}

SECTIONS
{
    .text : {
        *(.text.startup)
        *(.text*)
        *(.rodata*)
    } > ROM

    .data : {
        *(.data*)
        *(.sdata*)
    } > RAM

    .bss : {
        *(.bss*)
        *(.sbss*)
    } > RAM

    .stack (NOLOAD) : {
        . = ALIGN(8);
        _stack_top = .;
        . += 2K;
        _stack_bottom = .;
    } > RAM
}
