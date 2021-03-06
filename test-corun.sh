#!/bin/bash

MGDIR=/sys/kernel/debug/memguard
SCHED=rt  #normal
EXTRATAG=2bws-1mplayers-vox11-`date +"%m%d"`
#EXTRATAG=3bws-3mplayers-vox11-`date +"%m%d"`
#EXTRATAG=4bws-4mplayers-vox11-`date +"%m%d"`
#EXTRATAG=4bws-2mplayers-vox11-`date +"%m%d"`
#EXTRATAG=3bws-2mplayers-vox11-`date +"%m%d"`
#EXTRATAG=1bws-2mplayers-vox11-`date +"%m%d"`
VIDOUT=""
# EXTRATAG=4bws-4mplayers-vonull-`date +"%m%d"`
# VIDOUT="-vo null"
MG_BWS="500 500 100 100"
# MG_BWS="300 300 300 300"

if [ ! -z "$1" ]; then
    EXTRATAG="$1"
fi

echo "experiment for $EXTRATAG"


echo 16384 > /sys/kernel/debug/tracing/buffer_size_kb

error()
{
    echo "ERR: $*"
    exit 1
}

# init
do_init_mg-ss()
{
    echo "mg-ss"
    bws="$1"
    echo mb $bws > $MGDIR/limit
    echo exclusive 2 > $MGDIR/control
}

do_init_mg-br-ss()
{
    echo "mg-br-ss"
    bws="$1"
    echo mb $bws > $MGDIR/limit
    echo exclusive 2 > $MGDIR/control
    echo reclaim 1 > $MGDIR/control
}

do_load_spec()
{
    # TBD: lbm
    echo TBD
}

do_load()
{
    local cores
    acctype=$1
    if [[ $EXTRATAG == *"4bws"* ]]; then 
	cores="0 1 2 3"
    elif [[ $EXTRATAG == *"3bws"* ]]; then 
	cores="0 2 3"
    elif [[ $EXTRATAG == *"2bws"* ]]; then 
	cores="2 3"
    elif [[ $EXTRATAG == *"1bws"* ]]; then 
	cores="3"
    elif [[ $EXTRATAG == *"0bws"* ]]; then 
	cores=""
    else
	error "cores=$cores"
    fi
    for c in $cores; do
	./bandwidth -c $c -t 100000 -a $acctype -f corun-bw.log &
    done
}


drop_cache()
{
    sync
    echo 1 > /proc/sys/vm/drop_caches # free file caches
}

run_bench()
{
    drop_cache

    echo "run mplayer on C0"
    echo "" > /sys/kernel/debug/tracing/trace

    local pgm="mplayer-nobwlock"
    if [ "$USE_BWLOCK_FINE" = "1" ]; then
    	local pgm="mplayer-bwlockfine"
    # elif [ "$USE_BWLOCK_ALL" = "1" ]; then 
    #   local pgm="mplayer-bwlockcoarse"
    fi
    if [ "$SCHED" = "rt" ]; then
	pgm="$pgm -rt"
    fi
    if [[ $EXTRATAG == *"4mplayers"* ]]; then 
	taskset -c 1 ./$pgm 1080p.mp4 $VIDOUT >& /dev/null &
	taskset -c 2 ./$pgm 1080p.mp4 $VIDOUT >& /dev/null &
	taskset -c 3 ./$pgm 1080p.mp4 $VIDOUT >& /dev/null &
    elif [[ $EXTRATAG == *"3mplayers"* ]]; then 
	taskset -c 2 ./$pgm 1080p.mp4 $VIDOUT >& /dev/null &
	taskset -c 3 ./$pgm 1080p.mp4 $VIDOUT >& /dev/null &
    elif [[ $EXTRATAG == *"2mplayers"* ]]; then 
	taskset -c 2 ./$pgm 1080p.mp4 $VIDOUT >& /dev/null &
    fi
    # time taskset -c 0 perf record -e cache-misses -o perf.mplayer.llcmisses ./$pgm 1080p.mp4 $VIDOUT
    time taskset -c 0 perf record -o perf.mplayer.cycles ./$pgm 1080p.mp4 $VIDOUT
    # time taskset -c 0 ./$pgm 1080p.mp4 $VIDOUT
    
    cat /sys/kernel/debug/tracing/trace > mplayer.trace
}

end_bench()
{
    logdir=$1
    killall -2 bandwidth mplayer-bwlockcoarse mplayer-bwlockfine mplayer-nobwlock mplayer
    do_graph
    if [ ! -z "$logdir" ]; then
	[ ! -d "$logdir" ] && mkdir -v $logdir
	tail -n 5900 ~/timing-X.txt > $logdir/timing-X.txt
	mv timing-mplayer.txt play.log* utime.log* itime.log* stime.log* timestamp.log* corun-bw.log $logdir
	mv mplayer.trace* mplayer.core*.dat mplayer.figs.* $logdir
	mv perf.mplayer.* $logdir
    fi
    chown -R heechul.heechul $logdir
}

test_solo()
{
    rmmod memguard
    insmod ./memguard.ko
    USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    do_load write
    sleep 5
    end_bench log_${EXTRATAG}_solo
    rmmod memguard
}

test_corun()
{
    rmmod memguard
    insmod ./memguard.ko
    do_load write
    USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_corun
    rmmod memguard
}

test_mg()
{
    rmmod memguard
    insmod ./memguard.ko g_use_bwlock=0
    do_init_mg-br-ss "$MG_BWS"
    do_load write
    USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_mg-br-ss
    rmmod memguard
}

# fine grained locking
test_bwlock_fine() 
{
#    rmmod memguard
#    insmod ./memguard.ko
    local bwlockmode=$1
    if [ "$bwlockmode" = "shared" ]; then
	echo bwlockmode 0 > /sys/kernel/debug/memguard/control
	cat /sys/kernel/debug/memguard/control | grep bwlockmode
    elif [ "$bwlockmode" = "exclusive" ]; then
	echo bwlockmode 1 > /sys/kernel/debug/memguard/control
	cat /sys/kernel/debug/memguard/control | grep bwlockmode
    fi
    do_load write
    USE_BWLOCK_FINE=1 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_bwlock_fine-$bwlockmode
#    rmmod memguard
}

# whole bwlock
test_bwlock_all()
{
    rmmod memguard
    insmod ./memguard.ko
    do_load write
    ./bwlockset $Xpid 1
    USE_BWLOCK_ALL=1 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    ./bwlockset $Xpid 0
    end_bench log_${EXTRATAG}_bwlock_all
    rmmod memguard
}

plot()
{
    # file msut be xxx.dat form
    local start=$1
    local finish=$2
    local file="mplayer.figs.${start}-${finish}"
    cat > ${file}.scr <<EOF
set terminal postscript eps enhanced color "Times-Roman" 22
set yrange [0:100000]
set xrange [$start:$finish]
plot 'mplayer.core0.dat' ti "core0" w lp, \
     'mplayer.core1.dat' ti "core1" w lp, \
     'mplayer.core2.dat' ti "core2" w lp, \
     'mplayer.core3.dat' ti "core3" w lp
EOF
    gnuplot ${file}.scr > ${file}.eps
    epspdf  ${file}.eps
}

plot_core()
{
    # file msut be xxx.dat form
    local core=$1
    local start=$2
    local finish=$3
    local file="mplayer.figs.C${core}-${start}-${finish}"
    cat > ${file}.scr <<EOF
set terminal postscript eps enhanced color "Times-Roman" 22
set yrange [0:100000]
set xrange [$start:$finish]
plot 'mplayer.core$core.dat' ti "core$core" w lp
EOF
    gnuplot ${file}.scr > ${file}.eps
    epspdf  ${file}.eps
}


plot_stime_distribution()
{
    file="compare"
    cat > ${file}.scr <<EOF
set terminal postscript eps enhanced color "Times-Roman" 22
set yrange [0:50]
plot 'log_${EXTRATAG}_solo/stime.log' ti "Solo" w lp, \
     'log_${EXTRATAG}_corun/stime.log' ti "Default" w lp, \
     'log_${EXTRATAG}_mg-br-ss/stime.log' ti "MemGuard" w lp, \
     'log_${EXTRATAG}_bwlock_fine/stime.log' ti "bwlock(fine)" w lp, \
     'log_${EXTRATAG}_bwlock_all/stime.log' ti "bwlock(coarse)" w lp
EOF
    gnuplot ${file}.scr > ${file}.eps
    epspdf  ${file}.eps
}

do_graph()
{
    echo "plotting graphs"
    for core in 0 1 2 3; do
	[ ! -f mplayer.trace ] && error "mplayer.trace doesn't exist"
	cat mplayer.trace | grep "$core\]" > mplayer.trace.core$core
	grep update_statistics mplayer.trace.core$core | awk '{ print $15 " " $7 }' | \
	    grep -v throttled_error > mplayer.core$core.dat.tmp
	./traceproc.py mplayer.core$core.dat.tmp > mplayer.core$core.dat
    done
    plot 0 15000
    plot 14000 15000
    plot_core 0 0 15000
    plot_core 1 0 15000
}

copy_data()
{
    local dir=$1
#    echo "Copying produced data $dir"
    chown -R heechul.heechul $dir
    cp -r $dir ~/Dropbox/tmp
    chown -R heechul.heechul ~/Dropbox/tmp/$dir
}

Xpid=`pidof X`
echo "set X ($Xpid) to C1" 
taskset -p -c 1 $Xpid
if [ "$SCHED" = "rt" ]; then
   if chrt -p -f 1 $Xpid; then
	echo "X is running in RT priority"
   else
	echo "ERR: X is running at normal priority"
   fi
fi

#test_solo
#test_corun
# test_bwlock_all


#test_bwlock_fine shared
#test_bwlock_fine exclusive
test_mg

# for dir in log_${EXTRATAG}_*; do 
#     mkdir -p $dir || echo "WARN: overwrite"
#     avg_ftime=`cat $dir/stat.dat | grep "avg:" | awk '{ print $2 }'`
#     throughput=`cat $dir/corun-bw.log | awk '{ print $2 }' `
#     echo $dir $avg_ftime $throughput
# #    copy_data $dir
# done

tag="log_${EXTRATAG}"
echo $tag "name avg bw | 95pct stdev dmiss | avg(stime)"
for d in solo corun mg-br-ss bwlock_fine bwlock_fine-shared bwlock_fine-exclusive bwlock_all; do
    # cat $d/corun-bw.log
    if [ ! -d "${tag}_$d" ]; then
        continue
    fi
    # ./fps.pl ${tag}_$d/timestamp.log > ${tag}_$d/fps.dat
    ./printstat.py -d 41.0 ${tag}_$d/stime.log > ${tag}_$d/stat.dat
    A=`cat ${tag}_$d/stat.dat | grep "avg:" | awk '{ print $2 }'`
    B=`cat ${tag}_$d/corun-bw.log | awk '{s+=$2} END {print s}'`
    ./printstat.py -d 41.0 ${tag}_$d/utime.log > ${tag}_$d/stat_utime.dat
    C=`cat ${tag}_$d/stat_utime.dat | grep "avg:" | awk '{ print $2 }'`
    D=`cat ${tag}_$d/stat_utime.dat | grep "95pctile:" | awk '{ print $2 }'`
    G=`cat ${tag}_$d/stat_utime.dat | grep "median:" | awk '{ print $2 }'`
    E=`cat ${tag}_$d/stat_utime.dat | grep "stdev:" | awk '{ print $2 }'`
    F=`cat ${tag}_$d/stat_utime.dat | grep "ratio:" | awk '{ print $4 }'`
    printf "%25s %2.2f %d | %2.2f %2.2f %2.2f %2.2f| %2.2f\n" $d $C $B $D $G $E $F $A
done

# plot_stime_distribution
# cp compare.pdf ~/Dropbox/tmp/compare-${EXTRATAG}.pdf
# chown heechul.heechul ~/Dropbox/tmp/compare*.pdf

