#!/bin/bash

# if no arguments are given, disable the IOMMU stuff
if [ "$#" -ne 1 ] ; then
	IOMMU=false
else
	if [ "$1" = "IOMMU=OFF" ] ; then
		IOMMU=false
	elif [ "$1" = "IOMMU=ON" ] ; then
		IOMMU=true
	else
		echo "Could not recognize argument $1."
		echo "usage: init-server.sh IOMMU=[ON|OFF]"
		exit 1
	fi
fi

echo "[$HOSTNAME] install essential packages"
apt-get update --quiet=2
apt-get install --quiet=2 -y build-essential cmake linux-headers-`uname -r` pciutils libnuma-dev tmux gdb > /dev/null 2> /dev/null
echo "[$HOSTNAME] activate vfio"
modprobe vfio-pci
if [ "$IOMMU" = true ] ; then
	echo "[$HOSTNAME] bind network cards to the VFIO driver"
	~/bin/bind_network_cards_to_vfio.sh
fi

echo "[$HOSTNAME] install rust"
curl https://sh.rustup.rs -sSf | sh -s -- -y > /dev/null 2> /dev/null
source $HOME/.cargo/env

if [ "$HOSTNAME" = "omastar" ] ; then
	echo "[$HOSTNAME] install MoonGen"
	git clone --quiet https://github.com/emmericp/MoonGen.git
	cd MoonGen
	./build.sh > /dev/null 2> /dev/null
	./setup-hugetlbfs.sh
	cd
fi

if [ "$HOSTNAME" = "omastar" ] ; then
	echo "[$HOSTNAME] install benchmark-scripts"
	git clone --quiet https://github.com/ixy-languages/benchmark-scripts.git
fi

echo "[$HOSTNAME] install ixy (C)"
git clone --quiet https://github.com/emmericp/ixy.git
cd ixy
cmake . > /dev/null
make > /dev/null
cd

if [ "$IOMMU" = true ] ; then
	echo "[$HOSTNAME] install ixy (C) IOMMU version"
	git clone --quiet -b vfio-interrupt https://github.com/tzwickl/ixy.git ixy.iommu
	cd ixy.iommu
	./setup-hugetlbfs.sh
	cmake . > /dev/null
	make > /dev/null 2> /dev/null
	cd
fi

echo "[$HOSTNAME] install ixy.rs (Rust)"
git clone --quiet https://github.com/ixy-languages/ixy.rs
cd ixy.rs
cargo build --quiet --release --all-targets
cd

if [ "$IOMMU" = true ] ; then
	echo "[$HOSTNAME] install ixy.rs (Rust) IOMMU version"
	git clone --quiet -b vfio-interrupt https://github.com/tzwickl/ixy.rs.git ixy.rs.iommu
	cd ixy.rs.iommu
	cargo build --quiet --release --all-targets > /dev/null 2> /dev/null
	cd
fi

if [ "$IOMMU" = true ] ; then
	echo "binding X540-AT2 to VFIO driver"
	~/bin/bind_network_cards_to_vfio.sh
fi

#if [ "$IOMMU" = true ] ; then
#	echo "[$HOSTNAME] disable CPU turbo"
#	echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
#	echo "[$HOSTNAME] set CPU frequency to 66% of Max GHz"
#	echo 67 > /sys/devices/system/cpu/intel_pstate/max_perf_pct
#fi
