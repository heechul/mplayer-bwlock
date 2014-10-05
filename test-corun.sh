#!/bin/bash

MGDIR=/sys/kernel/debug/memguard
EXTRATAG=`date +"%m%d"`

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
    cores="$1"
    acctype=$2
    for c in $cores; do
	./bandwidth -c $c -t 100000 -a $acctype -f corun-bw.log &
    done
}


run_bench()
{
    echo "run mplayer on C0"
    time taskset -c 0 ./mplayer 1080p.mp4
}

end_bench()
{
    logdir=$1
    if [ ! -z "$logdir" ]; then
	[ ! -d "$logdir" ] && mkdir -v $logdir
	tail -n 5900 ~/timing-X.txt > $logdir/timing-X.txt
	mv timing-mplayer.txt play.log utime.log itime.log stime.log timestamp.log corun-bw.log $logdir
    fi
    killall -2 bandwidth mplayer
}

test_solo()
{
    rmmod memguard
    USE_BWLOCK=0 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_solo
    rmmod memguard
}

test_corun()
{
    rmmod memguard
    do_load "2 3" write
    USE_BWLOCK=0 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_corun
    rmmod memguard
}

test_mg()
{
    rmmod memguard
    insmod ./memguard.ko
    do_init_mg-br-ss "450 450 100 100"
    
    do_load "2 3" write
    USE_BWLOCK=0 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_mg-br-ss
    rmmod memguard
}

# fine grained locking
test_bwlock_fine() 
{
    # rmmod memguard
    # insmod ./memguard.ko
    do_load "2 3" write
    USE_BWLOCK_FINE=1 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_bwlock_fine
    # rmmod memguard
}

# whole bwlock
test_bwlock_all()
{
    # rmmod memguard
    # insmod ./memguard.ko
    do_load "2 3" write
    USE_BWLOCK_ALL=1 USE_TIMING=1 run_bench > play.log 2> timing-mplayer.txt
    end_bench log_${EXTRATAG}_bwlock_all
    # rmmod memguard
}

plot()
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

Xpid=`pidof X`
echo "set X ($Xpid) to C1" 
taskset -p -c 1 $Xpid

# test_solo
# test_corun
# test_mg
#test_bwlock_all
test_bwlock_fine

# plot
# cp compare.pdf ~/Dropbox/tmp/compare-${EXTRATAG}.pdf
# chown heechul.heechul ~/Dropbox/tmp/compare*.pdf

rm stat.dat
for dir in log_${EXTRATAG}_*; do 
#    cat $dir/play.log
    echo "$dir :"
    cat $dir/corun-bw.log
    ./fps.pl $dir/timestamp.log > $dir/fps.dat
    ./printstat.py -d 41.0 $dir/stime.log > $dir/stat.dat
    cp -r $dir ~/Dropbox/tmp
    chown -R heechul.heechul ~/Dropbox/tmp/$dir
done
