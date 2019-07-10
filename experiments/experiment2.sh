#!/usr/bin/env bash

START_RATE=0.1
STEP_RATE=0.1
MAX_RATE=0.8
TIME_LIMIT=30

ITRS_V=(0x000 0x008 0x010 0x028 0x0C8 0x190 0x320)
ITRS_S=(0 2 4 10 50 100 200)

for i in "${!ITRS_V[@]}"; do
  ./run.sh experiment2 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT} ${ITRS_V[$i]} "Uniform"
  mkdir ${ITRS_S[$i]}
  mv *.csv ${ITRS_S[$i]}
done