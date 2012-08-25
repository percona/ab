########################################################################
#
#   Autobench test configuration file for sysbench atomic test
#
########################################################################

sysbench_atomic.test_setup()
{
  #profiler information
  USE_OPROFILE=0
  VMLINUX=/tmp/vmlinux-2.6.16.46-0.12-smp
  
  #System statistic information: sar/vmstat/iostat
  COLLECT_STAT=1
  TEST_STAT_SAMPLE=10 # Get sample each 10 seconds

  #Stack size
  STACKSIZE=256

  #Test name
  TEST_NAME="sysbench_atomic"

  #If test have subtests specify them here
  TEST_CASES="READ_KEY_POINT \
  READ_KEY_POINT_NO_DATA \
  READ_KEY_POINT \
  READ_KEY_POINT_NO_DATA \
  READ_KEY_POINT_LIMIT \
  READ_KEY_POINT_NO_DATA_LIMIT \
  READ_PK_POINT \
  READ_PK_POINT_INDEX \
  READ_PK_RANGE \
  READ_PK_RANGE_INDEX \
  READ_KEY_RANGE \
  READ_KEY_RANGE_LIMIT \
  READ_KEY_RANGE_NO_DATA \
  READ_KEY_RANGE_NO_DATA_LIMIT \
  READ_FTS"

  #Test basedir
  TEST_BASEDIR=$AUTOBENCH_TESTBASEDIR/sysbench-atomic

  # Basedir for backup datafiles
  TEST_BACKUP_BASEDIR="$AUTOBENCH_BACKUPDIR/sysbench-atomic"

  #Test DB options                                                                                                                                                                                                                            
  SERVER_DB="phptest"
  SERVER_USER="root"
  SERVER_SOCKET="/tmp/mysql.sock"
  SERVER_HOST="127.0.0.1"
  SERVER_PORT="3306"

  #Does test support multi-user mode.
  TEST_MULTIUSER_MODE=1

  #Test options
  THREADS="4 16 64 128 256"
  ITERATIONS="1"
  DURATION=300

  #Sysbench specific options
  SYSBENCH_MRR=0
  SYSBENCH_TRX=1
  SYSBENCH_COND_PUSHDOW=0

  SYSBENCH_NUM_ROWS=1000000

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

  SB_ARGS='--test=$TEST_BASEDIR/phptest.lua \
  --oltp-table-size=$SYSBENCH_NUM_ROWS \
  --rand-type=uniform \
  --oltp-table-name=phptest \
  --rand-init=off \
  --max-requests=0 \
  --max-time=$DURATION \
  --mysql-host=$SERVER_HOST \
  --mysql-user=$SERVER_USER \
  --mysql-port=$SERVER_PORT \
  --mysql-db=$SERVER_DB \
  --myisam-max-rows=$SYSBENCH_NUM_ROWS \
  --mysql-table-engine=$ENGINE_NAME'


  TEST_ARGS_STAGE_PREPARE='--db-name=$SERVER_DB --mysql-bin=$MYSQL \
                           --mysql-args=\"$MYSQL_ARGS\" \
                           --sysbench-bin=$TEST_STAGE_RUN_EXE \
                           --sysbench-args=\"'$SB_ARGS' prepare\"'

  TEST_ARGS_STAGE_RUN=$SB_ARGS' --subtest=$TEST_CASE run'

  TEST_ARGS_STAGE_CLEANUP=""

  # Variable part of command line that will be used for substitution
  # of loop variables and will be joined with $TEST_ARGS_COMMON

  TEST_ARGS_TEMPLATE='"--num-threads=$TEST_THREAD "'

  ENGINE_DEFAULTS_FILE_MYISAM=$TEST_CNF_DIR/sysbench-atomic-myisam.cnf
  ENGINE_DEFAULTS_FILE_INNODB=$TEST_CNF_DIR/sysbench-atomic-innodb.cnf

}

test_pre_run()
{
  #SANITY CHECKS
  ENGINE_NAME=$(echo $ENGINE_NAME | tr a-z A-Z)
}


sysbench_atomic.help()
{
  cat << DATAEOF

  # sysbench specific options
  TEST_CASES=<READ_KEY_POINT, READ_KEY_POINT_NO_DATA, READ_KEY_POINT, 
              READ_KEY_POINT_NO_DATA, READ_KEY_POINT_LIMIT, READ_KEY_POINT_NO_DATA_LIMIT, 
              READ_PK_POINT, READ_PK_POINT_INDEX, READ_PK_RANGE, READ_PK_RANGE_INDEX, 
              READ_KEY_RANGE, READ_KEY_RANGE_LIMIT, READ_KEY_RANGE_NO_DATA, 
              READ_KEY_RANGE_NO_DATA_LIMIT, READ_FTS>

  SYSBENCH_NUM_ROWS=1000000            # number of rows. It's important to set correct number of rows
  SYSBENCH_MRR=0                       # enable/disable MRR
  SYSBENCH_TRX=1                       # enable/disable transaction mode
  SYSBENCH_COND_PUSHDOW=0              # enable/disable condition pushdown 

  #Test options
  THREADS="4 16 64 128 256"
  ITERATIONS="1"
  DURATION=300

DATAEOF
}

