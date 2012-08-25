#!/bin/bash
########################################################################
#
# Autobench test configuration file for mysql-bench test
#
########################################################################

mysql_bench.test_setup()
{
  #profile information
  USE_OPROFILE=0
  VMLINUX=/tmp/vmlinux-2.6.18.2-34-default
  
  #System statistic information: sar/vmstat/iostat
  COLLECT_STAT=0
  TEST_STAT_SAMPLE=10 # Get sample each 10 seconds

  #Stack size
  STACKSIZE=256

  #Test name
  TEST_NAME="mysql-bench"

  #Test basedir
  TEST_BASEDIR=$AUTOBENCH_TESTBASEDIR/mysql-bench/mysql-bench

  #Does test support multi-user mode.
  TEST_MULTIUSER_MODE=0

  #Test options
  THREADS="1"
  ITERATIONS="1"
  DURATION=0

  TEST_STAGE_PREPARE_GENERATE=""  # GENERATE INITIAL DATASET AND LOAD IT
  TEST_STAGE_PREPARE_RESTORE=""   # RESTORE DATADIR FROM BACKUP
  TEST_STAGE_RUN=1                # RUN || "" - RUN STAGE WILL BE SKIPPED
  TEST_STAGE_CLEANUP=""           #
  TEST_STAGE_PREPARE_INSTALL="1"

  TEST_STAGE_PREPARE_GENERATE_EXE=""
  TEST_STAGE_RUN_EXE="./run-all-tests"
  TEST_STAGE_CLEANUP_EXE=""

  TEST_ARGS_STAGE_PREPARE=""
  TEST_ARGS_STAGE_RUN=""
  TEST_ARGS_STAGE_CLEANUP=""

  #dl360-g5-c
  FS="ext3"
  HW="8 Cores, Xeon(E5345), 2.3Ghz, 16GB RAM"

  # Variable part of command line that will be used for substitution 
  # of loop/runtime variables and will be joined with $TEST_ARGS_COMMON
  TEST_ARGS_TEMPLATE='"--dir=$TEST_OUTDIR --suffix=_${MYSQLD_VERSION}_${ENGINE_NAME}_${MYSQLD_ARCH}  "'
}

mysql_bench.test_stage_run_pre()
{
  #Adjust mysql-bench arguments
  TEST_ARGS_COMMON='--user=$SERVER_USER --socket=$SERVER_SOCKET \
                    --log --create-options=ENGINE=$ENGINE_NAME --fs=$FS --hw=\"$HW\"'
                    
}

mysql_bench.help()
{
  cat << DATAEOF

  # mysql-bench specific options
  FS=<filesystem name>                           # ext3|xfs|etc
  HW=<hw spec of test box>                       # "8 Cores, Xeon(E5345), 2.3Ghz, 16GB RAM"

DATAEOF
}
