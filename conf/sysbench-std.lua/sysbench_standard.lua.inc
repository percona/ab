########################################################################
#
#   Autobench test configuration file for sysbench standard test
#
########################################################################

sysbench_standard.test_setup()
{
  #profiler information
  USE_OPROFILE=0
  #VMLINUX=/tmp/vmlinux-2.6.16.46-0.12-smp
  
  #System statistic information: sar/vmstat/iostat
  COLLECT_STAT=1
  TEST_STAT_SAMPLE=10 # Get sample each 10 seconds

  #Stack size
  STACKSIZE=256

  #Test name
  TEST_NAME="sysbench_standard"

  #If test have subtests specify them here
  TEST_CASES="OLTP_RW \
  SELECT_DISTINCT_RANGES \
  SELECT_ORDER_RANGES \
  SELECT_SUM_RANGES \
  SELECT_SIMPLE_RANGES \
  POINT_SELECT \
  OLTP_RO \
  UPDATE_KEY \
  UPDATE_NO_KEY"

  POINT_SELECT=" \
  --oltp-point-selects=1 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=on \
  --oltp-read-only=on"

  SELECT_SIMPLE_RANGES=" \
  --oltp-point-selects=0 --oltp-simple-ranges=1 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=on \
  --oltp-read-only=on"

  SELECT_SUM_RANGES=" \
  --oltp-point-selects=0 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=1 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=on \
  --oltp-read-only=on"

  SELECT_ORDER_RANGES=" \
  --oltp-point-selects=0 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=1 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=on \
  --oltp-read-only=on"

  SELECT_DISTINCT_RANGES=" \
  --oltp-point-selects=0 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=1 --oltp-skip-trx=on \
  --oltp-read-only=on"

  POINT_SELECT_TRX=" \
  --oltp-point-selects=1 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=off \
  --oltp-read-only=on"

  SELECT_SIMPLE_RANGES_TRX=" \
  --oltp-point-selects=0 --oltp-simple-ranges=1 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=off \
  --oltp-read-only=on"

  SELECT_DISTINCT_RANGES_TRX=" \
  --oltp-point-selects=0 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=1 --oltp-skip-trx=off \
  --oltp-read-only=on"


  SELECT_ORDER_RANGES_TRX=" \
  --oltp-point-selects=0 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=1 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=off \
  --oltp-read-only=on"

  SELECT_SUM_RANGES_TRX=" \
  --oltp-point-selects=0 --oltp-simple-ranges=0 \
  --oltp-sum-ranges=1 --oltp-order-ranges=0 \
  --oltp-distinct-ranges=0 --oltp-skip-trx=off \
  --oltp-read-only=on"


  OLTP_RW=" \
  --oltp-read-only=off  "

  OLTP_RO=" \
  --oltp-read-only=on "

  OLTP_RO_SKIP_TRX=" \
  --oltp-read-only=on --oltp-skip-trx=on "

  OLTP_RO_NO_PS="--oltp-read-only=on --oltp-test-mode=complex --oltp-simple-ranges=1 \
  --oltp-sum-ranges=1 --oltp-order-ranges=1 --oltp-distinct-ranges=1 \
  --oltp-point-selects=0 "

  OLTP_RO_NO_PS2="--oltp-read-only=on --oltp-test-mode=complex --oltp-simple-ranges=1 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 --oltp-distinct-ranges=0 \
  --oltp-point-selects=10 "


  OLTP_RW_NO_PS="--oltp-read-only=off --oltp-test-mode=complex --oltp-simple-ranges=1 \
  --oltp-sum-ranges=1 --oltp-order-ranges=1 --oltp-distinct-ranges=1 \
  --oltp-point-selects=0 --oltp-index-updates=1 --oltp-non-index-updates=1 "


  OLTP_RW_N_PS_SIR_SUR_OR_DR="--oltp-read-only=off --oltp-test-mode=complex --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 --oltp-distinct-ranges=0 \
  --oltp-point-selects=0 --oltp-index-updates=1 --oltp-non-index-updates=1 "

  OLTP_RW_N_PS_SIR_SUR_OR="--oltp-read-only=off --oltp-test-mode=complex --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=0 --oltp-distinct-ranges=1 \
  --oltp-point-selects=0 --oltp-index-updates=1 --oltp-non-index-updates=1 "

  OLTP_RW_N_PS_SIR_SUR="--oltp-read-only=off --oltp-test-mode=complex --oltp-simple-ranges=0 \
  --oltp-sum-ranges=0 --oltp-order-ranges=1 --oltp-distinct-ranges=1 \
  --oltp-point-selects=0 --oltp-index-updates=1 --oltp-non-index-updates=1 "

  OLTP_RW_N_PS_SIR="--oltp-read-only=off --oltp-test-mode=complex --oltp-simple-ranges=0 \
  --oltp-sum-ranges=1 --oltp-order-ranges=1 --oltp-distinct-ranges=1 \
  --oltp-point-selects=0 --oltp-index-updates=1 --oltp-non-index-updates=1 "



  UPDATE_KEY=" \
  --oltp-test-mode=nontrx \
  --oltp-nontrx-mode=update_key"

  UPDATE_NO_KEY=" \
  --oltp-test-mode=nontrx \
  --oltp-nontrx-mode=update_nokey"

  #Test basedir
  TEST_BASEDIR=$AUTOBENCH_TESTBASEDIR/sysbench-standard

  #Basedir for backup datafiles
  TEST_BACKUP_BASEDIR="$AUTOBENCH_BACKUPDIR/sysbench-standard"

  #Test DB options                                                                                                                                                                                                                            
  SERVER_DB="sbtest"
  SERVER_USER="root"
  SERVER_SOCKET="/tmp/mysql.sock"
#  SERVER_HOST="127.0.0.1"
#  SERVER_HOST="localhost"
#  SERVER_PORT="3306"

  #Does test support multi-user mode.
  TEST_MULTIUSER_MODE=1

  #Test options
  THREADS="4 16 64 128 256"
  ITERATIONS="1"
  DURATION=300

  #Sysbench specific options
  #ScaleFactor(number of warehouses)
  SYSBENCH_MRR=0
  SYSBENCH_TRX=1
  SYSBENCH_COND_PUSHDOW=0

  SYSBENCH_NUM_ROWS=1000000
  SYSBENCH_NUM_TABLES=1

  SB_NUM_ROWS_PREPARE=$SYSBENCH_NUM_ROWS
  SB_DIST="uniform"
  SB_AINC="on"
  SB_DIST_PREPARE="uniform"

  TEST_STAGE_PREPARE_GENERATE="1"  # GENERATE INITIAL DATASET AND LOAD IT
  TEST_STAGE_PREPARE_RESTORE=""  # RESTORE DATADIR FROM BACKUP
  TEST_STAGE_RUN="1"              # RUN || "" - RUN STAGE WILL BE SKIPPED
  TEST_STAGE_CLEANUP="1"          #

  TEST_STAGE_PREPARE_GENERATE_EXE="$AUTOBENCH_LIBDIR/sysbench-load-db.sh"
  TEST_STAGE_RUN_EXE=$SYSBENCH_0_5_EXE
  TEST_STAGE_CLEANUP_EXE="/bin/true"

  # BACKGROUND TASK 
  #TEST_BG_TASK="backup of sysbench database"
  #TEST_BG_TASK_DELAY=30
  #TEST_BG_TASK_RUN_EXE="$AUTOBENCH_LIBDIR/backup.sh"

  TEST_ARGS_STAGE_CLEANUP=""

  IMONITOR=""
  IMONITOR_INTERVAL="30"

  # Variable part of command line that will be used for substitution
  # of loop variables and will be joined with $TEST_ARGS_COMMON

  TEST_ARGS_TEMPLATE='"--num-threads=$TEST_THREAD "'

  ENGINE_DEFAULTS_FILE_MYISAM=$TEST_CNF_DIR/sysbench-std-myisam.cnf
  ENGINE_DEFAULTS_FILE_INNODB=$TEST_CNF_DIR/sysbench-std-innodb.cnf
 
}

sysbench_standard.test_pre_run()
{
  #SANITY CHECKS
  ENGINE_NAME=$(echo $ENGINE_NAME | tr a-z A-Z)

#  --mysql-host=$SERVER_HOST \
#  --mysql-port=$SERVER_PORT \


  if [ -f "$AUTOBENCH_LIBDIR/kernel_type.sh" -a -z "$KERNEL_TYPE" ]; then
    KERNEL_TYPE=`$AUTOBENCH_LIBDIR/kernel_type.sh`
    COMMENT="${COMMENT}.${KERNEL_TYPE}"
  fi


  SB_ARGS='--test=$TEST_BASEDIR/db/oltp.lua  \
  --oltp_tables_count=$SYSBENCH_NUM_TABLES \
  --oltp-table-size=$SYSBENCH_NUM_ROWS \
  --rand-init=on \
  --report-interval=1 \
  --rand-type=uniform \
  --forced-shutdown=1 \
  --max-time=$DURATION \
  --max-requests=0 \
  --percentile=99 \
  --mysql-socket=$SERVER_SOCKET \
  --mysql-user=$SERVER_USER \
  --mysql-db=$SERVER_DB \
  --mysql-table-engine=$ENGINE_NAME'

#  --myisam-max-rows=$SYSBENCH_NUM_ROWS \
#  --db-ps-mode=disable \

  if [ -z "$SB_NUM_ROWS_PREPARE" ]; then 
    SB_NUM_ROWS_PREPARE=$SYSBENCH_NUM_ROWS
  fi


  TEST_ARGS_STAGE_PREPARE='--db-name=$SERVER_DB --mysql-bin=$MYSQL \
                           --mysql-args=\"$MYSQL_ARGS\" \
                           --sysbench-bin=$TEST_STAGE_RUN_EXE \
                           --sysbench-args=\"'$SB_ARGS' \
			   --oltp-table-size=$SB_NUM_ROWS_PREPARE  prepare\"'

  TEST_ARGS_STAGE_WARMUP=$SB_ARGS' --max-time=60 ${!TEST_CASE} run'

  TEST_ARGS_STAGE_RUN=$SB_ARGS'  ${!TEST_CASE} run'

}


sysbench_standard.help()
{
  cat << DATAEOF

  # sysbench specific options
  TEST_CASES=<OLTP_RW,SELECT_DISTINCT_RANGES,SELECT_ORDER_RANGES,SELECT_SUM_RANGES,
              SELECT_SIMPLE_RANGES,POINT_SELECT,OLTP_RO,UPDATE_KEY,UPDATE_NO_KEY>

  SYSBENCH_NUM_ROWS=1000000            # number of rows. It's important to set correct number of rows

  #Test options
  THREADS="4 16 64 128 256"
  ITERATIONS="1"
  DURATION=300

DATAEOF
}

sysbench_standard.test_stage_run_pre_old()
{

#echo "ENGINE_NAME: $ENGINE_NAME IMONITOR: $IMONITOR"

if [ "$ENGINE_NAME" == "INNODB" ]; then 
if [ -n "$IMONITOR" ]; then 
(
trap 'echo "Got TERM signal."; \
      exit ' TERM

trap 'echo "Got INT signal."; \
      exit ' INT

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
sleep $IMONITOR_INTERVAL
done

)&

MONITOR_PID=$!
fi
fi


}

sysbench_standard.waitm()
{
  while [ true ];  do
  mysql $MYSQL_ARGS -e "set global innodb_max_dirty_pages_pct=0" sbtest
  wt=`mysql $MYSQL_ARGS -e "SHOW ENGINE INNODB STATUS\G" | grep "Modified db pages" | sort -u | awk '{print $4}'`
  if [[ "$wt" -lt 100 ]] ;
  then
    mysql $MYSQL_ARGS -e "set global innodb_max_dirty_pages_pct=90" sbtest
    break
  fi
  echo "mysql pages $wt" >> $TEST_OUTDIR/waitm.out
done

}

sysbench_standard.test_stage_run_post_old()
{
if [ $ENGINE_NAME == "INNODB" ]; then
if [ -n "$IMONITOR" ]; then

  if [ -n "$MONITOR_PID" ]; then
    kill -15 $MONITOR_PID
    MONITOR_PID=""
  fi
fi
fi

#sysbench_standard.waitm

}

sysbench_standard.test_stage_server_start_post()
{
  $MYSQL $MYSQL_ARGS -e'create user stat@localhost IDENTIFIED BY "statpass"'
  $MYSQL $MYSQL_ARGS -e'grant ALL ON *.* to stat@localhost'
  STAT_OFF=1
}

sysbench_standard.test_stage_run_pre()
{
#  engine_stat.setup
  engine_stat.pse_start

  if [ -n "$PERF" ]; then

    get_mysqld_pid

    if [ -n "$KERNEL_TYPE" -a "$KERNEL_TYPE" == "rhel" ]; then
      PERF_BIN="/usr/bin/perf"
    else
      PERF_BIN="/usr/sbin/perf"
      PERF_BIN="/usr/libexec/perf.2.6.39-100.0.15.el6uek.x86_64"
    fi

    show_msg "KERNEL_PERF: Starting perf($PERF_BIN) for PID: $MYSQLD_PID to perf.data.$TEST_OUTDIR_NAME"

    echo "$PERF_BIN record -g -o $TEST_OUTDIR/perf.data.${TEST_OUTDIR_NAME} --pid $MYSQLD_PID" >> $TEST_OUTDIR/perf.out
    echo "TEST_OUTDIR - $TEST_OUTDIR"
    $PERF_BIN record -g -o $TEST_OUTDIR/perf.data.${TEST_OUTDIR_NAME} --pid $MYSQLD_PID >> $TEST_OUTDIR/perf.out 2>&1 &
  fi

}

sysbench_standard.test_stage_run_post()
{
   echo "STAT_STOP"
#  engine_stat.stop
  engine_stat.pse_stop

  if [ -n "$PERF" ]; then 
    echo "KERNEL_PERF: Done  ${TEST_OUTDIR}/perf.data.${TEST_OUTDIR_NAME}"
    sudo killall -INT $PERF_BIN
    sleep 2
    $PERF_BIN report --stdio -i ${TEST_OUTDIR}/perf.data.${TEST_OUTDIR_NAME} > ${TEST_OUTDIR}/perf.stdio.${TEST_OUTDIR_NAME}
    bzip2 ${TEST_OUTDIR}/perf.data.${TEST_OUTDIR_NAME}
  fi

  if [ "$ENGINE_NAME" == "TOKUDB" ]; then 
    $MYSQL $MYSQL_ARGS -e'show engine tokudb status' >> $TEST_OUTDIR/tokudb.status
  fi

}

