#!/bin/bash
# execute this as root!
# unbind driver
echo "0000:05:00.0" > /sys/bus/pci/devices/0000:05:00.0/driver/unbind
echo "0000:05:00.1" > /sys/bus/pci/devices/0000:05:00.1/driver/unbind
echo "0000:03:00.0" > /sys/bus/pci/devices/0000:03:00.0/driver/unbind
echo "0000:03:00.1" > /sys/bus/pci/devices/0000:03:00.1/driver/unbind
# bind vfio driver
echo "8086 1528" > /sys/bus/pci/drivers/vfio-pci/new_id
echo "8086 10fb" > /sys/bus/pci/drivers/vfio-pci/new_id
# make the user own the device
# chown hubestef:hubestef /dev/vfio/36
