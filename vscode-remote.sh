#!/bin/bash

JOB_NAME=vscode-remote
TIMEOUT=300

if [ ! -z "$1" ] && [ $1 == "gpu" ]; then
    SBATCH_PARAM="-q ng --gpus=1 -t 04:00:00 --mem=32G -c 16"
else
    SBATCH_PARAM="-q ni -t 12:00:00 --mem=32G -c 16"
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
START=$(date +%s)

query_slurm(){
    # only list states that can result in a running job
    list=($(squeue --me --states=R,PD,S,CF,RF,RH,RQ -h -O JobId:" ",Name:" ",State:" ",NodeList:" " | grep $JOB_NAME))

    if [ ! ${#list[@]} -eq 0 ]; then
        echo ${list[@]}
        JOB_ID=${list[0]}
        JOB_FULLNAME=${list[1]}
        JOB_STATE=${list[2]}
        JOB_NODE=${list[3]}

        split=(${JOB_FULLNAME//%/ })
        JOB_PORT=${split[1]}
    else
        JOB_ID=""
        JOB_FULLNAME=""
        JOB_STATE=""
        JOB_NODE=""
        JOB_PORT=""
    fi
}

timeout() {
    if (( $(date +%s)-START > TIMEOUT )); then 
        echo "Timeout, exiting..."
        exit 1
    fi
}

if [ ! -z "$1" ] && [ $1 == "cancel" ]; then
    query_slurm
    while [ ! -z "${JOB_ID}" ]; do
        echo Cancelling job $JOB_ID
        scancel $JOB_ID
        timeout
        sleep 2
        query_slurm
    done
    exit 0
fi

if [ ! -z "$1" ] && [ $1 == "list" ]; then
    echo "$(squeue --me -O JobId,Partition,Name,State,TimeUsed,TimeLimit,NodeList | grep -E "JOBID|$JOB_NAME")"
    exit 0
fi

query_slurm

if [ -z "${JOB_STATE}" ]; then
    PORT=$(shuf -i 2000-65000 -n 1)
    /usr/bin/sbatch -J $JOB_NAME%$PORT $SBATCH_PARAM -o none $SCRIPT_DIR/job.sh $PORT
fi

while [ ! "$JOB_STATE" == "RUNNING" ]; do
    timeout
    sleep 5
    query_slurm
done

echo "Connecting to $JOB_NODE"

while ! nc $JOB_NODE $JOB_PORT; do 
    timeout
    sleep 1 
done