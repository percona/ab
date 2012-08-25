#!/bin/bash
########################################################################
#
#   Autobench test configuration file for dbt2 test
#
########################################################################


dbt2.test_setup()
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
  TEST_NAME="dbt2w10"

  #If test have subtests specify them here
  TEST_CASES="dbt2w50-backup"

  #Test basedir
  TEST_BASEDIR=$AUTOBENCH_TESTBASEDIR/dbt2/dbt2-0.37-fixed-23.10.2007/scripts

  #Basedir for backup datafiles
  TEST_BACKUP_BASEDIR=$AUTOBENCH_BACKUPDIR/dbt2w10

  #Does test support multi-user mode.
  TEST_MULTIUSER_MODE=1

  # Test options
  THREADS="16 40 80"
  ITERATIONS="1"
  DURATION=900

  # DBT2 options
  # ScaleFactor(number of warehouses)
  DBT2_SF=10
  DBT2_ZERO_DELAY=1
  DBT2_THREAD_DELAY=100
  DBT2_VERBOSE=1  
  DBT2_DATASET_DIR=$AUTOBENCH_TMPDIR/dbt2w10

  #InnoDB MONITOR
  IMONITOR="1"

  #SERVER DB
  SERVER_DB="dbt2w10"
  TEST_WARMUP_DURATION=300

  TEST_STAGE_PREPARE_GENERATE=""  # GENERATE INITIAL DATASET AND LOAD IT
  TEST_STAGE_PREPARE_RESTORE="1"  # RESTORE DATADIR FROM BACKUP
  TEST_STAGE_RUN="1"              # RUN || "" - RUN STAGE WILL BE SKIPPED
  TEST_STAGE_CLEANUP="1"          #

  TEST_STAGE_PREPARE_GENERATE_EXE="$TEST_BASEDIR/load.sh"
  TEST_STAGE_RUN_EXE="$TEST_BASEDIR/run_mysql.sh"
  TEST_STAGE_CLEANUP_EXE="$AUTOBENCH_LIBDIR/dbt2-cleanup.sh"


  TEST_ARGS_STAGE_PREPARE=' -d $SERVER_DB \
                            -f $DBT2_DATASET_DIR \
                            -s $SERVER_SOCKET \
                            -u $SERVER_USER'

  TEST_ARGS_STAGE_RUN=' -n $SERVER_DB \
                        -w $DBT2_SF \
                        -t $DURATION \
                        -o $SERVER_SOCKET \
                        -u $SERVER_USER \
                        -s $DBT2_THREAD_DELAY \
                        -e -v'

#  TEST_ARGS_STAGE_RUN=' -n $SERVER_DB \
#                        -w $DBT2_SF \
#                        -t $DURATION \
#                        -h $SERVER_HOST \
#                        -l $SERVER_PORT \
#                        -u $SERVER_USER \
#                        -s $DBT2_THREAD_DELAY \
#                        -e -v'


  TEST_ARGS_STAGE_WARMUP=' -n $SERVER_DB \
                        -w $DBT2_SF \
                        -t $TEST_WARMUP_DURATION \
                        -o $SERVER_SOCKET \
                        -u $SERVER_USER \
                        -s $DBT2_THREAD_DELAY \
                        -e -v'


  TEST_ARGS_STAGE_CLEANUP=' $TEST_BASEDIR $TEST_OUTDIR'

  # Variable part of command line that will be used for substitution
  # of loop variables and will be joined with $TEST_ARGS_COMMON

  TEST_ARGS_TEMPLATE='"-c $TEST_THREAD -z \"$MYSQLD_BASEDIR-$ENGINE_NAME-c$TEST_THREAD-$TEST_ITER\""'
}

dbt2.test_pre_run()
{
  #SANITY CHECKS
  ENGINE_NAME=`echo $ENGINE_NAME | tr a-z A-Z`

  if [[ -n $TEST_STAGE_PREPARE_GENERATE ]]; then 
    if [[ -z $DBT2_DATASET_DIR || ! -d $DBT2_DATASET_DIR ]]; then 
      usage "Dir: DBT2_DATASET_DIR $DBT2_DATASET_DIR doesn't exist. Define location of dataset in scenario file with DBT2_DATASET_DIR var"
    fi
  elif [[ -n $TEST_STAGE_PREPARE_RESTORE ]]; then 
    if [[ -z $TEST_BACKUP_BASEDIR || ! -d $TEST_BACKUP_BASEDIR ]]; then 
      usage "Dir: TEST_BACKUP_BASEDIR $TEST_BACKUP_BASEDIR doesnt exist"
    fi
  fi

  TEST_ARGS_STAGE_PREPARE="$TEST_ARGS_STAGE_PREPARE -e $ENGINE_NAME"
  
  killall client > /dev/null 2>&1
  killall driver > /dev/null 2>&1
}


dbt2.help()
{
  cat << DATAEOF

  # dbt2 specific options
  DBT2_SF=10                                     # ScaleFactor(number of warehouses)
  DBT2_DATASET_DIR=$AUTOBENCH_TMPDIR/dbt2w10     # Location of generated data files with dbgen

  # test options
  THREADS="16 40 80"                             # List of number of threads
  ITERATIONS="1 2 3"                             # List of number of iterations
  DURATION=900                                   # Test duration

DATAEOF
}

dbt2.test_stage_run_pre()
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

dbt2.test_stage_run_post()
{
  if [ -n "$IMONITOR" -a  -n "$MONITOR_PID" ]; then 
    echo -n "IMONITOR PID $MONITOR_PID in FILE:  "
    cat $TEST_OUTDIR/innodb-monitor.pid
    kill -15 $MONITOR_PID
    MONITOR_PID=""
  fi
}
