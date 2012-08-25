#!@PERL@
# -*- perl -*-
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
##########################################################
# this is the base file every test is using ....
# this is made for not changing every file if we want to
# add an option or just want to change something in
# code what is the same in every file ...
##########################################################

#
# The exported values are:

# $opt_...	Various options
# $date		Current date in ISO format
# $server	Object for current server
# $limits	Hash reference to limits for benchmark

$benchmark_version="3.0";
use Getopt::Long;

require "$pwd/server-cfg" || die "Can't read Configuration file: $!\n";

$|=1;				# Output data immediately

$opt_skip_test=$opt_skip_create=$opt_skip_delete=$opt_verbose=$opt_fast_insert
     =$opt_lock_tables=$opt_debug=$opt_skip_delete=$opt_fast=$opt_force=$opt_log
     =$opt_use_old_results=$opt_help=$opt_odbc=$opt_small_test=$opt_small_tables
     =$opt_samll_key_tables=$opt_stage=$opt_old_headers=$opt_die_on_errors=$opt_tcpip=$opt_random=0;
$opt_cmp=$opt_user=$opt_password=$opt_connect_options="";
$opt_server="mysql"; $opt_dir="output";
$opt_host="";$opt_database="test";
$opt_machine=""; $opt_suffix="";
$opt_create_options=undef;
$opt_create_index_options=undef;
$opt_max_table_size=undef;
$max_table_size=0;
$opt_optimization="None";
$opt_as3ap_single=$opt_as3ap_db_size=$opt_as3ap_no_query_cache=$opt_as3ap_no_load="";
$opt_as3ap_no_multi=$opt_as3ap_no_cleanup=$opt_as3ap_full="";
$opt_as3ap_generator="misc/as3apgen/as3apgen";
$opt_hw=$opt_fs="";
$opt_threads=5;
$opt_hires=1;
$opt_assume_mysql_version='4.0.15';
$opt_assume_mysql_tabletype='myisam';

$opt_time_limit=10*60;		# Don't wait more than 10 min for some tests

$log_prog_args=join(" ", skip_arguments(\@ARGV,"comments","cmp","server",
					"user", "host", "database", "password",
					"use-old-results","skip-test",
					"optimization","hw",
					"machine", "dir", "suffix", "log"));

&Getopt::Long::Configure( 'pass_through', 'no_auto_abbrev');

GetOptions("skip-test=s","comments=s","cmp=s","server=s","user=s","host=s",
           "database=s","password=s","loop-count=i","row-count=i",
           "skip-create","skip-delete","verbose","fast-insert","lock-tables",
           "debug","fast","force","field-count=i","regions=i","groups=i",
           "time-limit=i","log","use-old-results","machine=s","dir=s",
           "suffix=s","help","odbc","small-test","small-tables",
           "small-key-tables","stage=i","threads=i","random","old-headers",
           "die-on-errors","create-options=s","create-index-options=s",
	   "hires=i","tcpip","silent",
           "optimization=s","hw=s","fs=s","socket=s","as3ap-no-load",
           "connect-options=s","as3ap-db-size=s","as3ap-generator=s",
           "as3ap-no-query-cache","as3ap-single","as3ap-multi",
	   "as3ap-no-cleanup", "as3ap-full", "max-table-size=s",
	   "assume-mysql-version=s","assume-mysql-tabletype=s") || usage();

usage() if ($opt_help);

#as3apgen($opt_as3ap_db_size, 1) if ($opt_as3ap_db_size);

 if ($opt_max_table_size)
 {
   if ($opt_max_table_size =~ /^(\d*)G$/i) {
     $max_table_size=1024*1024*1024*$1;
   } elsif ($opt_max_table_size =~ /^(\d*)M$/i) {
     $max_table_size=1024*1024*$1;
   } elsif ($opt_max_table_size =~ /^(\d*)K$/i) {
     $max_table_size=1024*$1;
   } elsif ($opt_max_table_size =~ /^(\d*)$/i) {
     $max_table_size = $1;
   } else {
     warn "max-table-size value is illegal. Ignoring.."
   }
}


$server=get_server($opt_server,$opt_host,$opt_database,$opt_odbc,
                   machine_part(), $opt_socket, $opt_connect_options);
$limits=merge_limits($server,$opt_cmp);
$date=date();
@estimated=(0.0,0.0,0.0);		# For estimated time support

# if we dont want to use hires timer (set --hires=0 in the command line),
# inform My::Timer 
if (! $opt_hires)
{
 $My::Timer::use_hires=0;
}

{
  my $tmp= $opt_server;
  $tmp =~ s/_odbc$//;
  if (length($opt_cmp) && index($opt_cmp,$tmp) < 0)
  {
    $opt_cmp.=",$tmp";
  }
}
$opt_cmp=lc(join(",",sort(split(',',$opt_cmp))));

#
# set opt_lock_tables if one uses --fast and drivers supports it
#

if (($opt_lock_tables || $opt_fast) && $server->{'limits'}->{'lock_tables'})
{
  $opt_lock_tables=1;
}
else
{
  $opt_lock_tables=0;
}
if ($opt_fast)
{
  $opt_fast_insert=1;
  $opt_suffix="_fast" if (!length($opt_suffix));
}

if ($opt_odbc)
{
   $opt_suffix="_odbc" if (!length($opt_suffix));
}

if (!$opt_silent)
{
  print "Testing server '" . $server->version() . "' at $date\n\n";
}

if ($opt_debug)
{
  print "\nCurrent limits: \n";
  foreach $key (sort keys %$limits)
  {
    print $key . " " x (30-length($key)) . $limits->{$key} . "\n";
  }
  print "\n";
}

#
# Some help functions
#

sub skip_arguments
{
  my($argv,@skip_args)=@_;
  my($skip,$arg,$name,@res);

  foreach $arg (@$argv)
  {
    if ($arg =~ /^\-+([^=]*)/)
    {
      $name=$1;
      foreach $skip (@skip_args)
      {
	if (index($skip,$name) == 0)
	{
	  $name="";		# Don't use this parameters
	  last;
	}
      }
      push (@res,$arg) if (length($name));
    }
  }
  return @res;
}


sub merge_limits
{
  my ($server,$cmp)= @_;
  my ($name,$tmp_server,$limits,$res_limits,$limit,$tmp_limits);

  $res_limits=$server->{'limits'};
  if ($cmp)
  {
    foreach $name (split(",",$cmp))
    {
      $tmp_server= (get_server($name,$opt_host, $opt_database,
			       $opt_odbc,machine_part(),$opt_socket,$opt_connect_options,
			       1 # <-   in --cmp, just get limits;
			       )
		    || die "Unknown SQL server: $name\n");
      $limits=$tmp_server->{'limits'};
      %new_limits=();
      foreach $limit (keys(%$limits))
      {
	if (defined($res_limits->{$limit}) && defined($limits->{$limit}))
	{
	  $new_limits{$limit}=min($res_limits->{$limit},$limits->{$limit});
	}
      }
      %tmp_limits=%new_limits;
      $res_limits=\%tmp_limits;
    }
  }
  return $res_limits;
}

sub date
{
  my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
  sprintf("%04d-%02d-%02d %2d:%02d:%02d",
	  1900+$year,$mon+1,$mday,$hour,$min,$sec);
}

sub min
{
  my($min)=$_[0];
  my($i);
  for ($i=1 ; $i <= $#_; $i++)
  {
    $min=$_[$i] if ($min > $_[$i]);
  }
  return $min;
}

sub max
{
  my($max)=$_[0];
  my($i);
  for ($i=1 ; $i <= $#_; $i++)
  {
    $max=$_[$i] if ($max < $_[$i]);
  }
  return $max;
}


#
# Execute many statements in a row
#

sub do_many
{
  my ($dbh,@statements)=@_;
  my ($statement,$sth);

  foreach $statement (@statements)
  {
    if (!($sth=$dbh->do($statement)))
    {
      die "Can't execute command '$statement'\nError: $DBI::errstr\n";
    }
  }
}

sub safe_do_many
{
  my ($dbh,@statements)=@_;
  my ($statement,$sth);

  foreach $statement (@statements)
  {
    if (!($sth=$dbh->do($statement)))
    {
      print STDERR "Can't execute command '$statement'\nError: $DBI::errstr\n";
      return 1;
    }
  }
  return 0;
}



#
# Do a query and fetch all rows from a statement and return the number of rows
#

sub fetch_all_rows
{
  my ($dbh,$query,$must_get_result)=@_;
  my ($count,$sth);
  $count=0;

  print "$query: " if ($opt_debug);
  if (!($sth= $dbh->prepare($query)))
  {
    print "\n" if ($opt_debug);
    die "Error occured with prepare($query)\n -> $DBI::errstr\n";
    return undef;
  }
  if (!$sth->execute)
  {
    print "\n" if ($opt_debug);
    if (defined($server->{'error_on_execute_means_zero_rows'}) &&
       !$server->abort_if_fatal_error())
    {
      if (defined($must_get_result) && $must_get_result)
      {
	die "Error: Query $query didn't return any rows\n";
      }
      $sth->finish;
      print "0\n" if ($opt_debug);
      return 0;
    }
    die "Error occured with execute($query)\n -> $DBI::errstr\n";
    $sth->finish;
    return undef;
  }
  while ($sth->fetchrow_arrayref)
  {
    $count++;
  }
  print "$count\n" if ($opt_debug);
  if (defined($must_get_result) && $must_get_result && !$count)
  {
    die "Error: Query $query didn't return any rows\n";
  }
  $sth->finish;
  undef($sth);
  return $count;
}

sub do_query
{
  my($dbh,$query)=@_;
  print "$query\n" if ($opt_debug);
  $dbh->do($query) or
    die "\nError executing '$query':\n$DBI::errstr\n";
}

#
# Run a query X times
#

sub time_fetch_all_rows
{
  my($test_text,$result_text,$query,$dbh,$test_count)=@_;
  my($i,$loop_time,$end_time,$count,$rows,$estimated);

  print $test_text . "\n"   if (defined($test_text));
  $count=$rows=0;
  $loop_time=My::Timer::get_timer();
  for ($i=1 ; $i <= $test_count ; $i++)
  {
    $count++;
    $rows+=fetch_all_rows($dbh,$query) or die $DBI::errstr;
    $end_time=My::Timer::get_timer();
    last if ($estimated=predict_query_time($loop_time,$end_time,\$count,$i,
					   $test_count));
  }
  if ($estimated)
  { print "Estimated time"; }
  else
  { print "Time"; }
  print " for $result_text ($count:$rows): " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}


#
# Handle estimated time of the server is too slow
# Returns 0 if one should continue as normal
#

sub predict_query_time
{
  my ($loop_time,$end_time,$count_ref,$loop,$loop_count)= @_;
  my ($k,$tmp);

  if (($end_time->[0] - $loop_time->[0]) > $opt_time_limit)
  {
    # We can't wait until the SUN dies.  Try to predict the end time
    if ($loop != $loop_count)
    {
      $tmp=($end_time->[0] - $loop_time->[0]);
      print "Note: Query took longer then time-limit: $opt_time_limit\nEstimating end time based on:\n";
      print "$$count_ref queries in $loop loops of $loop_count loops took $tmp seconds\n";
      for ($k=0; $k < 3; $k++)
      {
	$tmp=$loop_time->[$k]+($end_time->[$k]-$loop_time->[$k])/$loop*
	  $loop_count;
	$estimated[$k]+=($tmp-$end_time->[$k]);
	$end_time->[$k]=$tmp;
      }
      $$count_ref= int($$count_ref/$loop*$loop_count);
      return 1;
    }
  }
  return 0;
}

#
# standard end of benchmark
#

sub end_benchmark
{
  my ($start_time)=@_;

  $end_time=My::Timer::get_timer();
  if ($estimated[0])
  {
    print "Estimated total time: ";
    $end_time->[0]+=$estimated[0];
    $end_time->[1]+=$estimated[1];
    $end_time->[2]+=$estimated[2];
  }
  else
  {
    print "Total time: "
    }
  print timestr(timediff($end_time, $start_time),"all") . "\n";
  exit 0;
}

sub print_time
{
  my ($estimated)=@_;
  if ($estimated)
  { print "Estimated time"; }
  else
  { print "Time"; }
}

#
# Create a filename part for the machine that can be used for log file.
#

sub machine_part
{
  my ($name,$orig);
  return $opt_machine if (length($opt_machine)); # Specified by user
# Specified by user
  $orig=$name=machine();
  $name="win9$1" if ($orig =~ /win.*9(\d)/i);
  $name="NT_$1" if ($orig =~ /Windows NT.*(\d+\.\d+)/i);
  $name="win2k" if ($orig =~ /Windows 2000/i);
  $name =~ s/\s+/_/g;		# Make the filenames easier to parse
  $name =~ s/-/_/g;
  $name =~ s/\//_/g;
  return $name;
}

sub machine
{
  $name= `uname -s -r -m`;
  if ($?)
  {
    $name= `uname -s -m`;
  }
  if ($?)
  {
    $name= `uname -s`;
  }
  if ($?)
  {
    $name= `uname`;
  }
  if ($?)
  {
    $name="unknown";
  }
  chomp($name); $name =~ s/[\n\r]//g;
  return $name;
}

sub as3apgen
{
  my ($as3ap_db_size, $as3ap_db_overwrite) = @_;

  if (!$as3ap_db_size)
  {
    $as3ap_db_size = 40;
  }

  if ($as3ap_db_size == 4 || $as3ap_db_size == 40 || 
      $as3ap_db_size == 400 || $as3ap_db_size == 4000 ||
      $as3ap_db_size == 40000 || $as3ap_db_size == 400000)
  {
    chomp($cwd = `pwd`);
    if (!opendir(DIR,"$cwd/Data/AS3AP"))
    {
      # Trying to create AS3AP dir

      print "Directory $cwd/Data/AS3AP not exists.\n";
      if (mkdir("$cwd/Data/AS3AP"))
      {
        print "Directory $cwd/Data/AS3AP successfully created\n";
      }
      else
      {
        die "Unable to create AS3AP directory for data files. \n$!\n" 
      }
    }
    else
    {
      if ( ! $as3ap_db_overwrite  && -f "$cwd/Data/AS3AP/uniques" &&
           -f "$cwd/Data/AS3AP/updates" &&  -f "$cwd/Data/AS3AP/hundred" && 
           -f "$cwd/Data/AS3AP/tenpct" && -f "$cwd/Data/AS3AP/tiny")
      {
        print "Found exists as3ap files in $cwd/Data/AS3AP\n";
        print "To force generation process use --as3ap-db-size option\n\n";
        return;
      }
    }

    if ( -x $opt_as3ap_generator )
    {
       $reroute = $opt_debug ? "" : ">/dev/null 2>&1";

       print "Start to generate AS3AP database files.\n";
       print "Logical size of database is $as3ap_db_size Mb.\n";

       $start_gen = My::Timer::get_timer();
       system("$opt_as3ap_generator -s $as3ap_db_size -p $cwd/Data/AS3AP $reroute");

       $exit_value  = $? >> 8;
       die "$opt_as3apgen exited with error code: $?" unless $exit_value == 0;

       print "AS3AP database text files succsesfully generated.\n\n";
       print "Time for as3apgen(1): ",My::Timer::timestr(timediff(My::Timer::get_timer(), $start_gen),"all"),"\n\n";
    }
    else
    {
       die "AS3AP generator $opt_as3ap_generator not found or non executable\n";
    }
  }
  else
  {
    print "Incorrect database size for as3ap test. Use only [4|40|400|4000|40000|400000]\n";
    usage();
    exit;
  }
  return;
}

sub as3ap_cleanup
{
  @as3ap_files = ("uniques", "updates", "tenpct", "hundred", "tiny");

  print "Clean up AS3AP files:";

  chomp($cwd = `pwd`);
  $cwd="$cwd/Data/AS3AP";

  foreach $file (@as3ap_files)
  {
    if (-f "$cwd/$file" && -o "$cwd/$file")
    {
      #Trying to delete file;
      if(! unlink "$cwd/$file")
      {
        print "Can't unlink $cwd/$file.\n";
      }
    }
  }
  print " Done.\n\n";
  print "If you want to leave as3ap files please use '--as3ap-no-cleanup' option\n\n"; 
}

sub lock_many_tables
{
  my ($dbh,$max_tables, $lock_type)=@_;

  $query="LOCK TABLES ";

  for ($i=1 ; $i <= $max_tables ; $i++)
  {
    $query=$query . " bench_$i $lock_type,";
  }
  chop($query);
  $loop_time=My::Timer::get_timer();

  $dbh->do($query) or die $DBI::errstr;

  $end_time=My::Timer::get_timer();
  print "Time for LOCK_MANY_tables_${lock_type} ($max_tables): " .
      My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}

sub unlock_tables
{
  my ($dbh,$lock_type)=@_;
   
  $loop_time=My::Timer::get_timer();
  $dbh->do("UNLOCK TABLES") or die $DBI::errstr;
  $end_time=My::Timer::get_timer();
  print "Time for UNLOCK_TABLES_${lock_type} ($max_tables): " .
      My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}


sub flush_tables
{
  my ($dbh,$lock_type)=@_;
  my $lock_mode="";
   
  if ($lock_type)
  {
    $lock_mode="_${lock_type}";
    $lock_mode=~s/ /\_/g;
  }
   
  $loop_time=My::Timer::get_timer();
  $dbh->do("FLUSH TABLES $lock_type") or die $DBI::errstr;
  $end_time=My::Timer::get_timer();
  print "Time for FLUSH_TABLES${lock_mode} ($max_tables): " .
      My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}


sub select_from_tables
{
  my ($dbh,$max_tables, $loop_count, $transaction, $warmup)=@_;
  $test_desc="ONE_table";

  if ($max_tables>1)
  {
    $test_desc="MANY_tables";
  }

  if ($transaction)
  {
    $test_desc.="_in_transaction"
  }
  else
  {
    $test_desc.="_no_transaction"
  }

  if ($warmup)
  {
    $test_desc.="_warmup";
  }

  $dbh->{'AutoCommit'} = 0  if ($transaction);

  $loop_time=My::Timer::get_timer();
  for ($i=1 ; $i <= $max_tables ; $i++)
  {
    for ($j=1; $j <= $loop_count; $j++)
    {
      $dbh->do("select * from  bench_$i") or die $DBI::errstr;
    }
  }

  if ($transaction)
  {
    $dbh->commit();
    $dbh->{'AutoCommit'} = 1;
  }

  $end_time=My::Timer::get_timer();
  print "Time for select_${test_desc} ($max_tables:$loop_count): " .
     My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}

sub create_many_tables
{
  ### Test how the database can handle many tables
  ### Create $max_tables ; Access all off them with a simple query
  ### and then drop the tables

  my ($dbh,$max_tables)=@_;

  for ($i=1 ; $i <= $max_tables ; $i++)
  {
    $dbh->do("drop table bench_$i" . $server->{'drop_attr'});
  }
  print "Testing create of tables\n";

  $loop_time=My::Timer::get_timer();

  for ($i=1 ; $i <= $max_tables ; $i++)
  {
    if (do_many($dbh,$server->create("bench_$i",
   				   ["i int NOT NULL",
				    "d double",
				    "f float",
				    "s char(10)",
				    "v varchar(100)"],
				   ["primary key (i)"])))
    {
      # Got an error; Do cleanup
      for ($i=1 ; $i <= $max_tables ; $i++)
      {
        $dbh->do("drop table bench_$i" . $server->{'drop_attr'});
      }
      die "Test aborted";
    }
  }

  $end_time=My::Timer::get_timer();
  print "Time for create_MANY_tables ($max_tables): " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
}

sub drop_many_tables
{
  ####
  #### Now we are going to drop $max_tables tables;
  ####

  my ($dbh,$max_tables, $lock)=@_;
  my $lock_mode="";

  if ($lock)
  {
    lock_many_tables($dbh,$max_tables,"WRITE");
    $lock_mode="_with_LOCK_WRITE";
  }

  $loop_time=My::Timer::get_timer();

  if ($opt_fast && $server->{'limits'}->{'multi_drop'} &&
      $server->{'limits'}->{'query_size'} > 11+$max_tables*10)
  {
    my $query="drop table bench_1";
    for ($i=2 ; $i <= $max_tables ; $i++)
    {
      $query.=",bench_$i";
    }
    $sth = $dbh->do($query . $server->{'drop_attr'}) or die $DBI::errstr;
  }
  else
  {
    for ($i=1 ; $i <= $max_tables ; $i++)
    {
      $sth = $dbh->do("drop table bench_$i" . $server->{'drop_attr'})
             or die $DBI::errstr;
    }
  }
  $end_time=My::Timer::get_timer();
  print "Time for drop_table_when_MANY_tables${lock_mode} ($max_tables): " .
      My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";

}

sub create_many_func
{
  my ($dbh,$max_func)=@_;
  
  for ($i=1;$i<=$max_func;$i++)
  {
    $dbh->do("drop function if exists f${i}") or die DBI::errstr;
  }

  $func_list="f1()";
  $loop_time=My::Timer::get_timer();
  for ($i=1;$i<=$max_func;$i++)
  {
    $table_list="bench_".(($i-1)*60+1);
    for ($j=2;$j<61;$j++)
    {
      $table_list.=",bench_".(($i-1)*60+$j);
    }
    $dbh->do("CREATE FUNCTION f${i}() RETURNS int RETURN (select count(*) from ".$table_list .")") or die DBI::errstr;
    $func_list.=",f$i()";
  }
  $end_time=My::Timer::get_timer();
  print "Time for create_many_functions (".($max_func)."): " .
         My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
                          
  print "Created $max_func functions. Each function accesses 60 tables. Total accessed tables: ",$max_func*60,"\n";  
}

sub open_many_tables
{
  my ($dbh,$max_func,$mode)=@_;
  
  my $func_list="SELECT f1()";
  my $i=1;

  do 
  {
    $i++;
    $func_list.=",f$i()";
    if ((!($i % 10) && $mode==1) || $i==$max_func)
    {
      $loop_time=My::Timer::get_timer();
      $dbh->do($func_list) or die $DBI::errstr;
      $end_time=My::Timer::get_timer();
      print "Time for open_many_tables_IN_1_connecion (".($i*60)."): " .
              My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";
    }
  } while($i<$max_func);
}

sub select_with_flush
{
  my ($dbh,$test_name,$table_name,$max_loop,$skip_flush)=@_;
  
  my @select_time=();
  my @flush_tim=();
  my $select_time;
  my $flush_time;

  $dbh->do('flush tables');
  $sth=$dbh->prepare("select * from $table_name");

  $loop_time=My::Timer::get_timer();

  for ($i=1 ; $i <= $max_loop ; $i++)
  {
    $loop_select_time=new Benchmark;
    $n=$sth->execute or die "Error: $DBI::errstr";
    while(@row=$sth->fetchrow_array)
    {};
    $end_select_time=new Benchmark;
    push @select_time,[$loop_select_time,$end_select_time];
  
    if (!$skip_flush)
    {
      $loop_flush_time=new Benchmark;
      $dbh->do('flush tables') or die "Error: $DBI::errstr";
      $end_flush_time=new Benchmark;
      push @flush_time,[$loop_flush_time,$end_flush_time];
    }
  } 

  $end_time=My::Timer::get_timer();
  print "Time for $test_name ($max_loop): " .
    My::Timer::timestr(timediff($end_time, $loop_time),"all") . "\n\n";

  $sth->finish();

  $select_time=timediff($select_time[0]->[1],$select_time[0]->[0]);
  $flush_time=timediff($flush_time[0]->[1],$flush_time[0]->[0]) if(!$skip_flush);

  for ($i=0 ; $i < $max_loop ; $i++)
  {
    $select_time=timesum($select_time,timediff($select_time[$i]->[1],$select_time[$i]->[0]));
    $flush_time=timesum($flush_time,timediff($flush_time[$i]->[1],$flush_time[$i]->[0])) if (!$skip_flush);
  }

  printf ("select * from bench_merge - %7.3f\n",timestr($select_time));
  printf ("flush tables              - %7.3f\n",timestr($flush_time)) if (!$skip_flush);
  print "\n";
}


#
# Usage
#

sub usage
{
    print <<EOF;
The MySQL benchmarks Ver $benchmark_version

All benchmark scripts take the following options, except as noted below:

--comments='string'
  Add a comment to the benchmark output.  Comments should contain extra
  information that 'uname -a' doesn't provide and should indicate whether
  the database server was started with some specific, non default, options.

--cmp=server[,server...]
  Run the test with limits from the given servers.  If you run all servers
  with the same --cmp, you will get a test that is comparable between
  the different sql servers.

--create-options='string'
  Additional options for CREATE TABLE statements.  For example, to
  create all MySQL tables as BDB tables, use:
  --create-options=TYPE=BDB
  
--create-index-options='string'
  Additional options for CREATE INDEX statements.  For example, to
  create all indexes as BTREE indexes, use:
  --create-index-options='USING BTREE' 
  It works for postgresql and mysql with HEAP tabletype.

--database=db_name (Default: $opt_database)
  The database in which to create the test tables.

--debug
  This is a test-specific option that is used only when debugging a test.
  It causes printing of debugging information.

--dir=dir_name (Default: $opt_dir)
  Option for 'run-all-tests' to specify the directory where the benchmark
  result output files should be stored.

--fast
  Allow the benchmark tests to use non-standard SQL statements to make the
  tests go faster.

--fast-insert
  Use "INSERT INTO table_name VALUES(...)" instead of
  "INSERT INTO table_name (....) VALUES(...)"
  Also, if the database server supports it, some tests uses multiple
  VALUES lists.

--field-count=num
  This is a test-specific option that is used only when debugging a test.
  It usually indicates how many fields there should be in the test table.

--force
  This is a test-specific option that is used only when debugging a test.
  It causes the test to continue even if there is some error.
  It also causes tables to be deleted before creating new ones.

--groups=num (Default: $opt_groups)
  This is a test-specific option that is used only when debugging a test.
  It usually indicates how many different groups there should be in the test.

--lock-tables
  Allow the database server to use table locking to get more speed.

--log
  Option for 'run-all-tests' to specify that benchmark summary results
  should be written to a RUN file in the output directory.  Without this
  option, summary results are written to stdout.

--loop-count=num (Default: $opt_loop_count)
  This is a test-specific option that is used only when debugging a test.
  It usually indicates how many times each test loop is executed.

--help
  Display this help message.

--hires={0,1} (Default: $opt_hires)
  Disable or enable use of Time::HiRes module for timing.

--host='host name' (Default: $opt_host)
  Host name where the database server is located.

--machine="machine or os_name"
  The machine/os name that to add to the benchmark output filename.
  The default is the OS name + version.

--odbc
  Use the ODBC DBI driver to connect to the database server.

--password='password'
  Password for the current user.

--socket='filename'
  If the database server supports connecting through a Unix socket file,
  use this socket file to connect.

--regions
  This is a test-specific option that is used only when debugging a test.
  This usually means how AND levels should be tested.

--old-headers
  Get the old benchmark headers from the old RUN- file.

--server='server name'  (Default: $opt_server)
  Run the test on the given SQL server.
  Known server names are: Access, Adabas, AdabasD, Empress, Oracle,
  Interbase, Firebird,  Informix, DB2, mSQL, MS-SQL, MySQL, Pg, Solid, 
  Sybase-ASA, Sybase-ASE, SAPdb, and SQLite

--silent
  Don't print information about the server when starting the test.

--skip-delete
  This is a test-specific option that is used only when debugging a test.
  It causes test tables not to be deleted after the test is run.

--skip-test=test1[,test2,...]
  Option to 'run-all-programs' not to execute the named tests.

--small-test
  This option runs some tests with smaller limits to get a faster test.
  It can be used if you just want to verify that the database server works,
  but don't have time to run a full test.

--small-tables
  This option causes some tests that normally generate large tables to use
  fewer rows.  It can be used with databases that can't handle the normal
  table sizes because of pre-sized partitions.

--suffix='string' (Default: $opt_suffix)
  The suffix that is added to the database name in the benchmark output
  filename. By varying the suffix, you can run benchmarks several times
  with different server options without overwriting existing output files.
  If you specify the --fast option, the suffix is automatically set to
  '_fast'.

--random
  Instruct the test suite to generate random initial values for sequence of
  test executions. It should be used for imitation of real conditions.

--threads=num (Default: 5)
  Number of threads for multi-user benchmarks.

--tcpip
  Inform test suite that we are using TCP/IP to connect to the server. In
  this case we cannot do many new connections in a row because we may fill
  the TCP/IP stack.

--time-limit=num (Default: $opt_time_limit)
  How long a test loop is allowed to take, in seconds, before the end result
  is 'estimated'.

--use-old-results
  Option to 'run-all-tests' to use the old results from the  '--dir' directory
  instead of running the tests.

--user='user_name'
  User name to log into the SQL server.

--verbose
  This is a test-specific option that is used only when debugging a test.
  It causes more information to be printed about what is going on.

--optimization='some comments'
  Add comments about optimization of DBMS that was performed before the test.
 
--hw='some comments'
  Add comments about hardware used for the test.

--fs='some comments'
  Add comments about filesystem used for the test.

--connect-options='some connect options'
  Additional options to be used when DBI connects to the server.
  Examples:
  --connect-options=mysql_read_default_file=/etc/my.cnf
  --connect-options=mysql_socket=/tmp/mysql.sock

--as3ap-db-size='DB size' 
  Generate database text files for AS3AP test and puts them in Data/AS3AP.
  Allowable values of DB size are 4, 40, 400, 4000, 40000, 400000 Mb. Be
  careful, because you can overwrite existing database text files.

--as3ap-generator='filename' (Default: $opt_as3ap_generator)
  Please specify here full path + filename for the 'as3ap generator' program
  if it is placed in a non-default location.

--as3ap-no-load
  Do not load as3ap data files into the database.

--as3ap-no-query-cache
  Prevent use of query cache technology by adding a unique prefix to
  every query.

--as3ap-no-single
  Disable execution of the single-user section of the as3ap test.

--as3ap-no-multi
  Disable execution of the multiple-user section of the as3ap test.

--as3ap-no-cleanup
  Do not clean up as3ap files from the Data/AS3AP directory.

--max-table-size=size
   test-insert will use tables with specified size. Size can be number
   (value in bytes),  or number with suffix K (in kilobytes), M (megabytes) or
   G (gigabytes). For example --max-table-size=2G

--assume-mysql-version=string
--assume-mysql-tabletype=string
   These options must be used in conjunction with --cmp=mysql. They define 
   the MySQL version and table type that the current DBMS is compared with.
   Default values are 4.0.14 for --assume-mysql-version and myisam for
   --assume-mysql-tabletype.  The version string must be in N.NN.NN format
  (for example, 3.23.56 or 4.1.1).  The table type must be innodb, myisam,
  isam, bdb, gemini, or heap.

EOF
  exit(0);
}



####
#### The end of the base file ...
####
1;
