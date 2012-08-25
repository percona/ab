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
##################### Standard benchmark inits ##############################

use DBI;
use Benchmark;
use My::Timer;

$opt_loop_count=10000; # Change this to make test harder/easier
# This is the default value for the amount of tables used in this test.

chomp($pwd = `pwd`); $pwd = "." if ($pwd eq '');
require "$pwd/bench-init.pl" || die "Can't read Configuration file: $!\n";

$create_loop_count=$opt_loop_count;
if ($opt_small_test)
{
  $opt_loop_count/=100;
  $create_loop_count/=1000;
}

$max_tables=min($limits->{'max_tables'},$opt_loop_count);

if ($opt_small_test)
{
  $max_tables=10;
}

print "Testing the speed of operations that utilize MDL locking\n";
print "Testing with $max_tables tables and $opt_loop_count loop count\n\n";

####
####  Connect and start timeing
####

$dbh = $server->connect();

#$max_tables=10000;
$max_func=int($max_tables/60);

$start_time=My::Timer::get_timer();

#preparing tables
create_many_tables($dbh,$max_tables);
create_many_func($dbh,$max_func);

#warmup
select_from_tables($dbh,$max_tables,1,'',1);

open_many_tables($dbh,$max_func,0);

#warmup
select_from_tables($dbh,$max_tables,1,'',1);

#Test 1 - select from every table in transaction 
print "Testing SELECT from  many tables($max_tables) in transaction\n";
select_from_tables($dbh,$max_tables,1,1,'');

#Test 2 - select from one table 
print "Testing SELECT from one table $opt_loop times\n";
select_from_tables($dbh,1,10000, '', '');

#warmup
select_from_tables($dbh,$max_tables,1,'',1);
#Test 3 - FLUSH TABLES 
print "Testing FLUSH TABLES\n";
flush_tables($dbh,'');

#warmup  
select_from_tables($dbh,$max_tables,1,'',1);
#Test 4 - FLUSH_TABLES_WITH_READ_LOCK
print "Testing FLUSH TABLES ... WITH READ LOCK\n";
flush_tables($dbh,"WITH READ LOCK");

#warmup
select_from_tables($dbh,$max_tables,1,'',1);

#Test 5 - LOCK TABLES ... READ
print "Testing LOCK TABLES ... READ  many tables($max_tables)\n";
lock_many_tables($dbh,$max_tables,"READ");
unlock_tables($dbh,"READ");

#Test 6 - LOCK TABLES ... WRITE 
print "Testing LOCK TABLES ... WRITE  many tables($max_tables)\n";
lock_many_tables($dbh,$max_tables,"WRITE");
unlock_tables($dbh,"WRITE");

#Test 7 - DROP TABLE 
print "Testing drop many tables($max_tables)\n";
drop_many_tables($dbh,$max_tables,undef);

#preparing tables
create_many_tables($dbh,$max_tables);

#warmup
select_from_tables($dbh,$max_tables,1,'',1);
#Test 8 - DROP TABLE with LOCK TABLES ... WRITE 
print "Testing drop many tables($max_tables) with LOCK TABLES ... WRITE\n";
drop_many_tables($dbh,$max_tables,1);

$dbh->disconnect;				# close connection
end_benchmark($start_time);


