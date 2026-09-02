# AgentOS stub image — educational assemble only
# Never dd onto host disks from automation.
AS ?= as
LD ?= ld
OBJCOPY ?= objcopy

.PHONY: all clean image

all: image

boot.bin: boot.s
	$(AS) --32 -o boot.o boot.s
	$(LD) -m elf_i386 -Ttext 0x7C00 -o boot.elf boot.o
	$(OBJCOPY) -O binary boot.elf boot.bin

kernel.o: kernel_stub.s
	$(AS) --64 -o kernel.o kernel_stub.s

# Dry-run / demo: concatenate stubs into image.bin marker
image: boot.bin kernel.o
	cat boot.bin > image.bin
	@echo "AgentOS stub image.bin written (blueprint only — not production)"
	@echo "Owner may experiment on disposable media; agents never reboot host."

clean:
	rm -f boot.o boot.elf boot.bin kernel.o image.bin
