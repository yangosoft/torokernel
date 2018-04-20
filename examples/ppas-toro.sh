#!/bin/sh
DoExitAsm ()
{ echo "An error occurred while assembling $1"; exit 1; }
DoExitLink ()
{ echo "An error occurred while linking $1"; exit 1; }
echo Assembling torohello
#/usr/bin/as --64 -o ToroHello.o  ToroHello.s
if [ $? != 0 ]; then DoExitAsm torohello; fi
echo Linking ToroHello
OFS=$IFS
IFS="
"
/usr/bin/ld -b elf64-x86-64 -m elf_x86_64     -s -L. -o ToroHello link-toro.res
if [ $? != 0 ]; then DoExitLink ToroHello; fi
IFS=$OFS
