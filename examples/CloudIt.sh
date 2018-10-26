#!/bin/sh
#
# CloudIt.sh <Application>
#
# Script to compile and run a Toro app in Linux. We base on wine 
# to generate the image and on KVM/QEMU to run it.
#
# Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
# All Rights Reserved
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

app="$1";
appsrc="$app.pas";
applpi="$app.lpi";
appimg="$app.img";
kvmfile="$app.kvm";

# check parameters
if [ "$#" -lt 1 ]; then
   echo "Usage: CloudIt.sh ApplicationName [Options]"
   exit 1
fi

# get the kvm parameters
if [ -f $kvmfile ]; then
   kvmparam=`cat $kvmfile`
else
   # parameters by default
   kvmparam="--vcpus=2 --ram=512"
fi

# this avoids to regenerate the image
if [ "$#" -ge 2 ]; then
    if [ "$2" = "onlykvm" ]; then
       # download release if it is indicated
       if [ "$#" -eq 4 ]; then
          if [ "$3" = "release" ]; then
	     wget "https://github.com/MatiasVara/torokernel/releases/download/master-""$4""/""$appimg" -O "$appimg"
          else
	     echo "Parameter: $3 not recognized"
	     exit 1
          fi
       fi
    # check if image exists
    if [ ! -f $appimg ]; then
       echo "$appimg does not exist, exiting"
       exit 1
    fi
    # destroy any previous instance
    virsh destroy $app
    virsh undefine $app
    # VNC is open at port 590X
    virt-install --name=$app --disk path=$appimg,bus=ide $kvmparam --boot hd &
    # show the serial console
    sleep 5
    virsh console $app
    exit 0
   fi
 echo "Parameter: $2 not recognized"
 exit 1
fi

# remove all compiled files
rm -f ../rtl/*.o ../rtl/*.ppu
rm -f $appimg

# remove the application
rm -f $app "$app.o"

if [ -f $appsrc ]; then
   fpc -TLinux -O2 $appsrc -o$app -Fu../rtl/ -Fu../rtl/drivers -MObjfpc
   ../builder/build 4 $app ../builder/boot.o $appimg
else
   echo "$appsrc does not exist, exiting"
   exit 1
fi
exit 0
# destroy any previous instance
virsh destroy $app
virsh undefine $app

if [ -f $appimg ]; then
   # VNC is open at port 590X
   virt-install --name=$app --disk path=$appimg,bus=ide $kvmparam --boot hd &
else
   echo "$appimg does not exist, exiting"
   exit 1
fi

# show the serial console
sleep 5
virsh console $app
