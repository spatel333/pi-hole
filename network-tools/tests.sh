#!/bin/bash


TARGET_IP="<ip_address>"
DURATION=30



# THROUPUT
# TCP throughput (up)
iperf3 -c ${TARGET_IP} -t ${DURATION}

# (down / reverse)
iperf3 -c ${TARGET_IP} -t ${DURATION} -R

# UDP THROUGHPUT (needed since Pi-Hole DNS is UDP-heavy)
iperf3 -c ${TARGET_IP} -ub 1G -t ${DURATION}



### LATENCY
echo "=== baseline (idle) ==="
mtr -rc 50 ${TARGET_IP}

echo "=== Starting background saturation load ==="
iperf3 -c ${TARGET_IP} -t 60 &
IPERF_PID=$!

sleep 5
echo "=== Latency WHILE saturated ==="
mtr -rc 50 ${TARGET_IP}

wait ${IPERF_PID}
# This tells us whether device's latency degrades disproportionatly under a load
