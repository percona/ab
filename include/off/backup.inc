########################################################################
#
#   Autobench test configuration file for backup test
#
########################################################################


backup.test_setup()
{
  #profile information
  USE_OPROFILE=0
  VMLINUX=/tmp/vmlinux-2.6.16.46-0.12-smp

  #System statistic information: sar/vmstat/iostat
  COLLECT_STAT=1
  TEST_STAT_SAMPLE=10 # Get sample each 10 seconds

  # Number of open files
  ulimit -n 90000

  #Stack size
  STACKSIZE=256

  #Test name
  TEST_NAME="backup"

  #If test have subtests specify them here
  #TEST_CASES="BACKUP RESTORE DUMP RESTORE_DUMP"
  TEST_CASE="BACKUP"

  #Test basedir
  TEST_BASEDIR=$AUTOBENCH_TESTBASEDIR/backup

  #Basedir for backup datafiles
  TEST_BACKUP_BASEDIR=""

  #Test DB options                                                                                                                                                                                                                            
  SERVER_DB="test"
  SERVER_USER="root"
  SERVER_SOCKET="/tmp/mysql.sock"
  SERVER_HOST="127.0.0.1"
  SERVER_PORT="3306"

  #Test options
  THREADS=1
  ITERATIONS=1
  DURATION=0

  TEST_BG_TASK=""
  TEST_BG_TASK_DELAY=""
  TEST_BG_TASK_RUN_EXE=""

  #########################
  # Test specific variables
  #########################
  DUMP_FILENAME="backup_file"

  TEST_STAGE_PREPARE_GENERATE="1"  # GENERATE INITIAL DATASET AND LOAD IT
  TEST_STAGE_PREPARE_RESTORE=""  # RESTORE DATADIR FROM BACKUP
  TEST_STAGE_RUN="1"              # RUN || "" - RUN STAGE WILL BE SKIPPED
  TEST_STAGE_CLEANUP="1"          #

  TEST_STAGE_PREPARE_GENERATE_EXE=""
  TEST_STAGE_RUN_EXE="$AUTOBENCH_LIBDIR/backup.sh"
  TEST_STAGE_CLEANUP_EXE="/bin/true"

  TEST_ARGS_STAGE_CLEANUP=""

  # Variable part of command line that will be used for substitution
  # of loop variables and will be joined with $TEST_ARGS_COMMON
  # TEST_THREAD TEST_ITER TEST_CASE?
  #
  # EXAMPLE: TEST_ARGS_TEMPLATE='"--num-threads=$TEST_THREAD "'

  TEST_ARGS_TEMPLATE=""
}


backup.test_pre_run()
{
  #SANITY CHECKS
  ENGINE_NAME=`echo $ENGINE_NAME | tr a-z A-Z`
}

backup.test_stage_prepare_pre()
{
 if [[ ($TEST_CASE = RESTORE_DUMP || $TEST_CASE = RESTORE || $TEST_CASE = RESTORE_OVERWRITE) && -z $TEST_MODE ]] ; then
    TEST_STAGE_PREPARE_INSTALL=1
    TEST_STAGE_PREPARE_GENERATE=""
    TEST_STAGE_PREPARE_RESTORE=""
  fi
}

backup.test_stage_run_pre_init()
{
  local DUMP_MODE=$1

  #MODES: BACKUP | DUMP | RESTORE | RESTORE_OVERWTITE | RESTORE_DUMP
  #[[ -z $DUMP_MODE ]] && DUMP_MODE=BACKUP

  # Dir where temporary backup files will be stored
  [[ -z $DUMP_DIR ]] && DUMP_DIR=$AUTOBENCH_TMPDIR

  # Filename for the backup/dump file. It will be suffixed with 
  # .dmp for dump and .bk for backup 
  [[ -z $DUMP_FILENAME ]] && DUMP_FILENAME="backup_file"

  #Arguments for mysqldump
  [[ -z $MYSQLDUMP_ARGS ]] && MYSQLDUMP_ARGS=" -x -R -E --triggers"
  #[[ -z $MYSQLDUMP_ARGS ]] && MYSQLDUMP_ARGS=" -R -E --triggers --single-transaction"

  #KEEP_DUMP_FILE=""
  #DUMP_FILE=""

  if [[ -n $DUMP_MODE ]]; then 

    if [[ -z $DUMP_DIR ]]; then 
      if [[ $DUMP_MODE = BACKUP || $DUMP_MODE = DUMP ]]; then 
        DUMP_DIR=$AUTOBENCH_TMPDIR
      else
        DUMP_DIR=$TEST_BACKUP_BASEDIR
      fi
    fi

    if [[ $DUMP_MODE = BACKUP ]]; then 
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.bk-"$(date +%s)
      DUMP_ARGS='--dump-mode=backup'
	       
   elif [[ $DUMP_MODE = IBACKUP ]]; then
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dmp-"$(date +%s)
      DUMP_ARGS="--dump-mode=ibackup --ibackup-bin=$IBACKUP_BIN --ibackup-helper=$IBACKUP_HELPER --ibackup-args=$IBACKUP_ARGS --backup-dir=$IBACKUP_DIR"

   elif [[ $DUMP_MODE = IBACKUP_INC ]]; then
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dmp-"$(date +%s)
      DUMP_ARGS="--dump-mode=ibackup-inc --ibackup-bin=$IBACKUP_BIN --ibackup-helper=$IBACKUP_HELPER --ibackup-args=\'$IBACKUP_ARGS\' --ibackup-inc-args=\'$IBACKUP_INC_ARGS\' --backup-dir=$IBACKUP_DIR"

   elif [[ $DUMP_MODE = IBACKUP_INC_ONLY ]]; then
      #FIXME: CHECK THAT LSN WAS PROVIDED FOR INCREMENTAL BACKUP ONLY!!!!!
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dmp-"$(date +%s)
      DUMP_ARGS="--dump-mode=ibackup-inc-only --ibackup-bin=$IBACKUP_BIN --ibackup-helper=$IBACKUP_HELPER --ibackup-args=\'$IBACKUP_ARGS\' --ibackup-inc-args=\'$IBACKUP_INC_ARGS\' --backup-dir=$IBACKUP_DIR"



    elif [[ $DUMP_MODE = XBACKUP ]]; then
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dmp-"$(date +%s)
      DUMP_ARGS="--dump-mode=xbackup --ibackup-bin=$XIBACKUP_BIN --ibackup-helper=$XIBACKUP_HELPER --backup-dir=$IBACKUP_DIR"

    elif [[ $DUMP_MODE = COPY ]]; then
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dmp-"$(date +%s)
      DUMP_ARGS="--dump-mode=copy --data-dir=$AUTOBENCH_DATADIR --backup-dir=$IBACKUP_DIR"

    elif [[ $DUMP_MODE = DUMP ]]; then 
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dmp-"$(date +%s)
      DUMP_ARGS='--dump-mode=dump'
	       
    elif [[ $DUMP_MODE = RESTORE ]]; then 
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.bk"
      DUMP_ARGS='--dump-mode=restore'
	       
    elif [[ $DUMP_MODE = RESTORE_OVERWRITE ]]; then 
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.bk"
      DUMP_ARGS='--dump-mode=restore_overwrite'
	       
    elif [[ $DUMP_MODE = RESTORE_DUMP ]]; then 
      [[ -z $DUMP_FILE ]] && DUMP_FILE="$DUMP_DIR/${DUMP_FILENAME}.$ENGINE_NAME.dump"
      DUMP_ARGS='--dump-mode=restore_dump'
    fi

    [[ -n $DUMP_FILE ]] && DUMP_ARGS="$DUMP_ARGS --dump-file=$DUMP_FILE"
  else
    #FIXME: exit or disable backup
    show_msg_date "ERROR: You need to define DUMP_MODE variable to perform backup"
  fi

  DUMP_COMMON_ARGS='--db=$SERVER_DB \
                    --mysql-bin=$MYSQL  --mysql-args=\"$MYSQL_ARGS\" \
                    --mysqldump-bin=$MYSQLDUMP --mysqldump-args=\"$MYSQLDUMP_ARGS\"'
}

backup.test_stage_run_pre()
{
  backup.test_stage_run_pre_init $TEST_CASE

  TEST_ARGS_STAGE_RUN="$DUMP_COMMON_ARGS $DUMP_ARGS"
}

backup.bg_task.test_stage_run_pre()
{
  backup.test_stage_run_pre_init $DUMP_MODE

  TEST_ARGS_BG_TASK="$DUMP_COMMON_ARGS $DUMP_ARGS"
  
  echo "OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO -oooooooooooooo!"
}

backup.test_stage_cleanup_post_init()
{
  local MODE=$1
  if [[ -n $DUMP_FILE && -f $DUMP_FILE && -n $MODE &&
        ( $MODE = BACKUP || $MODE = DUMP ) ]]; then
        if [[ -z $KEEP_DUMP_FILE ]]; then
          show_msg_date "Remove dump file: $DUMP_FILE"
          rm -f $DUMP_FILE
        else
          show_msg_date "Saved dump file: $DUMP_FILE"
        fi
        DUMP_FILE=""
  fi
}

backup.test_stage_cleanup_post()
{
 backup.test_stage_cleanup_post_init $TEST_CASE
}


backup.test_stage_cleanup_post()
{
  backup.test_stage_cleanup_post_init $TEST_CASE
}


backup.bg_task.test_stage_cleanup_post()
{
  if [[ -n $TEST_BG_TASK ]]; then 
    backup.test_stage_cleanup_post_init $DUMP_MODE
  fi
}

backup.test_post_run()
{
  DUMP_FILE=""
}


backup.help()
{
  cat << DATAEOF

  # backup specific options
  TEST_CASES=<BACKUP,DUMP,RESTORE,RESTORE_OVERWTITE,RESTORE_DUMP>

  # Dir where temporary backup files will be stored
  DUMP_DIR=<dir>  (Defaults: AUTOBENCH_TMPDIR)

  # Filename for the backup/dump file. It will be suffixed with
  # .dmp for dump and .bk for backup
  DUMP_FILENAME=<dump filename> (Defaults: backup_file)

  #Name of file (with path) of the backup file 
  DUMP_FILE=""                  (Defaults: DUMP_DIR/DUMP_FILENAME_<timestamp>)

  #Arguments for mysqldump
  MYSQLDUMP_ARGS=<mysqldump options> (Defaults: " -x -R -E --triggers")

  #Control remove or not dump file
  KEEP_DUMP_FILE=""             (Defaults: "")

DATAEOF
}

