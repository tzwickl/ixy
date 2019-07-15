#!/usr/bin/env bash

### Omanyte Configuration

DEVICE1_ID="0000:03:00.0"
DEVICE2_ID="0000:03:00.1"
IXY_PATH="/tmp/ixy"
RESULT_FILE=result.csv
PERF_FILE=perf.stat
POWERTOP_FILE=powertop.csv
POWERTOP_RESULT_FILE=powertop-result.csv

###
### Omastar Configuration

SOURCE_PORT=4
DEST_PORT=5

START_RATE=0.1
STEP_RATE=0.1
MAX_RATE=1.4
TIME_LIMIT=10

###
### Global Variables

IXY_PID=0
PERF_PID=0
POWERTOP_PID=0
MOONSNIFF_PID=0
CPUS="0,1"
ITR=0xFA7

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
# @param 2: The ITR
# @param 3: The first device ID
# @param 4: The second device ID
# @return: The PID of the ixy forwarder
function start_ixy_forwarder {
    cd ${1};
    nohup ./ixy-fwd ${2} ${3} ${4} > ixy.log 2>&1&
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
    if [[ -n "$pid" ]]; then
     echo "Killing Moongen ${pid}"
     kill -9 ${pid}
    fi
}

# Set the CPU affinity of the given process
# @param 1: CPU mask expressed as a decimal or hexadecimal number
# @param 2: The PID of the process
function set_cpu_affinity {
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

# Start the MoonSniff process
function start_moonsniff {
    cd /root/MoonGen;
    ./setup-hugetlbfs.sh > /dev/null 2>&1&
    rm *.mscap;
    rm *.csv;
    nohup sh -c "./build/MoonGen examples/moonsniff/sniffer.lua --seq-offset 50 1 0 2> /dev/null | tee moonsniff.log" > /dev/null &
    echo $!
}

# Stop the MoonSniff Process
# @param 1: The PID of the MoonSniff process
function stop_moonsniff {
    kill $(ps -o pid= --ppid $1)
}

# Generate the MoonSniff histogram
function gen_histogram {
    cd /root/MoonGen;
    ./build/MoonGen examples/moonsniff/post-processing.lua -i latencies-pre.mscap -s latencies-post.mscap
}

# Download the generated histogram
# @param 1: The name of the histogram file
function download_histogram {
    scp tilga:/root/MoonGen/hist.csv ./$1 > /dev/null
}

# @param 1: source port
# @param 2: dest port
# @param 3: packet rate
# @param 4: time limit
# @param 5: Poisson or Uniform distribution of packets
# @return: The number of received and transmitted packets
function run_moongen {
    cd /root/MoonGen;
    ./setup-hugetlbfs.sh > /dev/null 2>&1&
    case ${5} in
    "Poisson")
        output=$(./build/MoonGen l2-load-latency-poisson.lua -r ${3} -t ${4} ${1} ${2} 2> /dev/null | tee moongen.log)
        ;;
     "Uniform")
        output=$(./build/MoonGen l2-load-latency.lua -r ${3} -t ${4} ${1} ${2} 2> /dev/null | tee moongen.log)
        ;;
     "Ping")
        output=$(./build/MoonGen l2-ping.lua ${1} ${2} 2> /dev/null | tee moongen.log)
        ;;
     *)
        echo "Distribution function unknown:" ${5}
        # output=$(./moongen-simple start load-latency:${1}:${2}:rate=${3},timeLimit=${4} 2> /dev/null | tee moongen.log)
        ;;
    esac
    output=$(echo "${output}" | tail -n 4)
    rx=0;
    tx=0;
    while IFS= read -r line
    do
        if [[ ${line} == *"id=${1}] TX"* ]]; then
            tx=$(echo "${line}" | grep -P '\d+ (?=packets)' -o)
        fi
        if [[ ${line} == *"id=${2}] RX"* ]]; then
            rx=$(echo "${line}" | grep -P '\d+ (?=packets)' -o)
        fi
    done <<< ${output}
    echo "tx=\"${tx}\";rx=\"${rx}\""
}

# @param 1: Path to Ixy
# @param 2: Output file
# @param 3: Time Limit
function start_powertop {
    cd ${1};
    sleep=$(($3 + 1))
    nohup bash -c "sleep 1 && powertop --csv=${2} --time=1 --iteration=${sleep} 2>&1" > /dev/null &
    echo $!
}

# @param 1: Path to Ixy
# @param 2: Input files
# @param 3: Output file
# @return: The CPU C stages
function parse_powertop {
    cd ${1};
    rm ${3}; > /dev/null
    IFS='.' read -a arr <<< ${2}
    for filename in ${arr[0]}*.${arr[1]}; do
        powertop=$(cat "${filename}")
        line_found=0;
        c0=0
        c1=0
        c3=0
        c6=0
        while IFS= read -r line
        do
            IFS=';' read -a c_states <<< ${line};
            if [[ "$line_found" -ne 0 ]]; then
                if [[ ${line} == "C0"* ]]; then
                    c0=${c_states[1]};
                    continue;
                fi
                if [[ ${line} == "C1"* ]]; then
                    c1=${c_states[1]};
                    continue;
                fi
                if [[ ${line} == "C3"* ]]; then
                    c3=${c_states[1]};
                    continue;
                fi
                if [[ ${line} == "C6"* ]]; then
                    c6=${c_states[1]};
                    continue;
                fi
                if [[ ${line} == "POLL"* ]]; then
                    continue;
                fi
                echo "${c0};${c1};${c3};${c6}" | sed 's/ //g' >> ${3}
                break;
            fi
            if [[ ${line} == "CPU;0;CPU;6" ]]; then
                line_found=1;
            fi
        done <<< ${powertop}
        rm $filename
    done
}

# Download the generated powertop result file
# @param 1: Path to Ixy
# @param 2: The name of the powertop result file
# @param 3: The name of the downloaded file
function download_powertop {
    scp omanyte:${1}/${2} ${3}  > /dev/null
}

# Stop the powertop Process
# @param 1: Path to Ixy
# @param 2: Input files
# @param 3: The PID of the powertop process
function stop_powertop {
    cd ${1}
    IFS='.' read -a arr <<< ${2}
    for filename in ${arr[0]}*.${arr[1]}; do
        rm ${filename}
    done
    kill $(ps -o pid= --ppid $3)
}

# @param 1: Path to Ixy
# @param 2: Output file
# @param 3: Time Limit
# @param 4: List of CPUs to monitor
# @return: The PID of perf
function start_perf {
    cd ${1};
    sleep=$(($3 + 4))
    nohup sh -c "sleep 1 && perf stat -a -g --per-core --cpu=${4} -o ${2} -e cycles,irq:irq_handler_entry -- sleep ${sleep}" > /dev/null &
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
    irq0=0;
    cpu1=0;
    irq1=0;
    while IFS= read -r line
    do
        if [[ ${line} == "S0-C${3:0:1}"*"cycles"* ]]; then
            cpu0=$(echo "${line}" | sed 's/\,//g' | grep -P '\d+ (?=\ *cycles)' -o)
        fi
        if [[ ${line} == "S0-C${3:0:1}"*"irq"* ]]; then
            irq0=$(echo "${line}" | sed 's/\,//g' | grep -P '\d+ (?=\ *irq:irq_handler_entry)' -o)
        fi
        if [[ ${line} == "S0-C${3:2:1}"*"cycles"* ]]; then
            cpu1=$(echo "${line}" | sed 's/\,//g' | grep -P '\d+ (?=\ *cycles)' -o)
        fi
        if [[ ${line} == "S0-C${3:2:1}"*"irq"* ]]; then
            irq1=$(echo "${line}" | sed 's/\,//g' | grep -P '\d+ (?=\ *irq:irq_handler_entry)' -o)
        fi
    done <<< ${perf}
    rm ${2}
    echo "cpu0=\"${cpu0}\";irq0=\"${irq0}\";cpu1=\"${cpu1}\";irq1=\"${irq1}\""
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
# @param 5: Poisson or Uniform distribution of packets
function run_experiment1 {
    oldCounter=0;
    for rate in `seq ${1} ${2} ${3}`;
    do
        PERF_PID=$(ssh omanyte "$(typeset -f); start_perf \"$IXY_PATH\" \"$PERF_FILE\" \"$4\" \"$CPUS\"")
        MOONSNIFF_PID=$(ssh tilga "$(typeset -f); start_moonsniff")
        packets=$(ssh omastar "$(typeset -f); run_moongen \"$SOURCE_PORT\" \"$DEST_PORT\" \"$rate\" \"$4\" \"$5\"")
        ssh tilga "$(typeset -f); stop_moonsniff $MOONSNIFF_PID"
        MOONSNIFF_PID=0
        histo=$(ssh tilga "$(typeset -f); gen_histogram")
        download_histogram histo-${rate}.csv
        cpuCycles=$(ssh omanyte "$(typeset -f); parse_perf \"$IXY_PATH\" \"$PERF_FILE\" \"$CPUS\"")
        counter=$(ssh omanyte "$(typeset -f); parse_interrupts \"$DEVICE1_ID\"")
        interrupts="$(($counter-$oldCounter))"
        oldCounter=${counter};
        eval ${packets}
        eval ${cpuCycles}
        if [[ ${#CPUS} -eq 1 ]]; then
            echo "${rate}; ${interrupts}; ${tx}; ${rx}; ${cpu0}; ${irq0}" | sed 's/ //g' | tee -a ${RESULT_FILE}
        else
            echo "${rate}; ${interrupts}; ${tx}; ${rx}; ${cpu0}; ${irq0}; ${cpu1}; ${irq1}" | sed 's/ //g' | tee -a ${RESULT_FILE}
        fi
        PERF_PID=0
    done
}

# @param 1: Start Rate
# @param 2: Step Size
# @param 3: Max Rate
# @param 4: Time Limit
# @param 5: Poisson or Uniform distribution of packets
function run_experiment2 {
    oldCounter=0;
    for rate in `seq ${1} ${2} ${3}`;
    do
        PERF_PID=$(ssh omanyte "$(typeset -f); start_perf \"$IXY_PATH\" \"$PERF_FILE\" \"$4\" \"$CPUS\"")
        POWERTOP_PID=$(ssh omanyte "$(typeset -f); start_powertop \"$IXY_PATH\" \"$POWERTOP_FILE\" \"$4\"")
        ssh omanyte "$(typeset -f); set_cpu_affinity 2 \"$PERF_PID\""
        ssh omanyte "$(typeset -f); set_cpu_affinity 2 \"$POWERTOP_PID\""
        MOONSNIFF_PID=$(ssh tilga "$(typeset -f); start_moonsniff")
        packets=$(ssh omastar "$(typeset -f); run_moongen \"$SOURCE_PORT\" \"$DEST_PORT\" \"$rate\" \"$4\" \"$5\"")
        ssh tilga "$(typeset -f); stop_moonsniff $MOONSNIFF_PID"
        MOONSNIFF_PID=0
        histo=$(ssh tilga "$(typeset -f); gen_histogram")
        download_histogram histo-${rate}.csv
        cpuCycles=$(ssh omanyte "$(typeset -f); parse_perf \"$IXY_PATH\" \"$PERF_FILE\" \"$CPUS\"")
        ssh omanyte "$(typeset -f); parse_powertop \"$IXY_PATH\" \"$POWERTOP_FILE\" \"$POWERTOP_RESULT_FILE\""
        download_powertop ${IXY_PATH} ${POWERTOP_RESULT_FILE} powertop-${rate}.csv
        counter=$(ssh omanyte "$(typeset -f); parse_interrupts \"$DEVICE1_ID\"")
        interrupts="$(($counter-$oldCounter))"
        oldCounter=${counter};
        eval ${packets}
        eval ${cpuCycles}
        if [[ ${#CPUS} -eq 1 ]]; then
            echo "${rate}; ${interrupts}; ${tx}; ${rx}; ${cpu0}; ${irq0}" | sed 's/ //g' | tee -a ${RESULT_FILE}
        else
            echo "${rate}; ${interrupts}; ${tx}; ${rx}; ${cpu0}; ${irq0}; ${cpu1}; ${irq1}" | sed 's/ //g' | tee -a ${RESULT_FILE}
        fi
        PERF_PID=0
        POWERTOP_PID=0
    done
}

# Number of interrupts on same core
# @param 1: Start rate
# @param 2: Step size
# @param 3: Max rate
# @param 4: Time limit
# @param 5: ITR
# @param 6: Poisson or Uniform distribution of packets. Default Uniform
function experiment1_1 {
    CPUS="0";
    START_RATE=${1:-$START_RATE}
    STEP_RATE=${2:-$STEP_RATE}
    MAX_RATE=${3:-$MAX_RATE}
    TIME_LIMIT=${4:-$TIME_LIMIT}
    ITR=${5:-$ITR}
    DIST=${6:-"Uniform"} # Uniform or Poisson distribution of packets
    printf "Running experiment 1 with %s distribution: start rate %f, step rate %f, max rate %f, time limit %u, ITR %s\n" "${DIST}" "${START_RATE}" "${STEP_RATE}" "${MAX_RATE}" "${TIME_LIMIT}" "${ITR}"
    IXY_PID=$(ssh omanyte "$(typeset -f); start_ixy_forwarder \"$IXY_PATH\" \"$ITR\" \"$DEVICE1_ID\" \"$DEVICE2_ID\"")
    sleep 2
    ssh omanyte "$(typeset -f); set_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 1 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 1 \"$DEVICE2_ID\""
    sleep 2
    run_experiment1 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT} ${DIST}
}

# Number of interrupts on different core
function experiment1_2 {
    CPUS="0,1";
    ssh omanyte "$(typeset -f); set_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 2 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 2 \"$DEVICE2_ID\""
    sleep 2
    run_experiment1 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT}
}

# Number of interrupts on hyperthreading pair
function experiment1_3 {
    CPUS="0";
    ssh omanyte "$(typeset -f); set_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 40 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 40 \"$DEVICE2_ID\""
    sleep 2
    run_experiment1 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT}
}

# Number of interrupts on same core
# @param 1: Start rate
# @param 2: Step size
# @param 3: Max rate
# @param 4: Time limit
# @param 5: ITR
# @param 6: Poisson or Uniform distribution of packets. Default Uniform
function experiment2 {
    CPUS="0";
    START_RATE=${1:-$START_RATE}
    STEP_RATE=${2:-$STEP_RATE}
    MAX_RATE=${3:-$MAX_RATE}
    TIME_LIMIT=${4:-$TIME_LIMIT}
    ITR=${5:-$ITR}
    DIST=${6:-"Uniform"} # Uniform or Poisson distribution of packets
    printf "Running experiment 1 with %s distribution: start rate %f, step rate %f, max rate %f, time limit %u, ITR %s\n" "${DIST}" "${START_RATE}" "${STEP_RATE}" "${MAX_RATE}" "${TIME_LIMIT}" "${ITR}"
    IXY_PID=$(ssh omanyte "$(typeset -f); start_ixy_forwarder \"$IXY_PATH\" \"$ITR\" \"$DEVICE1_ID\" \"$DEVICE2_ID\"")
    sleep 2
    ssh omanyte "$(typeset -f); set_cpu_affinity 1 \"$IXY_PID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 1 \"$DEVICE1_ID\""
    ssh omanyte "$(typeset -f); set_interrupt_affinity 1 \"$DEVICE2_ID\""
    sleep 2
    run_experiment2 ${START_RATE} ${STEP_RATE} ${MAX_RATE} ${TIME_LIMIT} ${DIST}
}

function delete_all_reports {
   rm *.csv
}

function usage {
    echo "USAGE: "
}

function cleanup {
  echo "Cleanup"
  ssh omastar "$(typeset -f); stop_moon_gen"
  if [[ "$IXY_PID" -ne 0 ]]; then
    echo "Killing Ixy ${IXY_PID}"
    ssh omanyte "$(typeset -f); stop_ixy \"$IXY_PID\""
  fi
  if [[ "$PERF_PID" -ne 0  ]]; then
    echo "Killing Perf ${PERF_PID}"
    ssh omanyte "$(typeset -f); stop_perf \"$PERF_PID\""
  fi
  if [[ "$POWERTOP_PID" -ne 0  ]]; then
    echo "Killing Powertop ${POWERTOP_PID}"
    ssh omanyte "$(typeset -f); stop_powertop \"$IXY_PATH\" \"$POWERTOP_FILE\" \"$POWERTOP_PID\""
  fi
  if [[ "$MOONSNIFF_PID" -ne 0  ]]; then
    echo "Killing Moonsniff ${MOONSNIFF_PID}"
    ssh tilga "$(typeset -f); stop_moonsniff \"$MOONSNIFF_PID\""
  fi
}

### Pre Setup
> ${RESULT_FILE}
trap cleanup EXIT
ssh omanyte "$(typeset -f); build_ixy \"$IXY_PATH\""
###

"$@"