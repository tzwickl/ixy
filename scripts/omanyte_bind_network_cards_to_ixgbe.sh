#!/bin/bash
# execute this as root!
# unbind driver
echo "0000:05:00.0" > /sys/bus/pci/devices/0000:05:00.0/driver/unbind
echo "0000:05:00.1" > /sys/bus/pci/devices/0000:05:00.1/driver/unbind
echo "0000:03:00.0" > /sys/bus/pci/devices/0000:03:00.0/driver/unbind
echo "0000:03:00.1" > /sys/bus/pci/devices/0000:03:00.1/driver/unbind
# bind vfio driver
echo "0000:05:00.0" > /sys/bus/pci/drivers/ixgbe/bind
echo "0000:05:00.1" > /sys/bus/pci/drivers/ixgbe/bind
echo "0000:03:00.0" > /sys/bus/pci/drivers/ixgbe/bind
echo "0000:03:00.1" > /sys/bus/pci/drivers/ixgbe/bind
