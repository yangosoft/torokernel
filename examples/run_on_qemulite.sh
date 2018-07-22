set +x
fpc ToroHello.pas -oToroHello -Fu../rtl/ -Fu../rtl/drivers -MObjfpc
sh ppas-toro.sh
sudo qemu-system-x86_64 -machine pc-lite,accel=kvm,kernel_irqchip,nvdimm -cpu host -kernel ToroHello -m 1024 -smp 4  -device virtio-serial-pci,id=virtio-serial0 -chardev pty,id=charconsole0 -device virtconsole,chardev=charconsole0,id=console0 -nographic
