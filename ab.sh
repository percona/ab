#!/bin/bash
trap 'echo "Test was interrupted by Control-C at line $LINENO."; \
      collect_stat_stop ; run_hook test_stage_run_post ; killall cp;  exit' INT

trap 'echo "Test was interrupted. Got TERM signal."; \
      collect_stat_stop ; run_hook test_stage_run_post ; killall cp; exit ' TERM

trap 'log_mgs "Force to stop/kill server with -11. Possible deadlock?" \
              TEST_OUTDIR/server_stop.out; server_stop 11' ALRM
trap 


AUTOBENCH_CONFIG=""
EXIT_ON_ERROR=0
VERBOSE=""
FORCE=0
START_AND_EXIT=0
START_DIRTY=0
USE_RUNNING_SERVER=0

SED=$(which sed)
ECHO=echo

set -o pipefail

#FIXME: Check for correctness of hostname
HOSTNAME=$(hostname)

#Add command line 
echo "$0 $@" >> .autobench_history

usage() {

  if [ "$1" != "" ]; then
    echo ''
    echo "ERROR: $1"
  fi

cat << DEOF

 autobench: tool for automation of process of running various benchmarks

 Usage: ab.sh --test=<test_configuration_file> --servers=<server basedir>  [options]

Options to control autobench framework environment:

   --autobench-basedir=<basedir of framework installation>
   --autobench-datadir=<datadir>
   --autobench-serverdir=<dir to look for server basedirs>
   --autobench-testbasedir=<dir to look for test suites>
   --autobench-resultdir=<basedir for results>
   --autobench-backupdir=<basedir for backup of datadirs that will be used in test>
   --env=<file>  conf file for variables that may vary on different hosts

Options to control test scenario aspects:

   --test=<test_configuration_file[:option][:option][...]>
 
      test_configuration_file:
          autobench scenario file. See conf/ dir for scenario files.
      option:
          variable=value[,value][,...]]

      option - regular variable that allows to override settings specified 
               in the test scenario file

     Example: --test=conf/sysbench-std/ab_sb_std.cnf:duration=10:threads=1,2,3

   --engine=engine_name[.engine_ext][,engine_option][...]

     engine_name   - name of one of the MySQL engines <MyISAM,InnoDB,Falcon,etc>
     engine_ext    - optional string that accentuate engine specifics (see below)
     engine_option - mysqld option that passes to server as is

     Example:
       --engine=falcon,defaults-file=sysbench-falcon.cnf
       --engine=falcon.32k,defaults-file=sysbench-falcon.32k.cnf
   
   --servers=<server basedir>[,<server basedir>][...]
   --mode=<stage>[,stage],[...]
     stage: 
       prepare-install     - cleanup datadir and install initial mysql db
       prepare-generate    - include prepare-install stage + if definied in scenario file 
                             will run script that will generate/load data for the test
       prepare-restore     - cleanup datadir and copy datadir that will be used in test from backup 
       warmup              - not avaiable yet
       run                 - run the test 
       help                - usage information and test specific details
       cleanup             - run defined script to cleap-up and postprocess data

   --duration                Test duration
   --threads                 Number of threads
   --iterations              Number of iterations

Options to run test on running server:

   --extern                  Use running server for tests
   --server-db               Server db name
   --server-host             Server host
   --server-socket           Server socket
   --server-port             Server port
   --server-user             Server user 

Misc options:

   --start-and-exit          Only initialize and start the servers
   --start-dirty             Only start the servers (without initialization)
   --verbose                 More verbose output
   --comment                 Comments and tags that describe test peculiarity
   --force
DEOF

  #Show test specific information
  if [[ -n $TEST ]]; then 

cat <<DEOF  

Following variables can be used to control behavior of the test: $TEST
---------------------------------------------------------------- 
DEOF
    check_and_run ${TEST_MODULE}.help
  fi
  
  exit 1
}

# Return number of fields delimited by ","
params_number()
{
  COUNT=${1//[^\,]/}
  echo ${#COUNT}
}

find_dir()
{
  local DIRS=$1
  local DIR
  for DIR in $DIRS ; do
    if [ -d "$DIR" ] ; then
      echo "$DIR"
      break
    fi
  done

}

find_file()
{
  local FILES=$1
  local FILE
  for FILE in $FILES ; do
    if [ -f "$FILE" ] ; then
      echo "$FILE"
      break
    fi
  done
}

which ()
{
  IFS="${IFS=   }"; save_ifs="$IFS"; IFS=':'
  for file
  do
    file=$(basename $file)
    for dir in $PATH
    do
      if test -f $dir/$file
      then
        echo "$dir/$file"
        continue 2
      fi
    done
    #echo "Fatal error: Cannot find program $file in $PATH" 1>&2
    exit 1
  done
  IFS="$save_ifs"
  exit 0
}

log_msg()
{
  local MSG_TEXT=$1
  local MSG_FILE=$2
  local MSG_TYPE=$3

  if [ -n "$MSG_FILE" ] ; then 
    echo $MSG_TYPE "$MSG_TEXT" >> "$MSG_FILE"
  elif [ -n "$TEST_LOGFILE" ]; then 
    echo $MSG_TYPE "$MSG_TEXT" >> "$TEST_LOGFILE"
  fi
}

show_msg()
{
  local MSG_TEXT=$1
  local MSG_TYPE=$2
  
  echo $MSG_TYPE "$MSG_TEXT"

  if [ -n "$TEST_LOGFILE" ]; then 
    log_msg  "$MSG_TEXT" $TEST_LOGFILE $MSG_TYPE
  fi
  
  if [ -n "$AUTOBENCH_LOGFILE" ]; then 
    log_msg "$MSG_TEXT" $AUTOBENCH_LOGFILE $MSG_TYPE
  fi
}

show_msg_date()
{
  show_msg `date +%H:%M:%S`" $1" $2
}

log_msg_date()
{
  log_msg `date +%H:%M:%S`" $1" $2 $3
}

check_and_run()
{
  local ROUTINE=$1

  if [[ -n $ROUTINE ]]; then
    declare -F | grep "f ${ROUTINE}\$" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      ${ROUTINE}
    else
      echo "SKIPPING $ROUTINE"
    fi
  fi
}


run_hook()
{
  local HOOK=$1

  check_and_run ${TEST_MODULE}.${HOOK}
  check_and_run ${HOOK}
}

command_exec()
{
  local CMD=$1
  local OUTFILE=$2
  local RETURN_RC=$3
  local rc=""

  if [ -z "$CMD" ] ; then
    show_msg "ERROR: Got nothing instead of command line"
    exit 1
  fi

  if [ -n "$VERBOSE" ]; then
    log_msg "Executed command: $CMD" "/dev/fd/2"
  fi

  OUTFILE_LIVE=""
  if [ -n "$OUTFILE" -a "$OUTFILE" != "/dev/fd/2" ]; then
#    echo "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ - $OUTFILE"
#    SUFFIX_OUT=" | tee ${OUTFILE}.live"
     OUTFILE_LIVE=" >> ${OUTFILE}"
  fi

  Z=$(eval "$CMD $OUTFILE_LIVE  2>&1")
  rc=$?

  if [ -n "$OUTFILE" ] ; then
    log_msg "$Z" "$OUTFILE"
  fi

  if [ -n "$VERBOSE" ]; then
    log_msg "$Z" "/dev/fd/2" -n 
    log_msg "RC=$rc" "/dev/fd/2" -n 
  fi

  if [ -n "$RETURN_RC" ]; then
    echo "$rc" 
  fi
}

check_os_dependencies()
{
  OSTYPE=$(uname 2> /dev/null)

  if [[ $OSTYPE = SunOS || $OSTYPE = Linux ]];
  then
    MYSQL_BIN="mysql"
    MYSQLADMIN_BIN="mysqladmin"
    MYSQLDUMP_BIN="mysqldump"
    MYSQLD_BIN="mysqld"
    VMSTAT_BIN="vmstat"
    IOSTAT_BIN="iostat"
    SAR_BIN="sar"
  fi
  
  if [[ -n $(echo "$OSTYPE" | grep ^CYGWIN) || $OSTYPE = Linux ]];
  then
    KILLALL=killall
    VMSTAT_PARAM=" -n "
  elif [[ $OSTYPE = SunOS ]];
  then
    VMSTAT_PARAM=" 1"
    KILLALL=pkill
  fi
  
  if [[ $OSTYPE = Linux ]];
  then
    GDB_BIN="gdb"
  elif [[ -n $(echo "$OSTYPE" | grep ^CYGWIN) ]];
  then
    MYSQLD_BIN="mysqld.exe"
  fi
}

get_hw_details()
{
  OSTYPE=$(uname 2> /dev/null)

  if [[ $OSTYPE = Linux ]];
  then
    CPU_STRING=$(cat /proc/cpuinfo | grep -i "model name" | head -n 1 | cut -b 14-)
    CPU_SPEED=$(cat /proc/cpuinfo | grep -i "cpu MHZ" | head -n 1 | cut -b 12- | sed -e 's/\.[0-9]*//')
    PNUMS=$(cat /proc/cpuinfo | grep processor | tail -n 1 | cut -b 13-)
    PNUMS=$[PNUMS+=1]

    # determining cpu speed
    if [ $CPU_SPEED -gt 1000 ] ; then
      CPU_SPEED=$(echo $CPU_SPEED/1000 | bc -l | cut -b -4)
      CPU_SPEED=$CPU_SPEED"GHz"
    else
      CPU_SPEED=$CPU_SPEED"MHz"
    fi

    MEM_SIZE=$(cat /proc/meminfo | grep -i memtotal | sed -e 's/MemTotal: //' | sed -e 's/ kB//')
    MEM_SIZE=$(echo $MEM_SIZE/1024000 | bc -l | sed -e 's/\.[0-9]*//')

    HW_SPEC="${PNUMS}x${CPU_STRING}@${CPU_SPEED}, ${MEM_SIZE}GB"
  else
    HW_SPEC="Unknown"
  fi
}

set_autobench_parameters()
{
  for var in DURATION THREADS ITERATIONS ENGINE MODE \
             SERVER_DB SERVER_HOST SERVER_SOCKET SERVER_PORT SERVER_USER \
             TEST_BACKUP_BASEDIR ;
  do
    autobench_var="OPT_$var"

    # Here we are overriding some parameters from test scenario file with 
    # ones that were specified in command line as global 
    if [ -n "${!autobench_var}" ];  then
        if [[ ${var} = ENGINE ]]; then 
          eval $var=\"$(echo ${!autobench_var}|sed "s/:/ /g")\"
        else
          eval $var=\"$(echo ${!autobench_var})\"
        fi
    fi
  done
}

parse_test_mode_parameters()
{
  local save_ifs="$IFS"
  IFS=","
  TEST_STAGE_PREPARE_INSTALL=""
  TEST_STAGE_PREPARE_GENERATE=""
  TEST_STAGE_PREPARE_RESTORE=""
  TEST_STAGE_WARMUP=""
  TEST_STAGE_RUN=""
  TEST_STAGE_CLEANUP=""
  TEST_STAGE_HELP=""

  for param in $1 ; do

    case "$param" in
      prepare-install)
      TEST_STAGE_PREPARE_INSTALL=1
      ;;
      prepare-generate)
      TEST_STAGE_PREPARE_GENERATE=1
      ;;
      prepare-restore)
      TEST_STAGE_PREPARE_RESTORE=1
      ;;
      warmup)
      TEST_STAGE_WARMUP=1
      ;;
      run)
      TEST_STAGE_RUN=1
      ;;
      cleanup)
      TEST_STAGE_CLEANUP=1
      ;;
      help)
      TEST_STAGE_HELP=1
      ;;
    esac
  done
 
  IFS="$save_ifs"
}

check_test_mode_parameters()
{
  if [ -n "$TEST_STAGE_PREPARE_GENERATE" -a -n "$TEST_STAGE_PREPARE_RESTORE" ]; then 
    usage <<EOF
Wrong set of stages. It is not possible to have both prepare-generate and prepare-restore stages enabled.
EOF
  fi

  if [[ -n $TEST_STAGE_PREPARE_GENERATE ]]; then 
    if [[ -z $TEST_STAGE_RUN ]]; then 
      TEST_CASES="JUST_PREPARE"
      THREADS=1
      ITERATIONS=1
    fi
    TEST_STAGE_PREPARE_INSTALL=1
  fi
  
  if [[ -n $TEST_STAGE_HELP ]]; then 
    usage
  fi
}

parse_test_engine_parameters()
{
  ENGINE_ARGS=""
  ENGINE_NAME=""
  ENGINE_NAME_FULL=""
  ENGINE_EXT=""
  ENGINE_BACKUP_DIR=""
  ENGINE_DEFAULTS_FILE="none"

  local E_VAR=""
  local save_ifs="$IFS"
  IFS=","

  params="name=$1"

  for param in $params ; do
    param=$(echo "$param" | sed -e "s;^--;;")
    case "$param" in
      name=*)
        ENGINE_NAME_FULL=$(echo ${param#name=} | tr 'a-z' 'A-Z')
        ENGINE_NAME=${ENGINE_NAME_FULL%%.*}
        ENGINE_BACKUP_DIR=${ENGINE_NAME_FULL}

        if [[ $ENGINE_NAME_FULL != ${ENGINE_NAME_FULL##*.} ]]; then 
          ENGINE_EXT=${ENGINE_NAME_FULL#*.}
        fi
        
        # Get default cnf file for engine from scenario 
        E_VAR="ENGINE_DEFAULTS_FILE_${ENGINE_NAME}${ENGINE_EXT:+_${ENGINE_EXT}}"
        ENGINE_DEFAULTS_FILE=${!E_VAR}
      ;;
      comment=*)
        ENGINE_COMMENT=$(echo "$param" | sed -e "s;comment=;;")
      ;;
      defaults-file=*)
        ENGINE_DEFAULTS_FILE=$(echo "$param" | sed -e "s;defaults-file=;;")
      ;;
      *)
        ENGINE_ARGS="${ENGINE_ARGS} --$param"
      ;;
    esac
  done

  IFS="$save_ifs"

#  echo "$ENGINE_NAME $ENGINE_DEFAULTS_FILE $ENGINE_ARGS"
}

parse_test_parameters()
{
  #
  # Temporary collect all parameters passed with --test options
  # as AUTOBENCH_TEST_* parameters
  #
  local save_ifs="$IFS"
  IFS=":"
  
  local P_NAME=""
  local P_VALUE=""
  local TEST_VAR=""

  params="cnf=$1"

  for str in $params ; 
  do
    P_NAME=$(echo "$str" | sed -e "s;=.*;;")
    P_VALUE=$(echo "$str" | sed -e "s;$P_NAME=;;")
#    echo "TEST_PARAM: $str P_NAME:$P_NAME P_VALUE:$P_VALUE"

    TEST_VAR="AUTOBENCH_TEST_"$(echo $P_NAME| tr '[a-z]' '[A-Z]')
    #echo "TEST_VAR=$TEST_VAR VALUE=${!TEST_VAR}"
    if [[ -z ${!TEST_VAR} ]]; then
      eval "$TEST_VAR=$P_VALUE"
    else
      eval "$TEST_VAR=\"${!TEST_VAR} $P_VALUE\""
    fi
#    echo "TEST_VAR=$TEST_VAR VALUE=${!TEST_VAR}"
  done

  IFS="$save_ifs"
}

set_test_parameters()
{
  #
  # Assign values for parameters that were passed as part of --test option
  #
  for param in ${!AUTOBENCH_TEST_*}
  do
     VAR=$(echo "$param" | sed -e "s;AUTOBENCH_TEST_;;")
#    echo "Set test parameter ${VAR}=${!param}"
    eval "$VAR=\"${!param}\""
    unset $param

  done
}

autobench_init()
{

  if [ -n "$AUTOBENCH_CONFIG" ] ; then
    if [ -f "$AUTOBENCH_CONFIG" ] ; then
    . $AUTOBENCH_CONFIG
    else
      usage "ERROR: Can't find autobench config file - $AUTOBENCH_CONFIG"
    fi
  fi

  #Override settings from config file
  if [ -n "$OPT_AUTOBENCH_BASEDIR" ]; then AUTOBENCH_BASEDIR=$OPT_AUTOBENCH_BASEDIR; fi
  if [ -n "$OPT_AUTOBENCH_DATADIR" ]; then AUTOBENCH_DATADIR=$OPT_AUTOBENCH_DATADIR; fi
  if [ -n "$OPT_AUTOBENCH_SERVERDIR" ]; then AUTOBENCH_SERVERDIR=$OPT_AUTOBENCH_SERVERDIR; fi
  if [ -n "$OPT_AUTOBENCH_TESTBASEDIR" ]; then AUTOBENCH_TESTBASEDIR=$OPT_AUTOBENCH_TESTBASEDIR; fi
  if [ -n "$OPT_AUTOBENCH_RESULTDIR" ]; then AUTOBENCH_RESULTDIR=$OPT_AUTOBENCH_RESULTDIR; fi
  if [ -n "$OPT_TEST_BACKUP_BASEDIR" ]; then AUTOBENCH_BACKUP_BASEDIR=$OPT_TEST_BACKUP_BASEDIR; fi
  if [ -n "$OPT_AUTOBENCH_TMPDIR" ]; then AUTOBENCH_TMPDIR=$OPT_AUTOBENCH_TMPDIR; fi
 
  #Set/check missing values
  #echo "Autobench config file is not specified. Using built-in defaults"
  if [ -z "$AUTOBENCH_BASEDIR" ]; then
    if [ -n "$FORCE" -o -f "ab_test-defaults.cnf" ] ; then 
      AUTOBENCH_BASEDIR=$(pwd)
    else
      usage "Didn't find autobench files in the current dir. Either use --force option or specify autobench basedir with --autobench-basedir option"      
    fi
  fi

  if [[ -n $AUTOBENCH_BASEDIR ]]; then 
    if [[ $AUTOBENCH_BASEDIR = "." ]]; then 
      AUTOBENCH_BASEDIR=$(pwd)
    elif [[ ! -d $AUTOBENCH_BASEDIR ]] ; then
     usage "Autobench basedir doesn't exist. Please specify correct one with --autobench-basedir option"
    fi
  else
    usage "Please specify autobench basedir with --autobench-basedir option"
  fi

  [ -z "$AUTOBENCH_DATADIR" ] && AUTOBENCH_DATADIR=$AUTOBENCH_BASEDIR/data
  [ -z "$AUTOBENCH_SERVERDIR" ] && AUTOBENCH_SERVERDIR=$AUTOBENCH_BASEDIR/servers
  [ -z "$AUTOBENCH_TESTBASEDIR" ] && AUTOBENCH_TESTBASEDIR=$AUTOBENCH_BASEDIR/tests
  [ -z "$AUTOBENCH_RESULTDIR" ] && AUTOBENCH_RESULTDIR=$AUTOBENCH_BASEDIR/results
  [ -z "$AUTOBENCH_BACKUP_BASEDIR" ] && AUTOBENCH_BACKUP_BASEDIR=$AUTOBENCH_BASEDIR/backup
  [ -z "$AUTOBENCH_TMPDIR" ] && AUTOBENCH_TMPDIR=$AUTOBENCH_BASEDIR/tmp
  [ -z "$AUTOBENCH_LIBDIR" ] && AUTOBENCH_LIBDIR=$AUTOBENCH_BASEDIR/lib
  [ -z "$AUTOBENCH_INCDIR" ] && AUTOBENCH_INCDIR=$AUTOBENCH_BASEDIR/include

  dirs="AUTOBENCH_RESULTDIR AUTOBENCH_DATADIR AUTOBENCH_TMPDIR \
        AUTOBENCH_BACKUP_BASEDIR AUTOBENCH_TESTBASEDIR AUTOBENCH_SERVERDIR"

  for dir_var in $dirs
  do 
    ZZ=""
    dir=${!dir_var}
    if [ -n "$dir" ]; 
    then
      if [ ! -d "$dir" ] ; then 
        show_msg "creating directory $dir_var as $dir"
        ZZ=$(mkdir -p "$dir" 2>&1)
        if [ -n "$ZZ" ] ; then 
          show_msg "Error while creating dir $dir: $ZZ"
          exit 1
        fi
      fi
    else
      show_msg "Can't create directory. $dir_var has no value"
      exit 1
    fi
  done

  AUTOBENCH_PARSER="$AUTOBENCH_BASEDIR/autobench-report.pl"
  if [ ! -f $AUTOBENCH_PARSER ]; then 
    show_msg "WARNING: Can't find results parser script - $AUTOBENCH_PARSER. Some functionality will be missed"
  fi

} 


waitm()
{
  echo "WAITM!!! $MYSQL_ARGS"
  local wt=""
  local wt_old=""
  local cnt=0

  while [ true ]; do
    $MYSQL_BIN $MYSQL_ARGS -e "set global innodb_max_dirty_pages_pct=0" ${SERVER_DB}
    wt_old="$wt"
    wt=`$MYSQL_BIN $MYSQL_ARGS -e "SHOW ENGINE INNODB STATUS\G" | grep "Modified db pages" | sort -u | awk '{print $4}'`
    if [ "$wt" == "$wt_old" ]; then 
      cnt=$(($cnt+1))
    fi

    if [ $cnt -gt 10 ]; then 
      break 
    fi
    
    date
    echo "mysql pages $wt" 
    wt_gt=0
      for wt_id in $wt ; do 
        if [[ "$wt_id" -gt 100 ]] ; then
          wt_gt=1
        fi
      done
      if  [ $wt_gt -eq 0 ]; then 
        $MYSQL_BIN $MYSQL_ARGS  -e "set global innodb_max_dirty_pages_pct=90" ${SERVER_DB}
        break
      fi
    sleep 10
  done
}


get_mysqld_info()
{
  #FIXME: check for errors
  echo $MYSQL_ARGS
  MYSQLD_VERSION=$($MYSQLADMIN var $MYSQL_ARGS| grep " version "| cut -d "|" -f 3 | sed 's/ //g')
  MYSQLD_ARCH=$($MYSQLADMIN var $MYSQL_ARGS| grep "version_compile_machine"| cut -d "|" -f 3 | sed 's/ //g')
}

get_mysqld_pid()
{
  MYSQLD_PID=""
  MYSQLD_PID_FILE=$($MYSQLADMIN  var $MYSQL_ARGS | grep "pid"| cut -d "|" -f 3 | sed 's/ //g')
  if [ -f "$MYSQLD_PID_FILE" ] ; 
  then
    MYSQLD_PID=$(cat $MYSQLD_PID_FILE)
  fi
}

check_mysql_settings()
{
  #Check for mysql client tools
  for CLIENT_TOOL in MYSQL MYSQLADMIN MYSQLDUMP
  do
    CLIENT_TOOL_BIN=${CLIENT_TOOL}_BIN
    [[ -z ${!client_bin} ]] && \
    read $CLIENT_TOOL <<< $(find_file "${MYSQLD_BASEDIR}/bin/${!CLIENT_TOOL_BIN} ${MYSQLD_BASEDIR}/client/${!CLIENT_TOOL_BIN}  $(which ${!CLIENT_TOOL_BIN})")
    if [[ -z ${!CLIENT_TOOL} || ! -f ${!CLIENT_TOOL} ]]; then
      usage "Can't find $CLIENT_TOOL binary: ${!CLIENT_TOOL}"
      
    fi
  done
  				
  if [[ -n $SERVER_USER ]]; then 
    MYSQL_ARGS="-u $SERVER_USER"
  else
    usage "Please specify username with --mysql-user to connect to MySQL server"
  fi
  
  if [[ -z $SERVER_HOST || -z $SERVER_PORT ]]; 
  then
    if [[ -n $SERVER_SOCKET ]];
    then 
      MYSQL_ARGS="$MYSQL_ARGS -S $SERVER_SOCKET"
    else
      usage "Please specify either hostname/port or socket"
    fi
  else
    MYSQL_ARGS="$MYSQL_ARGS -h $SERVER_HOST -P $SERVER_PORT" 
  fi  

  if [[ -n $VERBOSE ]] ; then 
    show_msg "#################################################################################"
    show_msg "                           MySQL client specific variables"
    show_msg "#################################################################################"
    show_msg "SERVER_HOST:     $SERVER_HOST"
    show_msg "SERVER_SOCKET:   $SERVER_SOCKET"    
    show_msg "SERVER_PORT:     $SERVER_PORT"
    show_msg "SERVER_USER:     $SERVER_USER"
    show_msg "MYSQL CLIENT:    $MYSQL"
    show_msg "MYSQLADMIN:      $MYSQLADMIN"
    show_msg "MYSQL ARGS:      $MYSQL_ARGS"    
  fi

}

check_mysqld_settings()
{
  MYSQLD_ENGINE=$ENGINE_NAME
  MYSQLD_DEFAULTS_FILE=$ENGINE_DEFAULTS_FILE
  MYSQLD_ARGS=$ENGINE_ARGS
  MYSQLD_DATADIR=$AUTOBENCH_DATADIR
  ENGINE_DATADIR=$(echo "$MYSQLD_ARGS" | $SED -e "s;--datadir=;;")

  if [[ -z $ENGINE_DATADIR ]]; then 
    MYSQLD_DATADIR=$AUTOBENCH_DATADIR  
  fi

  MYSQLD=""
  
  BIN=$MYSQLD_BIN
  MYSQLD_INSTALL_DB_BASEDIR="basedir"  

  if [[ -z $MYSQLD ]] ; then
    if [[ -n $MYSQLD_BASEDIR && -d $MYSQLD_BASEDIR ]] ; then
      if [[ -x $MYSQLD_BASEDIR/bin/$BIN ]]; then
        MYSQLD="$MYSQLD_BASEDIR/bin/$BIN"
      elif [[ -x $MYSQLD_BASEDIR/sbin/$BIN ]]; then
        MYSQLD="$MYSQLD_BASEDIR/sbin/$BIN"
      elif [[ -x $MYSQLD_BASEDIR/libexec/$BIN ]]; then
        MYSQLD="$MYSQLD_BASEDIR/libexec/$BIN"
      elif [[ -x $MYSQLD_BASEDIR/sql/$BIN ]]; then
        MYSQLD="$MYSQLD_BASEDIR/sql/$BIN"
#        MYSQLD_LANG="$MYSQLD_BASEDIR/sql/share/english"
        MYSQLD_LANG="$MYSQLD_BASEDIR/sql/share"
        MYSQLD_INSTALL_DB_BASEDIR="srcdir"
      else
        show_msg "Cant detect mysqld binary using basedir $MYSQLD_BASEDIR"
        show_msg $OSTYPE $MYSQLD_BIN
        return 1
      fi
    else
      show_msg "Can't detect mysqld binary. Please specify either correct "
      show_msg "basedir with MYSQLD_BASEDIR var or location of mysqld binary "
      show_msg "with MYSQLD var"
      return 1
    fi
  else
    if [[ ! -x $MYSQLD ]] ; then
      show_msg "Cant find binary $MYSQLD. Please check value of MYSQLD var"
      return 1
    fi
  fi

  if [[ -n $(echo "$OSTYPE" | grep ^CYGWIN) ]];
  then 
    MYSQLD_DATADIR=$(rel2abs_dir $MYSQLD_DATADIR)
    MYSQLD_BASEDIR=$(rel2abs_dir $MYSQLD_BASEDIR)

    MYSQLD_DATADIR=$(cygpath -m $MYSQLD_DATADIR)
    MYSQLD_BASEDIR=$(cygpath -m $MYSQLD_BASEDIR)
    show_msg "$MYSQLD_DATADIR $MYSQLD_BASEDIR"
  fi

  MYSQLD_VERSION=$($MYSQLD --version | sed 's/.*Ver \(.*\) for .* on \(.*\) (.*(.*))/\1-\2/g;')
  MYSQLD_ARGS="--basedir=$MYSQLD_BASEDIR $MYSQLD_ARGS"

  if [ -n "$MYSQLD_LANG" ]; then 
    if [ ! -d "$MYSQLD_LANG" ]; then
      usage "Unable access MySQL language dir: $MYSQLD_LANG"
    else
      #MYSQLD_ARGS="$MYSQLD_ARGS --loose-language=$MYSQLD_LANG"
      MYSQLD_ARGS="$MYSQLD_ARGS --lc-messages-dir=$MYSQLD_LANG"
    fi
  fi

  if [ -z "$MYSQLD_DATADIR" -o ! -d "$MYSQLD_DATADIR" ] ; then
    show_msg "MySQL datadir '$MYSQLD_DATADIR' doesn't exist"
    show_msg "Please check MYSQLD_DATADIR variable in config file"
    return 1
  else
    MYSQLD_ARGS="--datadir=$MYSQLD_DATADIR $MYSQLD_ARGS"
  fi

  if [ -n "$MYSQLD_DEFAULTS_FILE" -a "$MYSQLD_DEFAULTS_FILE" != "none" ]; 
  then 
    if [ ! -e "$MYSQLD_DEFAULTS_FILE" ] ; 
    then
      show_msg "Unable to access mysqld defaults file $MYSQLD_DEFAULTS_FILE"
      show_msg "Check MYSQLD_DEFAULTS_FILE variable in config file"
      exit 1
    else
      if [ -n "$(echo "$OSTYPE" | grep ^CYGWIN)" ];
      then
        MYSQLD_DEFAULTS_FILE=$(rel2abs_file $MYSQLD_DEFAULTS_FILE)
        MYSQLD_DEFAULTS_FILE=$(cygpath -m $MYSQLD_DEFAULTS_FILE)
        show_msg "$MYSQLD_DEFAULTS_FILE"
      fi
      MYSQLD_ARGS="--defaults-file=$MYSQLD_DEFAULTS_FILE $MYSQLD_ARGS"
    fi
  else
    MYSQLD_ARGS="--no-defaults $MYSQLD_ARGS"
  fi
  
  if [[ -z $SERVER_SOCKET ]]; then 
    SERVER_SOCKET=$AUTOBENCH_TMPDIR/mysql.sock
    MYSQLD_ARGS="$MYSQLD_ARGS $SERVER_SOCKET"
  fi

  SKIP_ENGINES_FOR_INSTALL_DB=""
  for engine in innodb falcon maria ; do
    STATUS=$($MYSQLD --no-defaults --help --verbose --user=root 2>/dev/null| grep "^${engine} "| grep "TRUE")
    if [ -n "$STATUS" ]; then
      SKIP_ENGINES_FOR_INSTALL_DB="$SKIP_ENGINES_FOR_INSTALL_DB --skip-${engine}"
    fi
  done

  #TODO: Add command line option to switch that parameter on/off  
  MYSQLD_ARGS="$MYSQLD_ARGS --core "

  if [ -n "$VERBOSE" ] ; then 
    show_msg "#################################################################################"
    show_msg "                           MySQL server specific variables"
    show_msg "#################################################################################"
    show_msg "MYSQLD_BASEDIR: $MYSQLD_BASEDIR"
    show_msg "MYSQLD_DATADIR: $MYSQLD_DATADIR"
    show_msg "MYSQLD:         $MYSQLD"
    show_msg "MYSQLD_DEFAULTS_FILE: $MYSQLD_DEFAULTS_FILE"
    show_msg "MYSQLD_VERSION: $MYSQLD_VERSION"
    show_msg "MYSQLD_LANG:    $MYSQLD_LANG"
    show_msg "MYSQLD_ARGS:    $MYSQLD_ARGS"
    show_msg "MYSQLD_ENGINE:  $MYSQLD_ENGINE"
    show_msg "MYSQL CLIENT:   $MYSQL"
    show_msg "MYSQLADMIN:     $MYSQLADMIN"
  fi
  
  return 0  
}

check_test_settings()
{
  if [ -z "$TEST_BASEDIR" ]; then
    usage "Please specify location of test basedir in config file(TEST_BASEDIR)"
  elif [ ! -d "$TEST_BASEDIR" ]; then
    usage "Test basedir $TEST_BASEDIR doesn't exist. Check that test is installed under $AUTOBENCH_TESTBASEDIR or specify TESTBASEDIR with --autobench-testbasedir option"
  fi 

  #FIXME: INSTALL && WARMUP STAGES
  for stage in PREPARE_GENERATE RUN CLEANUP
  do 
    var="TEST_STAGE_${stage}"
    var_exe="${var}_EXE"

    if [ -n "${!var}" ]; then 
      if [ -n "${!var_exe}" ]; then
        FILE_EXE=$(find_file "${!var_exe} ${TEST_BASEDIR}/${!var_exe} `which ${!var_exe}`")

        if [ -z "$FILE_EXE" -o ! -x "$FILE_EXE" ]; then 
          usage "Can't find binary ${!var_exe} for $stage stage.
     Please check value of $var_exe variable in the scenario file"
        fi
      else
#          usage "You should specify executable script/binary for $stage stage.
#     Please check value of $var_exe variable in the scenario file" 
           show_msg ""
           show_msg "WARNING: Stage $stage is enabled but the executable file is not defined for this stage"
           show_msg "         Please check value of $var_exe variable in the scenario file" 
           show_msg ""
      fi
    fi
  done

  if [[ -z $DURATION ]]; then
    usage "Please specify duration of the test execution in config file(DURATION)"
  fi 

  if [[ -z $TEST_NAME ]]; then
    usage "Please specify name of test in config file(TEST_NAME)"
  fi 

  if [[ -z $COLLECT_STAT ]] ; then 
    COLLECT_STAT=0
  else
    collect_stat_init

    [[ -z "$TEST_STAT_SAMPLE" ]] && TEST_STAT_SAMPLE=10 #Get sample each 10 seconds
    if [ $DURATION -eq 0 -o $DURATION -le $TEST_STAT_SAMPLE ]; then 
      TEST_STAT_ITER=604800 
    else
      TEST_STAT_ITER=$(( $DURATION / $TEST_STAT_SAMPLE ))  
    fi  
  fi
  
  if [ -z "$USE_OPROFILE" ] ; then
    USE_OPROFILE=0
  fi
}

start_oprofile()
{
  OSTYPE=$(uname 2> /dev/null)
  
  if [[ $OSTYPE = Linux ]];
  then
    sudo opcontrol --shutdown >> $TEST_OUTDIR/oprofile.out 2>&1
    sleep 1
    if [[ -z $VMLINUX ]]; then 
      sudo opcontrol --no-vmlinux >> $TEST_OUTDIR/oprofile.out 2>&1
    else
      sudo opcontrol --vmlinux=$VMLINUX >> $TEST_OUTDIR/oprofile.out 2>&1
    fi
    sudo opcontrol -i $MYSQLD >> $TEST_OUTDIR/oprofile.out 2>&1
    sudo opcontrol --start >> $TEST_OUTDIR/oprofile.out 2>&1
    sleep 1
  fi
}

stop_oprofile()
{
  OSTYPE=$(uname 2> /dev/null)

  OPCONTROL_CALLGRAPTH_DEPTH=`opcontrol --status | grep "depth: "| grep -o "[0-9]*"`

  if [ "$OSTYPE" == "Linux" ];
  then
    sudo opcontrol --dump >> $TEST_OUTDIR/oprofile.out 2>&1
    sudo opcontrol --stop >> $TEST_OUTDIR/oprofile.out 2>&1
    sudo opreport --merge=tgid -l 2>/dev/null | head -n 30 >> $TEST_OUTDIR/oprofile.system 2>&1
    sudo opreport --merge=tgid -l $MYSQLD 2>/dev/null| head -n 30 >> $TEST_OUTDIR/oprofile.mysqld 2>&1
    if [ $OPCONTROL_CALLGRAPTH_DEPTH -gt 0 ]; then 
      sudo opreport --merge=tgid --callgraph -l $MYSQLD 2>/dev/null >> $TEST_OUTDIR/oprofile.mysqld.call 2>&1
    fi
    if  [ -n "$VMLINUX" ]; then 
      sudo opreport --merge=tgid -l $VMLINUX 2>/dev/null| head -n 50 >> $TEST_OUTDIR/oprofile.vmlinux 2>&1
    fi
    sudo opcontrol --save "$TEST_OUTDIR_NAME" >> $TEST_OUTDIR/oprofile.out 2>&1
    tar cjf "$TEST_OUTDIR/oprofile-${TEST_OUTDIR_NAME}.tar.bz2" "/var/lib/oprofile/samples/${TEST_OUTDIR_NAME}" 2>/dev/null
    sudo rm -rf "/var/lib/oprofile/samples/${TEST_OUTDIR_NAME}"
  fi
}

collect_stat_init()
{
  SAR=$(which $SAR_BIN)
  VMSTAT=$(which $VMSTAT_BIN)
  IOSTAT=$(which $IOSTAT_BIN)

  for TOOL in SAR VMSTAT IOSTAT ; 
  do 
    if [ -z "$TOOL" ]; then 
      show_msg "WARNING: $TOOL is not found"
    fi
  done
}

collect_stat_start()
{
  dstat -t -v --nocolor --output "$TEST_OUTDIR/dstat.out" $TEST_STAT_SAMPLE $TEST_STAT_ITER > /dev/null 2>&1 &

  if [ -n "$SAR" ]; then 
    $SAR -o "$TEST_OUTDIR/sar_raw.out" $TEST_STAT_SAMPLE $TEST_STAT_ITER > /dev/null 2>&1 &
  fi
  
  if [ -n "$VMSTAT" ]; then 
    $VMSTAT $VMSTAT_PARAM $TEST_STAT_SAMPLE $TEST_STAT_ITER  > $TEST_OUTDIR/vmstat.out 2>&1 &
  fi 
  
  if [ -n "$IOSTAT" ]; then 
    $IOSTAT -d  $TEST_STAT_SAMPLE $TEST_STAT_ITER > $TEST_OUTDIR/iostat.out 2>&1 &
    $IOSTAT -d -x  $TEST_STAT_SAMPLE $TEST_STAT_ITER > $TEST_OUTDIR/iostatx.out 2>&1 &
  fi 
}

collect_stat_stop()
{
  #Stop stat tools
  $KILLALL $SAR_BIN    > /dev/null 2>&1
  $KILLALL sadc        > /dev/null 2>&1
  $KILLALL $VMSTAT_BIN > /dev/null 2>&1
  $KILLALL $IOSTAT_BIN > /dev/null 2>&1
  killall dstat

  #create activity report
  if [ -f "$TEST_OUTDIR/sar_raw.out" -a -s "$TEST_OUTDIR/sar_raw.out" ]; then 
    $SAR -f $TEST_OUTDIR/sar_raw.out > $TEST_OUTDIR/sar_txt.out
  fi
}

server_start()
{
  show_msg_date "$STAGE_PREFIX STAGE: Start MySQL server: " -n 

  MYSQLD_LOG_FILE=$TEST_OUTDIR/mysqld.err

  if [ -n "$(echo "$OSTYPE" | grep ^CYGWIN)" ];
  then 
    MYSQLD_LOG_FILE=$(cygpath -m $MYSQLD_LOG_FILE)
  fi
  
  # Remove old socket file
  if [[ -f $SERVER_SOCKET ]]; then
    rm -f $SERVER_SOCKET
  fi
  
  #MYSQLD_ENV="LD_PRELOAD=/usr/local/google-perftools-0.99.2/.libs/libtcmalloc.so"
 
  show_msg "ENV"
  show_msg "$MYSQLD_ENV"
  show_msg "ENV"
  
  MYSQLD_ARGS_RUN="$MYSQLD_ARGS --log-error=$MYSQLD_LOG_FILE"
  
  RC=$(command_exec "$MYSQLD_ENV $MYSQLD $MYSQLD_ARGS_RUN >> $MYSQLD_LOG_FILE  &" "/dev/fd/2" 1)
  if [ $RC -eq 0 ]; then 
    log_msg "Server $MYSQLD was started with following arguments:" $TEST_OUTDIR/mysqld.out
    log_msg "$MYSQLD_ARGS_RUN"  $TEST_OUTDIR/mysqld.out
    log_msg "environment: $MYSQLD_ENV"  $TEST_OUTDIR/mysqld.out
    show_msg "Done"
    
    z=`grep "^innodb_buffer_pool_restore_at_startup" $MYSQLD_DEFAULTS_FILE`
    if [ -n "$z" ]; then 
    check_server_state 350
    server_state=$?
    mysqld_pid=""
    mysqld_pid=`pidof mysqld`
    show_msg_date "Found innodb_buffer_pool_restore_at_startup. datadir $MYSQLD_DATADIR pid $mysqld_pid"
    if [  -n "$mysqld_pid"  -a -f "$MYSQLD_DATADIR/ib_lru_dump" ]; then 
    show_msg_date "Loading LRU....:" -n
    z=""
    while [ true ]; do
      z=`grep "Completed reading buffer pool pages" $MYSQLD_LOG_FILE`
      if [ -n "$z" ]; then 
        show_msg "LRU loaded: $z"
        break
      fi
      sleep 5
    done
    fi
    fi
  else
    show_msg "Can't start mysqld. RC=$RC. Examine log file: $TEST_OUTDIR/mysqld.err"
  fi
}

check_pid()
{
  log_msg "Checking for pid $MYSQLD_PID_FILE $MYSQLD_PID" 

  count=60
  while [ $(($count)) -ne 0 -a -n "$MYSQLD_PID_FILE" -a \
          -f "$MYSQLD_PID_FILE" -a -n "`ps -eopid,fname| grep  mysqld | grep $MYSQLD_PID`" ]; do
    count=$(( $count-1 ))
    show_msg "Waiting for PID $MYSQLD_PID $MYSQLD_PID_FILE $count"
    sleep 1
  done
                                                                                                        
  if [ $(($count)) -eq 0 ]; then
    show_msg "Waited 60 sec. Server $MYSQLD_PID still running. Killing server $SIGNAL"
  else
    SIGNAL=""
  fi
}

server_stop()
{
  SIGNAL=9
  if [ -n "$1" ]; then
    SIGNAL=$1
    show_msg "Got SIGNAL $SIGNAL"
    #Save values of variables for mysql server
    command_exec "$MYSQLADMIN proc $MYSQL_ARGS" "$TEST_OUTDIR/mysqladmin-proc.out"
  fi
  
  show_msg_date "$STAGE_PREFIX STAGE: Check/Stop MySQL server:  " -n
  RC=$(command_exec "$MYSQLADMIN $MYSQL_ARGS ping" "$TEST_OUTDIR/mysqladmin-check-state.out" 1)

  if [ $RC -eq 0 ]; then 
    show_msg
    show_msg_date "$STAGE_PREFIX STAGE: Stopping MYSQL server: " -n 
    waitm 
    #>> $TEST_OUTDIR/waitm.out

    get_mysqld_pid
    RC=$(command_exec "$MYSQLADMIN shut $MYSQL_ARGS --shutdown_timeout=20" "$TEST_OUTDIR/mysqladmin-stop-server.out" 1)
    show_msg "RC=$RC"
    if [ $RC -eq 0 ]; then 
      check_pid
      show_msg "Done"
    else
      show_msg "$RC"
      check_pid
      if [ -n "$SIGNAL" ]; then 
        show_msg "Server still active after shutdown. Check $TEST_OUTDIR/mysqladmin-stop-server.out. Killing it"
        $KILLALL -${SIGNAL} $MYSQLD_BIN > /dev/null 2>&1
      fi
    fi
  else
    show_msg "Server not running"
  fi
    
}

fresh_db()
{
      mkdir ${MYSQLD_DATADIR}.fresh_db     
      ls -ld ${MYSQLD_DATADIR}.fresh_db    
      MYSQLD_DATADIR_ORIG=$MYSQLD_DATADIR  
      MYSQLD_DATADIR="$MYSQLD_DATADIR.fresh_db"
      install_db
      ls -1d $MYSQLD_DATADIR/*
      MYSQLD_DATADIR=$MYSQLD_DATADIR_ORIG
    
      if [ -d ${MYSQLD_DATADIR}.fresh_db/performance_schema ]; then
        echo "RM AND COPY P_S"
        rm -rf $MYSQLD_DATADIR/performance_schema
        cp -Rf ${MYSQLD_DATADIR}.fresh_db/performance_schema $MYSQLD_DATADIR
      fi

      if [ -d ${MYSQLD_DATADIR}.fresh_db/mysql ]; then
        echo "RM AND COPY MYSQL"
        rm -rf $MYSQLD_DATADIR/mysql
        cp -Rf ${MYSQLD_DATADIR}.fresh_db/mysql $MYSQLD_DATADIR
      fi
      
      rm -rf ${MYSQLD_DATADIR}.fresh_db
}


restore_data_from_backup()
{
  local ENGINE_NAME=$1
  TEST_START_TIME=$(date +%s)

  show_msg_date "$STAGE_PREFIX STAGE: Restore datadir from backup for engine $ENGINE_NAME ($ENGINE_EXT): " 

  if [ -n "$TEST_BACKUP_BASEDIR" -a -d "$TEST_BACKUP_BASEDIR" ]; then 

  MYSQL_BACKUP_DIR="$TEST_BACKUP_BASEDIR/$ENGINE_NAME"
  
  if [ -n "$ENGINE_EXT" ]; 
  then 
    MYSQL_BACKUP_DIR="$MYSQL_BACKUP_DIR.$ENGINE_EXT"
  fi
  
  if [ -d "$MYSQL_BACKUP_DIR" ] ; then
    if [ -n "$VERBOSE" ]; then 
      show_msg "Restore datadir from backup for engine $ENGINE_NAME:"
      show_msg "backup dir: $MYSQL_BACKUP_DIR datadir: $MYSQLD_DATADIR"
    fi
    if [ -n "$MYSQLD_DATADIR" -a "$MYSQLD_DATADIR" != "/" -a -d $MYSQLD_DATADIR ]; then 
    
      mkdir ${MYSQLD_DATADIR}.fresh_db
      #ls -ld ${MYSQLD_DATADIR}.fresh_db
      MYSQLD_DATADIR_ORIG=$MYSQLD_DATADIR  
      MYSQLD_DATADIR="$MYSQLD_DATADIR.fresh_db"
      install_db
      #ls -1d $MYSQLD_DATADIR/*
      MYSQLD_DATADIR=$MYSQLD_DATADIR_ORIG
    
    
      rm -rf $MYSQLD_DATADIR/* >> $TEST_OUTDIR/rm.out 2>&1 
      if [ $? -ne 0 ]; then
        show_msg ""
        show_msg "ERROR: errors happened while removing data:"
        tail -n 10 $TEST_OUTDIR/rm.out
        return 1
      fi

      ( cp -Rf $MYSQL_BACKUP_DIR/* $MYSQLD_DATADIR/ >>  $TEST_OUTDIR/cp.out 2>&1
      if [ $? -ne 0 ]; then
        show_msg ""
        show_msg "ERROR: errors happened while copying data:"
        tail -n 10 $TEST_OUTDIR/cp.out
        return 1
      fi ) &

      SRC_SIZE=`du -s $MYSQL_BACKUP_DIR | cut -f1`
      PCT_MAX=100
      PCT_CURRENT=0
      PCT_STEP=10
      echo -n "Copying data: "
      while [ true ]; do 
        DST_SIZE=`du -s $MYSQLD_DATADIR | cut -f1`
        PCT=`echo "scale=2;$DST_SIZE/$SRC_SIZE*100"|bc| cut -f1 -d'.'`
        
        if [ $PCT -gt $PCT_CURRENT ]; then 
          PCT_CURRENT=$(($PCT_CURRENT + $PCT_STEP))
          echo -n "..$PCT_CURRENT"
        else
          sleep 5
        fi
        if [ $PCT_CURRENT -ge $PCT_MAX ]; then 
          break 
        fi
      done 

      show_msg ""
      show_msg_date "Syncing/flushing data"
      sync


      if [ -d ${MYSQLD_DATADIR}.fresh_db/performance_schema ]; then 
        echo "RM AND COPY P_S"
        rm -rf $MYSQLD_DATADIR/performance_schema
        cp -Rf ${MYSQLD_DATADIR}.fresh_db/performance_schema $MYSQLD_DATADIR
      fi

      if [ -d ${MYSQLD_DATADIR}.fresh_db/mysql ]; then 
        echo "RM AND COPY MYSQL"
        rm -rf $MYSQLD_DATADIR/mysql
        cp -Rf ${MYSQLD_DATADIR}.fresh_db/mysql $MYSQLD_DATADIR
      fi
      
      rm -rf ${MYSQLD_DATADIR}.fresh_db


      TEST_DROP_CACHES=1
      OSTYPE=$(uname 2> /dev/null)
      if [[ $OSTYPE = Linux && -n $TEST_DROP_CACHES ]];
      then
        echo 3 > /proc/sys/vm/drop_caches
        show_msg "Cached droped with echo 3 > /proc/sys/vm/drop_caches"
      fi

    else
      show_msg ""
      show_msg "ERROR: $MYSQLD_DATADIR doesn't exist"
      return 1
    fi
  else
    show_msg ""
    show_msg "ERROR: Dir $MYSQL_BACKUP_DIR with backup datadir for engine $ENGINE_NAME doesn't exist"
    return 1
  fi
  else
    usage " Directory '$TEST_BACKUP_BASEDIR' don't exist. Please check TEST_BACKUP_BASEDIR variable"
    return 1
  fi
  ELAPSED_TIME=$((`date +%s`-$TEST_START_TIME))
  echo "Elapsed time for stage PREPARE-RESTORE:      $ELAPSED_TIME sec" >> $TEST_README
  show_msg_date "$STAGE_PREFIX Done"
  show_msg_date "$STAGE_PREFIX Elapsed time: $ELAPSED_TIME sec"

  show_msg "Done"
  return 0
}

rel2abs_file()
{
  f=$1
  t=$(dirname "$f") 
  y=$(echo "\`cd \\\` dirname $t\\\` ; pwd \`/\` basename $t\`" | sed s/\\\.//g)
  echo "$y$f"
}

rel2abs_dir()
{
  echo "`cd \` dirname $1\` ; pwd `/` basename $1`"
}
 
install_db()
{
  show_msg_date "$STAGE_PREFIX STAGE: Install initial MySQL DB"
  show_msg_date "$STAGE_PREFIX Installing mysql db to $MYSQLD_DATADIR (type:$MYSQLD_INSTALL_DB_BASEDIR)"

  MYSQL_INSTALL_DB=$(find_file "$MYSQLD_BASEDIR/scripts/mysql_install_db $MYSQLD_BASEDIR/bin/mysql_install_db")
  MYSQL_INSTALL_DB_ARGS="--datadir=$MYSQLD_DATADIR \
                         --${MYSQLD_INSTALL_DB_BASEDIR}=${MYSQLD_BASEDIR} $SKIP_ENGINES_FOR_INSTALL_DB --user=root"
#                         --force"

  MYSQL_INSTALL_DB_ARGS="$MYSQLD_ARGS  \
                         --datadir=$MYSQLD_DATADIR  --user=root "

  Z=$(echo "$MYSQLD_DATADIR" | grep "\.fresh_db$")
  if [ -n "$Z" ]; then 
#    echo "$MYSQLD_DATADIR ZZZZZZZZZZ $Z"
    MYSQL_INSTALL_DB_ARGS="$MYSQL_INSTALL_DB_ARGS --innodb_log_file_size=20M --innodb_log_group_home_dir=$MYSQLD_DATADIR"
  fi

  MYSQL_INSTALL_DB_ARGS=$(echo "$MYSQL_INSTALL_DB_ARGS" | sed -e s/--basedir/--$MYSQLD_INSTALL_DB_BASEDIR/)

  
  if [[ -n $MYSQLD_LANG ]] ; then
#    MYSQL_INSTALL_DB_ARGS="$MYSQL_INSTALL_DB_ARGS --windows"
    MYSQL_INSTALL_DB_ARGS="$MYSQL_INSTALL_DB_ARGS --loose-language=$MYSQLD_LANG"
    MYSQLD_INSTALL_DB_ARGS="$MYSQL_INSTALL_DB_ARGS --lc-messages-dir=$MYSQLD_LANG"
    
  fi
  
  if [ -n "$MYSQLD_DATADIR" -a -d $MYSQLD_DATADIR ]; then
    rm -rf $MYSQLD_DATADIR/*

    if [ -f "$MYSQL_INSTALL_DB" ] ; then
      echo "bash $MYSQL_INSTALL_DB $MYSQL_INSTALL_DB_ARGS" >> $TEST_OUTDIR/mysql_install_db.out
      command_exec "bash $MYSQL_INSTALL_DB $MYSQL_INSTALL_DB_ARGS" $TEST_OUTDIR/mysql_install_db.out
    else
      show_msg "Can't find mysql_install_db script $MYSQL_INSTALL_DB for basedir $MYSQLD_BASEDIR"
    fi
  else
    show_msg "ERROR: $MYSQLD_DATADIR doesn't exist"
  fi
  show_msg_date "$STAGE_PREFIX STAGE: Install initial MySQL DB: Done"
}
 
check_server_state()
{

  show_msg_date "$STAGE_PREFIX STAGE: Check server state: " 

  #Check that server started up correctly
  if [ -n "$1" ]; then 
  count=$1
  else
  count=240
  fi
  RC=1
  while [ $(($RC)) -ne 0 -a $(($count)) -ne 0 ]; do

    if [ -n $VERBOSE ]; then 
      show_msg_date "Pinging MySQL server: attempt=$count result code=$RC"
    fi
    log_msg "Pinging MySQL server: attempt=$count result code=$RC" $TEST_OUTDIR/mysqladmin-check-state.out
      
    count=$(( $count-1 ))
    sleep 2
    RC=$(command_exec "$MYSQLADMIN $MYSQL_ARGS ping" "$TEST_OUTDIR/mysqladmin-check-state.out" 1)
  done

  if [ $(($count)) -eq 0 ]; then
    show_msg "Can't start MYSQL SERVER:"
    cat $TEST_OUTDIR/mysqld.err
    return 1
  else
    if [ -f "$TEST_OUTDIR/mysqld.err" ]; then 
      START_ERR=$(cat $TEST_OUTDIR/mysqld.err | grep "ERROR")
      if [ -n "$START_ERR" ]; then 
       show_msg "==================================================================================="
       show_msg "          Following ERROR(s) was detected while trying to start the server "
       show_msg "==================================================================================="
       show_msg "$START_ERR"
       show_msg
      fi
    fi
  fi

  get_mysqld_pid
  show_msg "Done"
  return 0
}

run_test()
{
  CWD=$(pwd)

  if [ $USE_RUNNING_SERVER -eq 0 ]; then  
    check_mysqld_settings
    if [ $? -ne 0 ]; then 
      return 1
    fi
  fi

  if [[ $OSTYPE = Linux ]] ; then 
  #Set STACK SIZE
    ulimit -s $STACKSIZE
  fi

  #set defaults loop variables
  [[ -z $TEST_CASES ]] && TEST_CASES=$TEST_NAME
  [[ -z $ITERATIONS ]] && ITERATIONS=1
  [[ -z $THREADS ]]    && THREADS=1

  NEW_TEST_RUN=1

  for TEST_CASE in $(echo $TEST_CASES | sed "s/,/ /g") ; do
    for TEST_THREAD in $(echo $THREADS | sed "s/,/ /g") ; do
      for TEST_ITER in $(echo $ITERATIONS | sed "s/,/ /g") ; do

 #      show_msg "==================================================================================="
 #      show_msg "======================= STAGE: Beginning of test run loop ========================="
 #      show_msg "==================================================================================="
 #      show_msg "Total - tests: $TEST_CASES threads: $TEST_THREADS iterations: $TEST_ITERATIONS"
 #      show_msg "Current - test: $TEST_CASE  thread: $TEST_THREAD iteration: $TEST_ITER"
 #      show_msg "===================================================================================" 

        TEST_ERROR=""
        STAGE_PREFIX="test:$TEST_CASE-thread:$TEST_THREAD-iter:$TEST_ITER:#>"

        cd $CWD

        # HOOK: test_stage_prepare_pre
        run_hook test_stage_prepare_pre

        # Determine run number for an output directory with raw results
        RANDOM=$(date +%s)$$                                        
        RESULT_DIR_ID=$[ ( $RANDOM % 1000 ) + 1 ]
        RUN_NUMBER=-1
        if [ -z "$RUN_ID" ] ; then 
          RUN_ID=-1
        fi
        if [ -f "$AUTOBENCH_RESULTDIR/.run_number" ]; then
          read RESULT_DIR_ID RUN_ID RUN_NUMBER < "$AUTOBENCH_RESULTDIR/.run_number"
        fi

        if [ -z "$RUN_NUMBER" -o $((RUN_NUMBER)) -eq -1 ]; then
          RUN_NUMBER=0
        fi

        if [ -z "$RUN_ID" -o $((RUN_ID)) -eq -1 ]; then
          RUN_ID=0
        fi
      
        if [ $NEW_TEST_RUN -eq 1 ]; then 
          RUN_ID=$(( $RUN_ID + 1))
          NEW_TEST_RUN=0  
        fi

        RUN_NUMBER=$(( $RUN_NUMBER + 1))
        echo "$RESULT_DIR_ID $RUN_ID $RUN_NUMBER" > "$AUTOBENCH_RESULTDIR/.run_number"

        # Determine the output directory for storing data.
        TEST_OUTDIR_NAME="$HOSTNAME#$RESULT_DIR_ID-$RUN_ID-$RUN_NUMBER"
        TEST_OUTDIR="$AUTOBENCH_RESULTDIR/$TEST_OUTDIR_NAME"
        mkdir -p $TEST_OUTDIR

        TEST_README="$TEST_OUTDIR/readme.txt"
        TEST_LOGFILE="$TEST_OUTDIR/log.txt"
        TEST_STAGE_RUN_OUTFILE="$TEST_OUTDIR/run-result.out"
        TEST_STAGE_WARMUP_OUTFILE="$TEST_OUTDIR/warmup-result.out"
        TEST_STAGE_PREPARE_OUTFILE="$TEST_OUTDIR/prepare-result.out"
        TEST_STAGE_CLEANUP_OUTFILE="$TEST_OUTDIR/cleanup-result.out"

        if [ -n "$TEST_RESULTS_DIR_LIST" ]; then 
          TEST_RESULTS_DIR_LIST="$TEST_RESULTS_DIR_LIST $TEST_OUTDIR"
        else
          TEST_RESULTS_DIR_LIST="$TEST_OUTDIR"  
        fi

        show_msg_date "$STAGE_PREFIX STAGE: Test run initialization"  
        show_msg_date "$STAGE_PREFIX Logs and output: $TEST_OUTDIR_NAME"

        RUN_COMMENT="$COMMENT#$ENGINE_COMMENT"

        #TEST_OUTDIR="$MYSQLD_ID-$ENGINE-$DATE"

        HW_HOST=$(uname -n)
        HW_OS=$(uname -s)
        HW_KERNEL=$(uname -r)
        HW_ARCH=$(uname -m)
        #FIXME: detect FS
	FS="ext3"

        # Create a readme file in the output directory
        cat >> $TEST_README <<-DATA_EOF
---------------------------------------- Hardware details ---------------------------------
Date of test:  `date +"%Y-%m-%d %H:%M:%S"`
Hostname:      $HOSTNAME
OS:            $HW_OS
Kernel:        $HW_KERNEL
Arch:          $HW_ARCH      
CPU/RAM:       $HW_SPEC
Hardware key:  $HW_OS:$HW_KERNEL:$HW_ARCH:$FS:$HW_SPEC
Stack size:    `ulimit -s`
Open files:    `ulimit -n`
----------------------------------------- Test details ------------------------------------
Test config file:       $TEST_CNF
Test backup basedir:    $TEST_BACKUP_BASEDIR
Test suite name:        $TEST_NAME      
Test suite comment:     $TEST_COMMENT
Test name:              $TEST_CASE                

Test Duration(seconds): $DURATION        
Database Connections:   $TEST_THREAD          
Iteration:              $TEST_ITER            
Number of rows:         $NUMBER_OF_ROWS
---------------------------------------- Result details -----------------------------------
Result dir ID: $RESULT_DIR_ID
Run ID:        $RUN_ID
Run number:    $RUN_NUMBER
Comments:      $RUN_COMMENT

DATA_EOF

        show_msg_date "$STAGE_PREFIX === KEY STAGES ===: " -n
        [[ -n $TEST_STAGE_PREPARE_INSTALL ]]  && show_msg "PREPARE_INSTALL " -n
        [[ -n $TEST_STAGE_PREPARE_GENERATE ]] && show_msg "PREPARE_GENERATE " -n
        [[ -n $TEST_STAGE_PREPARE_RESTORE ]]  && show_msg "PREPARE_RESTORE " -n
        [[ -n $TEST_STAGE_WARMUP ]]           && show_msg "WARMUP " -n
        [[ -n $TEST_STAGE_RUN ]]              && show_msg "RUN " -n
        [[ -n $TEST_BG_TASK ]]                && show_msg "BG_TASK " -n
        [[ -n $TEST_STAGE_CLEANUP ]]          && show_msg "CLEANUP " -n
        show_msg ""   

        cat >> $TEST_README <<-DATA_EOF
---------------------------------------- Stages -----------------------------------
STAGE_PREPARE_GENERATE: $TEST_STAGE_PREPARE_GENERATE
STAGE_PREPARE_RESTORE:  $TEST_STAGE_PREPARE_RESTORE
STAGE_PREPARE_INSTALL:  $TEST_STAGE_PREPARE_INSTALL
STAGE_RUN:              $TEST_STAGE_RUN
STAGE_CLEANUP:          $TEST_STAGE_CLEANUP
BG_TASK:                $TEST_BG_TASK
DATA_EOF

        echo "${RUN_ID}_${RUN_NUMBER}_${TEST_CASE}_start" >> /tmp/dim_stat_ab.log
        

        if [ $USE_RUNNING_SERVER -eq 0 ]; then 
        #Stop server
        echo "${RUN_ID}_${RUN_NUMBER}_stop_server" >> /tmp/dim_stat_ab.log
        server_stop
     
        
        if [[ $START_DIRTY -eq 1 || 
              ( -z $TEST_STAGE_PREPARE_RESTORE && -z $TEST_STAGE_PREPARE_INSTALL ) ]]; then 
              show_msg_date "#-#" 
              show_msg_date "#-# MySQL server will use already existed datadir: $MYSQLD_DATADIR"
              show_msg_date "#-#"
              show_msg_date "Freshing P_S and MYSQL DBs"
              fresh_db
        elif [ -n "$TEST_STAGE_PREPARE_RESTORE" ] ; then 
          # Restore all needed datafiles from backup dir
          echo "${RUN_ID}_${RUN_NUMBER}_restore_datadir" >> /tmp/dim_stat_ab.log
          run_hook test_stage_prepare_restore_pre
          
          restore_data_from_backup $ENGINE_NAME 
          if [ $? -ne 0 ]; then 
            show_msg_date "ERROR: While restore $?"
            return 2
          fi
          run_hook test_stage_prepare_restore_post
          
        elif [ -n "$TEST_STAGE_PREPARE_INSTALL" ] ; then 
          run_hook test_stage_prepare_install_pre
          install_db
          show_msg ""
          run_hook test_stage_prepare_install_post
        fi
        
        #Start server
        server_start

        #Check that server started up correctly
        check_server_state

        if [ $? -ne 0 ]; then 
          show_msg ""
          show_msg "ERROR: runtime error: Can't start mysqld server"
          show_msg "ERROR: Skipping all remain tests for engine $ENGINE_NAME"
          return 2
        fi
        echo "${RUN_ID}_${RUN_NUMBER}_server_started" >> /tmp/dim_stat_ab.log
        run_hook test_stage_server_start_post

      fi         

      if [ $START_AND_EXIT -eq 1 ]; then 
        show_msg "Autobench was started with --start-and-exit. Exiting"
        exit 0
      fi

      if [ $START_DIRTY -eq 1 ]; then 
        show_msg "Autobench was started with --start-dirty. Exiting"
        exit 0
      fi

      #Get server version and arch 
      get_mysqld_info

      #
      #FIXME: Add proper routine call for structured result
      #
      TEST_STRUCTURED_OUTDIR="$AUTOBENCH_BASEDIR/results-$HOSTNAME#$RESULT_DIR_ID-structured/$TEST_NAME/$MYSQLD_VERSION/$RUN_ID"
      mkdir -p $TEST_STRUCTURED_OUTDIR
      ln -s $TEST_OUTDIR $TEST_STRUCTURED_OUTDIR/

      # Output run information into the readme.txt.
      cat >> $TEST_README <<-DATA_EOF
------------------------------------- MySQL server details --------------------------------
MySQL server key:       MySQL-$MYSQLD_VERSION/$MYSQLD_ARCH/$ENGINE_NAME      
MySQL server version:   $MYSQLD_VERSION       
MySQL server arch:      $MYSQLD_ARCH          
MySQL server datadir:   $MYSQLD_DATADIR
Engine name:            $ENGINE_NAME          
Engine name extension:  $ENGINE_EXT
Engine defaults file:   $ENGINE_DEFAULTS_FILE 
Engine additional args: $ENGINE_ARGS          
Engine backup data dir: ${TEST_BACKUP_BASEDIR:+${TEST_BACKUP_BASEDIR}/}${ENGINE_BACKUP_DIR}
DATA_EOF

      if [ -n "$ENGINE_DEFAULTS_FILE" -a "$ENGINE_DEFAULTS_FILE" != "none" ]; then 
        cp $ENGINE_DEFAULTS_FILE $TEST_OUTDIR
      fi

#      echo "==================================================================================="
#      echo "=============================== STAGE: TEST RUN  =================================="
#      echo "==================================================================================="
 
      if [ -n "$VERBOSE" ]; 
      then 
        show_msg_date "$STAGE_PREFIX STAGE: Details about test run "

        show_msg "------------------------------------------------"
        show_msg "TEST RUN DETAILS:"
        show_msg "------------------------------------------------"
        show_msg "DATE:                 `date`"
        show_msg "RESULT DIR:           $TEST_OUTDIR"
        show_msg "TEST_NAME:            $TEST_CASE"
        show_msg "TEST_ENGINE:          $ENGINE_NAME"
        show_msg "THREADS:              $TEST_THREAD" 
        show_msg "TEST ITERATION:       $TEST_ITER"
        show_msg "DURATION:             $DURATION"
        show_msg "TEST_STAGE_PREPARE:   $TEST_STAGE_PREPARE"
        show_msg "TEST_STAGE_RUN:       $TEST_STAGE_RUN"
        show_msg "TEST_STAGE_RUN:       $TEST_STAGE_CLEANUP"
        show_msg "MYSQL SERVER BINARY:  $MYSQLD"
        show_msg "MYSQL SERVER VERSION: $MYSQLD_VERSION"
        show_msg "MYSQL SERVER ARCH:    $MYSQLD_ARCH"
        show_msg ""
        show_msg "------------------------------------------------"
      fi

      #Substitute loop related variables to test argument's command line
      eval TEST_ARGS=${TEST_ARGS_TEMPLATE}

      if [ -n "$TEST_STAGE_PREPARE_GENERATE" ] ; then 
        #Generate and/or load data
        show_msg "==================================================================================="
        show_msg "========================= STAGE: Generate and/or load data ========================"
        show_msg "==================================================================================="

        show_msg_date "$STAGE_PREFIX STAGE: Generate and/or load data: "
        cd $TEST_BASEDIR

        if [[ -n $TEST_STAGE_PREPARE_GENERATE ]]; then 
          TEST_START_TIME=$(date +%s)

          TEST_PREPARE_ARGS=$(eval echo "$TEST_ARGS_COMMON $TEST_ARGS_STAGE_PREPARE")
          log_msg "PREPARE CMD LINE: $TEST_STAGE_PREPARE_GENERATE_EXE $TEST_PREPARE_ARGS" $TEST_STAGE_PREPARE_OUTFILE
          RC=$(command_exec "$TEST_STAGE_PREPARE_GENERATE_EXE $TEST_PREPARE_ARGS" $TEST_STAGE_PREPARE_OUTFILE 1)

          if [ $RC -ne 0 ]; then 
             show_msg ""
             show_msg "ERROR: Operation failed. Check $TEST_STAGE_PREPARE_OUTFILE"
             show_msg ""
             show_msg "Last 10 lines of $TEST_STAGE_PREPARE_OUTFILE log file"
             show_msg "..."
             tail -n 10 $TEST_STAGE_PREPARE_OUTFILE
             show_msg ""

             TEST_ERROR="PREPARE"
          else
            command_exec "$MYSQLADMIN reload $MYSQL_ARGS" $TEST_OUTDIR/mysqladmin-reload.out
            sync
            sleep 2
            ELAPSED_TIME=$((`date +%s`-$TEST_START_TIME))
            echo "Elapsed time for stage PREPARE-GENERATE:      $ELAPSED_TIME sec" >> $TEST_README
            show_msg_date "$STAGE_PREFIX Done"
            show_msg_date "$STAGE_PREFIX Elapsed time: $ELAPSED_TIME sec"
          fi   
        fi
        cd $CWD
      fi
      run_hook test_stage_prepare_post

      if [ -n "$TEST_STAGE_WARMUP" -a -z "$TEST_ERROR" ] ; then
        show_msg "==================================================================================="
        show_msg "================================= STAGE: WARMUP ==================================="
        show_msg "==================================================================================="
        
        show_msg "UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU"
        run_hook test_stage_warmup_pre
        show_msg "UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU2"
         show_msg "$TEST_ARGS_STAGE_WARMUP"  "$TEST_STAGE_WARMUP_EXE"

        show_msg_date "$STAGE_PREFIX STAGE: WARMUP: DURATION: $TEST_WARMUP_DURATION sec" 
        echo "${RUN_ID}_${RUN_NUMBER}_warmup" >> /tmp/dim_stat_ab.log

        cd "$TEST_BASEDIR"

        TEST_WARMUP_ARGS=$(eval echo "$TEST_ARGS_STAGE_WARMUP")
        log_msg "RUN CMD LINE: $TEST_STAGE_WARMUP_EXE  $TEST_WARMUP_ARGS" $TEST_STAGE_WARMUP_OUTFILE

        RC=$(command_exec "$TEST_STAGE_WARMUP_EXE $TEST_WARMUP_ARGS" "$TEST_STAGE_WARMUP_OUTFILE" 1)
        #if [ $RC -ne 0 ]; then
        #  show_msg_date "Warmup: ERROR: Operation failed. Check $TEST_STAGE_WARMUP_OUTFILE"
        #  TEST_ERROR="WARMUP"
        #else
        #  show_msg_date "Warmup: Done"
        #fi
        
        run_hook test_stage_warmup_post
        cd $CWD
      fi



      if [ -n "$TEST_STAGE_RUN" -a -z "$TEST_ERROR" ] ; then 
        #Run the test
        show_msg "==================================================================================="
        show_msg "=========================== STAGE: Run the test case =============================="
        show_msg "==================================================================================="

        show_msg_date "$STAGE_PREFIX STAGE: Start the test case: $TEST_CASE" 

        echo "${RUN_ID}_${RUN_NUMBER}_run" >> /tmp/dim_stat_ab.log         
        if [ $USE_OPROFILE -eq 1 ]; then
          start_oprofile
        fi

        if [ "$COLLECT_STAT" -eq 1 ] ; then
          #Start gather statistics
          collect_stat_start
        fi

        run_hook test_stage_run_pre

        cd "$TEST_BASEDIR"

        TEST_RUN_ARGS=$(eval echo "$TEST_ARGS_COMMON $TEST_ARGS $TEST_ARGS_STAGE_RUN")
        log_msg "RUN CMD LINE: $TEST_STAGE_RUN_EXE  $TEST_RUN_ARGS" $TEST_STAGE_RUN_OUTFILE

        TEST_START_TIME=$(date +%s)
        TEST_STOP_TIME=""
        if [[ -n $DURATION && $DURATION -gt 0 ]]; then 
          if [[ -n $WATCHDOG && $WATCHDOG = ON ]]; then
            SLEEP_TIME=$(( DURATION + 15 ))
            TEST_STOP_TIME=$(($TEST_START_TIME+$SLEEP_TIME))
            show_msg_date "$STAGE_PREFIX Test duration(+15sec): $SLEEP_TIME sec. Test stop time: " -n 
          else
            TEST_STOP_TIME=$(($TEST_START_TIME+$DURATION))
            show_msg_date "$STAGE_PREFIX Test duration: $DURATION sec. Test stop time: " -n
          fi
          date --date=@$TEST_STOP_TIME +%T
        else
          show_msg_date "Duration of the test execution is not limited. Please wait till end of the test or interrupt it with Ctrl-C"
	fi
        export OUR_PID=$$

        #( sleep $SLEEP_TIME ; echo "Sending alarm" >> $TEST_OUTDIR/log.txt ; kill -14 $OUR_PID ) &
        if [[ $WATCHDOG = ON ]]; then 
          ( sleep $SLEEP_TIME ; \
            echo "Killing $TEST_STAGE_RUN_EXE" >> $TEST_OUTDIR/log.txt;  \
            Z=$($MYSQL $MYSQL_ARGS -e'show processlist' | grep -v process | grep -v Id | cut -f 1 ) ; \
            for id in $Z ; do  echo "Kill ID=$id" >> $TEST_OUTDIR/log.txt; $MYSQLADMIN $MYSQL_ARGS kill $id ; done ; \
            sleep 3; \
            killall -9 $TEST_STAGE_RUN_EXE > /dev/null 2>&1 ) > /dev/null 2>&1  &

            WATCHDOG_PID=$!
        fi

        if [[ -n $TEST_BG_TASK ]]; then 
          TEST_BG_TASK_LOGFILE="$TEST_OUTDIR/bg_task.out"
          BG_PID_FILE="$TEST_OUTDIR/bg_task.pid"
          [[ -z $TEST_BG_TASK_DELAY ]] && TEST_BG_TASK_DELAY=0
          show_msg_date "background task: $TEST_BG_TASK"
          show_msg_date "background task: will start with delay - $TEST_BG_TASK_DELAY sec"

          ( 
            echo "$!" > $BG_PID_FILE
	    [ $TEST_BG_TASK_DELAY -gt 0 ] && sleep $TEST_BG_TASK_DELAY 

            run_hook bg_task.test_stage_run_pre

            log_msg_date "Start background task with delay $TEST_BG_TASK_DELAY sec" $TEST_BG_TASK_LOGFILE
            log_msg_date "$TEST_ARGS_BG_TASK" $TEST_BG_TASK_LOGFILE

            BG_TASK_START_TIME=$(date +%s) 
            TEST_ARGS_BG_TASK=$(eval echo "$TEST_ARGS_BG_TASK") 
            log_msg "RUN CMD LINE: $TEST_BG_TASK_RUN_EXE $TEST_ARGS_BG_TASK" $TEST_BG_TASK_LOGFILE
            BG_RC=$(command_exec "$TEST_BG_TASK_RUN_EXE $TEST_ARGS_BG_TASK" "$TEST_BG_TASK_LOGFILE" 1)
            BG_TASK_TIME=$((`date +%s` - $BG_TASK_START_TIME)) 

            log_msg "" $TEST_BG_TASK_LOGFILE
            log_msg "BG_TASK: RC=$BG_RC" $TEST_BG_TASK_LOGFILE
            log_msg "BG_TASK: Elapsed time: $BG_TASK_TIME" $TEST_README
            log_msg "BG_TASK: Elapsed time: $BG_TASK_TIME" $TEST_BG_TASK_LOGFILE
            log_msg_date "Stop background task" $TEST_BG_TASK_LOGFILE
            
            run_hook bg_task.test_stage_run_post

            rm -f $BG_PID_FILE
            exit $BG_RC
          ) >> $TEST_BG_TASK_LOGFILE 2>&1 &
          BG_PID=$!
        fi    

        RC=$(command_exec "$TEST_ENV $TEST_STAGE_RUN_EXE $TEST_RUN_ARGS" "$TEST_STAGE_RUN_OUTFILE" 1)

        if [[ $WATCHDOG = ON ]]; then
          kill -9 $WATCHDOG_PID > /dev/null 2>&1
        fi
        
        if [ $RC -ne 0 ]; then 
          show_msg ""
          show_msg "ERROR: Operation failed. Check $TEST_STAGE_RUN_OUTFILE"
          show_msg ""
          CURRENT_TIME=$(date +%s)
          if [[ -n "$TEST_STOP_TIME" && $CURRENT_TIME -ge $TEST_STOP_TIME ]]; 
          then 
            TEST_ERROR="RUN: Time exceeded"
            #Save values of variables for mysql server
            command_exec "$MYSQLADMIN proc $MYSQL_ARGS" "$TEST_OUTDIR/mysqladmin-proc-time-exceeded.out"
          else
            TEST_ERROR="RUN: Runtime failure"
          fi
	  show_msg ""
	  show_msg "Last 10 lines of $TEST_STAGE_RUN_OUTFILE log file"
	  show_msg "..."
	  tail -n 10 $TEST_STAGE_RUN_OUTFILE
	  show_msg ""
        else
          ELAPSED_TIME=$((`date +%s`-$TEST_START_TIME))
          echo "Elapsed time for stage RUN:      $ELAPSED_TIME" >> $TEST_README
          TEST_RESULT="N/A"
          if [ -n "$AUTOBENCH_PARSER" -a -f "$AUTOBENCH_PARSER" ]; then
#            echo "perl $AUTOBENCH_BASEDIR/$AUTOBENCH_PARSER --report-mode=single $TEST_OUTDIR" 
            TEST_RESULT=$(perl $AUTOBENCH_PARSER --report-mode=single $TEST_OUTDIR)
          fi
          show_msg_date "$STAGE_PREFIX Test finished OK"
          show_msg_date "$STAGE_PREFIX Elapsed time: $ELAPSED_TIME sec"
          show_msg_date "$STAGE_PREFIX Result: $TEST_RESULT"
        fi   
       
        if [ "$COLLECT_STAT" -eq 1 ] ; then
          #Stop gathering stat 
          collect_stat_stop
        fi

        if [ $USE_OPROFILE -eq 1 ] ; then
          stop_oprofile
        fi

        cd $CWD
        run_hook  test_stage_run_post

        if [ -n "$TEST_BG_TASK" ]; then 
          if [ -f "$BG_PID_FILE" ]; then 
            show_msg_date "background task: Check for background process $BG_PID"
            count=600
            while [ $(($count)) -ne 0 -a \
                   -n "$BG_PID_FILE" -a -f "$BG_PID_FILE" -a \
                   -n "`ps -eopid,fname| grep $BG_PID`" ]; \
            do
              count=$(( $count-1 ))
              show_msg "background task: Waiting for PID $BG_PID counter $count"
              sleep 1
            done ;
          fi
          wait $BG_PID
          show_msg_date "background task: finished with RC=$? Log file: $TEST_BG_TASK_LOGFILE"        
          show_msg_date "background task: ~Elapsed time:" -n
          if [[ -f $TEST_BG_TASK_LOGFILE ]]; then  
            tail -n 2 $TEST_BG_TASK_LOGFILE | grep 'time'
          else
            show_msg " Can't get data from result file: $TEST_BG_TASK_LOGFILE"
          fi
        fi                           
      fi
          
      #Save extended stat information from mysql server
      command_exec "$MYSQL $MYSQL_ARGS -e'show global status'" "$TEST_OUTDIR/mysql-show-global-status.out"          

      #Save values of variables for mysql server
      command_exec "$MYSQLADMIN var $MYSQL_ARGS" "$TEST_OUTDIR/mysqladmin-var.out"          

      #Save INNODB STATUS information from mysql server
      if [ "$ENGINE_NAME" == "INNODB" ]; 
      then 
        command_exec "$MYSQL $MYSQL_ARGS -e 'show engine innodb status\G'" "$TEST_OUTDIR/mysql-innodb-status.out"          
        command_exec "$MYSQL $MYSQL_ARGS -e 'show engine innodb mutex'" "$TEST_OUTDIR/mysql-innodb-mutex.out"          
      fi

      #Save FALCON information from mysql server
      if [ "$ENGINE_NAME" == "FALCON" ];
      then
        command_exec "$MYSQL $MYSQL_ARGS -vv information_schema \
        -e'select * from FALCON_TABLESPACE_IO ;  \
           select * from FALCON_VERSION;  \
           select * from FALCON_TRANSACTION_SUMMARY; \
           select * from FALCON_SERIAL_LOG_INFO;  \
           select * from FALCON_SYNCOBJECTS; \
           select * from FALCON_TRANSACTIONS'" "$TEST_OUTDIR/mysql-falcon-status.out"
      fi

      #routine to clean up/postprocess test results if [ -n
      if [ -n "$TEST_STAGE_CLEANUP"  ]; then

        show_msg_date "$STAGE_PREFIX STAGE: CLEANUP: "
        echo "${RUN_ID}_${RUN_NUMBER}_cleanup" >> /tmp/dim_stat_ab.log
  
        run_hook  test_stage_cleanup_pre
 
        if [[ -n $TEST_STAGE_CLEANUP_EXE && -f $TEST_STAGE_CLEANUP_EXE ]]; then 
          RC=$(command_exec "$TEST_STAGE_CLEANUP_EXE $TEST_ARGS_STAGE_CLEANUP" "$TEST_STAGE_CLEANUP_OUTFILE" 1)
          if [ $RC -ne 0 ]; then
            show_msg "ERROR: Operation failed. Check $TEST_STAGE_RUN_OUTFILE"
            TEST_ERROR="$TEST_ERROR  CLEANUP"
          else
            show_msg "Done"
          fi
        fi

        run_hook  test_stage_cleanup_post
        
      fi

      if [ $USE_RUNNING_SERVER -eq 0 ]; then 
        #Stop server
        if [ -n "$TEST_ERROR" -a "`echo "$TEST_ERROR"| grep "RUN: Time exceeded"`" ];
        then 
           echo "STOP 11"
          server_stop 11
        else
          server_stop
#           echo "STOP"
        fi
      fi

      #Save core file(s) in case of crash
      CORE_FILES=$(ls -1 $MYSQLD_DATADIR/core* 2>/dev/null)
      if [ -n "$CORE_FILES" ] ; then
        TEST_ERROR="$TEST_ERROR,FOUND MYSQLD CRASH"
        for CORE_FILE in $CORE_FILES ; do 
          if [ -n "$GDB_BIN" ]; then          
            core_file_name=$(basename $core_file)
            gdb  --batch -ex "set pagination off" -ex "bt" $MYSQLD $CORE_FILE > $TEST_OUTDIR/gdb.${core_file_name}.bt
            gdb  --batch -ex "set pagination off" -ex "thread apply all bt" $MYSQLD $CORE_FILE > $TEST_OUTDIR/gdb.${core_file_name}.thread.all.bt
          fi
          #cp $CORE_FILE $TEST_OUTDIR
        done
      fi                                           

      if [ $(ls -1 $MYSQLD_DATADIR/core* 2>/dev/null|wc -l) -gt 0 ] ; then
        TEST_ERROR="$TEST_ERROR,FOUND MYSQLD CRASH"
        #cp $MYSQLD_DATADIR/core* $TEST_OUTDIR
      fi

      #FIXME: Replace the hack below with proper handling of stages
      if [[ -n $TEST_STAGE_PREPARE_GENERATE && -z $TEST_STAGE_RUN ]]; then
        #Exit as we just need only generate stage
        break 3
      fi

      if [ -z "$TEST_ERROR" ]; then 
        TEST_OK_LIST="$TEST_OK_LIST $TEST_OUTDIR_NAME"
        show_msg_date "Test finished ok"
      else
        TEST_FAILED_LIST="$TEST_FAILED_LIST $TEST_OUTDIR_NAME"
        show_msg_date ""
        show_msg_date "Test failed at stage: $TEST_ERROR"
        show_msg_date ""
      fi        

      TEST_LOGFILE=""
       echo "${RUN_ID}_${RUN_NUMBER}_${TEST_CASE}_end" >> /tmp/dim_stat_ab.log
       sleep 1
      done  ;
    done  ;
  done  ;
  return 0
}

#echo "==================================================================================="
#echo "====================== STAGE: Autobench initialization ============================"
#echo "==================================================================================="

show_msg_date "autobench#> Autobench initialization: " 

#Setup OS specific variables  
check_os_dependencies

#Get hardware specification
get_hw_details

#Default server parameters
SERVER_DB="test"
SERVER_HOST="127.0.0.1"
SERVER_USER="root"
SERVER_SOCKET=""
SERVER_PORT="3306"

#---------------------------------------------------------
# Overiding values with command line options - if provided
#---------------------------------------------------------
while test $# -gt 0; do
  case "$1" in
  --autobench-config=*)
    AUTOBENCH_CONFIG=$($ECHO "$1" | $SED -e "s;--autobench-config=;;")   ;;
  --autobench-basedir=*)
    OPT_AUTOBENCH_BASEDIR=$($ECHO "$1" | $SED -e "s;--autobench-basedir=;;")   ;;
  --autobench-datadir=*)
    OPT_AUTOBENCH_DATADIR=$($ECHO "$1" | $SED -e "s;--autobench-datadir=;;")   ;;
  --autobench-serverdir=*)
    OPT_AUTOBENCH_SERVERDIR=$($ECHO "$1" | $SED -e "s;--autobench-serverdir=;;")   ;;
  --autobench-testbasedir=*)
    OPT_AUTOBENCH_TESTBASEDIR=$($ECHO "$1" | $SED -e "s;--autobench-testbasedir=;;")   ;;
  --autobench-resultdir=*)
    OPT_AUTOBENCH_RESULTDIR=$($ECHO "$1" | $SED -e "s;--autobench-resultdir=;;")   ;;
  --autobench-backupdir=*)
    OPT_TEST_BACKUP_BASEDIR=$($ECHO "$1" | $SED -e "s;--autobench-backupdir=;;")   ;;
  --env=*)
    OPT_ENV_FILE=$($ECHO "$1" | $SED -e "s;--env=;;")   ;;
  --extern)
    USE_RUNNING_SERVER=1 ;;
  --servers=*)
    SERVERS=$($ECHO "$1" | $SED -e "s;--servers=;;")    
    if [ -z "$SERVERS" ] ; then 
      usage "You have to specify at least one [path to] server basedir"
    fi
    ;;
  --server-id=*)
    OPT_SERVER_ID=$($ECHO "$1" | $SED -e "s;--server-id=;;")    ;;
  --server-cnf=*)
    OPT_SERVER_CNF=$($ECHO "$1" | $SED -e "s;--server-cnf=;;")    ;;
  --server-bin=*)
    OPT_SERVER_BIN=$($ECHO "$1" | $SED -e "s;--server-bin=;;")    ;;
  --server-lang=*)
    OPT_SERVER_LANG=$($ECHO "$1" | $SED -e "s;--server-lang=;;")    ;;
  --test=*)
    TEST_SET="${TEST_SET} "$(echo "$1" | sed -e "s;--test=;;")
    ;;
  --test-cases=*)
    OPT_TEST_CASES=$($ECHO "$1" | $SED -e "s;--test-cases=;;")    ;;
  --mode=*)
    OPT_MODE=$($ECHO "$1" | $SED -e "s;--mode=;;")    ;;
  --duration=*)
    OPT_DURATION=$($ECHO "$1" | $SED -e "s;--duration=;;")    ;;
  --threads=*)
    OPT_THREADS=$($ECHO "$1" | $SED -e "s;--threads=;;")    ;;
  --iterations=*)
    OPT_ITERATIONS=$($ECHO "$1" | $SED -e "s;--iterations=;;")    ;;
  --engine=*)
    OPT_ENGINE="${OPT_ENGINE} "$(echo "$1" | sed -e "s;--engine=;;") ;;
  --exit-on-error)
    EXIT_ON_ERROR=1 ;; 
  --server-db=*)
    OPT_SERVER_DB=$($ECHO "$1" | $SED -e "s;--server-db=;;")    ;;
  --server-host=*)
    OPT_SERVER_HOST=$($ECHO "$1" | $SED -e "s;--server-host=;;")    ;;
  --server-socket=*)
    OPT_SERVER_SOCKET=$($ECHO "$1" | $SED -e "s;--server-socket=;;")    ;;
  --server-port=*)
    OPT_SERVER_PORT=$($ECHO "$1" | $SED -e "s;--server-port=;;")    ;;
  --server-user=*)
    OPT_SERVER_USER=$($ECHO "$1" | $SED -e "s;--server-user=;;")    ;;
  --start-and-exit)
    START_AND_EXIT=1 ;;
  --start-dirty)
    START_DIRTY=1 ;;
  --verbose)
    VERBOSE=1 ;;
  --comment=*)
    COMMENT=$($ECHO "$1" | $SED -e "s;--comment=;;") ;;
  --force)
    FORCE=1 ;;
  -- )  shift; break ;;
  --*) $ECHO "Unrecognized option: $1" ; usage ;;
  * ) break ;;
  esac
  shift
done


#Initialize autobench variables and create required dir structure
autobench_init

if [ -z "$TEST_SET" ] ; then 
  usage "Define at least one test config file with --test=<options>"
fi

if [ $(params_number $TEST_SET) -gt 1 ]; then
  #Batch mode
  if [ -n "$OPT_TEST_CASES" ]; then 
    usage "You can't use --test-cases option because more than one test name was specified with --test option"
  fi
else
  if [ -n "$OPT_TEST_CASES" ]; then 
    TEST_CASES=$OPT_TEST_CASES ; 
  fi
fi

#Check existence of specified servers basedirs 
SERVERDIRS=""
if [ $USE_RUNNING_SERVER -eq 1 ]; then
  SERVERDIRS="EXTERN"  
else
  if [ -n "$SERVERS" ] ; then 
    for SERVERDIR in $(echo ${SERVERS} | sed "s/,/ /g") ; do
      DIR=$(find_dir "${SERVERDIR} ${AUTOBENCH_SERVERDIR}/${SERVERDIR}")
      if [ -z "$DIR" ]; then
        show_msg "WARNING: Specified directory ${SERVERDIR} doesn't exist and will be omited"
      else
        #echo "OK: $SERVERDIR exists as $DIR"
        SERVERDIRS="$SERVERDIRS $DIR"
      fi
    done
  else
    usage "Define at least one server basedir or use --extern to run the test against already running mysql server"
  fi
fi

if [ $(params_number $SERVERS) -gt 0 ]; then
  #Batch mode
  if [ -n "$OPT_SERVER_ID" ]; then 
    usage "You can't use --server-id option because more than one server was specified with --servers option"
  fi
  if [ -n "$OPT_SERVER_CNF" ]; then 
    usage "You can't use --server-cnf option because more than one test name was specified with --servers option"
  fi
  if [ -n "$OPT_SERVER_BIN" ]; then 
    usage "You can't use --server-bin option because more than one test name was specified with --servers option"
  fi
  if [ -n "$OPT_SERVER_LANG" ]; then 
    usage "You can't use --server-lang option because more than one test name was specified with --servers option"
  fi
else
  show_msg "Checks ...." -n

  if [ -n "$OPT_SERVER_ID" ]; then SERVER_ID=$OPT_SERVER_ID; fi
  if [ -n "$OPT_SERVER_CNF" ]; then SERVER_CNF=$OPT_SERVER_CNF; fi
  #FIXME: 
  #
  # Check -f $OPT_SERVER_CNF
  # Check -f $OPT_SERVER_BIN
  # Check -d $OPT_SERVER_LANG
  #
fi

if [ -n "$VERBOSE" ]; then 
  show_msg "AUTOBENCH_BASEDIR:      $AUTOBENCH_BASEDIR"
  show_msg "AUTOBENCH_DATADIR:      $AUTOBENCH_DATADIR"
  show_msg "AUTOBENCH_SERVERDIR:    $AUTOBENCH_SERVERDIR" 
  show_msg "AUTOBENCH_SERVERCNFDIR: $AUTOBENCH_SERVERCNFDIR"
  show_msg "AUTOBENCH_TESTBASEDIR:  $AUTOBENCH_TESTBASEDIR"
  show_msg "AUTOBENCH_RESULTDIR:    $AUTOBENCH_RESULTDIR"
  show_msg "AUTOBENCH_BACKUP_BASEDIR:    $AUTOBENCH_BACKUP_BASEDIR"
  show_msg "AUTOBENCH_TMPDIR:       $AUTOBENCH_TMPDIR" 
  show_msg ""
  show_msg "MYSQLD_BASEDIRS:        $SERVERDIRS"
  show_msg "ENGINES:                $OPT_ENGINE"
  show_msg "SET OF TESTS:           $TEST_SET"
  show_msg ""
fi

show_msg "Done"

for TEST in $TEST_SET ; do 

  #Reset_test_defaults
  . $AUTOBENCH_BASEDIR/ab_test-defaults.cnf

  #Set host specific variables
  ENV="$HOSTNAME.env"
  if [[ -n $OPT_ENV_FILE && -f $OPT_ENV_FILE ]]; then 
    . $OPT_ENV_FILE
  elif [[ -f $AUTOBENCH_BASEDIR/$ENV ]]; then 
    . $ENV
  elif [[ -f $AUTOBENCH_BASEDIR/ab-default.env ]]; then 
    . $AUTOBENCH_BASEDIR/ab-default.env
  fi

  parse_test_parameters $TEST

#  echo "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="
#  echo "                           TEST:  $AUTOBENCH_TEST_NAME"
#  echo "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="
#  echo 

  if [ -n "$AUTOBENCH_TEST_CNF" ] ; then 
    if [ -f "$AUTOBENCH_TEST_CNF" ] ; then 
      TEST_CNF="$AUTOBENCH_TEST_CNF"
      TEST_CNF_DIR=$(echo "`cd \` dirname $TEST_CNF\` ; pwd`")
    else
      usage "Can't find autobench test config file $AUTOBENCH_TEST_CNF"
    fi
  else
    #Check existence of test configuration file
    TEST_CNF=$(find_file "${AUTOBENCH_TEST_NAME}.cnf ${AUTOBENCH_TESTCNFDIR}/${AUTOBENCH_TEST_NAME}.cnf")
    if [ -z "$TEST_CNF" ]; then
      show_msg "ERROR: Can't find config file $AUTOBENCH_TEST_NAME.cnf for test $AUTOBENCH_TEST_NAME. Skipping this test"
      continue
    fi
  fi

  show_msg_date "autobench#> Loading/adjusting parameters for config file: $TEST_CNF" 

  #Load settings/defaults from the test scenario file
  set -e > /dev/null 2>&1
  . $TEST_CNF
  set +e  > /dev/null 2>&1
  
  run_hook test_setup

  #Apply global autobench parameters from command line
  set_autobench_parameters

  #Apply test specific parameters from command line
  set_test_parameters

#  check_mysql_settings
  check_test_settings

  TEST_RESULTS_DIR_LIST=""
  TEST_FAILED_LIST=""
  TEST_OK_LIST=""

  #Parse and substitute parameters of mode option
  if [ -n "$MODE" ]; then 
    parse_test_mode_parameters $MODE
  fi
  check_test_mode_parameters
  
  show_msg_date "autobench#> Done"

  show_msg_date "autobench:test suite#> Going to run tests from test suite: $TEST_NAME"
  show_msg_date "autobench:test suite#> =============================================="
  [ -n "$TEST_CASES" ] && show_msg_date "autobench:test suite#> List of test cases: $TEST_CASES" 
  show_msg_date "autobench:test suite#> Threads: $THREADS"
  show_msg_date "autobench:test suite#> Iterations: $ITERATIONS"  
  show_msg_date "autobench:test suite#>"
  show_msg

  for MYSQLD_BASEDIR in $SERVERDIRS ; 
  do 
    if [ "$MYSQLD_BASEDIR" == "EXTERN" ] ; then 
      show_msg_date "autobench:MySQL server#> Going to run test against running server:$MYSQLD_BASEDIR "
      check_mysql_settings
    else
      show_msg_date "autobench:MySQL server#> Going to run test against server from $MYSQLD_BASEDIR "
      check_mysql_settings
    fi
#    show_msg ""
    show_msg_date "autobench:MySQL server#> =========================================================="
    show_msg_date "autobench:MySQL server settings#> DB=$SERVER_DB:HOST=$SERVER_HOST:SOCKET=$SERVER_SOCKET:PORT=$SERVER_PORT:USER=$SERVER_USER"
    show_msg ""

    # Engine name should be explicitly specified either with command line 
    # or in test scenario file. Error otherwise
    if [[ -z $ENGINE ]] ; then 
      usage "ERROR: Define at least one engine"
    fi

    TEST_RUN_NR=1
  
    for TEST_DB_ENGINE in ${ENGINE} ; do 
 
       parse_test_engine_parameters $TEST_DB_ENGINE

       show_msg_date "autobench:Engine#> Going to run test for engine: $ENGINE_NAME"
       show_msg_date "autobench:Engine#> ==========================================="
       show_msg_date "autobench:Engine settings#> Defaults file:         $ENGINE_DEFAULTS_FILE"
       show_msg_date "autobench:Engine settings#> Engine args:           $ENGINE_ARGS"       
       show_msg_date "autobench:Engine settings#> Engine name extension: $ENGINE_EXT"       
       show_msg_date "autobench:Engine settings#> Engine backup datadir: ${TEST_BACKUP_BASEDIR:+${TEST_BACKUP_BASEDIR}/}${ENGINE_BACKUP_DIR}"       

       #Call test_pre_run hook in test scenario file
       run_hook test_pre_run

       #Run the test
       run_test 
       if [ $? -ne 0 ]; 
       then 
         show_msg_date ""
         show_msg_date "ERROR: Got CRITICAL ERROR during test run $?"
         show_msg_date "ERROR: Skipping all remain tests for engine $ENGINE_NAME"
         show_msg_date ""
         #FIXME: Handle result codes here 
       fi

       #Call test_pre_run hook in test scenario file
       run_hook test_post_run

       TEST_RUN_NR=$(($TEST_RUN_NR + 1))
    done ;
  done ;

  #TODO: Improve/extend REPORT stage
  show_msg "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="
  show_msg "                           Results of test $TEST_NAME"
  show_msg "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="
  for TEST_RESULT_DIR in $TEST_RESULTS_DIR_LIST
  do 
    show_msg $TEST_RESULT_DIR
  done 

  if [ -n "$TEST_OK_LIST" ]; then 
    show_msg "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="
    show_msg "                 Results of test $TEST_NAME that finished successfully             "
    show_msg "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="

    for TEST_OK in $TEST_OK_LIST
    do 
      show_msg $TEST_OK
    done 
  fi

  NUMBER_OF_FAILED_TESTS=0
  if [ -n "$TEST_FAILED_LIST" ]; then 
    show_msg "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="
    show_msg "                 Results of test $TEST_NAME that had failures             "
    show_msg "=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#="

    for TEST_FAILED in $TEST_FAILED_LIST
    do 
      show_msg $TEST_FAILED
      NUMBER_OF_FAILED_TESTS=$((NUMBER_OF_FAILED_TESTS + 1))
    done 
    
    [ $NUMBER_OF_FAILED_TESTS -gt 255 ] && NUMBER_OF_FAILED_TESTS=255

  fi 

done ;

exit $NUMBER_OF_FAILED_TESTS

# order in which parameters are overrided 
# defaults < parameters from test scenario file < module_file <  global parameters < test specific parameters
# MYSQL_*  < MYSQL_* from test file < global

# test=/tmp/dbt2.cnf:engine=myisam,defaults-file=myisam.cnf,option2,option3:mode=restore,run  
# test=sysbench 
# test=mysql-bench 
# engine=innodb:defaults-file=innodb.cnf,innodb_option1,innodb_option2
# server=/data0/server1:defaults-file=1   

#TODO: Add support of presets: config files where it will be possible to specify all 
#      details how to run set of tests as with command line options. So it will be 
#      possible to run script 
#      like:
#      ./autobench --preset=5.0-release-testing --server=<server dir list>  or 
#      ./autobench --preset=5.1vs6.0-oltp_tests --server=<server dir list>

#TODO: Extend server option with 'bin' prefix to allow specify exact binary 
#      that should be used to start server:
#      --server=/data0/mysql-dir-1:bin=<binary here>. 

#TODO: check --test and --engine options and detect cases when wrong separator 
#      was used

#TODO: In case of error send/trap signal and notify autobench owners afrewards

#TODO: Finish with warmup mode that should allow to specify workload that will run before
#      the test

#TODO: Add support for the engine plugins. It can be now resolved with installing 
#      of plugin in one of the hooks but better solution will be extending of 
#      --engine option.

#TODO: Merge 'inlcude' related stuff from experimental tree

#TODO: Merge module separation stuff when all modules will have own namespace
#      this needs to remove hacks for warmup and bg_task stages 
