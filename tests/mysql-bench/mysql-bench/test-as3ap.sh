#!@PERL@
# Copyright (C) 2000 MySQL AB & MySQL Finland AB & TCX DataKonsult AB
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.
#
# You should have received a copy of the GNU Library General Public
# License along with this library; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
# MA 02111-1307, USA
#
########################################################################
#
#                           AS3AP Benchmark
#
#  The ANSI SQL Standard Scalable and Portable Benchmark (AS3AP) models
#  complex and mixed workloads, including single-user and multi-user
#  tests, as well as operational and functional tests. 
#  Full specification of AS3AP Benchmark can be found in chapter 5 of 
#  "Benchmark Handbook".  http://www.benchmarkresources.com/handbook/5.html
#
#  The single-user test consists of 39 queries such as selection, join,
#  projection, aggregate, integrity, and bulk updates. These queries are
#  designed to test of the basic functions that a relational DBMS must
#  support, as defined by the ANSI SQL 2 Standard [ANSI90].
#
#  The multi-user test includes four main parts. The first is concurrent
#  random read test (information retrieval (IR) test) for execution a
#  one-row selection to get the maximum number of concurrent users the
#  system can handle retrieving the same table. The second is concurrent
#  random write test (on-line transaction processing (OLTP) test) for
#  execution a one-row update to get the number of concurrent users the
#  system can handle updating the same table. The last two (the mixed IR
#  test and the mixed OLTP test) are used to measure response time of
#  short transactions and report queries on the system under IR test or
#  OLTP test.
#
#  The test database consists of four tables. Each has the same number of
#  fields and the same number of records. The database scales up by by
#  multiplying the number of records in each table on 10. Data values are
#  created with uniform and non-uniform data distributions.
#
#############################################################################

use DBI;
use Benchmark;
use IO::Handle;
use IO::Select;
use POSIX ":sys_wait_h";
use My::Timer;

# Try to replace  standard 'time()' function with the same one from Time:HiRes package
# to get time in microseconds

BEGIN {
    eval "use Time::HiRes qw(time)";
}

chomp($pwd = `pwd`); $pwd = "." if ($pwd eq '');
require "$pwd/bench-init.pl" || die "Can't read Configuration file: $!\n";

if ($opt_debug)
{
  $,=" ";
  print "Run ",$pwd."/".$0,@ARGV,"\n";
  $,="";
}

# Setup 2 handlers to manage threads 
$SIG{USR1}= \&signal_USR1_handler;
$SIG{USR2}= \&signal_USR2_handler;

#Default behaviour - as3ap single-user test
if ($opt_as3ap_full)
{
  $opt_as3ap_single=1;
  $opt_as3ap_multi=1;
}
elsif (!$opt_as3ap_single && !$opt_as3ap_multi)
{
  $opt_as3ap_single=1;
}

#Local configuration options for multi-user test
$opt_detail_stat= 1;
$opt_skip_ir_test= 0;
$opt_skip_oltp_test= 0;

#Hash for multi_user test
my %work=();

print "Start AS3AP benchmark\n\n";

#Trying to generate as3ap files
#as3apgen(undef,0) if (!$opt_as3ap_db_size && !$opt_as3ap_no_load);


#Create tables 
#$rows_num = $opt_as3ap_no_load ? check_data() : load_data();


if (!$opt_as3ap_no_load)
{
  #Trying to generate as3ap files
  $opt_as3ap_db_size ? as3apgen($opt_as3ap_db_size, 1) : as3apgen(undef,0);

  #Create && load data into tables
  $rows_num = load_data();
}
else
{
  #Check rows number in dataset
  $rows_num = check_data();
}

if ($rows_num != 10000 && $rows_num != 100000 && $rows_num != 1000000 && $rows_num != 10000000 &&
    $rows_num != 100000000 && $rows_num != 1000000000)
{
  die "ERROR: Incorrect number of rows($rows_num) in test database."; 
}

$start_benchmark = My::Timer::get_timer();

if ($opt_as3ap_single)
{
  as3ap_single_user_test();
}

if ($opt_as3ap_multi)
{
  as3ap_multi_user_test();
}

print "Stop AS3AP benchmark\n\n";

my $end_benchmark = My::Timer::get_timer();

#Clean up as3ap files
as3ap_cleanup() if (!$opt_as3ap_no_cleanup);

print "Total time: ",My::Timer::timestr(timediff($end_benchmark, $start_benchmark),"all"),"\n\n";

#############################################################################
#
#                        AS3AP single-user benchmark.
#
#  All queries are run in standalone mode, and measuring of the elapsed
#  time performs for each operation or query.
#
#  One of part of test contains database maintenance operations such as
#  creating tables, load data from data files, bulding indices, and
#  running table scan query to test sequential I/O performance.
#
#  Another one divides on the next sections:
#    * selections - 7 queries.
#      The selections queries test the ability of the query optimizer to
#      correctly choose between a scan or the use of an index at run
#      time. Result of these queries is one row, or a range of 100 rows
#      or 10% of the rows.
#    * joins - 8 queries.
#      The join queries test how efficiently the system uses available
#      indices and how query complexity affects the relative performance
#      of the DBMS. Query complexity is modeled by increasing the number
#      of tables referenced from two to four. While the most query
#      optimizers use the correct access plan on two-way joins with
#      indices, often they not correctly optimize three and four-way
#      joins because of the higher complexity involved in evaluating all
#      the possible access methods.
#    * projections - 2 queries.
#      One query projects the hundred table on two columns, corresponding
#      to a signed integer and a variable length character columns, and
#      it produces 100 result rows. Thus it provides a test of how
#      efficiently the DBMS handles two data types in a complex operation
#      such as sorting. The second query projects on one column,
#      corresponding to a signed integer attribute, and has a 10%
#      selectivity.
#      Most of the processing time for a projection is incurred by the
#      elimination of duplicate tuples introduced when projecting on non
#      key columns. This makes the cost of a projection much higher than
#      the cost of a selection query with similar selectivity. Duplicate
#      elimination is usually performed by sorting. Thus tests of
#      projections also provide a test of the sort utility used by the
#      DBMS.
#    * aggregates - 6 queries.
#      These queries test how efficiently DBMS performs aggregative
#      functions, such as min(), max(), avg(), count().
#      Note: As MySQL currently has not some functionality (subselect,
#      view), so some queries from this section are omitted.
#    * updates - 8 queries.
#      The update queries are designed to check both integrity and
#      performance.
#      To check integrity, queries that attempt to append a row with a
#      duplicate key value are used and to evaluate performance, queries
#      that measure the overhead involved in updating index are provided.
#      Single-tuple updates and bulk updates are also provided.
#
#############################################################################

sub as3ap_single_user_test
{
  my $rc;

  my $dbh=$server->connect();

  print "Start Single-user AS3AP benchmark\n\n";
  
  my $start_test= My::Timer::get_timer();

  #
  # Selection tests
  # 
  test_query("sel_1_cl",
	     "Time to sel_as3ap",
	     "select col_key, col_int, col_signed, col_code, col_double, col_name 
 	      from updates where col_key = 1000",$dbh);

  test_query("join_3_cl",
             "Time to join_as3ap",
             "select uniques.col_signed, uniques.col_date, hundred.col_signed, 
                     hundred.col_date,  tenpct.col_signed, tenpct.col_date 
	      from uniques, hundred, tenpct 
	      where uniques.col_key = hundred.col_key and 
                    uniques.col_key = tenpct.col_key and 
                    uniques.col_key = 1000", $dbh);

  test_query("sel_100_ncl",
             "Time to sel_as3ap",
	     "select col_key, col_int, col_signed, col_code,col_double, col_name
	      from updates where col_int <= 100", $dbh);

  test_query("table_scan",
	     "Time to table_scan",
	     "select * from uniques where col_int = 1",$dbh);

  test_query("agg_func",
	     "Time for agg_as3ap",
	     "select min(col_key) from hundred group by col_name",$dbh);

  test_query("agg_scal",
	     "Time for agg_as3ap",
	     "select min(col_key) from uniques", $dbh);

  test_query("sel_100_cl",
             "Time for sel_as3ap",
	     "select col_key, col_int, col_signed, col_code, 
		  col_double, col_name 
	      from updates where col_key <= 100", $dbh);

  test_query("join_3_ncl",
	     "Time for join_as3ap",
	     "select uniques.col_signed, uniques.col_date, hundred.col_signed, 
                     hundred.col_date, tenpct.col_signed, tenpct.col_date 
              from uniques, hundred, tenpct 
              where uniques.col_code = hundred.col_code and 
                    uniques.col_code = tenpct.col_code and 
                    uniques.col_code = 'BENCHMARKS'", $dbh);

  test_query("sel_10pct_ncl",
             "Time for sel_as3ap",
             "select col_key, col_int, col_signed, col_code, col_double, col_name 
              from tenpct 
              where col_name = 'THE+ASAP+BENCHMARKS+'", $dbh);

  if ($limits->{'subqueries'})
  {
    test_query("agg_simple_report",
               "Time for agg_as3ap",
	       "select avg(updates.col_decim)  from updates 
                where updates.col_key in (
                                          select updates.col_key from updates, hundred 
			                   where hundred.col_key = updates.col_key and 
                                                 updates.col_decim > 980000000)", $dbh);
  }

  test_query("agg_info_retrieval",
             "Time for agg_as3ap",
	     "select count(col_key) 
	      from tenpct 
	      where col_name = 'THE+ASAP+BENCHMARKS' and 
                    col_int <= 100000000 and 
                    col_signed between 1 and 99999999  and 
                    not (col_float between -450000000 and 450000000) and 
                    col_double > 600000000 and 
                    col_decim < -600000000",$dbh);

  if ($limits->{'views'})
  {
    test_query("agg_create_view",
               "Time for agg_as3ap",
	       "create view reportview 
                (col_key,col_signed,col_date,col_decim, col_name,col_code,col_int) as 
                 select updates.col_key, updates.col_signed, updates.col_date, 
                 updates.col_decim, hundred.col_name, hundred.col_code, hundred.col_int 
                from updates, hundred 
		where updates.col_key = hundred.col_key",$dbh);

    test_query("agg_subtotal_report",
               "Time for agg_as3ap",
               "select avg(col_signed), min(col_signed), max(col_signed), max(col_date), 
                       min(col_date), count(distinct col_name), count(col_name), col_code, 
                       col_int 
                from reportview where col_decim >980000000 
                group by col_code, col_int",$dbh);


    test_query("agg_total_report",
	       "Time for agg_as3ap",
	       "select avg(col_signed), min(col_signed), max(col_signed), 
		     max(col_date), min(col_date), 
		     count(distinct col_name), count(col_name), 
		     count(col_code), count(col_int) 
	        from reportview 
	        where col_decim >980000000",$dbh);

    test_command("","","drop view reportview", $dbh, 0);
  }

  test_query("join_2_cl",
             "Time for join_as3ap",
             "select uniques.col_signed, uniques.col_name,
                      hundred.col_signed, hundred.col_name
               from uniques, hundred
               where uniques.col_key = hundred.col_key
                and uniques.col_key =1000"
             ,$dbh);

  test_query("join_2",
             "Time for join_as3ap",
             "select uniques.col_signed, uniques.col_name,
                       hundred.col_signed, hundred.col_name
                  from uniques, hundred
                 where uniques.col_address = hundred.col_address
                   and uniques.col_address = 'SILICON VALLEY'"
             ,$dbh);

  test_query("sel_variable_select_low",
             "Time for sel_as3ap",
             "select col_key, col_int, col_signed, col_code,
                      col_double, col_name
                      from tenpct
                      where col_signed < -500000000"
             ,$dbh);

  test_query("sel_variable_select_high",
             "Time for sel_as3ap",
             "select col_key, col_int, col_signed, col_code,
                      col_double, col_name
                      from tenpct
                      where col_signed < -250000000"
             ,$dbh);

  test_query("join_4_cl",
             "Time for join_as3ap",
             "select uniques.col_date, hundred.col_date,
                      tenpct.col_date, updates.col_date
               from uniques, hundred, tenpct, updates
               where uniques.col_key = hundred.col_key
                 and uniques.col_key = tenpct.col_key
                 and uniques.col_key = updates.col_key
                 and uniques.col_key = 1000"
             ,$dbh);

  test_query("proj_100",
             "Time for proj_100",
             "select distinct col_address, col_signed from hundred"
             ,$dbh);

  test_query("join_4_ncl",
             "Time for join_as3ap",
             "select uniques.col_date, hundred.col_date,
                          tenpct.col_date, updates.col_date
                  from uniques, hundred, tenpct, updates
                  where uniques.col_code = hundred.col_code
                      and uniques.col_code = tenpct.col_code
                      and uniques.col_code = updates.col_code
                      and uniques.col_code = 'BENCHMARKS'"
             ,$dbh);

  test_query("proj_10pct",
             "Time for proj_10pct",
             "select distinct col_signed from tenpct"
             ,$dbh);

  test_query("sel_1_ncl",
             "Time for sel_as3ap",
             "select col_key, col_int, col_signed, col_code,
                      col_double, col_name
                      from updates where col_code = 'BENCHMARKS'"
             ,$dbh);

  test_query("join_2_ncl",
             "Time for join_as3ap",
             "select uniques.col_signed, uniques.col_name,
                           hundred.col_signed, hundred.col_name
                      from uniques, hundred
                      where uniques.col_code = hundred.col_code
                      and uniques.col_code = 'BENCHMARKS'"
             ,$dbh);

  if ($limits->{'fk'})
  {
    create_as3ap_table($dbh,"integrity_temp");

    test_query("integrity_test_1",
  	     "Time for integrity_test",
  	     "insert into integrity_temp select *
  	      from hundred where col_int=0",$dbh);

    $rc= safe_test_command("integrity_test_2",
  	     "Time for integrity_test",
  	     "update hundred set col_signed = '-500000000'
  	      where col_int = 0",$dbh,1);

    if ($rc)
    {
      test_query("integrity_test_3",
                 "Time for integrity_test",
                 "update hundred set col_signed = '-500000000'
                 where col_int = 0",$dbh);
    }
  }

  push @drop_seq_command,$server->drop_index("updates","updates_int_bt");
  push @drop_seq_command,$server->drop_index("updates","updates_double_bt");
  push @drop_seq_command,$server->drop_index("updates","updates_decim_bt");
  push @drop_seq_command,$server->drop_index("updates","updates_code_h");

  test_many_command("Drop updates keys",
             "Time for drop_updates_keys",
             \@drop_seq_command,$dbh);

  create_as3ap_table($dbh,"saveupdates");

  test_command("bulk_save",
             "Time for bulk_as3ap",
             "insert into saveupdates select *
                      from updates where col_key between 5000 and 5999"
             ,$dbh,1);

  test_command("bulk_modify",
             "Time for bulk_as3ap",
             "update updates
                      set col_key = col_key - 100000
                      where col_key between 5000 and 5999"
             ,$dbh,1);

  safe_test_command("upd_append_duplicate",
             "Time for upd_as3ap",
             "insert into updates
                   values (6000, 0, 60000, 39997.90,
                            50005.00, 50005.00,
                            '11/10/1985', 'CONTROLLER',
                            'ALICE IN WONDERLAND',
                            'UNIVERSITY OF ILLINOIS AT CHICAGO')"
             ,$dbh,1);

  test_command("upd_remove_duplicate",
             "Time for upd_as3ap",
             "delete from updates where col_key = 6000 and col_int = 0"
             ,$dbh,1);

  test_command("upd_app_t_mid",
             "Time for upd_as3ap",
             "insert into updates
                values (5005, 5005, 50005, 50005.00, 50005.00,
                        50005.00, '1/1/1988', 'CONTROLLER',
                        'ALICE IN WONDERLAND',
                        'UNIVERSITY OF ILLINOIS AT CHICAGO')"
             ,$dbh,1);

  test_command("upd_mod_t_mid",
             "Time for upd_as3ap",
             "update updates set col_key = '-5000'
                  where col_key = 5005"
             ,$dbh,1);

  test_command("upd_del_t_mid",
             "Time for upd_as3ap",
             "delete from updates
                 where (col_key='5005') or (col_key='-5000')"
             ,$dbh,1);

  test_command("upd_app_t_end",
             "Time for upd_as3ap",
             "delete from updates
                 where (col_key='5005') or (col_key='-5000')"
             ,$dbh,1);

  test_command("upd_mod_t_end",
             "Time for upd_as3ap",
             "update updates
                  set col_key = -1000
                  where col_key = 1000000001"
             ,$dbh,1);

  test_command("upd_del_t_end",
             "Time for upd_as3ap",
             "delete from updates where col_key = -1000"
             ,$dbh,1);

  test_command("create_idx_updates_code_h",
  	     "time for create_idx_as3ap",
  	     "create index updates_code_h on updates (col_code)",
  	     $dbh,1);

  test_command("upd_app_t_mid",
             "Time for upd_as3ap",
             "insert into updates
                values (5005, 5005, 50005, 50005.00, 50005.00,
                        50005.00, '1/1/1988', 'CONTROLLER',
                        'ALICE IN WONDERLAND',
                        'UNIVERSITY OF ILLINOIS AT CHICAGO')"
             ,$dbh,1);

  test_command("upd_mod_t_cod",
             "Time for upd_as3ap",
             "update updates
                  set col_code = 'SQL+GROUPS'
                  where col_key = 5005"
             ,$dbh,1);

  test_command("upd_del_t_mid",
             "Time for upd_as3ap",
             "delete from updates
                 where (col_key='5005') or (col_key='-5000')"
             ,$dbh,1);

  test_command("create_idx_updates_int_bt",
  	     "time for create_idx_as3ap",
  	     "create index updates_int_bt on updates (col_int)",
  	     $dbh,1);

  test_command("upd_app_t_mid",
             "Time for upd_as3ap",
             "insert into updates
                values (5005, 5005, 50005, 50005.00, 50005.00,
                        50005.00, '1/1/1988', 'CONTROLLER',
                        'ALICE IN WONDERLAND',
                        'UNIVERSITY OF ILLINOIS AT CHICAGO')"
             ,$dbh,1);

  test_command("upd_mod_t_int",
             "Time for upd_as3ap",
             "update updates set col_int = 50015 where col_key = 5005"
             ,$dbh,1);

  test_command("upd_del_t_mid",
             "Time for upd_as3ap",
             "delete from updates
                 where (col_key='5005') or (col_key='-5000')"
             ,$dbh,1);

  test_command("bulk_append",
             "Time for bulk_as3ap",
             "insert into updates select * from saveupdates"
             ,$dbh,1);

  test_command("bulk_delete",
             "Time for bulk_as3ap",
             "delete from updates where col_key < 0"
             ,$dbh,1);

####
#### Delete the tables
####

  if (!$opt_skip_delete)                          # Only used when testing
  {
    print "Removing tables\n";
    $loop_time= My::Timer::get_timer();

    $dbh->do("drop table hundred" . $server->{'drop_attr'});
    $dbh->do("drop table updates" . $server->{'drop_attr'});
    $dbh->do("drop table uniques" . $server->{'drop_attr'});
    $dbh->do("drop table tenpct" . $server->{'drop_attr'});
    $dbh->do("drop table tiny" . $server->{'drop_attr'});
    $dbh->do("drop table saveupdates" . $server->{'drop_attr'});
    $dbh->do("drop table integrity_temp" . $server->{'drop_attr'});

    $end_time=My::Timer::get_timer();
    print "Time to drop_table (7): " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
  }

  if ($opt_fast && defined($server->{vacuum}))
  {
    $server->vacuum(0,\$dbh);
  }

  $dbh->disconnect;

  my $end_test= My::Timer::get_timer();

  print "Total time for AS3AP_SingleUser_Test(1): ",My::Timer::timestr(timediff($end_test, $start_test),"all"),"\n\n";

}


#############################################################################
#
#  AS3AP Multi-User test implementation 
#  Detail information about AS3AP test can be found at 
#  http://www.benchmarkresources.com/handbook/5.html
#
#  AS3AP Multi-user test
#
#  Multi-user test consists of four main parts.
#
#  1. An Information Retrieval (IR) test, where all users execute a
#  single-row selection query, ir_select, on the same table. This query
#  selects a single row using an index. It is executed with browse access
#  (Level 0 isolation).
#
#  2. An OLTP test, where all users execute a single-row update,
#  oltp_update, on the same table. This update randomly selects a single
#  row using an index and updates a nonindexed attribute. It is executed
#  with repeatable access (Level 3 isolation).
#
#  3. A Mixed Workload IR/OLTP Test, where one user executes a cross
#  section of ten update and retrieval queries, and all the others
#  execute the same IR/OLTP query as in the first/second test.
#
#  The first two tests can be used to measure the throughput as a
#  function of the number of concurrent database users. Before measuring
#  of performance of each test, we run this test for some time to fill up
#  both internal DBMS and OS buffers, and cache memory. Results of first
#  two tests are in trasaction per second (tps).
#
#  The third measures the degradation of response time for a cross
#  section of queries caused by system load. Results of this test are the
#  elapsed time for each query in the cross section test.
#
#  For now run test in next sequences
#
#  1. Run IR_Test test for (1 | 15) minutes to fill up DBMS cashes.
#  2. Run another one  IR_Test for (1 | 5) minutes for measuring throughput. 
#  3. Replace one background IR_Test with the cross section script.
#  4. Run queries to check correctness of the sequential and random bulk updates.
#  5. Run OLTP_Test test for (1 | 15) minutes to fill up DBMS cashes.
#  6. Run IR_Test for (1 | 5) minutes for measuring throughput. 
#  7. Replace one background OLTP_Test with the cross section script.
#  8. Run queries to check correctness of the sequential and random bulk updates.
#
##################################################################################


sub as3ap_multi_user_test
{

  if ($opt_small_test)
  {
    # Time given in seconds
    $startup_time= 1*60;
    $IR_test_time= 1*60;
  }
  else
  {
    $startup_time= 15*60;
    $IR_test_time= 5*60;
  }

  print "Start Multi-User AS3AP benchmark\n\n";
  print "Number of threads are $opt_threads\n\n";

  # Initializing variable
  my $interrupted= 0;
  my $get_stat= 0;

  #Initalize random generator
  my $seed1= 23;
  my $seed2= 6;

  ###
  ### Start Multi-User AS3AP Benchmark
  ###
  
  my $start_test= My::Timer::get_timer();

  if (!$opt_skip_ir_test)
  {

    # Part 1
    # Information Retrieval (IR) Test

    print "\nAS3AP: Start IR_Test (".localtime().")\n\n";

    $start_ir_test= My::Timer::get_timer();

    print "IR_Test: Start IR_Test_Background. Run $opt_threads threads during ".($startup_time/60)." min. for filling up DBMS caches \n\n";

    for ($i= 0 ; $i < $opt_threads ; $i++)
    {
      #Create new handles
      my $write_handle= new IO::Handle;
      my $read_handle= new IO::Handle;

      #Create pipe for statistics
      pipe($read_handle,$write_handle);
      $write_handle->autoflush(1);

      if ($pid = fork)
      {
        close($write_handle);
        $work{$pid}= $read_handle;
      }
      else
      {
        die "cannot fork: $!" unless defined $pid;
        #Close parent handle
        close $read_handle;
        test_loop(\&ir_test, $rows_num, $i, $write_handle)
      }
    }

    my $dbh = $server->connect();

    # IR_Test: Run test with threads for 1 or 15 mins
    sleep($startup_time);

    # IR_Test: Measuring throughput with IR_Test for 1 or 5 min
    print "IR_Test: Run additional IR_Test during ".($IR_test_time/60)." min. for measuring throughput \n\n";

    my $stime= time();
    my $etime= $stime + $IR_test_time;
    my $count= 0;

    %ir_test=();
    $ir_test{max}=0;
    $ir_test{min}=999999;
    $ir_test{iter}=0;
    $ir_test{sum}=0;   

    $SIG{ALRM}= sub { die "timeout" };

    #print "Time ".localtime()."\n";

    eval
    {
      alarm ($IR_test_time + 1);

      while (time()<$etime)
      {
        $iter_start= time();
        ir_test($dbh,$rows_num);
        my $time = time() - $iter_start;        

        if ($time < $ir_test{min})
        {
          $ir_test{min}= $time;
        }
        elsif ($time > $ir_test{max})
        {
          $ir_test{max}= $time;
        }
        $ir_test{sum}+=$time;
        $ir_test{iter}++;
      }
      alarm(0);
    };

    $etime= time() - $stime;

    $SIG{ALRM}= 'DEFAULT';

    #print "Time ".localtime()." Count $count\n";

    if ($@ =~ /timeout/ )
    {
      print "IR_Test: Interrupted\n" if($opt_debug);
    }

    single_report("IR_Test_thread",{ $$ => [sprintf("%10s",$ir_test{iter}),
                                            sprintf("%7.3f",($etime)/60),
                                            express_stat(\%ir_test)
                                           ]
                                   }) if ($opt_detail_stat);

    printf("IR_Test: Throughput for IR_Test - %10.3f transactions per second during %6.3f min\n\n",
           $ir_test{iter}/$etime, $etime/60);

    # Mixed Workload IR_Test: Stop one thread and run CrossSectionTest
    $res= kill_and_report(1);

    if ($opt_detail_stat)
    {
      single_report("Workload IR_Test",$res);
    }

    #$dbh= check_server($dbh);

    cross_section_tests($dbh,"IR_Test");

    correctness_check_test($dbh, "IR_Test");			# Run Integrity Test

    # IR_Test: Stop all threads

    print "IR_Test: Stop IR_Test_Background and get detail statistics\n\n" if($opt_detail_stat);

    #Stop all threads
    $res= kill_and_report(scalar(keys %work));

    $end_ir_test= My::Timer::get_timer();

    #Detail statistics (broken)
    stage_report("IR_Test_Background",$res) if($opt_detail_stat);
    $dbh->disconnect;

    print "\nTime for IR_Test(1): ",
                      My::Timer::timestr(timediff($end_ir_test, $start_ir_test),"all") . "\n\n";

  }

  if (!$opt_skip_oltp_test)
  {

    # Part 2
    # OLTP_Test

    print "\nAS3AP: Start OLTP_Test ".localtime()."\n\n";

    $start_oltp_test= My::Timer::get_timer();

    print "OLTP_Test: Start OLTP_Test_Background. Run $opt_threads threads during ".($startup_time/60)." min. for filling up DBMS caches\n\n";

    for ($i= 0 ; $i < $opt_threads ; $i++)
    {
      #Create new handles
      my $write_handle= new IO::Handle;
      my $read_handle= new IO::Handle;

      #Create pipe for statistics
      pipe($read_handle,$write_handle);
      $write_handle->autoflush(1);

      if ($pid = fork)
      {
        close($write_handle);
        $work{$pid}= $read_handle;
      }
      else
      {
        die "cannot fork: $!" unless defined $pid;
        #Close parent handle
        close $read_handle;
        test_loop(\&oltp_update_test,$rows_num,$i,$write_handle)
      }
    }

    my $dbh=$server->connect();

    # OLTP_Test: Run test with threads for 1 or 15 mins
    sleep($startup_time);

    # OLTP_Test: Measuring throughput with IR_Test for 1 or 5 mins
    $stime= time();
    $etime= $stime + $IR_test_time;
    $count= 0;

    print "OLTP_Test: Run additional IR_Test during ".($IR_test_time/60)." min. for measuring throughput \n\n";

    %ir_test= ();

    %ir_test=();
    $ir_test{max}=0;
    $ir_test{min}=999999;
    $ir_test{iter}=0;
    $ir_test{sum}=0;   

    $SIG{ALRM}= sub { die "timeout" };

    #print "Time ".localtime()."\n";

    eval {
      alarm ($IR_test_time + 1);

      while (time()<$etime)
      {
        $iter_start= time();
        ir_test($dbh,$rows_num);
        my $time = time() - $iter_start;        

        if ($time < $ir_test{min})
        {
          $ir_test{min}= $time;
        }
        elsif ($time > $ir_test{max})
        {
          $ir_test{max}= $time;
        }
        $ir_test{sum}+=$time;
        $ir_test{iter}++;
      }
      alarm(0);
    };

    $etime= time() - $stime;

    $SIG{ALRM}= 'DEFAULT';

    #print "Time ".localtime()." Count $count\n";

    if ($@ =~ /timeout/ && $opt_debug)
    {
      print "OLTP_Test: Interrupted\n";
    }

    single_report("IR_Test_thread",{ $$ => [sprintf("%10s",$ir_test{iter}),
                                            sprintf("%7.3f",($etime)/60),
                                            express_stat(\%ir_test)
                                           ]
                                   }) if ($opt_detail_stat);

    printf("OLTP_Test: Throughput for IR_Test - %10.3f transactions per second during %6.3f min\n\n",
           $ir_test{iter}/$etime, $etime/60);

    # Mixed Workload OLTP_Test: Stop one thread and run CrossSectionTest

    $res= kill_and_report(1);
    print "Kill ok\n" if($opt_debug && $res);

    if ($opt_detail_stat)
    {
      single_report("Workload OLTP_Test",$res);
    }

    #$dbh= check_server($dbh);
    #print "Check server ok\n" if($opt_debug && $dbh);

    cross_section_tests($dbh,"OLTP_Test");

    correctness_check_test($dbh, "OLTP_Test");			# Run Integrity Test

    # OLTP_Test: Stop all threads
    print "OLTP_Test: Stop OLTP_Test_Background and get detail statistics\n\n" if($opt_detail_stat);
    $res= kill_and_report(scalar(keys %work));

    $end_oltp_test= My::Timer::get_timer();
    stage_report("OLTP_Test_Background",$res) if ($opt_detail_stat);
    $dbh->disconnect;

    print "\nTime for OLTP_Test(1): ",
                    My::Timer::timestr(timediff($end_oltp_test, $start_oltp_test),"all"),"\n\n";
  }

  my $end_test= My::Timer::get_timer();

  ###
  ### Finish AS3AP test. Some cleanups.
  ###

  print "Total time for AS3AP_MultiUser_Test(1): ",My::Timer::timestr(timediff($end_test, $start_test),"all"),"\n\n";

}

###
### THREAD MANAGMENT FUNCTIONS
###

sub get_report
{
  my ($num_report)= @_;
  my %tmp= ();
  my @ready_h= ();
  my @ready= ();
  my $handle;
  my $result;

  my $select= IO::Select->new();

  #Add all handles to select
  $select->add(values %work);

  while(@ready_h != $num_report)
  {
    @ready= $select->can_read(undef);
    @ready_h= (@ready_h,@ready);
    $select->remove(@ready);
  }

  foreach $handle (@ready_h)
  {
    $result= <$handle>;
    chomp($result);
    my ($pid,@params)= split(/,/,$result);
    $tmp{$pid}= \@params;
  }
  return \%tmp;
}

sub kill_and_report 
{
  my ($max_to_kill)= @_;

  my @pids= ();
  my $children= 0;
  my $errors= 0;
  my $i;
  my $answer;

  if ($max_to_kill == keys %work)
  {
    kill USR1, keys %work;			
  }
  else
  {
    @pids= sort {$a<=>$b} keys %work;
    for($i= 0; $i < $max_to_kill; $i++)
    {
      kill USR1,$pids[$i]; 
    }
  }
  print "kill_and_report: Before report\n" if($opt_debug);

  $answer= get_report($max_to_kill);

  print "kill_and_report: After report\n" if($opt_debug);

  while ($children != $max_to_kill && (($pid=wait()) != -1))
  {

    #This is our child, not pipe open|close and they not stoped
    if (exists($work{$pid}) && WIFEXITED($?))
    {
      $errors++ if (($?/256) != 0);

      #Get handle for this pid
      $read_handle= $work{$pid};

      #Clean-up
      close($read_handle);

      #For checking number of count killing process			
      $children++;	
      delete($work{$pid});
    }
  }
  return $answer;
}


sub signal_USR2_handler
{
  $SIG{USR2}=\&signal_USR2_handler;
  $get_stat++;
}

sub signal_USR1_handler
{
  $SIG{USR1}=\&signal_USR1_handler;
  $interrupted= 1;
}

sub test_loop
{

  my ($routine, $count, $thread,$writeh)=@_;
  my $dbh_test;
  my $time;
  my %routine= ();
  my %stat= ();

  $stat{sum}=0;
  $stat{iter}=0;
  $stat{max}=0;
  $stat{min}=999999;

  print "Fork $$ process \n" if ($opt_debug);

  # Set new random seq
  if ($opt_random)
  {
     srand(200 + $thread);
  }
  else
  {  
     $seed1+=rand($thread*100);
  }

  my $iter= 0;
  my $count_stat= 0;

  $dbh_test=$server->connect();

  $start_time= time();
	
  while (!$interrupted)
  {	
    $routine_start= time();
    my $ret= $routine->($dbh_test,$count);			# Exec routine 

    $time= time()-$routine_start;
    $stat{sum} += $time;
    $stat{iter}++;

    if ($time < $stat{min})
    {  
      $stat{min}= $time;
    }
    elsif ($time > $stat{max})
    {
      $stat{max}= $time;
    }

    send_report($writeh,sprintf("%10s",$stat{iter}),sprintf("%7.3f",(time()-$start_time)/60),
                express_stat(\%stat)) if($get_stat);

  }
  $end_time = time();


  send_report($writeh,sprintf("%10s",$stat{iter}),sprintf("%7.3f",($end_time-$start_time)/60),
	      express_stat(\%stat));

#  print "PID $$ Performance - ",$#thread+1," iter/s time to run ",($end_time-$start_time)," End time $end_time\n";
#    if ($opt_debug);

  $dbh_test->disconnect;
  $dbh_test= 0;
  close $writeh;  # this will happen anyway
  
  exit(0);	

  sub send_report
  {
    my ($wh,@params)= @_;
    print $wh "$$,",join(",",@params),"\n";
    $get_stat--;
    $iter= 0;
    $count_stat++;
  }

}


###
### AS3AP MULTI-USER FUNCTIONS
###

sub ir_test
{
  my ($dbh, $count)= @_;
  my $rnd= 1;

  while($rnd == 1) {$rnd=int(urand($count))}; #Skip key value = 1

  #Check for query cache.
  if ($opt_as3ap_no_query_cache)
  {
    $rnd .= "+ 0*".int(urand($count));	
  }

  my $rows= fetch_all_rows($dbh,"select col_key, col_code, col_date, 
                                      col_signed, col_name 
                               from updates where col_key = $rnd");

  print "$$ ERROR: Rows = $rows != 1\n SQL: select col_key, col_code, col_date,col_signed, col_name  
          from updates where col_key = $rnd " if ($rows!=1);

  return $rows;
}

sub oltp_update_test
{
  my ($dbh,$count)= @_;
  my $rnd= 1;

  while($rnd == 1) {$rnd=int(urand($count))}; #Skip key value = 1

  #Check for query cache.
  if ($opt_as3ap_no_query_cache)
  {
    $rnd .= "+ 0*".int(urand($count));	
  }

  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'} = 0;
  }

  $rc= $dbh->do("update updates set col_signed = col_signed+1 
                   where col_key = $rnd");

  if ($server->{transactions})
  {
    defined($rc) ? $dbh->commit() : $dbh->rollback();
    $dbh->{'AutoCommit'} = 1;
  }
  return 1;
}

sub cross_section_tests
{

  my ($dbh, $name)= @_;

  print "$name: Start CrossSectionTest\n\n" if($opt_debug);

  my $stime= My::Timer::get_timer();

  #Create Temporary Table
  create_as3ap_table($dbh,"sel100seq");
  create_as3ap_table($dbh,"sel100rand");

  if ($opt_extened_stat)
  {
    kill USR2, keys %work;
    $res=get_report(scalar(keys %work));
    single_report("Before cross_section_tests",$res);
  }

  # cross_section_tests: sel_1_ncl

  test_command("","","select col_key, col_int, col_signed, col_code,
                 col_double, col_name
             from updates where col_code = 'BENCHMARKS'", $dbh,0);

  print "$name: Start CrossSectionTest 1\n" if($opt_debug); 

  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("sel_1_ncl",$res);
  }

  # cross_section_tests: sel_100_seq
  test_command("","","insert into sel100seq select * from updates 
                     where updates.col_key between 1001 and 1100", $dbh, 0);

  print "$name: Start CrossSectionTest 2\n" if($opt_debug);

  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("sel_100_seq",$res); 
  }

  # cross_section_tests: sel_100_rand
  test_command("","","insert into sel100rand select * from updates
                     where updates.col_int between 1001 and 1100", $dbh, 0);

  print "$name: Start CrossSectionTest 3\n" if($opt_debug);

  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("sel_100_rand",$res);  
  }

  #cross_section_tests: mod_100_seq_abort
  if ($server->{transactions})
  {
    #Start transaction
    $dbh->{'AutoCommit'}= 0;

    $row=$dbh->do("update updates 
                   set col_double = col_double+100000000 
                   where col_key between 1001 and 1100");

    print "mod_100_seq_abort: Affected $row rows\n" if($opt_ext_debug);
    $dbh->rollback or warn "$DBI::errstr\n";
    $dbh->{'AutoCommit'} = 1		
  }


  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("mod_100_seq_abort",$res);  
  }

  #cross_section_tests: mod_100_rand
  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'}= 0;
  }

  $row=$dbh->do("update updates 
	     set col_double = col_double+100000000
	     where col_int between 1001 and 1100");

  print "mod_100_rand: Affected $row rows\n"  if($opt_ext_debug);

  if ($server->{transactions})
  {
    $dbh->commit;
    $dbh->{'AutoCommit'} = 1
  }

  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("mod_100_rand",$res);  
  }

  # cross_section_tests: unmod_100_seq
  if ($server->{transactions})
  {
    $dbh->{AutoCommit}= 0;
  }

  $row= $dbh->do("update updates 
            set col_double = col_double-100000000
            where col_key between 1001 and 1100");

  print "unmod_100_seq: Affected $row rows\n"  if($opt_ext_debug);

  if ($server->{transactions})
  {
    $dbh->commit;
    $dbh->{'AutoCommit'} = 1
  }

  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("unmod_100_seq",$res);  
  }

  print "$name: Start CrossSectionTest 4\n" if($opt_debug);

  #cross_section_tests: unmod_100_rand
  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'}= 0;
  }

  #In handbook there is "where clause for col_key"
  $row=$dbh->do("update updates 
	     set col_double = col_double-100000000
	     where col_int between 1001 and 1100");

  print "unmod_100_rand: Affected $row rows\n"  if($opt_ext_debug);

  if ($server->{transactions})
  {
    $dbh->commit;
    $dbh->{'AutoCommit'} = 1
  }

  print "$name: Start CrossSectionTest 5\n" if($opt_debug);
  if ($opt_extended_stat)
  {
    kill USR2, keys %work;
    $res= get_report(scalar(keys %work));
    single_report("unmod_100_seq",$res);  
  }

  my $etime= My::Timer::get_timer();
  print "Time for ${name}_CrossSectionTests(1): ", My::Timer::timestr(timediff($etime, $stime),"all") . "\n";

}

sub correctness_check_test
{

  my ($dbh, $name)= @_;

  my $rows;

  print "\n$name: Start CorrectnessCheckTest\n\n";

  # correctness_check_test: checkmod_100_seq
  $rows= fetch_row($dbh,"select count(*) from updates, sel100seq
                         where updates.col_key=sel100seq.col_key and 
                               updates.col_double!=sel100seq.col_double");

  if ($rows == 100)
  {
    print "checkmod_100_seq: PASSED $rows\n"
  }
  else
  {
    print "checkmod_100_seq: FAILED $rows\n"
  }

  # correctness_check_test: checkmod_100_rand
  $rows= fetch_row($dbh,"select count(*) from updates, sel100rand
                         where updates.col_int=sel100rand.col_int and 
                               updates.col_double!=sel100rand.col_double");

  if ($rows == 100)
  {
    print "checkmod_100_rand: PASSED $rows\n"
  }
  else
  {
    print "checkmod_100_rand: FAILED $rows\n"
  }
  print "\n$name: Stop CorrectnessCheckTest\n\n";
}

sub check_server
{
  my($dbh_tmp)=@_;

  $check_server= "select 1 from updates";

  if (!defined($dbh_tmp->do($check_server)))
  {
    $dbh_tmp->disconnect;
    print "Connection to DB closed. Tring to reconnect to DB\n";
    $dbh_tmp = $server->connect;
  }

  return $dbh_tmp;
}

sub check_data
{
  my $dbh= $server->connect;
  return fetch_row($dbh,"select count(*) from updates");
}


sub load_data
{

  my $dbh= $server->connect;

  #Create Tables
  create_as3ap_table($dbh,"hundred");
  create_as3ap_table($dbh,"updates");
  create_as3ap_table($dbh,"uniques");
  create_as3ap_table($dbh,"tenpct");

  $dbh->do("drop table tiny");
  do_many($dbh,$server->create("tiny",["col_key int not null"],[]));

  #Load DATA

  print "Load DATA\n\n";

  @table_names= ("updates","uniques","hundred","tenpct", "tiny");

  $loop_time= My::Timer::get_timer();

  if ($server->{'transactions'})
  {
    $dbh->{'AutoCommit'}=0;
  }

  if ($opt_fast && $server->{'limits'}->{'load_data_infile'})
  {
    for ($ti = 0; $ti <= $#table_names; $ti++)
    {
      my $table_name= $table_names[$ti];
      my $file= "$pwd/Data/AS3AP/${table_name}";
      print "$table_name - $file\n" if ($opt_debug);
      $row_count += $server->insert_file($table_name,$file,$dbh);
    }
  }
  else
  {
    for ($ti = 0; $ti <= $#table_names; $ti++)
    {
      my $table_name= $table_names[$ti];
      my $insert_start= "insert into $table_name values (";
      open(DATA, "$pwd/Data/AS3AP/${table_name}") 
 	         || die "Can't open text file: $pwd/Data/AS3AP/${table_name}\n"; 
      while (<DATA>)
      {
        chomp;
	next unless ( $_ =~ /\w/ );     # skip blank lines
	$command= $insert_start."$_".")";
	print "$command\n" if ($opt_debug);
	$sth= $dbh->do($command) or die "Got error: $DBI::errstr when executing '$command'\n";
        $row_count++;
      }
      close(DATA);
    }
  }

  if ($server->{'transactions'})
  {
    $dbh->commit;
    $dbh->{'AutoCommit'} = 1
  }
	
  $end_time=My::Timer::get_timer();
  print "Time for Load Data - " . "($row_count): " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";

  create_index($dbh);

  $dbh->disconnect;

  return ($row_count-1)/4;
}


sub create_as3ap_table
{
  my ($dbh,$table_name)=@_;
  my @fields=(
		 "col_key     int             not null",
		 "col_int     int             not null",
		 "col_signed  int             not null",
		 "col_float   float           not null",
		 "col_double  double          not null",
		 "col_decim   numeric(18,2)   not null",
		 "col_date    char(20)        not null",
		 "col_code    char(10)        not null",
		 "col_name    char(20)        not null",
		 "col_address char(80)        not null");  

  #Create Table
  $dbh->do("drop table $table_name");
  do_many($dbh,$server->create("$table_name",\@fields,[]));
}

sub create_index
{
  my ($dbh)=@_;

  print "Create Index\n\n";

  test_command("create_idx_updates_key_bt",
	       "time for create_idx_as3ap",
	       "create unique index updates_key_bt on updates (col_key)",$dbh,1);

  test_command("create_idx_updates_int_bt",
	       "time for create_idx_as3ap",
	       "create index updates_int_bt on updates (col_int)",$dbh,1);

  test_command("create_idx_updates_code_h",
	     "time for create_idx_as3ap",
	       "create index updates_code_h on updates (col_code)",$dbh,1);

  test_command("create_idx_updates_decim_bt",
	       "time for create_idx_as3ap",
	       "create index updates_decim_bt on updates (col_decim)",$dbh,1);

  test_command("create_idx_updates_double_bt",
	       "time for create_idx_as3ap",
	       "create index updates_double_bt on updates (col_double)",$dbh,1);


  if ($opt_as3ap_single)
  {

    test_command("create_idx_uniques_key_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create unique index uniques_key_bt on uniques (col_key)",$dbh,1);			    

    test_command("create_idx_hundred_key_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create unique index hundred_key_bt on hundred (col_key)",				    
    	     $dbh,1);										    

    test_command("create_idx_tenpct_key_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create unique index tenpct_key_bt on tenpct (col_key)",$dbh,1);			    

    test_command("create_idx_tenpct_key_code_bt",						    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_key_code_bt on tenpct (col_key,col_code)",			    
    	     $dbh,1);										    

    test_command("create_idx_tiny_key_bt",							    
    	     "time for create_idx_as3ap",							    
    	     "create index tiny_key_bt on tiny (col_key)",$dbh,1);				    

    test_command("create_idx_tenpct_int_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_int_bt on tenpct (col_int)",$dbh,1);				    

    test_command("create_idx_tenpct_signed_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_signed_bt on tenpct (col_signed)",$dbh,1);			    

    test_command("create_idx_uniques_code_h",							    
    	     "time for create_idx_as3ap",						    
    	     "create index uniques_code_h on uniques (col_code)",$dbh,1);				    

    test_command("create_idx_tenpct_double_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_double_bt on tenpct (col_double)",$dbh,1);			    

    test_command("create_idx_tenpct_float_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_float_bt on tenpct (col_float)",$dbh,1);			    

    test_command("create_idx_tenpct_decim_bt",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_decim_bt on tenpct (col_decim)",$dbh,1);			    

    test_command("create_idx_hundred_code_h",							    
    	     "time for create_idx_as3ap",						    
    	     "create index hundred_code_h on hundred (col_code)",$dbh,1);				    

    test_command("create_idx_tenpct_name_h",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_name_h on tenpct (col_name)",$dbh,1);				    

    test_command("create_idx_tenpct_code_h",							    
    	     "time for create_idx_as3ap",						    
    	     "create index tenpct_code_h on tenpct (col_code)",$dbh,1);				    

    if ($limits->{'fk'})
    {
      #We have to create index explicitly for foreign key column 
      test_command("create_idx_hundred_signed",							    
    	     "time for create_idx_as3ap",						    
    	     "create index hundred_signed_bt on hundred (col_signed)",$dbh,1);

      test_command("create_idx_hundred_foreign",							    
    	     "time for create_idx_as3ap",						    
    	     "alter table hundred add constraint fk_hundred_updates foreign key (col_signed)	    
    				      references updates (col_key)",$dbh,1);			    
    }
  }
}

###
### HELPER FUNCTIONS
###

sub urand
{

  my ($max)=@_;

  if ($opt_random)
  {
    return rand($max);
  }
  else
  {
    # Generate uniformly distributed random numbers using the 32-bit
    # generator from figure 3 of:
    # L'Ecuyer, P. Efficient and portable combined random number
    # generators, C.A.C.M., vol. 31, 742-749 & 774-?, June 1988.
    # The cycle length is claimed to be 2.30584E+18
    
    $k= int ($seed1 / 53668);
    $seed1= 40014 * ($seed1 - $k * 53668) - $k * 12211;
    if ($seed1 < 0) 
    {
      $seed1= $seed1 + 2147483563;
    }
    
    $k= int ($seed2 / 52774);
    $seed2= 40692 * ($seed2 - $k * 52774) - $k * 3791;
    if ($seed2 < 0)
    {
      $seed2= $seed2 + 2147483399;
    }
    $z= $seed1 - $seed2;
    
    if ($z < 1) {$z= $z + 2147483562};
    
    return int($max * ($z / 2147483563));
  }
}


#
# Collect execution time of every transactions 
# and return min,max,avg  
#
sub express_stat
{

  my ($data)= @_;
 
  return (sprintf("%7.3f",$data->{min}),
	  sprintf("%7.3f",$data->{max}),
	  $data->{iter} ? sprintf("%7.3f",$data->{sum}/$data->{iter}) : 0
	 );
}

sub single_report
{
  my ($name, $data)= @_;

  print "\nStatistics for: $name\n";
  print "-"x65,"\n";
  print "|   PID   | NUM ITER |  TIME |  MIN  |  MAX  |  AVG  | ITER/sec |\n";
  print "-"x65,"\n";
  foreach  my $item (keys %{$data})
  {
    my $rate=@{$data->{$item}}->[0]/(@{$data->{$item}}->[1]*60);
    push @{$data->{$item}}, sprintf("%10.3f",$rate);

    printf("|%9s",$item);
    print map (sprintf("|%s",$_),@{$data->{$item}}),"|\n";
  }
  print "-"x65,"\n"; 
}

sub stage_report
{
  my ($name,$data)= @_;
 
  my @max_oper_time=();
  my @min_oper_time=();
  my @thread_time=();
  my $sum_iter=0;
  my $sum_avg_oper_time=0;
  my $sum_thread_time=0;
  my $number_threads=keys %{$data};

  single_report("Background threads", $data);
 
  foreach  my $item (keys %{$data})
  {
    push @thread_time,@{$data->{$item}}->[1]*60;
    push @min_oper_time,@{$data->{$item}}[2];
    push @max_oper_time,@{$data->{$item}}[3];
    push @throughput, @{$data->{$item}}->[0]/(@{$data->{$item}}->[1]*60);

    $sum_iter+=@{$data->{$item}}[0];
    $sum_thread_time+=@{$data->{$item}}[1]*60;
    $sum_avg_oper_time+=@{$data->{$item}}[4];

  }

  $sum_iter/=$number_threads;
  $sum_thread_time/=$number_threads;
  $sum_avg_oper_time/=$number_threads;
  $avg_throughput = $sum_iter/$sum_thread_time;

  $deviation=0;

  foreach $rate (@throughput)
  {
    $deviation+= abs($rate-$avg_throughput);
  }

  $deviation/=scalar(@throughput);

  print "\n","-"x79,"\n";

  printf("$name: Fastest iteration time for all threads         - %10.3f\n",
	 (sort {$a<=>$b} @min_oper_time)[0]);
  printf("$name: Slowest iteration time for all threads         - %10.3f\n",
	 (sort {$b<=>$a} @max_oper_time)[0]);
  printf("$name: Avg time of iteration for all treads           - %10.3f\n",$sum_avg_oper_time);

  printf("$name: Iterations in all threads                      - %10.3f\n",
	 $sum_iter*$number_threads);
  printf("$name: Avg thread running time  (sec)                 - %10.3f\n",$sum_thread_time);
  printf("$name: Avg number of iterations per thread            - %10.3f\n",$sum_iter);
  printf("$name: Avg throughput of thread (iter per sec)        - %10.3f\n",
	 $avg_throughput);
  printf("$name: Throughput deviation                           - %10.3f\n",
	 $deviation);

  print "-"x79,"\n";
}

##
## DB primitives
##

sub test_command
{
  my($test_text,$result_text,$query,$dbh)=@_;
  my($i,$loop_time,$end_time);

  print $test_text . "\n";
  $loop_time=My::Timer::get_timer();
  $dbh->do($query) or die $DBI::errstr;
  $end_time=My::Timer::get_timer();
  print $result_text . "(1) $test_text: " .
  My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}

sub fetch_row
{
  my($dbh,$query)=@_;
  my($sth,$value);

  $sth=$dbh->prepare($query) or die $DBI::errstr;
  $sth->execute or die $sth->errstr;
  $value=$sth->fetchrow_array;
  $sth->finish;

  return $value;
}


############################ HELP FUNCTIONS ##############################

sub test_query
{
  my($test_text,$result_text,$query,$dbh)=@_;
  my($i,$loop_time,$end_time);

  print $test_text . "\n";
  $loop_time=My::Timer::get_timer();

  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'} = 0;
  }

  defined(fetch_all_rows($dbh,$query)) or warn $DBI::errstr;

  if ($server->{transactions})
  {
    $dbh->commit() or warn "$DBI::errstr\n";
    $dbh->{'AutoCommit'} = 1;
  }

  $end_time=My::Timer::get_timer();
  print $result_text . "(1) $test_text: " .
  My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}


sub test_command
{
  my($test_text,$result_text,$query,$dbh, $mode)=@_;
  my($i,$loop_time,$end_time);

  if ($mode)
  {
    print $test_text . "\n";
    $loop_time=My::Timer::get_timer();
  }

  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'} = 0;
  }

  $dbh->do($query) or warn $DBI::errstr;

  if ($server->{transactions})
  {
    $dbh->commit() or warn "$DBI::errstr\n";
    $dbh->{'AutoCommit'} = 1;
  }

  if ($mode)
  {
    $end_time=My::Timer::get_timer();
    print $result_text . "(1) $test_text: " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
  }
}

sub safe_test_command
{

  # In this subroutine we invert general behavior.
  # Success on fail and fail on success.

  # mode: simple - 0, advanced - 1
  my($test_text,$result_text,$query, $dbh, $mode)=@_;
  my($loop_time,$end_time);

  if ($mode)
  {
    print $test_text . "\n";
    $loop_time=My::Timer::get_timer();
  }

    $dbh->{'RaiseError'} = 1;
  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'} = 0;
  }

  eval 
  {
    $dbh->do($query);

    if ($server->{transactions})
    {
      $dbh->commit;
      $dbh->{'AutoCommit'} = 0;
      $dbh->{'RaiseError'} = 0;
    }
  };

  if (!$@)
  {
    #We should print fail message here
    print STDERR "$result_text: We executed command $query but we should not.\n";
    return 1;
  }


  if ($server->{transactions})
  {
    $dbh->rollback or warn "$DBI::errstr\n";
    $dbh->{'AutoCommit'} = 0;
  }
  $dbh->{'RaiseError'} = 0;
  
  if ($mode)
  {
    $end_time=My::Timer::get_timer();
    print $result_text . "(1) $test_text: " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
  }
  return 0;
}

sub test_many_command
{
  my($test_text,$result_text,$query,$dbh)=@_;
  my($loop_time,$end_time);

  print $test_text . "\n";
  $loop_time=My::Timer::get_timer();

  if ($server->{transactions})
  {
    $dbh->{'AutoCommit'} = 0;
  }

  foreach $statement (@{$query})
  {
    if (!($sth=$dbh->do($statement)))
    {
      print STDERR "Can't execute command '$statement'\nError: $DBI::errstr\n";
      if ($server->{transactions})
      {
        $dbh->rollback or warn "$DBI::errstr\n";
        $dbh->{'AutoCommit'} = 1;
      }
      return 1;
    }
  }

  if ($server->{transactions})
  {
    $dbh->commit() or warn "$DBI::errstr\n";
    $dbh->{'AutoCommit'} = 1;
  }

  $end_time=My::Timer::get_timer();
  print $result_text . "(1) $test_text: " .
  My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}

