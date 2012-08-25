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

echo "Starting InnoDB monitor thread in background: $TEST_OUTDIR/innodb-monitor.out"

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
sleep $IMONITOR_SLEEP_DELAY
done

)&
        
MONITOR_PID=$!
              
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

P_S=""
P_S=`mysql $MYSQL_ARGS -uroot -e"show variables like 'performance_schema'" -sss | grep ON`

if [ -n "$P_S" ]; then 

echo
echo "PSE MONITORING ON"
echo

mysql -vvv $MYSQL_ARGS -S /tmp/mysql.sock  >> $TEST_OUTDIR/test_stage_run_pre.out << SQL1EOF

UPDATE performance_schema.SETUP_INSTRUMENTS SET ENABLED = 'NO';

truncate table  performance_schema.EVENTS_WAITS_CURRENT;                          
truncate table  performance_schema.EVENTS_WAITS_HISTORY;                         
truncate table  performance_schema.EVENTS_WAITS_HISTORY_LONG;                    
truncate table  performance_schema.EVENTS_WAITS_SUMMARY_BY_EVENT_NAME;
truncate table  performance_schema.EVENTS_WAITS_SUMMARY_BY_INSTANCE;             
truncate table  performance_schema.EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME;
truncate table  performance_schema.FILE_SUMMARY_BY_EVENT_NAME;                   
truncate table  performance_schema.FILE_SUMMARY_BY_INSTANCE;        

UPDATE performance_schema.SETUP_INSTRUMENTS SET ENABLED = 'YES';

#UPDATE performance_schema.SETUP_INSTRUMENTS  set enabled='YES', timed='YES' where NAME like '%wait/synch/mutex/sql/LOCK_open%';
#UPDATE performance_schema.SETUP_INSTRUMENTS  set enabled='YES', timed='YES' where NAME like '%wait/synch/mutex/sql/MDL%';
#UPDATE performance_schema.SETUP_INSTRUMENTS  set enabled='YES', timed='YES' where NAME like '%wait/synch/rwlock/sql/MDL%';

UPDATE performance_schema.SETUP_TIMERS   set timer_name='CYCLE';

UPDATE performance_schema.SETUP_CONSUMERS   set enabled='YES';

select max(TIMER_START) from performance_schema.EVENTS_WAITS_HISTORY into @marker_begin;
select @marker_begin;


select version();
show engine performance_schema status;
show variables like "performance%";
show status like "performance%";

select * from performance_schema.PERFORMANCE_TIMERS;
select * from performance_schema.SETUP_CONSUMERS;
select * from performance_schema.SETUP_INSTRUMENTS;
select * from performance_schema.SETUP_TIMERS;
SQL1EOF

fi 
}


engine_stat.pse_stop()
{

if [ -n "$P_S" ]; then 


mysql -w 3 -vvv $MYSQL_ARGS -S /tmp/mysql.sock >> $TEST_OUTDIR/test_stage_run_post.out << SQL2EOF

UPDATE performance_schema.SETUP_INSTRUMENTS SET ENABLED = 'NO';

select max(TIMER_START) from performance_schema.EVENTS_WAITS_HISTORY into @marker_end;
select @marker_end;


show engine performance_schema status;
show variables like "performance%";
show status like "performance%";

select * from performance_schema.PERFORMANCE_TIMERS;
select * from performance_schema.SETUP_CONSUMERS;
select * from performance_schema.SETUP_INSTRUMENTS;
select * from performance_schema.SETUP_TIMERS;
SQL2EOF


#mysql $MYSQL_ARGS -vvvv performance_schema \
#-e ' select THREAD_ID, EVENT_ID, EVENT_NAME, TIMER_WAIT, SOURCE, TIMER_START, OBJECT_INSTANCE_BEGIN, OPERATION from EVENTS_WAITS_HISTORY_LONG order by TIMER_START asc' > $TEST_OUTDIR/pse.EWHL.out

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * from EVENTS_WAITS_SUMMARY_BY_EVENT_NAME order by SUM_TIMER_WAIT desc' > $TEST_OUTDIR/pse.SUM_EVENT_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * from EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME order by SUM_TIMER_WAIT desc ' > $TEST_OUTDIR/pse.SUM_THREAD_EVENT_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * from EVENTS_WAITS_SUMMARY_BY_INSTANCE order by SUM_TIMER_WAIT desc' > $TEST_OUTDIR/pse.SUM_INSTANCE;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select THREAD_ID, SUM(COUNT_STAR), SUM(SUM_TIMER_WAIT) from EVENTS_WAITS_SUMMARY_BY_THREAD_BY_EVENT_NAME group by THREAD_ID' >> $TEST_OUTDIR/pse.MISC;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * FROM MUTEX_INSTANCES ' >> $TEST_OUTDIR/pse.MUTEX;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * FROM RWLOCK_INSTANCES ' >> $TEST_OUTDIR/pse.RW_LOCK;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * from performance_schema.FILE_SUMMARY_BY_EVENT_NAME' > $TEST_OUTDIR/pse.FILE_SUM_EVENT_NAME;

mysql $MYSQL_ARGS performance_schema -vvvv \
-e 'select * from performance_schema.FILE_SUMMARY_BY_INSTANCE' > $TEST_OUTDIR/pse.FILE_SUM_INSTANCE;

fi

}

