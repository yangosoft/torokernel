qemu-system-x86_64 -machine pc-lite,accel=kvm,kernel_irqchip,nvdimm -cpu host -kernel kernel.bin -m 1024,maxmem=20G,slots=2 -smp 1 -s -nographic
