#!/bin/bash

# load_db_mysql.sh

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
    file=`basename $file`
    for dir in $PATH
    do
      if test -f $dir/$file
      then
        echo "$dir/$file"
        continue 2
      fi
    done
    echo "Fatal error: Cannot find program $file in $PATH" 1>&2
    exit 1
  done
  IFS="$save_ifs"
  exit 0
}

usage() {

  if [ "$1" != "" ]; then
    echo ''
    echo "error: $1"
  fi

  echo ''
  echo 'usage: mysql_load_db.sh [options]'
  echo 'options:'
  echo '       --db-name <database name>'
  echo '       --sysbench-bin=<sysbench binary>'
  echo '       --sysbench-args=<sysbench arguments>'
  echo '       --mysql-bin=<mysql binary>'
  echo '       --mysql-args=<mysql arguments>'
  echo ''
  echo 'Example: sh load_db.sh --db-name sysb10000 --sysbench-bin=sysbench-0.5.0 --mysql-bin=mysql'
  echo ''
}

command_exec()
{
  if [ -n "$VERBOSE" ]; then
    echo "Executed command: $1"
  fi

  eval "$1"

  rc=$?
  if [ $rc -ne 0 ]; then
   echo "ERROR: rc=$rc"
   case $rc in
     127) echo "COMMAND NOT FOUND"
          ;;
       *) echo "SCRIPT INTERRUPTED"
          ;;
    esac
    exit 255
  fi
}

#DEFAULTs
DB_NAME=""
ECHO=echo
SED=`which sed`


while test $# -gt 0; do
  case "$1" in
    --db-name=*)
      DB_NAME=`$ECHO "$1" | $SED -e "s;--db-name=;;"`   ;;
    --mysql-bin=*)
      MYSQL_BIN=`$ECHO "$1" | $SED -e "s;--mysql-bin=;;"`   ;;          
    --mysql-args=*)
      MYSQL_ARGS=`$ECHO "$1" | $SED -e "s;--mysql-args=;;"`   ;;          

    --sysbench-bin=*)
      SYSBENCH_BIN=`$ECHO "$1" | $SED -e "s;--sysbench-bin=;;"`   ;;          
    --sysbench-args=*)
      SYSBENCH_ARGS=${SYSBENCH_ARGS}" "`$ECHO "$1" | $SED -e "s;--sysbench-args=;;"`   ;;          
    -- )  shift; break ;;
    --*) $ECHO "Unrecognized option: $1" ; usage ;;
    * ) break ;;
  esac
  shift
done
         
if [ "$DB_NAME" == "" ]; then
  usage "specify database name using --db-name=<db_name> "
  exit 1
fi

MYSQL=$(find_file "${MYSQL_BIN} `which ${MYSQL_BIN}`")
SYSBENCH=$(find_file "${SYSBENCH_BIN} `which ${SYSBENCH_BIN}`")

if [ ! -f "$MYSQL" ]; then
  usage "MySQL client binary '$MYSQL_BIN' not exists.
       Please adjust PATH variable or specify correct one using --mysql-bin #"
  exit 1
fi

if [ ! -f "$SYSBENCH" ]; then
  usage "Sysbench binary '$SYSBENCH_BIN' not exists.
       Please adjust PATH variable or specify correct one using --sysbench-bin #"
  exit 1
fi


echo ""
echo "Loading of sysbench dataset to database $DB_NAME."
echo ""
echo "SYSBENCH_BIN:      $SYSBENCH"
echo "SYSBENCH_ARGS:     $SYSBENCH_ARGS"
echo "MYSQL_BIN:         $MYSQL"
echo "MYSQL_ARGS:        $MYSQL_ARGS"

MYSQL="$MYSQL $MYSQL_ARGS"
SYSBENCH="$SYSBENCH $SYSBENCH_ARGS"

command_exec "$MYSQL -e \"drop database if exists $DB_NAME\" "
command_exec "$MYSQL -e \"create database $DB_NAME\" "

# Load data
echo ""
command_exec "$SYSBENCH"
