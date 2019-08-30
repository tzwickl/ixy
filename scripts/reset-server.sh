#!/bin/bash

USER=zwickl

# if not exactly 2 arguments are given die with usage
if [ "$#" -ne 2 ] ; then
	echo "usage: reset-server.sh [server] IOMMU=[ON|OFF]"
	exit 1
else
	SERVER="$1"
	if [ "$2" = "IOMMU=OFF" ] ; then
		IOMMU=false
	elif [ "$2" = "IOMMU=ON" ] ; then
		IOMMU=true
	else
		echo "Could not recognize argument $2."
		echo "usage: reset-server.sh [server] IOMMU=[ON|OFF]"
		exit 1
	fi
fi

echo "[$SERVER] set debian image"
pos nodes image $SERVER debian-stretch

if [ "$IOMMU" = true ] ; then
	echo "[$SERVER] set bootparameter intel_iommu=on"
	pos nodes bootparameter $SERVER intel_iommu=on
else
	echo "[$SERVER] set bootparameter intel_iommu=off"
	pos nodes bootparameter $SERVER intel_iommu=off
fi

echo "[$SERVER] reset the server"
pos nodes reset $SERVER

echo "[$SERVER] push files to server"
ssh -q $SERVER mkdir bin
scp -q /home/$USER/bin/ls-iommu.sh $SERVER:bin/
scp -q /home/$USER/bin/"$SERVER"_bind_network_cards_to_vfio.sh $SERVER:bin/bind_network_cards_to_vfio.sh
scp -q /home/$USER/bin/"$SERVER"_bind_network_cards_to_ixgbe.sh $SERVER:bin/bind_network_cards_to_ixgbe.sh
scp -q /home/$USER/bin/init-server.sh $SERVER:bin/init-server.sh

echo "[$SERVER] initialize server"
if [ "$IOMMU" = true ] ; then
	ssh -q $SERVER "bin/init-server.sh" "IOMMU=ON"
else
	ssh -q $SERVER "bin/init-server.sh" "IOMMU=OFF"
fi

echo "[$SERVER] done with reset-server.sh"
