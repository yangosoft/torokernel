set +x
fpc ToroHello.pas -oToroHello -Fu../rtl/ -Fu../rtl/drivers -MObjfpc
sh ppas-toro.sh
qemu-system-x86_64 -machine pc-lite,accel=kvm,kernel_irqchip,nvdimm -cpu host -kernel ToroHello -m 1024 -smp 1 -nographic
