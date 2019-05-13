#!/usr/bin/env bash

### Omanyte Configuration

DEVICE1_ID="0000:03:00.0"
DEVICE2_ID="0000:03:00.1"
IXY_PATH="/tmp/ixy"
RESULT_FILE=result.csv
PERF_FILE=perf.stat

###
### Omastar Configuration

SOURCE_PORT=4
DEST_PORT=5
START_RATE=1
STEP_SIZE_RATE=1
MAX_RATE=10
TIME_LIMIT=10

###
### Global Variables

IXY_PID=0
PERF_PID=0
CPUS="0,1"

###

# Build Ixy
# @param 1: The path to Ixy
function build_ixy {
    cd ${1};
    cmake .
    make
    chmod 774 setup-hugetlbfs.sh
    ./setup-hugetlbfs.sh
}

# Start Ixy forwarder
# @param 1: The path to Ixy
# @param 2: The first device ID
# @param 3: The second device ID
# @return: The PID of the ixy forwarder
function start_ixy_forwarder {
    cd ${1};
    nohup ./ixy-fwd ${2} ${3} > /dev/null 2>&1&
    echo $!
}

# Stop the Ixy Process
# @param 1: The PID of the ixy process
function stop_ixy {
    kill -9 $1;
}

# Stop the MoonGen Process
function stop_moon_gen {
    pid=$(ps aux | grep ./build/MoonGen | grep -v grep | awk '{print $2}')
    kill -9 ${pid}
}

# Set the CPU affinity of the Ixy process
# @param 1: CPU mask expressed as a decimal or hexadecimal number
# @param 2: The PID of the ixy process
function set_ixy_cpu_affinity {
    taskset -p ${1} ${2}
}

# Set the interrupt affinity
# @param 1: CPU mask expressed as a hexadecimal number
# @param 2: The ID of the Device
function set_interrupt_affinity {
    # disable IRQ balance
    systemctl stop irqbalance
    irq=0
    while IFS= read -r line
    do
        if [[ ${line} == *"${2}"* ]]; then
            for val in ${line}
            do
                irq=${val::-1}
                break;
            done
        fi
    done < "/proc/interrupts"

    echo ${1} > /proc/irq/${irq}/smp_affinity
}

# Parses the interrupts file and extracts the number of interrupts
# @param 1: The ID of the Device
# @return: The total number of interrupts
function parse_interrupts {
    CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    while IFS= read -r line
    do
        if [[ ${line} == *"${1}"* ]]; then
            TOTAL_INTERRUPTS=0;
            INDEX=0;
            for val in ${line}
            do
                if [[ ${INDEX} -eq 0 ]] || [[ ${INDEX} -gt ${CPU_CORES} ]]; then
                    INDEX=$((INDEX + 1))
                    continue;
                fi
                INDEX=$((INDEX + 1))
                TOTAL_INTERRUPTS="$(($TOTAL_INTERRUPTS+$val))"
            done
            echo ${TOTAL_INTERRUPTS}
        fi
    done < "/proc/interrupts"
}

# @param 1: source port
# @param 2: dest port
# @param 3: packet rate
# @param 4: time limit
# @return: The number of received and transmitted packets
function run_moongen {
    cd /root/MoonGen;
    output=$(./moongen-simple start load-latency:${1}:${2}:rate=${3},timeLimit=${4} 2> /dev/null | tee moongen.log)
    output=$(echo "${output}" | tail -n 4)
    rx=0;
    tx=0;
    while IFS= read -r line
    do
        if [[ ${line} == *"id=${1}"* ]]; then
            tx=$(echo "${line}" | grep -P '\d+ (?=packets)' -o)
        fi
        if [[ ${line} == *"id=${2}]"* ]]; then
            rx=$(echo "${line}" | grep -P '\d+ (?=packets)' -o)
        fi
    done <<< ${output}
    echo "tx=\"${tx}\";rx=\"${rx}\""
}

# @param 1: Path to Ixy
# @param 2: Output file
# @param 3: Sleep time
# @param 4: List of CPUs to monitor
# @return: The PID of perf
function run_perf {
    cd ${1};
    nohup sh -c "sleep 10 && perf stat -a -g --per-core --cpu=${4} -o ${2} -e cycles -- sleep ${3}" > /dev/null &
    echo $!
}

# @param 1: Path to Ixy
# @param 2: Perf file
# @param 3: List of CPUs
# @return: The CPU cycles
function parse_perf {
    cd ${1};
    perf=$(cat "${2}")
    cpu0=0;
    cpu1=0;
    while IFS= read -r line
    do
        if [[ ${line} == "S0-C${3:0:1}"* ]]; then
            cpu0=$(echo "${line}" | sed 's/\,//g' | grep -P '\d+ (?=\ *cycles)' -o)
        fi
        if [[ ${line} == "S0-C${3:2:1}"* ]]; then
            cpu1=$(echo "${line}" | sed 's/\,//g' | grep -P '\d+ (?=\ *cycles)' -o)
        fi
    done <<< ${perf}
    echo "cpu0=\"${cpu0}\";cpu1=\"${cpu1}\""
}

# Stop the perf Process
# @param 1: The PID of the perf process
function stop_perf {
    kill $(ps -o pid= --ppid $1)
}

# @param 1: Start Rate
# @param 2: Step Size
# @param 3: Max Rate
# @param 4: Time Limit
function run_experiment {
    oldCounter=0;
    for rate in `seq ${1} ${2} ${3}`;
    do
        PERF_PID=$(ssh omanyte "$(typeset -f); run_perf \"$IXY_PATH\" \"$PERF_FILE\" \"$TIME_LIMIT\" \"$CPUS\"")
        packets=$(ssh omastar "$(typeset -f); run_moongen \"$SOURCE_PORT\" \"$DEST_PORT\" \"$rate\"mp/s \"$4\"")
        cpuCycles=$(ssh omanyte "$(typeset -f); parse_perf \"$IXY_PATH\" \"$PERF_FILE\" \"$CPUS\"")
        counter=$(ssh omanyte "$(typeset -f); parse_interrupts \"$DEVICE1_ID\"")
        interrupts="$(($counter-$oldCounter))"
        oldCounter=${counter};
        eval ${packets}
        eval ${cpuCycles}
        echo "${rate}; ${interrupts}; ${tx}; ${rx}; ${cpu0}; ${cpu1}" | sed 's/ //g' | tee -a ${RESULT_FILE}
        PERF_PID=NULL
    done
}

# Number of interrupts on same core
function experiment1_1 {
    CPUS="1";
    ssh omanyte "$(typeset -f); set_ixy_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 1 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 1 \"$DEVICE2_ID\""
    sleep 2
    run_experiment ${START_RATE} ${STEP_SIZE_RATE} ${MAX_RATE} ${TIME_LIMIT}s
}

# Number of interrupts on different core
function experiment1_2 {
    CPUS="1,2";
    ssh omanyte "$(typeset -f); set_ixy_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 2 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 2 \"$DEVICE2_ID\""
    sleep 2
    run_experiment ${START_RATE} ${STEP_SIZE_RATE} ${MAX_RATE} ${TIME_LIMIT}s
}

# Number of interrupts on hyperthreading pair
function experiment1_3 {
    CPUS="1,8";
    ssh omanyte "$(typeset -f); set_ixy_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 40 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 40 \"$DEVICE2_ID\""
    sleep 2
    run_experiment ${START_RATE} ${STEP_SIZE_RATE} ${MAX_RATE} ${TIME_LIMIT}s
}

function usage {
    echo "USAGE: "
}

function cleanup {
  echo "Cleanup"
    ssh omastar "$(typeset -f); stop_moon_gen"
  if [[ -n "$IXY_PID" ]]; then
    ssh omanyte "$(typeset -f); stop_ixy \"$IXY_PID\""
  fi
  if [[ -n "$PERF_PID" ]]; then
    ssh omanyte "$(typeset -f); stop_perf \"$PERF_PID\""
  fi
}

### Pre Setup
> ${RESULT_FILE}
trap cleanup EXIT
ssh omanyte "$(typeset -f); build_ixy \"$IXY_PATH\""
IXY_PID=$(ssh omanyte "$(typeset -f); start_ixy_forwarder \"$IXY_PATH\" \"$DEVICE1_ID\" \"$DEVICE2_ID\"")
###

"$@"