#!/bin/bash
# this script is best called with
# bash -x init

# omanyte-iommu <-> omastar-noiommu
/home/hubestef/bin/reset-server.sh omanyte IOMMU=ON & /home/hubestef/bin/reset-server.sh omastar IOMMU=OFF

echo "[init.sh] You probably want to run MoonGen on omastar and the ixy.rs echoer on omanyte:"
echo "[omastar] 'MoonGen/build/MoonGen benchmark-scripts/ixy-bench.lua 2 3'"
echo "[omanyte] 'cargo run --release --example forwarder 0000:05:00.0 0000:05:00.1'"

