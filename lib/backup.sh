#!/bin/bash

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
  echo 'test-backup.sh: script that helps backup/restore mysql database(s)'
  echo ''
  echo 'usage: test-backup.sh [options]'
  echo 'options:'
  echo '       --db=<database name(s)>'
  echo '       --mysqldump-bin=<mysqldump binary>'
  echo '       --mysqldump-args=<mysqldump arguments>'
  echo '       --mysql-bin=<mysql binary>'
  echo '       --mysql-args=<mysql arguments>'
  echo '       --dump-mode=<backup|restore|dump|restore_dump|ibackup|xbackup>'
  echo '       --dump-file=<filename of dump(backup image)>'
  echo '       --backup-dir=<directory where to store backup'
  echo '       --ibackup-bin=<ibbackup binary>'
  echo '       --ibackup-args=<ibbackup arguments>'
  echo '       --ibackup-helper=<innobackup script>'  
  echo ''
  echo 'Example: sh test-backup.sh --db=test --mysql-bin=mysql --dump-mode=backup --dump-file=/tmp/test-dump.img'
  echo ''

  if [ "$2" != "" ]; then 
    exit $2
  fi
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


backup_with_mysql_backup()
{
  echo ''
  echo "Performing backup of database(s) $BACKUP_DB with mysql backup to file $DUMP_FILE"
  echo ''

  command_exec "$MYSQL $MYSQL_ARGS -vvv -e\"backup database $BACKUP_DB to '$DUMP_FILE';show warnings\""
  echo  "Dump size:" $(ls -skh $DUMP_FILE)
}

restore_with_mysql_restore()
{
  STMT_OPTION=$1

  echo ''
  echo "Performing restore of database(s) from mysql backup image file $DUMP_FILE"
  echo ''
  
  command_exec "$MYSQL $MYSQL_ARGS -vvv -e\"restore from '$DUMP_FILE' $STMT_OPTION;show warnings\""
}

backup_with_mysqldump()
{
  echo ''
  echo "Performing backup of database(s) $BACKUP_DB with mysqldump to file $DUMP_FILE"
  echo ''
  
  if [ ! -f "$DUMP_FILE" ] ; then 
    command_exec "$MYSQLDUMP $MYSQL_ARGS $MYSQLDUMP_ARGS  -vvv --databases $BACKUP_DB  2>&1 > $DUMP_FILE"
    echo  "Dump size:" $(ls -skh $DUMP_FILE)
  else
    usage "Dump file $DUMP_FILE already exists" 1
  fi
}

restore_with_mysql()
{
  echo ''
  echo "Performing restore of database(s) from mysqldump file $DUMP_FILE"
  echo ''
  
  command_exec "$MYSQL $MYSQL_ARGS -B  2>&1 < $DUMP_FILE "
}

backup_with_copy()
{
  local SRC_DIR=$1
  local DST_DIR=$2
  if [ -e "$SRC_DIR"  -a -e "$DST_DIR" ]; then 
    cp -Rf $SRC_DIR $DST_DIR  2>&1
  else
    echo "ERROR: Either src $SRC_DIR or dst $DST_DIR are not accessable"
  fi
}


create_ibackup_cnf()
{
for p in innodb_data_file_path innodb_data_home_dir innodb_log_group_home_dir \
         datadir innodb_log_files_in_group innodb_log_file_size socket port ; do

  val=`$MYSQL $MYSQL_ARGS  -e"show variables like '$p'" -sss|sed -e 's/.*\t\(.*$\)/\1/'`
  pp="IBACKUP_$p"
  eval "$pp=$val"
  echo "$pp - Value ${!pp}"
done

if [[ -z "$IBACKUP_innodb_data_home_dir" ]]; then
  IBACKUP_innodb_data_home_dir="$IBACKUP_datadir"
fi

if [[ "$IBACKUP_innodb_log_group_home_dir" = "./" ]]; then
  IBACKUP_innodb_log_group_home_dir="$IBACKUP_datadir"
fi
echo
echo
echo

tmp_file=`mktemp tmp.cnf.XXXXXX`
if [ $? -ne 0 ]; then
  echo "lib/backup.sh: Can't create temporary file with mktemp"
  exit
fi

#echo "TMP: $tmp_file"

echo "#temporary cnf file for IHB" >> $tmp_file
echo "[mysqld]" >> $tmp_file

for p in innodb_data_file_path innodb_data_home_dir innodb_log_group_home_dir \
         datadir innodb_log_files_in_group innodb_log_file_size ; do
 pp="IBACKUP_$p"
 echo "$p = ${!pp}" >> $tmp_file
done

echo "[mysql]" >>  $tmp_file
echo "socket=$IBACKUP_socket" >> $tmp_file
echo "user=root" >> $tmp_file
echo "port=$IBACKUP_port" >>  $tmp_file

IBACKUP_CNF=$tmp_file

}
                 

backup_with_ibackup()
{
echo 
echo "Starting innobackup:"
echo 

BACKUP_START_TIME=$(date +%s)

create_ibackup_cnf
if [ -n "$IBACKUP_socket" ]; then 
  IHBACKUP_ARGS="$IHBACKUP_ARGS --socket=${IBACKUP_socket}"
fi
echo "$INNOBACKUP --ibbackup=$IBBACKUP --databases=$BACKUP_DB $IHBACKUP_ARGS $IBACKUP_CNF $BACKUP_DIR"
$INNOBACKUP --ibbackup=$IBBACKUP --databases=$BACKUP_DB $IHBACKUP_ARGS $IBACKUP_CNF $BACKUP_DIR 2>&1 | tee $BACKUP_DIR/lsn.out

LSN=""

LSN=`grep "Was able" $BACKUP_DIR/lsn.out| egrep -o \[0123456789\]\+`

if [ -z "$LSN" ]; then 
  LSN=`grep "changes from lsn" $BACKUP_DIR/lsn.out | egrep -o 'to lsn [0123456789]+' | egrep -o '[0123456789]+'`
fi

echo  "LSN: $LSN"
if [ -z $LSN ]; then
exit 1;
fi
echo  "Dump size:" $(du -skh $BACKUP_DIR)
ELAPSED_TIME=$((`date +%s`-$BACKUP_START_TIME))
echo  "Backup time: $ELAPSED_TIME"

rm -f $IBACKUP_CNF
}

backup_with_ibackup_incremental()
{

for param in $IHBACKUP_INC_ARGS ; do
    param=$(echo "$param" | sed -e "s;^--;;")
  case "$param" in
    inc-interval=*)
      IBACKUP_INC_INTERVAL=$(echo "$param" | sed -e "s;inc-interval=;;")
    ;;
    inc-lsn=*)
      IBACKUP_INC_LSN=$(echo "$param" | sed -e "s;inc-lsn=;;")
    ;;
    inc-count=*)
      IBACKUP_INC_COUNT=$(echo "$param" | sed -e "s;inc-count=;;")
    ;;
  esac
done

echo "innobackup incremental with interval $IBACKUP_INC_INTERVAL count $IBACKUP_INC_COUNT"

if [ $DUMP_MODE == "ibackup-inc" ]; then 
  #create initial full backup 
  backup_with_ibackup
  sleep $IBACKUP_INC_INTERVAL
else
  LSN=$IBACKUP_INC_LSN
fi

IHBACKUP_ARGS_ORIG=$IHBACKUP_ARGS

  while [ $(($IBACKUP_INC_COUNT)) -ne 0 ]; do
    echo "Creating incremental backup $IBACKUP_INC_COUNT from LSN: $LSN"

    IHBACKUP_ARGS="$IHBACKUP_ARGS_ORIG --incremental --lsn $LSN"
    backup_with_ibackup

    IBACKUP_INC_COUNT=$(( $IBACKUP_INC_COUNT-1 ))
    sleep $IBACKUP_INC_INTERVAL
  done

echo  "Dump size:" $(du -skh $BACKUP_DIR)
}



backup_with_xbackup()
{
  echo "xtrabackup"

create_ibackup_cnf
echo "$INNOBACKUP --ibbackup=$IBBACKUP --databases=$BACKUP_DB $IBACKUP_ARGS --defaults-file=$IBACKUP_CNF $BACKUP_DIR $MYSQL_ARGS"
if [ -n "$IBACKUP_socket" ]; then 
  IBACKUP_ARGS="$IBACKUP_ARGS --socket=${IBACKUP_socket}"
fi

$INNOBACKUP --ibbackup=$IBBACKUP --databases=$BACKUP_DB $IBACKUP_ARGS --defaults-file=$IBACKUP_CNF $BACKUP_DIR

rm -f $IBACKUP_CNF

}

#DEFAULTs
BACKUP_DB=""
ECHO=echo
SED=`which sed`
VERBOSE=1

MYSQL_BIN=mysql
MYSQLDUMP_BIN=mysqldump
MYSQL_ARGS=""
MYSQLDUMP_ARGS=""


while test $# -gt 0; do
  case "$1" in
    --db=*)
      BACKUP_DB=`$ECHO "$1" | $SED -e "s;--db=;;"`   ;;
    --mysql-bin=*)
      MYSQL_BIN=`$ECHO "$1" | $SED -e "s;--mysql-bin=;;"`   ;;
    --mysql-args=*)
      MYSQL_ARGS=`$ECHO "$1" | $SED -e "s;--mysql-args=;;"`   ;;
    --mysqldump-bin=*)
      MYSQLDUMP_BIN=`$ECHO "$1" | $SED -e "s;--mysqldump-bin=;;"`   ;;
    --mysqldump-args=*)
      MYSQLDUMP_ARGS=`$ECHO "$1" | $SED -e "s;--mysqldump-args=;;"`   ;;
    --dump-file=*)
      DUMP_FILE=`$ECHO "$1" | $SED -e "s;--dump-file=;;"`   ;;
    --dump-mode=*) 
      DUMP_MODE=`$ECHO "$1" | $SED -e "s;--dump-mode=;;"`   ;;
    --data-dir=*)
      DATA_DIR=`$ECHO "$1" | $SED -e "s;--data-dir=;;"`   ;;
    --backup-dir=*)
      BACKUP_DIR=`$ECHO "$1" | $SED -e "s;--backup-dir=;;"`   ;;
    --ibackup-bin=*)
      IHBACKUP_BIN=`$ECHO "$1" | $SED -e "s;--ibackup-bin=;;"`   ;;
    --ibackup-args=*)
      IHBACKUP_ARGS=`$ECHO "$1" | $SED -e "s;--ibackup-args=;;"`   ;;
    --ibackup-inc-args=*)
      IHBACKUP_INC_ARGS=`$ECHO "$1" | $SED -e "s;--ibackup-inc-args=;;"`   ;;
    --ibackup-helper=*)
      IHBACKUP_HELPER=`$ECHO "$1" | $SED -e "s;--ibackup-helper=;;"`   ;;
    -- )  shift; break ;;
    --*) usage "Unrecognized option: $1" 2 ;;
    * ) break ;;
  esac
  shift
done


MYSQL=$(find_file "${MYSQL_BIN} `which ${MYSQL_BIN}`")
MYSQLDUMP=$(find_file "${MYSQLDUMP_BIN} `which ${MYSQLDUMP_BIN}`")

echo ""
echo "DUMP_MODE:         $DUMP_MODE"
echo "DUMP_FILE:         $DUMP_FILE"
echo "MYSQLDUMP_BIN:     $MYSQLDUMP"
echo "MYSQLDUMP_ARGS:    $MYSQLDUMP_ARGS"
echo "MYSQL_BIN:         $MYSQL"
echo "MYSQL_ARGS:        $MYSQL_ARGS"

if [ -n "$DUMP_MODE" ] ; then 

  if [ "$DUMP_MODE" == "restore" -o \
       "$DUMP_MODE" == "restore_overwrite" -o \
       "$DUMP_MODE" == "restore_dump" ]; then 
     if [ -n "$DUMP_FILE" ]; then 
       if [ ! -f "$DUMP_FILE" ]; then
         usage "Dump file not found: $DUMP_FILE" 1
       fi
     else
       usage "You need to specify dump file with --dump-file option" 1
     fi
  fi

  if [ "$DUMP_MODE" == "backup" -o "$DUMP_MODE" == "dump" ]; then 
    if [ -z "$BACKUP_DB" ]; then 
       usage "You need to specify database(s) with --db option" 2
    fi
  fi

  if [ "$DUMP_MODE" == "backup" -o \
       "$DUMP_MODE" == "restore" -o \
       "$DUMP_MODE" == "restore_overwrite" -o \
       "$DUMP_MODE" == "restore_dump" ] && [ ! -f "$MYSQL" ]; then
    usage "MySQL client binary '$MYSQL' not exists.
       Please adjust PATH variable or specify correct one using --mysql-bin #" 1
  fi

  if [ "$DUMP_MODE" == "dump" -a ! -f "$MYSQLDUMP" ]; then
    usage "mysqldump binary '$MYSQLDUMP' not exists.
       Please adjust PATH variable or specify correct one using --mysqldump-bin #" 1
  fi

  echo "DUMP MODE $DUMP_MODE"

  if [ "$DUMP_MODE" == "ibackup" -o "$DUMP_MODE" == "xbackup" \
       -o "$DUMP_MODE" == "ibackup-inc" -o "$DUMP_MODE" == "ibackup-inc-only" ]; then 
     IBBACKUP=$(find_file "${IHBACKUP_BIN} `which ${IHBACKUP_BIN}`")
     INNOBACKUP=$(find_file "${IHBACKUP_HELPER} `which ${IHBACKUP_HELPER}`")
     if [ ! -d "$BACKUP_DIR" ]; then 
       usage "Backup dir '$BACKUP_DIR' not exists." 1
     fi 
     if [ ! -f "$IBBACKUP" ]; then 
       usage "Can't find IBBACKUP binary '$IHBACKUP_BIN'" 1
     fi
     if [ ! -f "$INNOBACKUP" ]; then 
       usage "Can't find INNOBACKUP helper  '$IHBACKUP_HELPER'" 1
     fi
  fi
  
  case "$DUMP_MODE" in
    backup)
         backup_with_mysql_backup ;;
    restore)
         restore_with_mysql_restore ;;
    restore_overwrite)
         restore_with_mysql_restore overwrite;;
    dump)   
         backup_with_mysqldump ;;
    restore_dump)   
         restore_with_mysql ;;
    ibackup)   
         backup_with_ibackup ;;
    ibackup-inc)   
         backup_with_ibackup_incremental ;;
    ibackup-inc-only)   
         backup_with_ibackup_incremental ;;
    xbackup)   
         backup_with_xbackup ;;
    copy)
         backup_with_copy $DATA_DIR $BACKUP_DIR ;;
    *) usage "Unrecognized/invlaid value of --dump-mode option: $DUMP_MODE" 2 ; break ;;
  esac
else
  usage "You have to specify one of dump modes: backup, restore, dump, restore_dump"  2
fi

exit 0
