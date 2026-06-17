#===========================================================
# lunahan_ultrasound_ASIC — Firmware Build System
#===========================================================
# Builds RISC-V firmware for lunahan_v1 RV32IMC target
#===========================================================

# Toolchain
CROSS_COMPILE = riscv64-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
AS      = $(CROSS_COMPILE)as
LD      = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE    = $(CROSS_COMPILE)size

# Build options
CFLAGS  = -march=rv32imc -mabi=ilp32 -O2 -Wall -ffreestanding -nostdlib
CFLAGS += -I../digital -I.
LDFLAGS = -T link.ld -nostdlib -Wl,--gc-sections

# Sources
SRCS    = tof_demo.c startup.S
OBJS    = $(SRCS:.c=.o)
OBJS   := $(OBJS:.S=.o)

# Targets
TARGET  = firmware
HEX     = $(TARGET).hex
ELF     = $(TARGET).elf
BIN     = $(TARGET).bin
LST     = $(TARGET).lst

# Default
.PHONY: all clean dump

all: $(HEX) dump

# Compile C sources
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Assemble startup
%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

# Link
$(ELF): $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $@
	$(SIZE) $@

# Generate hex (for Verilog $readmemh)
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $@
	$(OBJCOPY) -O binary $< $(BIN)

# Disassembly for debugging
dump: $(ELF)
	$(OBJDUMP) -d $< > $(LST)

clean:
	rm -f $(OBJS) $(ELF) $(HEX) $(BIN) $(LST)
