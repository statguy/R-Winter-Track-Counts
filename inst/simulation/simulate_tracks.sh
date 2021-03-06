#!/bin/bash

if [ -z "$1" ]
then
echo "Missing parameter 'exec path'".
exit
fi
if [ -z "$2" ]
then
echo "Missing parameter 'iterations'".
exit
fi
if [ -z "$3" ]
then
echo "Missing parameter 'max_nodes'".
exit
fi

exec_path=$1
iterations=$2
max_nodes=$3
count_days=1

for scenario in A B C D E F; do
  python "$exec_path"/parallel_r.py -t "$iterations" -n "$max_nodes" -l 10.0 -b ~/tmp/blacklist.txt -v ~/git/Winter-Track-Counts/inst/simulation/simulate.R notest "$scenario"
done

# ./simulate_tracks.sh ~/git/RParallelScreen/ 101:150 60
# ./simulate_tracks.sh ~/git/RParallelScreen/ 151:161 11
