#!/bin/bash

MGDIR=/sys/kernel/debug/memguard
EXTRATAG=4bws-t300-`date +"%m%d"`
SCHED=rt  #normal
VIDOUT="-vo null"

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

do_load()
{
    local cores="$1"
    acctype=$2
    for c in $cores; do
	./bandwidth -c $c -t 100000 -a $acctype -f corun-bw.log &
    done
}


run_bench()
{
    echo "run mplayer on C0"
    echo "" > /sys/kernel/debug/tracing/trace
    if [ "$SCHED" = "rt" ]; then
	time taskset -c 0 ./mplayer -rt 1080p.mp4 $VIDOUT
    else
	time taskset -c 0 ./mplayer 1080p.mp4 $VIDOUT
    fi
    cat /sys/kernel/debug/tracing/trace > mplayer.trace
}

end_bench()
{
    logdir=$1
    do_graph
    if [ ! -z "$logdir" ]; then
	[ ! -d "$logdir" ] && mkdir -v $logdir
	tail -n 5900 ~/timing-X.txt > $logdir/timing-X.txt
	mv timing-mplayer.txt play.log utime.log itime.log stime.log timestamp.log corun-bw.log $logdir
	mv mplayer.trace* mplayer.core*.dat mplayer.figs.* $logdir

    fi
    killall -2 bandwidth mplayer
}

test_solo()
{
    rmmod memguard
    insmod ./memguard.ko
    USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_solo
    rmmod memguard
}

test_corun()
{
    rmmod memguard
    insmod ./memguard.ko
    do_load "0 1 2 3" write
    USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_corun
    rmmod memguard
}

test_mg()
{
    rmmod memguard
    insmod ./memguard.ko
    do_init_mg-br-ss "450 450 100 100"
    do_load "0 1 2 3" write
    USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_mg-br-ss
    rmmod memguard
}

# fine grained locking
test_bwlock_fine() 
{
    rmmod memguard
    insmod ./memguard.ko
    do_load "0 1 2 3" write
    USE_BWLOCK_FINE=1 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_bwlock_fine
    rmmod memguard
}

# whole bwlock
test_bwlock_all()
{
    rmmod memguard
    insmod ./memguard.ko
    do_load "0 1 2 3" write
    USE_BWLOCK_ALL=1 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
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
     'mplayer.core2.dat' ti "core3" w lp
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
plot 'log_${EXTRATAG}_solo/stime.log' ti "solo" w lp, \
     'log_${EXTRATAG}_corun/stime.log' ti "corun" w lp, \
     'log_${EXTRATAG}_mg-br-ss/stime.log' ti "mg-br-ss" w lp, \
     'log_${EXTRATAG}_bwlock/stime.log' ti "bwlock" w lp
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
	grep update_statistics mplayer.trace.core$core | awk '{ print $7 }' | \
	    grep -v throttled_error > mplayer.core$core.dat
    done
    plot 0 15000
    plot 14000 15000
    plot_core 0 0 15000
    plot_core 1 0 15000
}

copy_data()
{
    local dir=$1
    echo "Copying produced data $dir"
    mkdir -p $dir || echo "WARN: overwrite"
    cat $dir/corun-bw.log
    ./fps.pl $dir/timestamp.log > $dir/fps.dat
    ./printstat.py -d 41.0 $dir/stime.log > $dir/stat.dat
    chown -R heechul.heechul $dir
    cp -r $dir ~/Dropbox/tmp
    chown -R heechul.heechul ~/Dropbox/tmp/$dir
}

# Xpid=`pidof X`
# echo "set X ($Xpid) to C1" 
# echo $Xpid > /sys/fs/cgroup/tasks
# taskset -p -c 1 $Xpid
# if [ "$SCHED" = "rt" ]; then
#     if chrt -p -f 1 $Xpid; then
# 	echo "X is running in RT priority"
#     else
# 	echo "ERR: X is running at normal priority"
#     fi
# fi

test_solo
test_corun
test_bwlock_all
test_bwlock_fine
test_mg

# plot_stime_distribution
# cp compare.pdf ~/Dropbox/tmp/compare-${EXTRATAG}.pdf
# chown heechul.heechul ~/Dropbox/tmp/compare*.pdf
for dir in log_${EXTRATAG}_*; do 
    copy_data $dir
done
