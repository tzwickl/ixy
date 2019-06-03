#!/usr/bin/env bash

START_RATE=0.1
STEP_RATE=0.1
MAX_RATE=1.4
TIME_LIMIT=30

ITRS_V=(0x000 0x008 0x010 0x028 0x0C8 0x190 0x320 0x4B0 0x640 0x7D0 0x960 0xAF0 0xC80 0xE10 0xFA7)
ITRS_S=(0 2 4 10 50 100 200 300 400 500 600 700 800 900 1000)

for i in "${!ITRS_V[@]}"; do
  ./run.sh experiment1_1 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT} ${ITRS_V[$i]}
  mkdir ${ITRS_S[$i]}
  mv *.csv ${ITRS_S[$i]}
done