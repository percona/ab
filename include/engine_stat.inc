#!/bin/bash
########################################################################
#
#   Autobench test configuration file for dbt2 test
#
########################################################################


engine_stat.setup()
{

if [ "$ENGINE_NAME" == "INNODB" ]; then 

echo
echo "INNODB MONITORING=$IMONITOR"
echo

if [ -n "$IMONITOR" ]; then 

if [ -z "$IMONITOR_SLEEP_DELAY" ]; then 
  IMONITOR_SLEEP_DELAY=30
fi

echo "Starting InnoDB monitor thread in background: $TEST_OUTDIR/innodb-monitor.out $$"

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
  echo "DUMP_DATE=$output_date INTERVAL: $diff $$" >> $TEST_OUTDIR/innodb-monitor.out
  echo "$output" >>$TEST_OUTDIR/innodb-monitor.out
  echo  >>$TEST_OUTDIR/innodb-monitor.out
  ok_date=$output_date
fi
sleep $IMONITOR_SLEEP_DELAY
done

)&
        
MONITOR_PID=$!
echo $MONITOR_PID
              
fi
fi

if [ "$ENGINE_NAME" == "PBXT" ]; then

echo
echo "PBXT MONITORING=$PMONITOR"
echo

if [ -n "$PMONITOR" ]; then
echo "Starting PBXT  monitor thread in background: $TEST_OUTDIR/pbxt-monitor.out"

#(
#trap 'echo "Got TERM signal.";   exit ' TERM
#trap 'echo "Got INT signal.";   exit ' INT
nohup /data0/ranger/5.1.43-pbxt1.0.10g/bin/xtstat -d pbxt -D5 > $TEST_OUTDIR/pbxt-monitor.out  &

#) &  


MONITOR_PID=$!

echo $MONITOR_PID
fi
fi
}

engine_stat.stop()
{
if [ -n "$IMONITOR" -o -n "$PMONITOR" ]; then

  if [ -n "$MONITOR_PID" ]; then 
    echo "Killing $MONITOR_PID I:$IMONITOR P:$PMONITOR"
    kill -15 $MONITOR_PID
    MONITOR_PID=""
  fi
fi
}



engine_stat.pse_start()
{

if [ -z "$PSE_VAR_NEW" ]; then 

EVENTS_WAITS_SUMMARY_BY_EVENT_NAME=EVENTS_WAITS_SUMMARY_BY_EVENT_NAME
FILE_SUMMARY_BY_INSTANCE=FILE_SUMMARY_BY_INSTANCE
FILE_SUMMARY_BY_EVENT_NAME=FILE_SUMMARY_BY_EVENT_NAME
EVENTS_WAITS_SUMMARY_GLOBAL_BY_EVENT_NAME=EVENTS_WAITS_SUMMARY_GLOBAL_BY_EVENT_NAME
EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME=EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME
EVENTS_WAITS_SUMMARY_BY_INSTANCE=EVENTS_WAITS_SUMMARY_BY_INSTANCE
PERFORMANCE_TIMERS=PERFORMANCE_TIMERS
SETUP_CONSUMERS=SETUP_CONSUMERS
SETUP_INSTRUMENTS=SETUP_INSTRUMENTS
SETUP_TIMERS=SETUP_TIMERS
RWLOCK_INSTANCES=RWLOCK_INSTANCES
MUTEX_INSTANCES=MUTEX_INSTANCES
EVENTS_WAITS_HISTORY=EVENTS_WAITS_HISTORY

else

MUTEX_INSTANCES=mutex_instances
RWLOCK_INSTANCES=rwlock_instances
SETUP_TIMERS=setup_timers
SETUP_INSTRUMENTS=setup_instruments
SETUP_CONSUMERS=setup_consumers
PERFORMANCE_TIMERS=performance_timers
EVENTS_WAITS_SUMMARY_BY_INSTANCE=events_waits_summary_by_instance
EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME=events_waits_summary_global_by_event_name
FILE_SUMMARY_BY_EVENT_NAME=file_summary_by_event_name
FILE_SUMMARY_BY_INSTANCE=file_summary_by_instance
EVENTS_WAITS_SUMMARY_BY_EVENT_NAME=events_waits_summary_by_event_name
EVENTS_WAITS_HISTORY=events_waits_history

fi



P_S=""
P_S=`mysql -uroot -e"show variables like 'performance_schema'" -sss | grep ON`

if [ -n "$P_S" ]; then 

echo
echo "PSE MONITORING ON: PSE_MODE: '$PSE_MODE' PSE_TYPE: '$PSE_TYPE' PSE_CONSUMER_MODE: '$PSE_CONSUMER_MODE'"
echo

#DISABLE AND RESET PSE
mysql -f -vvv $MYSQL_ARGS >> $TEST_OUTDIR/test_stage_run_pre.out << SQL1EOF

UPDATE performance_schema.$SETUP_INSTRUMENTS SET ENABLED = 'NO';
UPDATE performance_schema.$SETUP_CONSUMERS  set enabled='NO';

truncate table  performance_schema.$EVENTS_WAITS_CURRENT;                          
truncate table  performance_schema.$EVENTS_WAITS_HISTORY;                         
truncate table  performance_schema.$EVENTS_WAITS_HISTORY_LONG;                    
truncate table  performance_schema.$$EVENTS_WAITS_SUMMARY_BY_EVENT_NAME;
truncate table  performance_schema.$EVENTS_WAITS_SUMMARY_GLOBAL_BY_EVENT_NAME;
truncate table  performance_schema.$EVENTS_WAITS_SUMMARY_BY_INSTANCE;             
truncate table  performance_schema.$EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME;
truncate table  performance_schema.$FILE_SUMMARY_BY_EVENT_NAME;                   
truncate table  performance_schema.$FILE_SUMMARY_BY_INSTANCE;        
SQL1EOF

#ENABLE PSE_INSTRUMENTS

#UPDATE performance_schema.SETUP_INSTRUMENTS  set enabled='YES', timed='YES' where NAME like '%wait/synch/mutex/sql/LOCK_open%';
#UPDATE performance_schema.SETUP_INSTRUMENTS  set enabled='YES', timed='YES' where NAME like '%wait/synch/mutex/sql/MDL%';
#UPDATE performance_schema.SETUP_INSTRUMENTS  set enabled='YES', timed='YES' where NAME like '%wait/synch/rwlock/sql/MDL%';

#PSE_MODE=$1
#PSE_TYPE=$2

#CONSTRUCT PSE_COND

if [ -n "$PSE_MODE" -a -n "$PSE_TYPE" ]; then 

join_cond="or"
prefix_cond=""
pse_mode=""
PSE_COND=""
exclude_cond=""
if [ $PSE_MODE == "ALL" ]; then
 pse_mode="%"
elif [ $PSE_MODE == "INNODB" ]; then
 pse_mode="innodb"
elif [ $PSE_MODE == "ALL_NOT_INNODB" ]; then
 join_cond="and"
 prefix_cond="not"
 pse_mode="%"
 exclude_cond="and NAME not like 'wait/%/%/innodb/%'"
else
  echo "PSE_MODE=$PSE_MODE WRONG PSE_MODE=$PSE_MODE"
  exit 255
fi
save_ifs="$IFS"
IFS=","
for pse_type in $PSE_TYPE ; do
if [ "$pse_type" == "ALL" ]; then
#  PSE_COND=" NAME $prefix_cond like 'wait/synch/%/$pse_mode/%' $join_cond NAME $prefix_cond like 'wait/io/file/$pse_mode/%'"
  PSE_COND=" NAME like 'wait/%/%/$pse_mode/%'"
elif [ $pse_type == "mutex" -o $pse_type == "rwlock" -o $pse_type == "cond" ]; then
  if [ -z "$PSE_COND" ]; then
#    PSE_COND=" NAME $prefix_cond like 'wait/synch/$pse_type/$pse_mode/%'"
    PSE_COND=" NAME like 'wait/synch/$pse_type/$pse_mode/%'"
  else
#    PSE_COND="$PSE_COND $join_cond NAME $prefix_cond like 'wait/synch/$pse_type/$pse_mode/%'"
     PSE_COND="$PSE_COND or NAME like 'wait/synch/$pse_type/$pse_mode/%'"
  fi
elif [ $pse_type == "io" ]; then
  if [ -z "$PSE_COND" ]; then
    PSE_COND=" NAME like 'wait/io/file/$pse_mode/%'"
  else
#    PSE_COND="$PSE_COND $join_cond NAME $prefix_cond like 'wait/io/file/$pse_mode/%'"
    PSE_COND="$PSE_COND or NAME like 'wait/io/file/$pse_mode/%'"
  fi
else
  echo "PSE_TYPE=$PSE_TYPE WRONG pse_type=$pse_type"
  exit 255
fi
done
IFS="$save_ifs"

if [ -n "$exclude_cond" ]; then 
  PSE_COND="( $PSE_COND ) $exclude_cond"
fi


mysql -vvv $MYSQL_ARGS >> $TEST_OUTDIR/test_stage_run_pre.out << SQL1EOF
UPDATE performance_schema.$SETUP_INSTRUMENTS SET ENABLED = 'YES' where $PSE_COND
SQL1EOF

fi

#ENABLE PSE_CONSUMERS
if [ -n "$PSE_CONSUMER_MODE" ]; then 

if [ $PSE_CONSUMER_MODE = "CURRENT" ]; then 
PSE_CONSUMERS_COND="where name='EVENTS_WAITS_CURRENT'"
elif [ $PSE_CONSUMER_MODE = "BIGBANG" ]; then
PSE_CONSUMERS_COND=""
else
echo "PSE_CONSUMERS_COND=$PSE_CONSUMER_MODE WRONG PSE_CONSUMERS_COND=$PSE_CONSUMER_MODE"
fi

mysql -vvv $MYSQL_ARGS >> $TEST_OUTDIR/test_stage_run_pre.out << SQL1EOF
UPDATE performance_schema.$SETUP_CONSUMERS  set enabled='YES' $PSE_CONSUMERS_COND;
SQL1EOF
fi
 
#REMAIN PSE_INITIALIZATION
mysql -f -vvv $MYSQL_ARGS >> $TEST_OUTDIR/test_stage_run_pre.out << SQL1EOF

UPDATE performance_schema.$SETUP_TIMERS   set timer_name='CYCLE';
select max(TIMER_START) from performance_schema.$EVENTS_WAITS_HISTORY into @marker_begin;
select @marker_begin;


select version();
show engine performance_schema status;
show variables like "performance%";
show status like "performance%";

select * from performance_schema.$PERFORMANCE_TIMERS;
select * from performance_schema.$SETUP_CONSUMERS;
select * from performance_schema.$SETUP_INSTRUMENTS;
select * from performance_schema.$SETUP_TIMERS;
SQL1EOF

PSE_LOST=`grep lost $TEST_OUTDIR/test_stage_run_pre.out | grep -v "| 0"`
if [ -n "$PSE_LOST" ]; then 
 show_msg ""
 show_msg "================================================================================="
 show_msg "WARNING: Lost PSE instruments detected on START"
 show_msg "$PSE_LOST" 
 show_msg "================================================================================="
 show_msg ""
fi

fi 
}


engine_stat.pse_stop()
{

if [ -n "$P_S" ]; then 


mysql -f -vvv $MYSQL_ARGS >> $TEST_OUTDIR/test_stage_run_post.out << SQL2EOF

UPDATE performance_schema.$SETUP_INSTRUMENTS SET ENABLED = 'NO';

select max(TIMER_START) from performance_schema.$EVENTS_WAITS_HISTORY into @marker_end;
select @marker_end;


show engine performance_schema status;
show variables like "performance%";
show status like "performance%";

select * from performance_schema.$PERFORMANCE_TIMERS;
select * from performance_schema.$SETUP_CONSUMERS;
select * from performance_schema.$SETUP_INSTRUMENTS;
select * from performance_schema.$SETUP_TIMERS;
SQL2EOF

PSE_LOST=`grep lost $TEST_OUTDIR/test_stage_run_pre.out | grep -v "| 0"`
if [ -n "$PSE_LOST" ]; then 
 show_msg ""
 show_msg "================================================================================="
 show_msg "WARNING: Lost PSE instruments detected on STOP"
 show_msg "$PSE_LOST" 
 show_msg "================================================================================="
 show_msg ""
fi


#mysql $MYSQL_ARGS -vvvv performance_schema \
#-e ' select THREAD_ID, EVENT_ID, EVENT_NAME, TIMER_WAIT, SOURCE, TIMER_START, OBJECT_INSTANCE_BEGIN, OPERATION from EVENTS_WAITS_HISTORY_LONG order by TIMER_START asc' > $TEST_OUTDIR/pse.EWHL.out

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select sum(count_star) from $EVENTS_WAITS_SUMMARY_BY_EVENT_NAME" > $TEST_OUTDIR/pse.SUM_EVENT_COUNT;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select sum(count_star) from $EVENTS_WAITS_SUMMARY_GLOBAL_BY_EVENT_NAME" > $TEST_OUTDIR/pse.SUM_EVENT_GLOBAL_COUNT;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * from $EVENTS_WAITS_SUMMARY_BY_EVENT_NAME order by SUM_TIMER_WAIT desc" > $TEST_OUTDIR/pse.SUM_EVENT_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * from $EVENTS_WAITS_SUMMARY_GLOBAL_BY_EVENT_NAME order by SUM_TIMER_WAIT desc" > $TEST_OUTDIR/pse.SUM_EVENT_GLOBAL_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * from $EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME order by SUM_TIMER_WAIT desc " > $TEST_OUTDIR/pse.SUM_THREAD_EVENT_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * from $EVENTS_WAITS_SUMMARY_BY_INSTANCE order by SUM_TIMER_WAIT desc" > $TEST_OUTDIR/pse.SUM_INSTANCE;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select THREAD_ID, SUM(COUNT_STAR), SUM(SUM_TIMER_WAIT) from $EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME group by THREAD_ID" >> $TEST_OUTDIR/pse.MISC;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * FROM $MUTEX_INSTANCES " >> $TEST_OUTDIR/pse.MUTEX;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * FROM $RWLOCK_INSTANCES " >> $TEST_OUTDIR/pse.RW_LOCK;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * from performance_schema.$FILE_SUMMARY_BY_EVENT_NAME" > $TEST_OUTDIR/pse.FILE_SUM_EVENT_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e "select * from performance_schema.$FILE_SUMMARY_BY_INSTANCE" > $TEST_OUTDIR/pse.FILE_SUM_INSTANCE;

fi

}

