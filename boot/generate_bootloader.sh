set -x
nasm -g -f elf64 qemu_boot.s
ld -n -o kernel.bin -T linker.ld qemu_boot.o
