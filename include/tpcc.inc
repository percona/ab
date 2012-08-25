#!/bin/bash
########################################################################
#
#   Autobench test configuration file for tpcc test
#
########################################################################

tpcc.test_setup()
{
  #profile information
  USE_OPROFILE=0
  VMLINUX=/tmp/vmlinux-2.6.16.46-0.12-smp

  #System statistic information: sar/vmstat/iostat
  COLLECT_STAT=1
  TEST_STAT_SAMPLE=10 # Get sample each 10 seconds

  #Stack size
  STACKSIZE=256

  #Test name
  TEST_NAME="tpcc_w10"

  #If test have subtests specify them here
  TEST_CASES="tpccw50-backup"

  #Test basedir
  TEST_BASEDIR=$AUTOBENCH_TESTBASEDIR/tpcc

  #Basedir for backup datafiles
  TEST_BACKUP_BASEDIR=$AUTOBENCH_BACKUPDIR/tpcc_w10

  #Does test support multi-user mode.
  TEST_MULTIUSER_MODE=1

  # Test options
  THREADS="16 40 80"
  ITERATIONS="1"
  DURATION=900
  WARMUPTIME=10

  # TPCC options
  # ScaleFactor(number of warehouses)
  TPCC_SF=10
  TPCC_ZERO_DELAY=1
  TPCC_THREAD_DELAY=100
  TPCC_VERBOSE=1  
  TPCC_DATASET_DIR=$AUTOBENCH_TMPDIR/tpcc_w10

  #InnoDB MONITOR
  IMONITOR="1"

  #SERVER DB
  SERVER_DB="TPCC_W${TPCC_SF}"
  TEST_WARMUP_DURATION=300

  TEST_STAGE_PREPARE_GENERATE=""  # GENERATE INITIAL DATASET AND LOAD IT
  TEST_STAGE_PREPARE_RESTORE="1"  # RESTORE DATADIR FROM BACKUP
  TEST_STAGE_RUN="1"              # RUN || "" - RUN STAGE WILL BE SKIPPED
  TEST_STAGE_CLEANUP="1"          #

  TEST_STAGE_PREPARE_GENERATE_EXE="$TEST_BASEDIR/load_tpcc.sh"
  TEST_STAGE_RUN_EXE="$TEST_BASEDIR/tpcc_start"
  TEST_STAGE_CLEANUP_EXE="$AUTOBENCH_LIBDIR/tpcc-cleanup.sh"
  TEST_STAGE_CLEANUP_EXE="/bin/true"

  SERVER_PORT=3306
  SERVER_HOST=127.0.0.1
  SERVER_DB='test'

  TEST_ARGS_STAGE_PREPARE='  $SERVER_DB  $TPCC_SF'

  TEST_ARGS_STAGE_RUN=' -h $SERVER_HOST -P $SERVER_PORT -d "$SERVER_DB" -u $SERVER_USER -p \"\"  -w $TPCC_SF -r $WARMUPTIME -l $DURATION -i 1 '

  TEST_ARGS_STAGE_CLEANUP=' $TEST_BASEDIR $TEST_OUTDIR'

  # Variable part of command line that will be used for substitution
  # of loop variables and will be joined with $TEST_ARGS_COMMON

  TEST_ARGS_TEMPLATE='"-c $TEST_THREAD "'
}

tpcc.test_pre_run()
{
  #SANITY CHECKS
  ENGINE_NAME=`echo $ENGINE_NAME | tr a-z A-Z`

  if [[ -n $TEST_STAGE_PREPARE_RESTORE ]]; then 
    if [[ -z $TEST_BACKUP_BASEDIR || ! -d $TEST_BACKUP_BASEDIR ]]; then 
      usage "Dir: TEST_BACKUP_BASEDIR $TEST_BACKUP_BASEDIR doesnt exist"
    fi
  fi

#  TEST_ARGS_STAGE_PREPARE="$TEST_ARGS_STAGE_PREPARE -e $ENGINE_NAME"
  
#  killall client > /dev/null 2>&1
#  killall driver > /dev/null 2>&1
}


tpcc.help()
{
  cat << DATAEOF

  # tpcc specific options
  TPCC_SF=10                                     # ScaleFactor(number of warehouses)
  TPCC_DATASET_DIR=$AUTOBENCH_TMPDIR/tpccw10     # Location of generated data files with dbgen

  # test options
  THREADS="16 40 80"                             # List of number of threads
  ITERATIONS="1 2 3"                             # List of number of iterations
  DURATION=900                                   # Test duration

DATAEOF
}

tpcc.test_stage_run_pre()
{

if [ -n "$IMONITOR" ]; then 

(
trap 'echo "Got TERM signal."; \
      cat $TEST_OUTDIR/innodb-monitor.pid; \ 
      exit ' TERM

trap 'echo "Got INT signal."; \
      cat $TEST_OUTDIR/innodb-monitor.pid; \ 
      exit ' INT

echo $? >>$TEST_OUTDIR/innodb-monitor.pid
echo $$ >>$TEST_OUTDIR/innodb-monitor.pid
while [ true ]; do
output_date=`date +%s`
output=`mysql -uroot -e'show engine  innodb mutex; show engine innodb status\G' -S /tmp/mysql.sock 2>&1`
if [ $? -eq 0 ]; then
  let diff=$ok_date-$output_date
  echo "DUMP_DATE=$output_date INTERVAL: $diff " >> $TEST_OUTDIR/innodb-monitor.out
  echo "$output" >>$TEST_OUTDIR/innodb-monitor.out
  echo  >>$TEST_OUTDIR/innodb-monitor.out
  ok_date=$output_date
fi
sleep 30
done

)&

MONITOR_PID=$!
fi

}

tpcc.test_stage_run_post()
{
  if [ -n "$IMONITOR" -a  -n "$MONITOR_PID" ]; then 
    echo -n "IMONITOR PID $MONITOR_PID in FILE:  "
    cat $TEST_OUTDIR/innodb-monitor.pid
    
    kill -HUP $MONITOR_PID
    sleep 10
    kill $MONITOR_PID
    sleep 10
    kill -HUP $MONITOR_PID
    sleep 10
    show_msg "Waiting for pid: $MONITOR_PID"
    wait $MONITOR_PID
    
    MONITOR_PID=""
  fi
}

tpcc.test_stage_prepare_restore_pre()
{
  echo
  if [ -n "$TPCC_VIRIDENT_FORMAT" ]; then
   tpcc.virident
  fi
}

tpcc.test_stage_prepare_restore_post()
{
  show_msg_date "test_stage_prepare_restore_post"
  if [ -n "$TPCC_LOG_DIR" ]; then 
    tpcc.copy_log_files
  fi
  show_msg_date "done"
}


tpcc.copy_log_files()
{

  if [ -n "$TPCC_LOG_DIR" -a -d "$TPCC_LOG_DIR" ]; then 
    show_msg_date "Copy log files to $TPCC_LOG_DIR"
    cp -Rf $MYSQL_BACKUP_DIR/ib_log* $TPCC_LOG_DIR
  else
    show_msg_date "Directory for InnoDB log files $TPCC_LOG_DIR is inaccesible"
    exit 255
  fi
}

tpcc.virident()
{
  show_msg_date "VIRIDENT: Preparing Tachion drive for testing... "

  while [ true ]; do 
    kpid=`lsof | grep tachion | grep -o '\b[0-9]*\b' | head -n 1`
    if [ -n "$kpid" ]; then 
      show_msg_date "/mnt/tachion is busy due to pid: $kpid. Killing it"
      kill -9 $kpid 
      sleep 60
    else
      show_msg_date "/mnt/tachion is not busy. continue preparation of verident..."
      break
    fi  
   done


  if [ -n "`mount | grep tachio`" ]; then
    umount /mnt/tachion
    if [ $? -ne 0 ];
      then 
        echo "Can't unmount /mnt/tachion"
        exit 255
    fi
  fi

  if [ `which vgc-config` ]; then
    vgc-config -r -d /dev/vgca >> $TEST_OUTDIR/virident_format.out
    service vgcd reload >> $TEST_OUTDIR/virident_format.out
    mkfs.xfs -s size=4096 /dev/vgca0 >> $TEST_OUTDIR/virident_format.out
    mount /dev/vgca0 /mnt/tachion -o nobarrier >> $TEST_OUTDIR/virident_format.out
    mkdir /mnt/tachion/data >> $TEST_OUTDIR/virident_format.out
    show_msg_date "VIRIDENT: /mnt/tachion is ready for testing"
    sleep 10
    /etc/STATsrv/STAT-service stop
    sleep 5
    /etc/STATsrv/STAT-service start
  else
    show_msg_date "ERROR: EXIT as can't prepare tachion partition"
    exit 255
  fi
}
