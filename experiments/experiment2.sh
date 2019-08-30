#!/usr/bin/env bash

START_RATE=0.2
STEP_RATE=0.4
MAX_RATE=2.4
TIME_LIMIT=30

#ITRS_V=(0x008 0x010 0x018 0x020 0x028 0x030 0x038 0x040 0x048 0x050)
#ITRS_S=(2 4 6 8 10 12 14 16 18 20)
ITRS_V=(0x030 0x038 0x040 0x048 0x050)
ITRS_S=(12 14 16 18 20)

for i in "${!ITRS_V[@]}"; do
  ./run.sh experiment2 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT} ${ITRS_V[$i]} "Poisson"
  mkdir ${ITRS_S[$i]}
  mv *.csv ${ITRS_S[$i]}
done