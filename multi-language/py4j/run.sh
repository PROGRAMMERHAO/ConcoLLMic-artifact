#!/bin/bash

TESTER_NAME=$1
TIMEOUT=$2

hostname=`hostname | cut -c 1-4`

if [ $# -lt 1 ]; then
    echo "Usage: $0 <TESTER_NAME> [timeout_seconds]"
    echo "TESTER_NAME must be 'concolic' or its variants"
    exit 1
fi

if [ $# -eq 2 ]; then
    TIMEOUT_SECONDS=$2
    echo "Using specified timeout of $TIMEOUT_SECONDS for testing ultrajson with $TESTER_NAME."
else
    TIMEOUT_SECONDS=60
    echo "Using default timeout of 60 seconds for testing ultrajson with $TESTER_NAME."
fi

# Set default paths

current_time=$(date +%m%d%H%M)
export SHARED_DIR="/shared/${TESTER_NAME}-${current_time}-${hostname}"

export INPUT="${SHARED_DIR}/input"
export OUTPUT="${SHARED_DIR}/output"

export INSTR_ROOT="/py4j-inst"

mkdir -p $INPUT

cp /seed_execs/* $INPUT/

# echo execution command and start time
echo "Executing command: $0 $@" > ${SHARED_DIR}/execution_command.log
echo "Start time: $(date)" >> ${SHARED_DIR}/execution_command.log

setup_concolic_environment() {
    echo "Setting up Concolic environment"
    pushd /concolic-agent
    if [ "${USE_LOCAL_CODE:-0}" = "1" ]; then
        echo "USE_LOCAL_CODE=1: skipping git pull, using mounted local code"
        echo "USE_LOCAL_CODE=1 (local code, no git pull)" >> ${SHARED_DIR}/execution_command.log
    else
        git fetch origin
        git reset --hard origin/main    # pull the latest version
        pip install -r requirements.txt
        pip install -r requirements-dev.txt
        git_version=$(git rev-parse HEAD)
        echo "git version: $git_version" >> ${SHARED_DIR}/execution_command.log
    fi
    popd
}

# ------------------ Start Tester ------------------
export PYTHONPATH=${INSTR_ROOT}
case $TESTER_NAME in
  "concolic")
    echo "Running with Concolic"
    echo "python3 ACE.py run --project_dir $INSTR_ROOT --execution ${INPUT}/run.py --timeout 10 --out $OUTPUT --plateau_slot 30"  >> ${SHARED_DIR}/execution_command.log

    # call the wrapped function to pull the latest version of ACE
    setup_concolic_environment

    cd /concolic-agent
    timeout -k 10 $TIMEOUT_SECONDS /bin/bash -c \
        "python3 ACE.py run --project_dir $INSTR_ROOT --execution ${INPUT}/run.py --timeout 10 --out $OUTPUT --plateau_slot 30" \
        > /dev/null 2>&1 &
    wait
    export QUEUE_DIR="$OUTPUT"
    ;;
esac


if [ $? -eq 124 ]; then
    echo "Testing timed out after $TIMEOUT_SECONDS seconds."
else
    echo "Testing completed. Starting replay."
fi

# ------------------ Replay ------------------
covfile="${SHARED_DIR}/coverage_summary.csv"

python3 ACE.py replay $QUEUE_DIR $INSTR_ROOT $covfile --timeout 10 > ${SHARED_DIR}/replay.log 2>&1

python3 ACE.py run_data $QUEUE_DIR > ${SHARED_DIR}/run_data.log

echo "Replaying completed."

