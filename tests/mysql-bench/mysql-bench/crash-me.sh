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

# Written by Monty Widenius for the TCX/Monty Program/Detron benchmark suite.
# Empress and PostgreSQL patches by Luuk de Boer
# Extensions for ANSI/ISO SQL and Mimer by Bengt Gunne
# Some additions and corrections by Matthias Urlich
#
# This programs tries to find all limits for a sql DBMS
# It gets the name from what it does to most servers :)
#
# Be sure to use --help before running this!
#
# If you want to add support for another server, add a new package for the
# server in server-cfg.  You only have to support the 'new' and 'version'
# functions. new doesn't need to have any limits if one doesn't want to
# use the benchmarks.
#

# TODO:
# CMT includes types and functions which are synonyms for other types
# and functions, including those in SQL9x. It should label those synonyms
# as such, and clarify ones such as "mediumint" with comments such as
# "3-byte int" or "same as xxx".

$version="1.62";

use DBI;
use Getopt::Long;
chomp($pwd = `pwd`); $pwd = "." if ($pwd eq '');
require "$pwd/server-cfg" || die "Can't read Configuration file: $!\n";

$opt_server="mysql"; $opt_host="localhost"; $opt_database="test";
$opt_dir="limits";
$opt_user=$opt_password="";$opt_verbose=1;
$opt_debug=$opt_help=$opt_restart=$opt_force=$opt_quick=$opt_odbc=0;
$opt_log_all_queries=$opt_fix_limit_file=$opt_batch_mode=$opt_version=0;
$opt_db_start_cmd="";           # the db server start command
$opt_check_server=0;		# Check if server is alive before each query
$opt_sleep=10;                  # time to sleep while starting the db server
$limit_changed=0;               # For configure file
$reconnect_count=0;
$opt_suffix=$opt_socket=$opt_connect_options="";
$opt_comment=$opt_config_file=$opt_log_queries_to_file="";
$limits{'crash_me_safe'}='yes';
$prompts{'crash_me_safe'}='crash me safe';
$limits{'operating_system'}= machine();
$prompts{'operating_system'}='crash-me tested on';
$retry_limit=3;

GetOptions("help","server=s","debug","user=s","password=s",
"database=s","restart","force","quick","log-all-queries","comment=s",
"host=s","fix-limit-file","dir=s","db-start-cmd=s","sleep=s","suffix=s",
"batch-mode","config-file=s","log-queries-to-file=s","check-server",
"version","socket=s", "connect_options=s", "odbc",
"verbose!" => \$opt_verbose) || usage();
usage() if ($opt_help);
version() && exit(0) if ($opt_version);

$opt_suffix .= "_odbc" if ($opt_odbc); 
$opt_suffix = '-'.$opt_suffix if (length($opt_suffix));
$opt_config_file = "$pwd/$opt_dir/$opt_server$opt_suffix.cfg"
  if (length($opt_config_file) == 0);
$log_prefix='   ###';  # prefix for log lines in result file
$safe_query_log='';
$safe_query_result_log='';
$log{"crash-me"}="";

#!!!

if ($opt_fix_limit_file)
{
  print "Fixing limit file for $opt_server\n";
  read_config_data();
  $limit_changed=1;
  save_all_config_data();
  exit 0;
}

$server=get_server($opt_server,$opt_host,$opt_database, $opt_odbc,
                   "", $opt_socket, $opt_connect_options);
$opt_server=$server->{'cmp_name'};

$|=1;                           # For debugging

print "Running $0 $version on '",($server_version=$server->version()),"'\n\n";
print "I hope you didn't have anything important running on this server....\n";
read_config_data();
if ($limit_changed)             # Must have been restarted
{
  save_config_data('crash_me_safe','no',"crash me safe");
}

if (!$opt_force && !$opt_batch_mode)
{
  server_info();
}
else
{
  print "Using --force.  I assume you know what you are doing...\n";
}
print "\n";

save_config_data('crash_me_version',$version,"crash me version");
if ($server_version)
{
  save_config_data('server_version',$server_version,"server version");
}
if (length($opt_comment))
{
  save_config_data('user_comment',$opt_comment,"comment");
}

$opt_log=0;
if (length($opt_log_queries_to_file))
{
  open(LOG,">$opt_log_queries_to_file") || 
    die "Can't open file $opt_log_queries_to_file\n";
  $opt_log=1;
}

#
# Set up some limits for items regared as unlimited
# We don't want to take up all resources from the server...
#

$max_connections="+1000";       # Number of simultaneous connections
$max_buffer_size="+16000000";   # size of communication buffer.
$max_string_size="+8000000";    # Enough for this test
$max_name_length="+512";        # Actually 256, but ...
$max_keys="+64";                # Probably too big.
$max_join_tables="+64";         # Probably too big.
$max_columns="+8192";           # Probably too big.
$max_row_length=$max_string_size;
$max_key_length="+8192";        # Big enough
$max_order_by="+64";		# Big enough
$max_expressions="+10000";
$max_big_expressions="+100";
$max_stacked_expressions="+2000";
$query_size=$max_buffer_size;
$longreadlen=16000000;		# For retrieval buffer


#
# First do some checks that are needed for the rest of the benchmark
# 
#
use sigtrap;		       # Must be removed with perl5.005_2 on Win98
$SIG{PIPE} = 'IGNORE';
$problem_counter=0;
$SIG{SEGV} = sub {
  $problem_counter +=1;
  if ($problem_counter >= 100) {
    die("Too many problems, try to restart");
  } else {
    warn('SEGFAULT');
  };    
};
$dbh=safe_connect();

#
# Test if the DBMS  require RESTRICT/CASCADE after DROP TABLE
#

# Really remove the crash_me table
$prompt="drop table require cascade/restrict";
$drop_attr="";
$dbh->do("drop table crash_me");
$dbh->do("drop table crash_me cascade");
if (!safe_query_l('drop_requires_cascade',
         ["create table crash_me (a integer not null)",
		 "drop table crash_me"]))
{
  $dbh->do("drop table crash_me cascade");  
  if (safe_query_l('drop_requires_cascade',
        ["create table crash_me (a integer not null)",
		  "drop table crash_me cascade"]))
  {
    save_config_data('drop_requires_cascade',"yes","$prompt");
    $drop_attr="cascade";
  }
  else
  {
    #die "Can't create and drop table 'crash_me'\n";
    add_log('drop_requires_cascade',
            "Can't create and drop table 'crash_me'\n");
    save_config_data('drop_requires_cascade',"no","$prompt");
  }
}
else
{
  save_config_data('drop_requires_cascade',"no","$prompt");
  $drop_attr="";
}

# Remove tables from old runs
$dbh->do("drop table crash_me $drop_attr");
$dbh->do("drop table crash_me2 $drop_attr");
$dbh->do("drop table crash_me3 $drop_attr");
$dbh->do("drop table crash_q $drop_attr");
$dbh->do("drop table crash_q1 $drop_attr");

$dbh->do("drop table crash_me_t1 $drop_attr");
$dbh->do("drop table crash_me_t2 $drop_attr");
$dbh->do("drop table crash_me_t10 $drop_attr");

$prompt="Tables without primary key";
if (!safe_query_l('no_primary_key',
      ["create table crash_me (a integer not null,b char(10) not null)",
		 "insert into crash_me (a,b) values (1,'a')"]))
{
  if (!safe_query_l('no_primary_key',
      ["create table crash_me (a integer not null,b char(10) not null".
        ", primary key (a))",
	 "insert into crash_me (a,b) values (1,'a')"]))
  {
    #die "Can't create table 'crash_me' with one record: $DBI::errstr\n";
    add_log('no_primary_key',
            "Can't create table 'crash_me' with one record: $DBI::errstr\n");
  }
  save_config_data('no_primary_key',"no",$prompt);
}
else
{
  save_config_data('no_primary_key',"yes",$prompt);
}

#
#  Define strings for character NULL and numeric NULL used in expressions
#
$char_null=$server->{'char_null'};
$numeric_null=$server->{'numeric_null'};
if ($char_null eq '')
{
  $char_null="NULL";
}
if ($numeric_null eq '')
{
  $numeric_null="NULL";
}

print "$prompt: $limits{'no_primary_key'}\n";

report("SELECT without FROM",'select_without_from',"select 1");
if ($limits{'select_without_from'} ne "yes")
{
  $end_query=" from crash_me";
  $check_connect="select a from crash_me";
}
else
{
  $end_query="";
  $check_connect="select 1";
}

assert($check_connect);
assert("select a from crash_me where b<'b'");

report("Select constants",'select_constants',"select 1 $end_query");
report("Select table_name.*",'table_wildcard',
       "select crash_me.* from crash_me");

unless ( $server_version =~ /ODBC/) {
  report("database.table syntax",'db_table_syntax',
       "select * from $opt_database.crash_me");
}
 else 
{
 add_log('db_table_syntax','dont test this parameter, because our connection is over ODBC');
 save_config_data('db_table_syntax','incompleted','database.table syntax');
 print "db_table_syntax:\tincompleted \n";
} 
       
report("Allows \' and \" as string markers",'quote_with_"',
       'select a from crash_me where b<"c"');
check_and_report("Double '' as ' in strings",'double_quotes',[],
		 "select 'Walker''s' $end_query",[],"Walker's",1);
check_and_report("Multiple line strings","multi_strings",[],
		 "select a from crash_me where b < 'a'\n'b'",[],"1",0);
check_and_report("\" as identifier quote (ANSI SQL)",'quote_ident_with_"',[],
		 'select "A" from crash_me',[],"1",0);
check_and_report("\` as identifier quote",'quote_ident_with_`',[],
		 'select `A` from crash_me',[],"1",0);
check_and_report("[] as identifier quote",'quote_ident_with_[',[],
		 'select [A] from crash_me',[],"1",0);
report('Double "" in identifiers as "','quote_ident_with_dbl_"',
        'create table crash_me1 ("abc""d" integer)',
	'drop table crash_me1');		 

report("Column alias","column_alias","select a as ab from crash_me");
report_one("Table alias","table_alias",[["select b.a from crash_me as b","yes"],
                                        ["select b.a from crash_me b ","without_AS"]]);
report("Functions",'functions',"select 1+1 $end_query");
report("Group functions",'group_functions',"select count(*) from crash_me");
report("Group functions with distinct",'group_distinct_functions',
       "select count(distinct a) from crash_me");
report("Group functions with several distinct",'group_many_distinct_functions',
       "select count(distinct a), count(distinct b) from crash_me");
report("Group by",'group_by',"select a from crash_me group by a");
report("Group by position",'group_by_position',
       "select a from crash_me group by 1");
report("Group by alias",'group_by_alias',
       "select a as ab from crash_me group by ab");
report("Group on unused column",'group_on_unused',
       "select count(*) from crash_me group by a");

report("Order by",'order_by',"select a from crash_me order by a");
report("Order by position",'order_by_position',
       "select a from crash_me order by 1");
report("Order by function","order_by_function",
       "select a from crash_me order by a+1");
report("Order by on unused column",'order_on_unused',
       "select b from crash_me order by a");
# little bit deprecated
#check_and_report("Order by DESC is remembered",'order_by_remember_desc',
#		 ["create table crash_q (s int,s1 int)",
#		  "insert into crash_q values(1,1)",
#		  "insert into crash_q values(3,1)",
#		  "insert into crash_q values(2,1)"],
#		 "select s,s1 from crash_q order by s1 DESC,s",
#		 ["drop table crash_q $drop_attr"],[3,2,1],7,undef(),3);
report("Compute",'compute',
       "select a from crash_me order by a compute sum(a) by a");
report("INSERT with Value lists",'insert_multi_value',
       "create table crash_q (s char(10))",
       "insert into crash_q values ('a'),('b')",
       "drop table crash_q $drop_attr");
report("INSERT with set syntax",'insert_with_set',
       "create table crash_q (a integer)",
       "insert into crash_q SET a=1",
       "drop table crash_q $drop_attr");
report("INSERT with DEFAULT","insert_with_default",
       "create table crash_me_q (a int)",
       "insert into crash_me_q (a) values (DEFAULT)",
       "drop table crash_me_q $drop_attr");

report("INSERT with empty value list","insert_with_empty_value_list",
       "create table crash_me_q (a int)",
       "insert into crash_me_q (a) values ()",
       "drop table crash_me_q $drop_attr");

report("INSERT DEFAULT VALUES","insert_default_values",
       "create table crash_me_q (a int)",
       "insert into crash_me_q  DEFAULT VALUES",
       "drop table crash_me_q $drop_attr");
       
report("allows end ';'","end_colon", "select * from crash_me;");
try_and_report("LIMIT number of rows","select_limit",
	       ["with LIMIT",
		"select * from crash_me limit 1"],
	       ["with TOP",
		"select TOP 1 * from crash_me"]);
report("SELECT with LIMIT #,#","select_limit2", 
      "select * from crash_me limit 1,1");
report("SELECT with LIMIT # OFFSET #",
      "select_limit3", "select * from crash_me limit 1 offset 1");

# The following alter table commands MUST be kept together!
if ($dbh->do("create table crash_q (a integer, b integer,c1 CHAR(10))"))
{
  report("Alter table add column",'alter_add_col',
	 "alter table crash_q add d integer");
  report_one("Alter table add many columns",'alter_add_multi_col',
	     [["alter table crash_q add (f integer,g integer)","yes"],
	      ["alter table crash_q add f integer, add g integer","with add"],
	      ["alter table crash_q add f integer,g integer","without add"]] );
  report("Alter table change column",'alter_change_col',
	 "alter table crash_q change a e char(50)");

  # informix can only change data type with modify
  report_one("Alter table modify column",'alter_modify_col',
	     [["alter table crash_q modify c1 CHAR(20)","yes"],
	      ["alter table crash_q alter c1 CHAR(20)","with alter"]]);
  report("Alter table alter column default",'alter_alter_col',
	 "alter table crash_q alter b set default 10");
  report_one("Alter table drop column",'alter_drop_col',
	     [["alter table crash_q drop column b","yes"],
	      ["alter table crash_q drop column b restrict",
	      "with restrict/cascade"]]);
  report("Alter table rename table",'alter_rename_table',
	 "alter table crash_q rename to crash_q1");
}
# Make sure both tables will be dropped, even if rename fails.
$dbh->do("drop table crash_q1 $drop_attr");
$dbh->do("drop table crash_q $drop_attr");

$dbh->do("create table crash_q (c1 CHAR(10))");

report_one("rename table","rename_table",[
       ["rename table crash_q to crash_q1","yes"],
       ["rename crash_q to crash_q1","oracle_syntax"]
       ]);
# Make sure both tables will be dropped, even if rename fails.
$dbh->do("drop table crash_q1 $drop_attr");
$dbh->do("drop table crash_q $drop_attr");

report("truncate","truncate_table",
       "create table crash_q (a integer, b integer,c1 CHAR(10))",
       "truncate table crash_q",
       "drop table crash_q $drop_attr");

if (safe_query([create_table("crash_q",
            ["a integer","b integer","c1 CHAR(10)"],
          ["index (c1)"])]) 
          and safe_query([create_table("crash_q1",
          ["a integer","b integer","c1 CHAR(10) not null"],["index (c1)"])]))
 
{
  report("Alter table add constraint",'alter_add_constraint',
	 "alter table crash_q add constraint c2 check(a > b)");
  report_one("Alter table drop constraint",'alter_drop_constraint',
	     [["alter table crash_q drop constraint c2","yes"],
	      ["alter table crash_q drop constraint c2 restrict",
	      "with restrict/cascade"]]);
  report("Alter table add unique",'alter_add_unique',
	 "alter table crash_q add constraint u1 unique(c1)");
  try_and_report("Alter table drop unique",'alter_drop_unique',
		 ["with constraint",
		  "alter table crash_q drop constraint u1"],
		 ["with constraint and restrict/cascade",
		  "alter table crash_q drop constraint u1 restrict"],
		 ["with drop key",
		  "alter table crash_q drop key c1"]);
  try_and_report("Alter table add primary key",'alter_add_primary_key',
		 ["with constraint",
		  "alter table crash_q1 add constraint p1 primary key(c1)"],
		 ["with add primary key",
		  "alter table crash_q1 add primary key(c1)"]);
  report("Alter table add foreign key",'alter_add_foreign_key',
	 "alter table crash_q add constraint f1 foreign key(c1)".
	 " references crash_q1(c1)");
  try_and_report("Alter table drop foreign key",'alter_drop_foreign_key',
		 ["with drop constraint",
		  "alter table crash_q drop constraint f1"],
		 ["with drop constraint and restrict/cascade",
		  "alter table crash_q drop constraint f1 restrict"],
		 ["with drop foreign key",
		  "alter table crash_q drop foreign key f1"]);
  try_and_report("Alter table drop primary key",'alter_drop_primary_key',
		 ["drop constraint",
		  "alter table crash_q1 drop constraint p1 restrict"],
		 ["drop primary key",
		  "alter table crash_q1 drop primary key"]);
}
$dbh->do("drop table crash_q $drop_attr");
$dbh->do("drop table crash_q1 $drop_attr");

check_and_report("Case insensitive compare","case_insensitive_strings",
		 [],"select b from crash_me where b = 'A'",[],'a',1);
check_and_report("Ignore end space in compare","ignore_end_space",
		 [],"select b from crash_me where b = 'a '",[],'a',1);
check_and_report("Group on column with null values",'group_by_null',
		 ["create table crash_q (s char(10))",
		  "insert into crash_q values(null)",
		  "insert into crash_q values(null)"],
		 "select count(*),s from crash_q group by s",
		 ["drop table crash_q $drop_attr"],2,0);

$prompt="Having";
if (!defined($limits{'having'}))
{                               # Complicated because of postgreSQL
  if (!safe_query_result_l("having",
      "select a from crash_me group by a having a > 0",1,0))
  {
    if (!safe_query_result_l("having",
           "select a from crash_me group by a having a < 0",
	    1,0))
    { save_config_data("having","error",$prompt); }
    else
    { save_config_data("having","yes",$prompt); }
  }
  else
  { save_config_data("having","no",$prompt); }
}
print "$prompt: $limits{'having'}\n";

if ($limits{'having'} eq 'yes')
{
  report("Having with group function","having_with_group",
	 "select a from crash_me group by a having count(*) = 1");
}

if ($limits{'column_alias'} eq 'yes')
{
  report("Order by alias",'order_by_alias',
	 "select a as ab from crash_me order by ab");
  if ($limits{'having'} eq 'yes')
  {
    report("Having on alias","having_with_alias",
	   "select a as ab from crash_me group by a having ab > 0");
  }
}
report("binary numbers (0b1001)","binary_numbers","select 0b1001 $end_query");
report("hex numbers (0x41)","hex_numbers","select 0x41 $end_query");
report("binary strings (b'0110')","binary_strings","select b'0110' $end_query");
report("hex strings (x'1ace')","hex_strings","select x'1ace' $end_query");

report_result("Value of logical operation (1=1)","logical_value",
	      "select (1=1) $end_query");

report_result("Value of TRUE","value_of_true","select TRUE $end_query");
report_result("Value of FALSE","value_of_false","select FALSE $end_query");

$logical_value= $limits{'logical_value'};

$false=0;
$result="no";
if ($res=safe_query_l('has_true_false',"select (1=1)=true $end_query")) {
  $false="false";
  $result="yes";
}
save_config_data('has_true_false',$result,"TRUE and FALSE");

#
# Check how many connections the server can handle:
# We can't test unlimited connections, because this may take down the
# server...
#

$prompt="Simultaneous connections (installation default)";
print "$prompt: ";
if (defined($limits{'connections'}))
{
  print "$limits{'connections'}\n";
}
else
{
  @connect=($dbh);

  for ($i=1; $i < $max_connections ; $i++)
  {
    if (!($dbh=DBI->connect($server->{'data_source'},$opt_user,$opt_password,
			  { PrintError => 0})))
    {
      print "Last connect error: $DBI::errstr\n" if ($opt_debug);
      last;
    }
    $dbh->{LongReadLen}= $longreadlen; # Set retrieval buffer
    print "." if ($opt_debug);
    push(@connect,$dbh);
  }
  print "$i\n";
  save_config_data('connections',$i,$prompt);
  foreach $dbh (@connect)
  {
    print "#" if ($opt_debug);
    $dbh->disconnect || warn $dbh->errstr;           # close connection
  }

  $#connect=-1;                 # Free connections

  if ($i == 0)
  {
    print "Can't connect to server: $DBI::errstr.".
          "  Please start it and try again\n";
    exit 1;
  }
  $dbh=retry_connect();
}


#
# Check size of communication buffer, strings...
#

$prompt="query size";
print "$prompt: ";
if (!defined($limits{'query_size'}))
{
  $query="select ";
  $first=64;
  $end=$max_buffer_size;
  $select= $limits{'select_without_from'} eq 'yes' ? 1 : 'a';

  assert($query . "$select$end_query");

  $first=$limits{'restart'}{'low'} if ($limits{'restart'}{'low'});

  if ($limits{'restart'}{'tohigh'})
  {
    $end = $limits{'restart'}{'tohigh'} - 1;
    print "\nRestarting this with low limit: $first and high limit: $end\n";
    delete $limits{'restart'};
    $first=$first+int(($end-$first+4)/5);           # Prefere lower on errors
  }
  for ($i=$first ; $i < $end ; $i*=2)
  {
    last if (!safe_query($query . 
            (" " x ($i - length($query)-length($end_query) -1)) 
	      . "$select$end_query"));
    $first=$i;
    save_config_data("restart",$i,"") if ($opt_restart);
  }
  $end=$i;

  if ($i < $max_buffer_size)
  {
    while ($first != $end)
    {
      $i=int(($first+$end+1)/2);
      if (safe_query($query .
		     (" " x ($i - length($query)-length($end_query) -1)) .
		     "$select$end_query"))
      {
	$first=$i;
      }
      else
      {
	$end=$i-1;
      }
    }
  }
  save_config_data('query_size',$end,$prompt);
}
$query_size=$limits{'query_size'};

print "$limits{'query_size'}\n";

#
# Check for reserved words
# This check is for standard SQL foundation reserved words only; other parts
# of the Standard (e.g. SQL/CLI) may define additional reserved keywords.
# 

check_reserved_words($dbh);

#
# Test data types supported by various platforms.
#
@sql_types=(
	    "INT ARRAY", "INT ARRAY[5]",
# Other options include:
# INT ARRAY??(5??)
	    "BIGINT",
	    "BINARY LARGE OBJECT", "BINARY LARGE OBJECT(2K)",
# See BLOB tests for other options.
	    "BLOB", "BLOB(1M)",
# Other options include:
# BLOB(2K CHARACTERS), BLOB(2K OCTETS), BLOB(1K), BLOB(1M), BLOB(1G)
	    "BOOLEAN",
	    "CHAR", "CHAR(5)", "CHARACTER", "CHARACTER(5)",
# Other options include:
# CHAR(5 CHARACTERS), CHAR(5 OCTETS), plus
# CHARACTER SET and COLLATE definitions
	    "CHAR LARGE OBJECT", "CHAR LARGE OBJECT(2K)",
	    "CHARACTER LARGE OBJECT", "CHARACTER LARGE OBJECT(1M)",
# See CLOB tests for other options.
	    "CHAR VARYING(5)", "CHARACTER VARYING(5)",
# See VARCHAR tests for other options.
	    "CLOB", "CLOB(1G)",
# Other options include:
# CLOB(2K CHARACTERS), CLOB(2K OCTETS), CLOB(1K), CLOB(1M), CLOB(1G)
# plus CHARACTER SET and COLLATE definitions
	    "DATE",
	    "DEC(6,2)", "DECIMAL", "DECIMAL(6)", "DECIMAL(6,2)",
	    "DOUBLE PRECISION",
	    "FLOAT", "FLOAT(8)",
	    "INT", "INTEGER",
	    "INTERVAL DAY", "INTERVAL DAY(3)",
	    "INTERVAL DAY TO HOUR", "INTERVAL DAY TO MINUTE",
	    "INTERVAL DAY TO SECOND", "INTERVAL DAY TO SECOND(3)",
# INTERVAL DAY can have a precision for all options
	    "INTERVAL HOUR", "INTERVAL HOUR(3)",
	    "INTERVAL HOUR TO MINUTE",
	    "INTERVAL HOUR TO SECOND", "INTERVAL HOUR TO SECOND(3)",
# INTERVAL HOUR can have a precision for all options
	    "INTERVAL MINUTE", "INTERVAL MINUTE(3)",
	    "INTERVAL MINUTE TO SECOND", "INTERVAL MINUTE TO SECOND(3)",
# INTERVAL MINUTE can have a precision for all options
	    "INTERVAL MONTH", "INTERVAL MONTH(3)",
	    "INTERVAL SECOND", "INTERVAL SECOND(3)", "INTERVAL  SECOND(3,3)",
	    "INTERVAL YEAR", "INTERVAL YEAR(3)", "INTERVAL YEAR TO MONTH",
# INTERVAL YEAR can have a precision for all options
	    "INT MULTISET",
	    "NATIONAL CHAR", "NATIONAL CHAR(5)",
	    "NATIONAL CHARACTER", "NATIONAL CHARACTER(5)",
# See NCHAR tests for other options.
	    "NATIONAL CHAR VARYING(5)", "NATIONAL CHARACTER VARYING(5)",
# See NCHAR VARYING tests for other options.
	    "NATIONAL CHARACTER LARGE OBJECT", "NATIONAL CHARACTER LARGE OBJECT(2K)",
# See NCLOB tests for other options.
	    "NCHAR", "NCHAR(5)",
# Other options include:
# NCHAR(5 CHARACTERS), NCHAR(5 OCTETS), plus COLLATE definitions
	    "NCHAR LARGE OBJECT", "NCHAR LARGE OBJECT(1M)",
# See NCLOB tests for other options.
	    "NCHAR VARYING(5)",
# Other options include:
# NCHAR VARYING(5 CHARACTERS), NCHAR VARYING(5 OCTETS)
# plus COLLATE definitions
	    "NCLOB", "NCLOB(1G)",
# Other options include:
# NCLOB(2K CHARACTERS), NCLOB(2K OCTETS), NCLOB(1K), NCLOB(1M), NCLOB(1G)
# plus COLLATE definitions
	    "NUMERIC", "NUMERIC(6)", "NUMERIC(6,2)",
	    "REAL",
	    "REF(udt_name)",
	    "ROW(field1 INT)", "ROW(field1 INT, field2 CHAR(10)",
	    "SMALLINT",
	    "TIME", "TIME(3)", "TIME WITH TIMEZONE", "TIME WITHOUT TIME  ZONE",
	    "TIMESTAMP", "TIMESTAMP(3)",
	    "TIMESTAMP WITH TIMEZONE", "TIMESTAMP WITHOUT TIME ZONE",
	    "VARCHAR(5)"
# Other options include:
# VARCHAR(5 CHARACTERS), VARCHAR(5 OCTETS), plus
# CHARACTER SET and COLLATE definitions
 );


#  -- An "odbc_type" is a data type defined by ODBC 3.0, but not included as
#     a data type in standard SQL. This is a small list because standard SQL
#     and ODBC generally have the same set of data types (standard SQL data
#     types are not repeated in this list).
@odbc_types=("BINARY", "BINARY(5)", "LONG VARBINARY", 
             "VARBINARY",
             "VARBINARY(5)",
             "BIT",
             "DOUBLE",
             "GUID",
             "LONG VARCHAR", "LONG VARCHAR(5)", "VARCHAR",
             "LONGWVARCHAR", "VARWCHAR(5)", "WCHAR(5)",
             "TINYINT",
             "UTCDATETIME", "UTCTIME"
);

#  -- An "extra_type" is a data type defined by a DBMS vendor, that is not
#     also included as a data type in standard SQL or ODBC.
@extra_types=(
                # additional vendor-specific MySQL (v4.x) datatypes
              "BIGINT UNSIGNED ZEROFILL", "BIGINT(5) UNSIGNED ZEROFILL",
                # Other options include:
                # BIGINT UNSIGNED, BIGINT ZEROFILL
              "BIT(2)",
              "BOOL",
              "CHAR(5) BINARY", "CHAR(5) ASCII", "CHAR(5) UNICODE",
              "DECIMAL UNSIGNED ZEROFILL", "DECIMAL(6) UNSIGNED ZEROFILL",
              "DECIMAL(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # DEC UNSIGNED ZEROFILL, DEC(6) UNSIGNED ZEROFILL, DEC(6,2)UNSIGNED ZEROFILL
                # DECIMAL UNSIGNED, DEC UNSIGNED, DECIMAL ZEROFILL, DEC ZEROFILL
                # DECIMAL(6) UNSIGNED, DEC(6) UNSIGNED, DECIMAL(6) ZEROFILL, DEC(6) ZEROFILL
                # DECIMAL(6,2) UNSIGNED, DEC(6,2) UNSIGNED,
                # DECIMAL(6,2) ZEROFILL, DEC(6,2) ZEROFILL
              "DOUBLE UNSIGNED ZEROFILL", "DOUBLE(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # DOUBLE UNSIGNED, DOUBLE ZEROFILL
                # DOUBLE(6,2) UNSIGNED, DOUBLE(6,2) ZEROFILL
              "DOUBLE PRECISION UNSIGNED ZEROFILL", "DOUBLE PRECISION(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # DOUBLE PRECISION UNSIGNED, DOUBLE PRECISION ZEROFILL
                # DOUBLE PRECISION(6,2) UNSIGNED, DOUBLE PRECISION(6,2) ZEROFILL
              "ENUM('RED','BLUE')",
              "FIXED UNSIGNED ZEROFILL", "FIXED(6) UNSIGNED ZEROFILL",
              "FIXED(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # FIXED UNSIGNED, FIXED ZEROFILL
                # FIXED(6) UNSIGNED, FIXED(6) ZEROFILL
                # FIXED(6,2) UNSIGNED, FIXED(6,2) ZEROFILL
              "FLOAT(4) UNSIGNED ZEROFILL", "FLOAT(6,2)", "FLOAT(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # FLOAT(4) UNSIGNED, FLOAT(4) ZEROFILL
                # FLOAT(6,2) UNSIGNED, FLOAT(6,2) ZEROFILL
              "INT1", "INT3", "INT NOT NULL AUTO_INCREMENT,UNIQUE(Q)",
              "INT UNSIGNED", "INT ZEROFILL", "INT UNSIGNED ZEROFILL",
              "INT(5) UNSIGNED", "INT(5) ZEROFILL", "INT(5) UNSIGNED ZEROFILL",
                # Other options include:
                # INTEGER(5) UNSIGNED ZEROFILL, INTEGER UNSIGNED, INTEGER ZEROFILL
              "LONGBLOB", "LONGTEXT",
              "MEDIUMBLOB", "MEDIUMTEXT",
              "MEDIUMINT", "MEDIUMINT UNSIGNED ZEROFILL", "MEDIUMINT(5) UNSIGNED ZEROFILL",
                # Other options include:
                # MEDIUMINT UNSIGNED, MEDIUMINT ZEROFILL
              "MIDDLEINT",
              "NATIONAL CHAR(5) BINARY", "NATIONAL CHAR(5) ASCII","NATIONAL CHAR(5) UNICODE",
              "NATIONAL VARCHAR(5) BINARY",
              "NUMERIC UNSIGNED ZEROFILL", "NUMERIC(6) UNSIGNED ZEROFILL",
              "NUMERIC(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # NUMERIC UNSIGNED, NUMERIC ZEROFILL
                # NUMERIC(6) UNSIGNED, NUMERIC(6) ZEROFILL
                # NUMERIC(6,2) UNSIGNED, NUMERIC(6,2) ZEROFILL
              "REAL UNSIGNED ZEROFILL", "REAL(6,2) UNSIGNED ZEROFILL",
                # Other options include:
                # REAL(6,2) UNSIGNED, REAL(6,2) ZEROFILL
              "SET('RED', 'BLUE')",
              "SMALLINT UNSIGNED ZEROFILL", "SMALLINT(5) UNSIGNED ZEROFILL",
                # Other options include:
                # SMALLINT UNSIGNED, SMALLINT ZEROFILL
              "TEXT(10)",
              "TINYBLOB", "TINYTEXT",
              "TINYINT UNSIGNED ZEROFILL", "TINYINT(5) UNSIGNED ZEROFILL",
                # Other options include:
                # TINYINT UNSIGNED, TINYINT ZEROFILL
              "VARCHAR(5) BINARY",
              "YEAR", "YEAR(2)",
                # Other options include:
                # "YEAR(4)

                # additional vendor-specific IBM DB2 Universal Database (v8.x) datatypes
              "CHAR FOR BIT DATA", "CHAR(5) FOR BIT DATA",
              "CHARACTER FOR BIT DATA", "CHARACTER(5) FOR BIT DATA",
              "CHAR VARYING(5) FOR BIT DATA", "CHARACTER VARYING(5) FOR BIT DATA",
              "DATALINK", "DATALINK(2)",
              "DBCLOB(2)",
                # Other options include:
                # DBCLOB(1K), DBCLOB(1M), DBCLOB(1G)
              "GRAPHIC", "GRAPHIC(5)", "LONG VARGRAPHIC", "VARGRAPHIC(5)",
              "LONG VARCHAR FOR BIT DATA", "VARCHAR(5) FOR BIT DATA",
              "NUM", "NUM(6)", "NUM(6,2)",

                # additional vendor-specific Microsoft SQL Server 2000 datatypes
              "BINARY VARYING", "BINARY VARYING(5)",
              "DATETIME", "SMALLDATETIME",
              "IMAGE",
              "INT NOT NULL IDENTITY,UNIQUE(Q)",
              "MONEY", "SMALLMONEY",
              "NATIONAL TEXT", "NTEXT", "TEXT",
              "NVARCHAR(5)",
              "ROWVERSION",
              "SQL_VARIANT",
              "UNIQUEIDENTIFIER",

                # additional vendor-specific Oracle Database (release 10g) datatypes
              "BFILE",
              "BINARY_FLOAT", "BINARY_DOUBLE",
              "CHAR(5 BYTE)",
                # Other options include:
                # CHAR(5 CHAR)
              "LONG",
              "MLSLABEL",
              "NUMBER", "NUMBER(6)", "NUMBER(6,2)",
              "NVARCHAR2(5)",
              "RAW(5)", "LONG RAW",
              "ROWID", "UROWID", "UROWID(5)",
              "TIMESTAMP WITH LOCAL TIME ZONE", "TIMESTAMP(3) WITH LOCAL TIME ZONE",
              "VARCHAR2(5)",
                # Other options include:
                # VARCHAR2(5 BYTE), VARCHAR2(5 CHAR)

                # additional vendor-specific Frontbase datatypes
                # (list not intended to be complete)
              "BYTE",
                # additional vendor-specific Informix datatypes
                # (list not intended to be complete)
              "SERIAL", "SMALLFLOAT",
                # additional vendor-specific mSQL datatypes
                # (list not intended to be complete)
              "UINT",
                # additional vendor-specific PostgreSQL datatypes
                # (list not intended to be complete)
              "ABSTIME", "BIT VARYING(2)", "BOX", "CIDR", "CIRCLE", "FLOAT4", "FLOAT8",
              "INET", "INT2", "INT4", "INT8", "INTERVAL", "LINE", "LSEG", "MACADDR",
              "PATH", "POINT", "POLYGON", "RELTIME"
);


@types=(["SQL:2003",\@sql_types],
 ["ODBC_3.0",\@odbc_types],
 ["Vendor_specific",\@extra_types]);


foreach $types (@types)
{
  print "\nSupported $types->[0] types\n";
  $tmp=@$types->[1];
  foreach $use_type (@$tmp)
  {
    $type=$use_type;
    $type =~ s/\(.*\)/(1 arg)/;
    if (index($use_type,",")>= 0)
    {
      $type =~ s/\(1 arg\)/(2 arg)/;
    }
    if (($tmp2=index($type,",unique")) >= 0)
    {
      $type=substr($type,0,$tmp2);
    }
    $tmp2=$type;
    $tmp2 =~ s/ /_/g;
    $tmp2 =~ s/_not_null//g;
    report("Datatype $type","type_$types->[0]_$tmp2",
	   "create table crash_q (q $use_type)",
	   "drop table crash_q $drop_attr");
  }
}

#
# Test some type limits
#


check_and_report("Remembers end space in char()","remember_end_space",
		 ["create table crash_q (a char(10))",
		  "insert into crash_q values('hello ')"],
		 "select a from crash_q where a = 'hello '",
		 ["drop table crash_q $drop_attr"],
		 'hello ',6);

check_and_report("Remembers end space in varchar()",
		 "remember_end_space_varchar",
		 ["create table crash_q (a varchar(10))",
		  "insert into crash_q values('hello ')"],
		 "select a from crash_q where a = 'hello '",
		 ["drop table crash_q $drop_attr"],
		 'hello ',6);

if (($limits{'type_extra_float(2_arg)'} eq "yes" ||
    $limits{'type_sql_decimal(2_arg)'} eq "yes") &&
    (!defined($limits{'storage_of_float'})))
{
  my $type=$limits{'type_extra_float(2_arg)'} eq "yes" ? "float(4,1)" :
    "decimal(4,1)";
  my $result="undefined";
  if (execute_and_check("storage_of_float",["create table crash_q (q1 $type)",
			 "insert into crash_q values(1.14)"],
			"select q1 from crash_q",
			["drop table crash_q $drop_attr"],1.1,0) &&
      execute_and_check("storage_of_float",["create table crash_q (q1 $type)",
			 "insert into crash_q values(1.16)"],
			"select q1 from crash_q",
			["drop table crash_q $drop_attr"],1.1,0))
  {
    $result="truncate";
  }
  elsif (execute_and_check("storage_of_float",["create table crash_q (q1 $type)",
			    "insert into crash_q values(1.14)"],
			   "select q1 from crash_q",
			   ["drop table crash_q $drop_attr"],1.1,0) &&
	 execute_and_check("storage_of_float",["create table crash_q (q1 $type)",
			    "insert into crash_q values(1.16)"],
			   "select q1 from crash_q",
			   ["drop table crash_q $drop_attr"],1.2,0))
  {
    $result="round";
  }
  elsif (execute_and_check("storage_of_float",["create table crash_q (q1 $type)",
			    "insert into crash_q values(1.14)"],
			   "select q1 from crash_q",
			   ["drop table crash_q $drop_attr"],1.14,0) &&
	 execute_and_check("storage_of_float",["create table crash_q (q1 $type)",
			    "insert into crash_q values(1.16)"],
			   "select q1 from crash_q",
			   ["drop table crash_q $drop_attr"],1.16,0))
  {
    $result="exact";
  }
  $prompt="Storage of float values";
  print "$prompt: $result\n";
  save_config_data("storage_of_float", $result, $prompt);
}

try_and_report("Type for row id", "rowid",
	       ["rowid",
		"create table crash_q (a rowid)",
		"drop table crash_q $drop_attr"],
	       ["auto_increment",
		"create table crash_q (a int not null auto_increment".
		", primary key(a))","drop table crash_q $drop_attr"],
	       ["oid",
		"create table crash_q (a oid, primary key(a))",
		"drop table crash_q $drop_attr"],
	       ["serial",
		"create table crash_q (a serial, primary key(a))",
		"drop table crash_q $drop_attr"]);

try_and_report("Automatic row id", "automatic_rowid",
	       ["_rowid",
		"create table crash_q (a int not null, primary key(a))",
		"insert into crash_q values (1)",
		"select _rowid from crash_q",
		"drop table crash_q $drop_attr"]);

#
# Test functions
#

@sql_functions=
  (["+, -, *, / (arithmetic)","arithmetic","5*3-4/2+1",14,0],
   ["|| (concatenation)","concatenation","'abc' || 'def'","abcdef",1],
   ["CASE (searched)","searched_case",
     "case when 1 > 2 then 'false' when 2 > 1 then 'true' end", "true",1],
   ["CASE (simple)","simple_case",
     "case 2 when 1 then 'false' when 2 then 'true' end", "true",1],
   ["CAST","cast","CAST(1 as CHAR)","1",1],
   ["CHAR_LENGTH","char_length","char_length(b)","10",0],

   ["CHARACTER_LENGTH","character_length","character_length('abcd')","4",0],
   ["COALESCE","coalesce","coalesce($char_null,'bcd','qwe')","bcd",1],
   ["CURRENT_DATE","current_date","current_date",0,2],
   ["CURRENT_TIME","current_time","current_time",0,2],
   ["CURRENT_TIMESTAMP","current_timestamp","current_timestamp",0,2],
   ["EXTRACT (year)","extract_year",
     "extract(year from timestamp '2000-12-23 18:43:12.987')",2000,0],
   ["EXTRACT (month)","extract_month",
     "extract(month from timestamp '2000-12-23 18:43:12.987')",12,0],
   ["EXTRACT (day)","extract_day",
     "extract(day from timestamp '2000-12-23 18:43:12.987')",23,0],
   ["EXTRACT (hour)","extract_hour",
     "extract(hour from timestamp '2000-12-23 18:43:12.987')",18,0],
   ["EXTRACT (minute)","extract_minute",
     "extract(minute from timestamp '2000-12-23 18:43:12.987')",43,0],
   ["EXTRACT (second)","extract_second",
     "extract(second from timestamp '2000-12-23 18:43:12')",12,0],
   ["EXTRACT (tz_hour)","extract_tz_hour",
     "extract(timezone_hour from timestamp '2000-12-23 18:43:12+10:30')",10,0],
   ["EXTRACT (tz_minute)","extract_tz_minute",
     "extract(timezone_minute from timestamp '2000-12-23 18:43:12+10:30')",30,0],
   ["LOCALTIME","localtime","localtime",0,2],
   ["LOCALTIMESTAMP","localtimestamp","localtimestamp",0,2],
   ["LOWER","lower","LOWER('ABC')","abc",1],
   ["NULLIF with strings","nullif_string",
       "NULLIF(NULLIF('first','second'),'first')",undef(),4],
   ["NULLIF with numbers","nullif_num","NULLIF(NULLIF(1,2),1)",undef(),4],
   ["OCTET_LENGTH","octet_length","octet_length('abc')",3,0],
   ["POSITION","position","position('ll' in 'hello')",3,0],
   ["SUBSTRING (character string)","substring_character_string",
     "substring('abcd' from 2 for 2)","bc",1],
   ["SUBSTRING (regular expression)","substring_regular_expression",
     "substring('abcd' similar '_b' escape '&') ","ab",1],
   ["TRIM","trim","trim(' abc ')","abc",3],
   ["TRIM (both)","trim_both","trim(both ' ' from ' abc ')","abc",3],
   ["TRIM (lead/trail)","trim_leading_&_trailing",
     "trim(trailing from trim(LEADING FROM ' abc '))","abc",3],
   ["UPPER","upper","UPPER('abc')","ABC",1],
   );

@odbc_functions=
  (["ASCII", "ascii", "ASCII('A')","65",0],
   ["BIT_LENGTH","bit_length","bit_length('abc')",24,0],
   ["CHAR", "char", "CHAR(65)"  ,"A",1],
   ["CONCAT(2 arg)","concat", "concat('a','b')","ab",1],
   ["DIFFERENCE()","difference","difference('abc','abe')",3,0],
   ["INSERT","insert","insert('abcd',2,2,'ef')","aefd",1],
   ["LEFT","left","left('abcd',2)","ab",1],
   ["LTRIM","ltrim","ltrim('   abcd')","abcd",1],
   ["REAL LENGTH","length","length('abcd ')","5",0],
   ["ODBC LENGTH","length_without_space","length('abcd ')","4",0],
   ["LOCATE(2 arg)","locate_2","locate('bcd','abcd')","2",0],
   ["LOCATE(3 arg)","locate_3","locate('bcd','abcd',3)","0",0],
   ["LCASE","lcase","lcase('ABC')","abc",1],
   ["REPEAT","repeat","repeat('ab',3)","ababab",1],
   ["REPLACE","replace","replace('abbaab','ab','ba')","bababa",1],
   ["RIGHT","right","right('abcd',2)","cd",1],
   ["RTRIM","rtrim","rtrim(' abcd  ')"," abcd",1],
   ["SPACE","space","space(5)","     ",3],
   ["SOUNDEX","soundex","soundex('hello')",0,2],
   ["ODBC SUBSTRING","substring","substring('abcd',3,2)","cd",1],
   ["UCASE","ucase","ucase('abc')","ABC",1],

   ["ABS","abs","abs(-5)",5,0],
   ["ACOS","acos","acos(0)","1.570796",0],
   ["ASIN","asin","asin(1)","1.570796",0],
   ["ATAN","atan","atan(1)","0.785398",0],
   ["ATAN2","atan2","atan2(1,0)","1.570796",0],
   ["CEILING","ceiling","ceiling(-4.5)",-4,0],
   ["COS","cos","cos(0)","1.00000",0],
   ["COT","cot","cot(1)","0.64209262",0],
   ["DEGREES","degrees","degrees(6.283185)","360",0],
   ["EXP","exp","exp(1.0)","2.718282",0],
   ["FLOOR","floor","floor(2.5)","2",0],
   ["LOG","log","log(2)","0.693147",0],
   ["LOG10","log10","log10(10)","1",0],
   ["MOD","mod","mod(11,7)","4",0],
   ["PI","pi","pi()","3.141593",0],
   ["POWER","power","power(2,4)","16",0],
   ["RAND","rand","rand(1)",0,2],       # Any value is acceptable
   ["RADIANS","radians","radians(360)","6.283185",0],
   ["ROUND(2 arg)","round","round(5.63,2)","5.6",0],
   ["SIGN","sign","sign(-5)",-1,0],
   ["SIN","sin","sin(1)","0.841471",0],
   ["SQRT","sqrt","sqrt(4)",2,0],
   ["TAN","tan","tan(1)","1.557408",0],
   ["TRUNCATE","truncate","truncate(18.18,-1)",10,0],
   ["NOW","now","now()",0,2],           # Any value is acceptable
   ["CURDATE","curdate","curdate()",0,2],
   ["CURTIME","curtime","curtime()",0,2],
   ["TIMESTAMPADD","timestampadd",
    "timestampadd(SQL_TSI_SECOND,1,'1997-01-01 00:00:00')",
    "1997-01-01 00:00:01",1],
   ["TIMESTAMPDIFF","timestampdiff",
    "timestampdiff(SQL_TSI_SECOND,'1997-01-01 00:00:02',".
     " '1997-01-01 00:00:01')","1",0],
   ["USER()","user()","user()",0,2],
   ["DATABASE","database","database()",0,2],
   ["IFNULL","ifnull","ifnull(2,3)",2,0],
   ["ODBC syntax LEFT & RIGHT", "fn_left",
    "{ fn LEFT( { fn RIGHT('abcd',2) },1) }","c",1],
   );



@extra_functions=
  (
   ["& (bitwise and)",'&',"5 & 3",1,0],
   ["| (bitwise or)",'|',"1 | 2",3,0],
   ["<< and >> (bitwise shifts)",'binary_shifts',"(1 << 4) >> 2",4,0],
   ["<> in SELECT","<>","1<>1","0",0],
   ["=","=","(1=1)",1,$logical_value],
   ["~* (case insensitive compare)","~*","'hi' ~* 'HI'",1,$logical_value],
   ["AND and OR in SELECT","and_or","1=1 AND 2=2",$logical_value,0],
   ["AND as '&&'",'&&',"1=1 && 2=2",$logical_value,0],
   ["ASCII_CHAR", "ascii_char", "ASCII_CHAR(65)","A",1],
   ["ASCII_CODE", "ascii_code", "ASCII_CODE('A')","65",0],
   ["ATN2","atn2","atn2(1,0)","1.570796",0],
   ["BETWEEN in SELECT","between","5 between 4 and 6",$logical_value,0],
   ["BIT_COUNT","bit_count","bit_count(5)",2,0],
   ["CEIL","ceil","ceil(-4.5)",-4,0], # oracle
   ["CHARINDEX","charindex","charindex('a','crash')",3,0],
   ["CHR", "chr", "CHR(65)"  ,"A",1], # oracle
   ["CONCAT(list)","concat_list", "concat('a','b','c','d')","abcd",1],
   ["CONVERT","convert","convert(CHAR,5)","5",1],
   ["COSH","cosh","cosh(0)","1",0], # oracle hyperbolic cosine of n.
   ["ELT","elt","elt(2,'ONE','TWO','THREE')","TWO",1],
   ["ENCRYPT","encrypt","encrypt('hello')",0,2],
   ["FIELD","field","field('IBM','NCA','ICL','SUN','IBM','DIGITAL')",4,0],
   ["FORMAT","format","format(1234.5555,2)","1,234.56",1],
   ["GETDATE","getdate","getdate()",0,2],
   ["GREATEST","greatest","greatest('HARRY','HARRIOT','HAROLD')","HARRY",1],
   ["IF","if", "if(5,6,7)",6,0],
   ["IN on numbers in SELECT","in_num","2 in (3,2,5,9,5,1)",$logical_value,0],
   ["IN on strings in SELECT","in_str","'monty' in ('david','monty','allan')", $logical_value,0],
   ["INITCAP","initcap","initcap('the soap')","The Soap",1], 
       # oracle Returns char, with the first letter of each word in uppercase
   ["INSTR (Oracle syntax)", "instr_oracle", "INSTR('CORPORATE FLOOR','OR',3,2)"  ,"14",0], # oracle instring
   ["INSTRB", "instrb", "INSTRB('CORPORATE FLOOR','OR',5,2)"  ,"27",0], 
      # oracle instring in bytes
   ["INTERVAL","interval","interval(55,10,20,30,40,50,60,70,80,90,100)",5,0],
   ["LAST_INSERT_ID","last_insert_id","last_insert_id()",0,2],
   ["LEAST","least","least('HARRY','HARRIOT','HAROLD')","HAROLD",1], 
      # oracle
   ["LENGTHB","lengthb","lengthb('CANDIDE')","14",0], 
      # oracle length in bytes
   ["LIKE ESCAPE in SELECT","like_escape",
     "'%' like 'a%' escape 'a'",$logical_value,0],
   ["LIKE in SELECT","like","'a' like 'a%'",$logical_value,0],
   ["LN","ln","ln(95)","4.55387689",0], 
      # oracle natural logarithm of n
   ["LOCATE as INSTR","instr","instr('hello','ll')",3,0],
   ["LOG(m,n)","log(m_n)","log(10,100)","2",0], 
      # oracle logarithm, base m, of n
   ["LOGN","logn","logn(2)","0.693147",0], 
      # informix
   ["LPAD","lpad","lpad('hi',4,'??')",'??hi',3],
   ["MOD as %","%","10%7","3",0],
   ["NOT BETWEEN in SELECT","not_between","5 not between 4 and 6",0,0],
   ["NOT LIKE in SELECT","not_like","'a' not like 'a%'",0,0],
   ["NOT as '!' in SELECT","!","! 1",0,0],
   ["NOT in SELECT","not","not $false",$logical_value,0],
   ["ODBC CONVERT","odbc_convert","convert(5,SQL_CHAR)","5",1],
   ["OR as '||'",'||',"1=0 || 1=1",$logical_value,0],
   ["PASSWORD","password","password('hello')",0,2],
   ["PASTE", "paste", "paste('ABCDEFG',3,2,'1234')","AB1234EFG",1],
   ["PATINDEX","patindex","patindex('%a%','crash')",3,0],
   ["POW","pow","pow(3,2)",9,0],
   ["RANGE","range","range(a)","0.0",0], 
       # informix range(a) = max(a) - min(a)
   ["REGEXP in SELECT","regexp","'a' regexp '^(a|b)*\$'",$logical_value,0],
   ["REPLICATE","replicate","replicate('a',5)","aaaaa",1],
   ["REVERSE","reverse","reverse('abcd')","dcba",1],
   ["ROOT","root","root(4)",2,0], # informix
   ["ROUND(1 arg)","round1","round(5.63)","6",0],
   ["RPAD","rpad","rpad('hi',4,'??')",'hi??',3],
   ["SINH","sinh","sinh(1)","1.17520119",0], # oracle hyperbolic sine of n
   ["STR","str","str(123.45,5,1)",123.5,3],
   ["STRCMP","strcmp","strcmp('abc','adc')",-1,0],
   ["STUFF","stuff","stuff('abc',2,3,'xyz')",'axyz',3],
   ["SUBSTRB", "substrb", "SUBSTRB('ABCDEFG',5,4.2)"  ,"CD",1], 
      # oracle substring with bytes
   ["SUBSTRING as MID","mid","mid('hello',3,2)","ll",1],
   ["SUBSTRING_INDEX","substring_index",
     "substring_index('www.tcx.se','.',-2)", "tcx.se",1],
   ["TAIL","tail","tail('ABCDEFG',3)","EFG",0],
   ["TANH","tanh","tanh(1)","0.462117157",0], 
      # oracle hyperbolic tangent of n
   ["TRANSLATE","translate","translate('abc','bc','de')",'ade',3],
   ["TRIM; Many char extension",
     "trim_many_char","trim(':!' FROM ':abc!')","abc",3],
   ["TRIM; Substring extension",
     "trim_substring","trim('cb' FROM 'abccb')","abc",3],
   ["TRUNC","trunc","trunc(18.18,-1)",10,0], # oracle
   ["UID","uid","uid",0,2], # oracle uid from user
   ["UNIX_TIMESTAMP","unix_timestamp","unix_timestamp()",0,2],
   ["USERENV","userenv","userenv",0,2], # oracle user enviroment
   ["VERSION","version","version()",0,2],
   ["automatic num->string convert","auto_num2string","concat('a',2)","a2",1],
   ["automatic string->num convert","auto_string2num","'1'+2",3,0],
   ["concatenation with +","concat_as_+","'abc' + 'def'","abcdef",1],
   ["SUBSTR (2 arg)",'substr2arg',"substr('abcd',2)",'bcd',1],  #sapdb func
   ["SUBSTR (3 arg)",'substr3arg',"substr('abcd',2,2)",'bc',1],
   ["LFILL (3 arg)",'lfill3arg',"lfill('abcd','.',6)",'..abcd',1],
   ["RFILL (3 arg)",'rfill3arg',"rfill('abcd','.',6)",'abcd..',1],
   ["RPAD (4 arg)",'rpad4arg',"rpad('abcd',2,'+-',8)",'abcd+-+-',1],
   ["LPAD (4 arg)",'rpad4arg',"lpad('abcd',2,'+-',8)",'+-+-abcd',1],
   ["TRIM (1 arg)",'trim1arg',"trim(' abcd ')",'abcd',1],
   ["TRIM (2 arg)",'trim2arg',"trim('..abcd..','.')",'abcd',1],
   ["LTRIM (2 arg)",'ltrim2arg',"ltrim('..abcd..','.')",'abcd..',1],
   ["RTRIM (2 arg)",'rtrim2arg',"rtrim('..abcd..','.')",'..abcd',1],
   ["EXPAND",'expand2arg',"expand('abcd',6)",'abcd  ',0],
   ["REPLACE (2 arg) ",'replace2arg',"replace('AbCd','bC')",'Ad',1],
   ["MAPCHAR",'mapchar',"mapchar('Aâ')",'Aa',1],
   ["ALPHA",'alpha',"alpha('Aâ',2)",'AA',1],
   ["ASCII in string cast",'ascii_string',"ascii('a')",'a',1],
   ["EBCDIC in string cast",'ebcdic_string',"ebcdic('a')",'a',1],
   ["TRUNC (1 arg)",'trunc1arg',"trunc(222.6)",222,0],
   ["FIXED",'fixed',"fixed(222.6666,10,2)",'222.67',0],
   ["FLOAT",'float',"float(6666.66,4)",6667,0],
   ["LENGTH",'length',"length(1)",2,0],
   ["INDEX",'index',"index('abcdefg','cd',1,1)",3,0],
   ["MICROSECOND",'microsecond',
      "MICROSECOND('19630816200212111111')",'111111',0],
   ["TIMESTAMP",'timestamp',
      "timestamp('19630816','00200212')",'19630816200212000000',0],
   ["VALUE",'value',"value(NULL,'WALRUS')",'WALRUS',0],
   ["DECODE",'decode',"DECODE('S-103','T72',1,'S-103',2,'Leopard',3)",2,0],
   ["NUM",'num',"NUM('2123')",2123,0],
   ["CHR (any type to string)",'chr_str',"CHR(67)",'67',0],
   ["HEX",'hex',"HEX('A')",41,0],
   );


@sql_group_functions=
  (
   ["AVG","avg","avg(a)",1,0],
   ["COUNT (*)","count_*","count(*)",1,0],
   ["COUNT column name","count_column","count(a)",1,0],
   ["COUNT(DISTINCT expr)","count_distinct","count(distinct a)",1,0],
   ["MAX on numbers","max","max(a)",1,0],
   ["MAX on strings","max_str","max(b)","a",1],
   ["MIN on numbers","min","min(a)",1,0],
   ["MIN on strings","min_str","min(b)","a",1],
   ["SUM","sum","sum(a)",1,0],
   ["ANY","any","any(a)",$logical_value,0],
   ["EVERY","every","every(a)",$logical_value,0],
   ["SOME","some","some(a)",$logical_value,0],
   );

@extra_group_functions=
  (
   ["BIT_AND",'bit_and',"bit_and(a)",1,0],
   ["BIT_OR", 'bit_or', "bit_or(a)",1,0],
   ["COUNT(DISTINCT expr,expr,...)",
     "count_distinct_list","count(distinct a,b)",1,0],
   ["STD","std","std(a)",0,0],
   ["STDDEV","stddev","stddev(a)",0,0],
   ["VARIANCE","variance","variance(a)",0,0],
   );

@where_functions=
(
 ["= ALL","eq_all","b =all (select b from crash_me)",1,0],
 ["= ANY","eq_any","b =any (select b from crash_me)",1,0],
 ["= SOME","eq_some","b =some (select b from crash_me)",1,0],
 ["BETWEEN","between","5 between 4 and 6",1,0],
 ["EXISTS","exists","exists (select * from crash_me)",1,0],
 ["IN on numbers","in_num","2 in (3,2,5,9,5,1)",1,0],
 ["LIKE ESCAPE","like_escape","b like '%' escape 'a'",1,0],
 ["LIKE","like","b like 'a%'",1,0],
 ["MATCH UNIQUE","match_unique",
   "1 match unique (select a from crash_me)",1,0],
 ["MATCH","match","1 match (select a from crash_me)",1,0],
 ["MATCHES","matches","b matcjhes 'a*'",1,0],
 ["NOT BETWEEN","not_between","7 not between 4 and 6",1,0],
 ["NOT EXISTS","not_exists",
   "not exists (select * from crash_me where a = 2)",1,0],
 ["NOT LIKE","not_like","b not like 'b%'",1,0],
 ["NOT UNIQUE","not_unique",
   "not unique (select * from crash_me where a = 2)",1,0],
 ["UNIQUE","unique","unique (select * from crash_me)",1,0],
 );

@types=(["sql",\@sql_functions,0],
	["odbc",\@odbc_functions,0],
	["extra",\@extra_functions,0],
	["where",\@where_functions,0]);

@group_types=(["sql",\@sql_group_functions,0],
	      ["extra",\@extra_group_functions,0]);


foreach $types (@types)
{
  print "\nSupported $types->[0] functions\n";
  $tmp=@$types->[1];
  foreach $type (@$tmp)
  {
    if (defined($limits{"func_$types->[0]_$type->[1]"}))
    {
      next;
    }
    if ($types->[0] eq "where")
    {
      check_and_report("Function $type->[0]","func_$types->[0]_$type->[1]",
		       [],"select a from crash_me where $type->[2]",[],
		       $type->[3],$type->[4]);
    }
    elsif ($limits{'functions'} eq 'yes')
    {
      if (($type->[2] =~ /char_length\(b\)/) && (!$end_query))
      {
	my $tmp= $type->[2];
	$tmp .= " from crash_me ";
	undef($limits{"func_$types->[0]_$type->[1]"});
	check_and_report("Function $type->[0]",
			 "func_$types->[0]_$type->[1]",
			 [],"select $tmp ",[],
			 $type->[3],$type->[4]);
      }
      else
      {
	undef($limits{"func_$types->[0]_$type->[1]"});
	$result = check_and_report("Function $type->[0]",
			    "func_$types->[0]_$type->[1]",
			    [],"select $type->[2] $end_query",[],
			    $type->[3],$type->[4]);
	if (!$result)
	{
	  # check without type specifyer
	  if ($type->[2] =~ /DATE /)
	  {
	    my $tmp= $type->[2];
	    $tmp =~ s/DATE //;
	    undef($limits{"func_$types->[0]_$type->[1]"});
	    $result = check_and_report("Function $type->[0]",
				  "func_$types->[0]_$type->[1]",
				  [],"select $tmp $end_query",[],
				  $type->[3],$type->[4]);
	  }
	  if (!$result)
	  {
	    if ($types->[0] eq "odbc" && ! ($type->[2] =~ /\{fn/))
	    {
	     my $tmp= $type->[2];
	     # Check by converting to ODBC format
	     undef($limits{"func_$types->[0]_$type->[1]"});
	     $tmp= "{fn $tmp }";
	     $tmp =~ s/('1997-\d\d-\d\d \d\d:\d\d:\d\d')/{ts $1}/g;
	     $tmp =~ s/(DATE '1997-\d\d-\d\d')/{d $1}/g;
	     $tmp =~ s/(TIME '12:13:14')/{t $1}/g;
	     $tmp =~ s/DATE //;
	     $tmp =~ s/TIME //;
	     check_and_report("Function $type->[0]",
			      "func_$types->[0]_$type->[1]",
			      [],"select $tmp $end_query",[],
			      $type->[3],$type->[4]);
	    }
	  }
        }
      }
    }
  }
}

if ($limits{'functions'} eq 'yes')
{
  foreach $types (@group_types)
  {
    print "\nSupported $types->[0] group functions\n";
    $tmp=@$types->[1];
    foreach $type (@$tmp)
    {
      check_and_report("Group function $type->[0]",
		       "group_func_$types->[0]_$type->[1]",
		       [],"select $type->[2],a from crash_me group by a",[],
		       $type->[3],$type->[4]);
    }
  }
  print "\n";
  report("mixing of integer and float in expression","float_int_expr",
	 "select 1+1.0 $end_query");
  if ($limits{'func_odbc_exp'} eq 'yes')
  {
    report("No need to cast from integer to float",
	   "dont_require_cast_to_float", "select exp(1) $end_query");
  }
  check_and_report("Is 1+NULL = NULL","null_num_expr",
		   [],"select 1+$numeric_null $end_query",[],undef(),4);
  $tmp=sql_concat("'a'",$char_null);
  if (defined($tmp))
  {
    check_and_report("Is $tmp = NULL", "null_concat_expr", [],
		     "select $tmp $end_query",[], undef(),4);
  }
  $prompt="Need to cast NULL for arithmetic";
  add_log("Need_cast_for_null",
    " Check if numeric_null ($numeric_null) is 'NULL'");
  save_config_data("Need_cast_for_null",
		   ($numeric_null eq "NULL") ? "no" : "yes",
		   $prompt);
}
else
{
  print "\n";
}


#  Test: NOROUND 
{
 my $result = 'undefined';
 my $error;
 print "NOROUND: ";
 save_incomplete('func_extra_noround','Function NOROUND');

# 1) check if noround() function is supported
 $error = safe_query_l('func_extra_noround',"select noround(22.6) $end_query");
 if ($error ne 1)         # syntax error -- noround is not supported 
 {
   $result = 'no'
 }
 else                   # Ok, now check if it really works
 {
   $error=safe_query_l('func_extra_noround', 
     ["create table crash_me_nr (a int)",
    "insert into crash_me_nr values(noround(10.2))",
    "drop table crash_me_nr $drop_attr"]);
   if ($error == 1)
   {
     $result= "syntax only";
   }
   else
   {
     $result= 'yes';
   }
 }
 print "$result\n";
 save_config_data('func_extra_noround',$result,"Function NOROUND");
}


check_parenthesis("func_sql_","CURRENT_DEFAULT_TRANSFORM_GROUP");
check_parenthesis("func_sql_","CURRENT_PATH");
check_parenthesis("func_sql_","CURRENT_ROLE");
check_parenthesis("func_sql_","CURRENT_USER");
check_parenthesis("func_sql_","SESSION_USER");
check_parenthesis("func_sql_","SYSTEM_USER");
check_parenthesis("func_sql_","USER");
check_parenthesis('func_extra_',"SYSDATE");


if ($limits{'type_sql_date'} eq 'yes')
{  # 
   # Checking the format of date in result. 
   
    safe_query("drop table crash_me_d $drop_attr");
    assert("create table crash_me_d (a date)");
    # find the example of date
    my $dateexample;
    if ($limits{'func_extra_sysdate'} eq 'yes') {
     $dateexample='sysdate';
    } 
    if ($limits{'func_extra_sysdate'} eq 'with_parenthesis') {
     $dateexample='sysdate()';
    } 
    elsif ($limits{'func_sql_current_date'} eq 'yes') {
     $dateexample='CURRENT_DATE';
    } 
    elsif ($limits{'func_odbc_curdate'} eq 'yes') {
     $dateexample='curdate()';
    } 
    elsif ($limits{'func_extra_getdate'} eq 'yes') {
	$dateexample='getdate()';
    }
    elsif ($limits{'func_odbc_now'} eq 'yes') {
	$dateexample='now()';
    } else {
	#try to guess 
	$dateexample="DATE '1963-08-16'";
    } ;
    
    my $key = 'date_format_inresult';
    my $prompt = "Date format in result";
    if (! safe_query_l('date_format_inresult',
       "insert into crash_me_d values($dateexample) "))
    { 
	#die "Cannot insert date ($dateexample):".$last_error; 
        add_log($key,
                "Cannot insert date ($dateexample):".$last_error."\n");
        save_config_data($key,"unknown",$prompt);

        #FIXME: It seems that we have to rewrite below as
        #       else
        #       {
        #         ...
    };
    my $sth= $dbh->prepare("select a from crash_me_d");
    add_log('date_format_inresult',"< select a from crash_me_d");
    $sth->execute;
    $_= $sth->fetchrow_array;
    add_log('date_format_inresult',"> $_");
    safe_query_l($key,"delete from crash_me_d");   
    if (/\d{4}-\d{2}-\d{2}/){ save_config_data($key,"iso",$prompt);} 
    elsif (/\d{2}-\d{2}-\d{2}/){ save_config_data($key,"short iso",$prompt);}
    elsif (/\d{2}\.\d{2}\.\d{4}/){ save_config_data($key,"euro",$prompt);}
    elsif (/\d{2}\.\d{2}\.\d{2}/){ save_config_data($key,"short euro",$prompt);}
    elsif (/\d{2}\/\d{2}\/\d{4}/){ save_config_data($key,"usa",$prompt);}
    elsif (/\d{2}\/\d{2}\/\d{2}/){ save_config_data($key,"short usa",$prompt);}
    elsif (/\d*/){ save_config_data($key,"YYYYMMDD",$prompt);}
    else  { save_config_data($key,"unknown",$prompt);};
    $sth->finish;

    check_and_report("Supports YYYY-MM-DD (ISO) format","date_format_ISO",
		     [ "insert into crash_me_d(a)  values ('1963-08-16')"],
		     "select a from crash_me_d",
		     ["delete from crash_me_d"],
		     make_date_r(1963,8,16),1);

    check_and_report("Supports DATE 'YYYY-MM-DD' (ISO) format",
		     "date_format_ISO_with_date",
		     [ "insert into crash_me_d(a) values (DATE '1963-08-16')"],
		     "select a from crash_me_d",
		     ["delete from crash_me_d"],
		     make_date_r(1963,8,16),1);

    check_and_report("Supports DD.MM.YYYY (EUR) format","date_format_EUR",
		     [ "insert into crash_me_d(a) values ('16.08.1963')"],
		     "select a from crash_me_d",
		     ["delete from crash_me_d"],
		     make_date_r(1963,8,16),1);
    check_and_report("Supports DATE 'DD.MM.YYYY' (EUR) format",
		     "date_format_EUR_with_date",
		     [ "insert into crash_me_d(a) values (DATE '16.08.1963')"],
		     "select a from crash_me_d",
		     ["delete from crash_me_d"],
		     make_date_r(1963,8,16),1);

    check_and_report("Supports YYYYMMDD format",
	 "date_format_YYYYMMDD",
	 [ "insert into crash_me_d(a) values ('19630816')"],
	 "select a from crash_me_d",
	 ["delete from crash_me_d"],
	 make_date_r(1963,8,16),1);
    check_and_report("Supports DATE 'YYYYMMDD' format",
	 "date_format_YYYYMMDD_with_date",
	 [ "insert into crash_me_d(a) values (DATE '19630816')"],
	 "select a from crash_me_d",
	 ["delete from crash_me_d"],
	 make_date_r(1963,8,16),1);

    check_and_report("Supports MM/DD/YYYY format",
	 "date_format_USA",
	 [ "insert into crash_me_d(a) values ('08/16/1963')"],
	 "select a from crash_me_d",
	 ["delete from crash_me_d"],
	 make_date_r(1963,8,16),1);
    check_and_report("Supports DATE 'MM/DD/YYYY' format",
	 "date_format_USA_with_date",
	 [ "insert into crash_me_d(a) values (DATE '08/16/1963')"],
	 "select a from crash_me_d",
	 ["delete from crash_me_d"],
	 make_date_r(1963,8,16),1);


 

    check_and_report("Supports 0000-00-00 dates","date_zero",
	 ["create table crash_me2 (a date not null)",
	  "insert into crash_me2 values (".make_date(0,0,0).")"],
	 "select a from crash_me2",
	 ["drop table crash_me2 $drop_attr"],
	 make_date_r(0,0,0),1);

    check_and_report("Supports 0001-01-01 dates","date_one",
	 ["create table crash_me2 (a date not null)",
	  "insert into crash_me2 values (".make_date(1,1,1).")"],
	 "select a from crash_me2",
	 ["drop table crash_me2 $drop_attr"],
	 make_date_r(1,1,1),1);
    
    check_and_report("Supports 9999-12-31 dates","date_last",
	["create table crash_me2 (a date not null)",
        "insert into crash_me2 values (".make_date(9999,12,31).")"],
        "select a from crash_me2",
	["drop table crash_me2 $drop_attr"],
	make_date_r(9999,12,31),1);
    
    check_and_report("Supports 'infinity dates","date_infinity",
	 ["create table crash_me2 (a date not null)",
	 "insert into crash_me2 values ('infinity')"],
	 "select a from crash_me2",
	 ["drop table crash_me2 $drop_attr"],
	 "infinity",1);
    
    if (!defined($limits{'date_with_YY'}))
    {
	check_and_report("Supports YY-MM-DD dates","date_with_YY",
	   ["create table crash_me2 (a date not null)",
	   "insert into crash_me2 values ('98-03-03')"],
	   "select a from crash_me2",
	   ["drop table crash_me2 $drop_attr"],
	   make_date_r(1998,3,3),5);
	if ($limits{'date_with_YY'} eq "yes")
	{
	    undef($limits{'date_with_YY'});
	    check_and_report("Supports YY-MM-DD 2000 compilant dates",
	       "date_with_YY",
	       ["create table crash_me2 (a date not null)",
	       "insert into crash_me2 values ('10-03-03')"],
	       "select a from crash_me2",
	       ["drop table crash_me2 $drop_attr"],
	       make_date_r(2010,3,3),5);
	}
    }
    
# Test: WEEK()
    {
	my $result="no";
	my $error;
	print "WEEK:";
	save_incomplete('func_odbc_week','WEEK');
	$error = safe_query_result_l('func_odbc_week',
	     "select week(".make_date(1997,2,1).") $end_query",5,0);
	# actually this query must return 4 or 5 in the $last_result,
	# $error can be 1 (not supported at all) , -1 ( probably USA weeks)
	# and 0 - EURO weeks
	if ($error == -1) { 
	    if ($last_result == 4) {
		$result = 'USA';
	    } else {
		$result='error';
		add_log('func_odbc_week',
		  " must return 4 or 5, but $last_result");
	    }
	} elsif ($error == 0) {
	    $result = 'EURO';
	}
	print " $result\n";
	save_config_data('func_odbc_week',$result,"WEEK");
    }
    
    my $insert_query ='insert into crash_me_d values('.
        make_date(1997,2,1).')';
    safe_query($insert_query);
    
    foreach $fn ( (
		   ["DAYNAME","dayname","dayname(a)","",2],
		   ["MONTH","month","month(a)","",2],
		   ["MONTHNAME","monthname","monthname(a)","",2],
		   ["DAYOFMONTH","dayofmonth","dayofmonth(a)",1,0],
		   ["DAYOFWEEK","dayofweek","dayofweek(a)",7,0],
		   ["DAYOFYEAR","dayofyear","dayofyear(a)",32,0],
		   ["QUARTER","quarter","quarter(a)",1,0],
		   ["YEAR","year","year(a)",1997,0]))
    {
	$prompt='Function '.$fn->[0];
	$key='func_odbc_'.$fn->[1];
	add_log($key,"< ".$insert_query);
	check_and_report($prompt,$key,
			 [],"select ".$fn->[2]." from crash_me_d",[],
			 $fn->[3],$fn->[4]
			 );
	
    };
    safe_query(['delete from crash_me_d', 
		'insert into crash_me_d values('.make_date(1963,8,16).')']);
    foreach $fn ((
	  ["DATEADD","dateadd","dateadd(day,3,make_date(1997,11,30))",0,2],
	  ["MDY","mdy","mdy(7,1,1998)","make_date_r(1998,07,01)",0], # informix
	  ["DATEDIFF","datediff",
	     "datediff(month,'Oct 21 1997','Nov 30 1997')",0,2],
	  ["DATENAME","datename","datename(month,'Nov 30 1997')",0,2],
	  ["DATEPART","datepart","datepart(month,'July 20 1997')",0,2],
	  ["DATE_FORMAT","date_format", 
	    "date_format('1997-01-02 03:04:05','M W D Y y m d h i s w')", 0,2],
	  ["FROM_DAYS","from_days",
	    "from_days(729024)","make_date_r(1996,1,1)",1],
	  ["FROM_UNIXTIME","from_unixtime","from_unixtime(0)",0,2],
	  ["MONTHS_BETWEEN","months_between",
	   "months_between(make_date(1997,2,2),make_date(1997,1,1))",
	   "1.03225806",0], # oracle number of months between 2 dates
	  ["PERIOD_ADD","period_add","period_add(9602,-12)",199502,0],
	  ["PERIOD_DIFF","period_diff","period_diff(199505,199404)",13,0],
	  ["WEEKDAY","weekday","weekday(make_date(1997,11,29))",5,0],
	  ["ADDDATE",'adddate',
	   "ADDDATE(make_date(2002,12,01),3)",'make_date_r(2002,12,04)',0],
	  ["SUBDATE",'subdate',
	   "SUBDATE(make_date(2002,12,04),3)",'make_date_r(2002,12,01)',0],
	  ["DATEDIFF (2 arg)",'datediff2arg',
	   "DATEDIFF(make_date(2002,12,04),make_date(2002,12,01))",'3',0],
	  ["WEEKOFYEAR",'weekofyear',
	   "WEEKOFYEAR(make_date(1963,08,16))",'33',0],
# table crash_me_d must contain  record with 1963-08-16 (for CHAR)
	  ["CHAR (conversation date)",'char_date',
	   "CHAR(a,EUR)",'16.08.1963',0],
	  ["MAKEDATE",'makedate',"MAKEDATE(1963,228)"
	   ,'make_date_r(1963,08,16)',0],
	  ["TO_DAYS","to_days",
	   "to_days(make_date(1996,01,01))",729024,0],
	  ["ADD_MONTHS","add_months",
	   "add_months(make_date(1997,01,01),1)","make_date_r(1997,02,01)",0], 
	      # oracle the date plus n months
	  ["LAST_DAY","last_day",
	  "last_day(make_date(1997,04,01))","make_date_r(1997,04,30)",0], 
	      # oracle last day of month of date
	  ["DATE",'date',"date(make_date(1963,8,16))",
	     'make_date_r(1963,8,16)',0],
	  ["DAY",'day',"DAY(make_date(2002,12,01))",1,0]))
    {
	$prompt='Function '.$fn->[0];
	$key='func_extra_'.$fn->[1];
	my $qry="select ".$fn->[2]." from crash_me_d";
	while( $qry =~ /^(.*)make_date\((\d+),(\d+),(\d+)\)(.*)$/)
	{
	    my $dt= &make_date($2,$3,$4);
	    $qry=$1.$dt.$5;
	};
	my $result=$fn->[3];
	while( $result =~ /^(.*)make_date_r\((\d+),(\d+),(\d+)\)(.*)$/)
	{
	    my $dt= &make_date_r($2,$3,$4);
	    $result=$1.$dt.$5;
	};
	check_and_report($prompt,$key,
			 [],$qry,[],
			 $result,$fn->[4]
			 );
	
    }
    
    safe_query("drop table crash_me_d $drop_attr");    
    
}

if ($limits{'type_sql_time'} eq 'yes')
{  # 
   # Checking the format of date in result. 
   
    safe_query("drop table crash_me_t $drop_attr");
    assert("create table crash_me_t (a time)");
    # find the example of time
    my $timeexample;
    if ($limits{'func_sql_current_time'} eq 'yes') {
     $timeexample='CURRENT_TIME';
    } 
    elsif ($limits{'func_odbc_curtime'} eq 'yes') {
     $timeexample='curtime()';
    } 
    elsif ($limits{'func_sql_localtime'} eq 'yes') {
	$timeexample='localtime';
    }
    elsif ($limits{'func_odbc_now'} eq 'yes') {
	$timeexample='now()';
    } else {
	#try to guess 
	$timeexample="'02:55:12'";
    } ;
    
    my $key = 'time_format_inresult';
    my $prompt = "Time format in result";
    if (! safe_query_l('time_format_inresult',
       "insert into crash_me_t values($timeexample) "))
    { 
        #die "Cannot insert time ($timeexample):".$last_error; 
        add_log($key,
                "Cannot insert time ($timeexample):".$last_error."\n");
        save_config_data($key,"unknown",$prompt);

        #FIXME: It seems that we have to rewrite below as
        #       else
        #       {
        #         ...
    };
    my $sth= $dbh->prepare("select a from crash_me_t");
    add_log('time_format_inresult',"< select a from crash_me_t");
    $sth->execute;
    $_= $sth->fetchrow_array;
    add_log('time_format_inresult',"> $_");
    safe_query_l($key,"delete from crash_me_t");   
    if (/\d{2}:\d{2}:\d{2}/){ save_config_data($key,"iso",$prompt);} 
    elsif (/\d{2}\.\d{2}\.\d{2}/){ save_config_data($key,"euro",$prompt);}
    elsif (/\d{2}:\d{2}\s+(AM|PM)/i){ save_config_data($key,"usa",$prompt);}
    elsif (/\d{8}$/){ save_config_data($key,"HHHHMMSS",$prompt);}
    elsif (/\d{4}$/){ save_config_data($key,"HHMMSS",$prompt);}
    else  { save_config_data($key,"unknown",$prompt);};
    $sth->finish;

    check_and_report("Supports HH:MM:SS (ISO) time format","time_format_ISO",
		     [ "insert into crash_me_t(a)  values ('20:08:16')"],
		     "select a from crash_me_t",
		     ["delete from crash_me_t"],
		     make_time_r(20,8,16),1);

    check_and_report("Supports HH.MM.SS (EUR) time format","time_format_EUR",
		     [ "insert into crash_me_t(a) values ('20.08.16')"],
		     "select a from crash_me_t",
		     ["delete from crash_me_t"],
		     make_time_r(20,8,16),1);

    check_and_report("Supports HHHHmmSS time format",
	 "time_format_HHHHMMSS",
	 [ "insert into crash_me_t(a) values ('00200816')"],
	 "select a from crash_me_t",
	 ["delete from crash_me_t"],
	 make_time_r(20,8,16),1);

    check_and_report("Supports HHmmSS time format",
	 "time_format_HHHHMMSS",
	 [ "insert into crash_me_t(a) values ('200816')"],
	 "select a from crash_me_t",
	 ["delete from crash_me_t"],
	 make_time_r(20,8,16),1);
	 
    check_and_report("Supports HH:MM:SS (AM|PM) time format",
	 "time_format_USA",
	 [ "insert into crash_me_t(a) values ('08:08:16 PM')"],
	 "select a from crash_me_t",
	 ["delete from crash_me_t"],
	 make_time_r(20,8,16),1);	 
    
    my $insert_query ='insert into crash_me_t values('.
        make_time(20,8,16).')';
    safe_query($insert_query);
    
    foreach $fn ( (
            ["HOUR","hour","hour('".make_time(12,13,14)."')",12,0],
            ["ANSI HOUR","hour_time","hour(TIME '".make_time(12,13,14)."')",12,0],
            ["MINUTE","minute","minute('".make_time(12,13,14)."')",13,0],
            ["SECOND","second","second('".make_time(12,13,14)."')",14,0]

    ))
    {
	$prompt='Function '.$fn->[0];
	$key='func_odbc_'.$fn->[1];
	add_log($key,"< ".$insert_query);
	check_and_report($prompt,$key,
			 [],"select ".$fn->[2]." $end_query",[],
			 $fn->[3],$fn->[4]
			 );
	
    };
#    safe_query(['delete from crash_me_t', 
#		'insert into crash_me_t values('.make_time(20,8,16).')']);
    foreach $fn ((
         ["TIME_TO_SEC","time_to_sec","time_to_sec('".
	          make_time(1,23,21)."')","5001",0],
         ["SEC_TO_TIME","sec_to_time","sec_to_time(5001)",
	      make_time_r(01,23,21),1],
         ["ADDTIME",'addtime',"ADDTIME('".make_time(20,2,12).
	    "','".make_time(0,0,3)."')",make_time_r(20,2,15),0],
         ["SUBTIME",'subtime',"SUBTIME('".make_time(20,2,15)
	          ."','".make_time(0,0,3)."')",make_time_r(20,2,12),0],
         ["TIMEDIFF",'timediff',"TIMEDIFF('".make_time(20,2,15)."','".
	 make_time(20,2,12)."')",make_time_r(0,0,3),0],
         ["MAKETIME",'maketime',"MAKETIME(20,02,12)",make_time_r(20,2,12),0],
         ["TIME",'time',"time('".make_time(20,2,12)."')",make_time_r(20,2,12),0]
    ))
    {
	$prompt='Function '.$fn->[0];
	$key='func_extra_'.$fn->[1];
	my $qry="select ".$fn->[2]." $end_query";
	my $result=$fn->[3];
	check_and_report($prompt,$key,
			 [],$qry,[],
			 $result,$fn->[4]
			 );
	
    }
    
    safe_query("drop table crash_me_t $drop_attr");    
    
}


# NOT id BETWEEN a and b
if ($limits{'func_where_not_between'} eq 'yes')
{
   my $result = 'error';
   my $err;
   my $key='not_id_between';
   my $prompt='NOT ID BETWEEN interprets as ID NOT BETWEEN';
   print "$prompt:";
   save_incomplete($key,$prompt);
   safe_query_l($key,["create table crash_me_b (i int)",
         "insert into crash_me_b values(2)",
         "insert into crash_me_b values(5)"]);
   $err =safe_query_result_l($key,
    "select i from crash_me_b where not i between 1 and 3",
     5,0);
   if ($err eq 1) {
      if (not defined($last_result)) {
        $result='no';
      };
   };
   if ( $err eq 0) {
      $result = 'yes';
   };
   safe_query_l($key,["drop table crash_me_b"]);
   save_config_data($key,$result,$prompt);
   print "$result\n";
};




report("LIKE on numbers","like_with_number",
       "create table crash_q (a int,b int)",
       "insert into crash_q values(10,10)",
       "select * from crash_q where a like '10'",
       "drop table crash_q $drop_attr");

report("column LIKE column","like_with_column",
       "create table crash_q (a char(10),b char(10))",
       "insert into crash_q values('abc','abc')",
       "select * from crash_q where a like b",
       "drop table crash_q $drop_attr");

report("update of column= -column","NEG",
       "create table crash_q (a integer)",
       "insert into crash_q values(10)",
       "update crash_q set a=-a",
       "drop table crash_q $drop_attr");

if ($limits{'func_odbc_left'} eq 'yes' ||
    $limits{'func_odbc_substring'} eq 'yes')
{
  my $type= ($limits{'func_odbc_left'} eq 'yes' ?
	     "left(a,4)" : "substring(a for 4)");

    check_and_report("String functions on date columns","date_as_string",
		     ["create table crash_me2 (a date not null)",
		      "insert into crash_me2 values ('1998-03-03')"],
		     "select $type from crash_me2",
		     ["drop table crash_me2 $drop_attr"],
		     "1998",1);
}


$tmp=sql_concat("b","b");
if (defined($tmp))
{
  check_and_report("char are space filled","char_is_space_filled",
		   [],"select $tmp from crash_me where b = 'a         '",[],
		   'a         a         ',6);
}

if (!defined($limits{'multi_table_update'}))
{
  if (check_and_report("Update with many tables","multi_table_update",
	   ["create table crash_q (a integer,b char(10))",
	    "insert into crash_q values(1,'c')",
	    "update crash_q left join crash_me on crash_q.a=crash_me.a set crash_q.b=crash_me.b"],
            "select b from crash_q",
	   ["drop table crash_q $drop_attr"],
	   "a",1,undef(),2))
  {
    check_and_report("Update with many tables","multi_table_update",
	     ["create table crash_q (a integer,b char(10))",
	      "insert into crash_q values(1,'c')",
	      "update crash_q,crash_me set crash_q.b=crash_me.b ".
	      "where crash_q.a=crash_me.a"],
	     "select b from crash_q",
	     ["drop table crash_q $drop_attr"],
		     "a",1,
		    1);
  }
}

report("DELETE FROM table1,table2...","multi_table_delete",
       "create table crash_q (a integer,b char(10))",
       "insert into crash_q values(1,'c')",
       "delete crash_q.* from crash_q,crash_me where crash_q.a=crash_me.a",
       "drop table crash_q $drop_attr");

check_and_report("Update with sub select","select_table_update",
		 ["create table crash_q (a integer,b char(10))",
		  "insert into crash_q values(1,'c')",
		  "update crash_q set b= ".
		  "(select b from crash_me where crash_q.a = crash_me.a)"],
		 "select b from crash_q",
		 ["drop table crash_q $drop_attr"],
		 "a",1);

check_and_report("Calculate 1--1","minus_neg",[],
		 "select a--1 from crash_me",[],0,2);

report("ANSI SQL simple joins","simple_joins",
       "select crash_me.a from crash_me, crash_me t0");

#
# Check max string size, and expression limits
#
$found=undef;
foreach $type (('mediumtext','text','text()','blob','long'))
{
  if ($limits{"type_extra_$type"} eq 'yes')
  {
    $found=$type;
    last;
  }
}
if (defined($found))
{
  $found =~ s/\(\)/\(%d\)/;
  find_limit("max text or blob size","max_text_size",
	     new query_many(["create table crash_q (q $found)",
			     "insert into crash_q values ('%s')"],
			    "select * from crash_q","%s",
			    ["drop table crash_q $drop_attr"],
			    min($max_string_size,$limits{'query_size'}-30)));

}

# It doesn't make lots of sense to check for string lengths much bigger than
# what can be stored...

find_limit(($prompt="constant string size in where"),"where_string_size",
	   new query_repeat([],"select a from crash_me where b >='",
			    "","","1","","'"));
if ($limits{'where_string_size'} == 10)
{
  save_config_data('where_string_size','nonstandard',$prompt);
}

if ($limits{'select_constants'} eq 'yes')
{
  find_limit("constant string size in SELECT","select_string_size",
	     new query_repeat([],"select '","","","a","","'$end_query"));
}

goto no_functions if ($limits{'functions'} ne "yes");

if ($limits{'func_odbc_repeat'} eq 'yes')
{
  find_limit("return string size from function","repeat_string_size",
	     new query_many([],
			    "select repeat('a',%d) $end_query","%s",
			    [],
			    $max_string_size,0));
}

$tmp=find_limit("simple expressions","max_expressions",
		new query_repeat([],"select 1","","","+1","",$end_query,
				 undef(),$max_expressions));

if ($tmp > 10)
{
  $tmp= "(1" . ( '+1' x ($tmp-10) ) . ")";
  find_limit("big expressions", "max_big_expressions",
	     new query_repeat([],"select 0","","","+$tmp","",$end_query,
			      undef(),$max_big_expressions));
}

find_limit("stacked expressions", "max_stack_expression",
	   new query_repeat([],"select 1","","","+(1",")",$end_query,
				undef(),$max_stacked_expressions));

no_functions:

if (!defined($limits{'max_conditions'}))
{
  find_limit("OR and AND in WHERE","max_conditions",
	     new query_repeat([],
			      "select a from crash_me where a=1 and b='a'","",
			      "", " or a=%d and b='%d'","","","",
			      [],($query_size-42)/29,undef,2));
  $limits{'max_conditions'}*=2;
}
# The 42 is the length of the constant part.
# The 29 is the length of the variable part, plus two seven-digit numbers.

find_limit("tables in join", "join_tables",
	   new query_repeat([],
			    "select crash_me.a",",t%d.a","from crash_me",
			    ",crash_me t%d","","",[],$max_join_tables,undef,
			    1));

# Different CREATE TABLE options

report("primary key in create table",'primary_key_in_create',
       "create table crash_q (q integer not null,primary key (q))",
       "drop table crash_q $drop_attr");

report("unique in create table",'unique_in_create',
       "create table crash_q (q integer not null,unique (q))",
       "drop table crash_q $drop_attr");

if ($limits{'unique_in_create'} eq 'yes')
{
  report("unique null in create",'unique_null_in_create',
	 "create table crash_q (q integer,unique (q))",
	 "insert into crash_q (q) values (NULL)",
	 "insert into crash_q (q) values (NULL)",
	 "insert into crash_q (q) values (1)",
	 "drop table crash_q $drop_attr");
}

report("default value for column",'create_default',
       "create table crash_q (q integer default 10 not null)",
       "drop table crash_q $drop_attr");

report("default value function for column",'create_default_func',
       "create table crash_q (q integer not null,q1 integer default (1+1))",
       "drop table crash_q $drop_attr");

report("temporary tables",'temporary_table',
       "create temporary table crash_q (q integer not null)",
       "drop table crash_q $drop_attr");

report_one("create table from select",'create_table_select',
	   [["create table crash_q SELECT * from crash_me","yes"],
	    ["create table crash_q AS SELECT * from crash_me","with AS"]]);
$dbh->do("drop table crash_q $drop_attr");

report("index in create table",'index_in_create',
       "create table crash_q (q integer not null,index (q))",
       "drop table crash_q $drop_attr");

# The following must be executed as we need the value of end_drop_keyword
# later
if (!(defined($limits{'create_index'}) && defined($limits{'drop_index'})))
{
  if ($res=safe_query_l('create_index',"create index crash_q on crash_me (a)"))
  {
    $res="yes";
    $drop_res="yes";
    $end_drop_keyword="";
    if (!safe_query_l('drop_index',"drop index crash_q"))
    {
      # Can't drop the standard way; Check if mSQL
      if (safe_query_l('drop_index',"drop index crash_q from crash_me"))
      {
        $drop_res="with 'FROM'";	# Drop is not ANSI SQL
        $end_drop_keyword="drop index %i from %t";
      }
      # else check if Access or MySQL
      elsif (safe_query_l('drop_index',"drop index crash_q on crash_me"))
      {
        $drop_res="with 'ON'";	# Drop is not ANSI SQL
        $end_drop_keyword="drop index %i on %t";
      }
      # else check if MS-SQL
      elsif (safe_query_l('drop_index',"drop index crash_me.crash_q"))
      {
        $drop_res="with 'table.index'"; # Drop is not ANSI SQL
        $end_drop_keyword="drop index %t.%i";
      }
    }
    else
    {
      # Old MySQL 3.21 supports only the create index syntax
      # This means that the second create doesn't give an error.
      $res=safe_query_l('create_index',["create index crash_q on crash_me (a)",
      		     "create index crash_q on crash_me (a)",
      		     "drop index crash_q"]);
      $res= $res ? 'ignored' : 'yes';
    }
  }
  else
  {
    $drop_res=$res='no';
  }
  save_config_data('create_index',$res,"create index");
  save_config_data('drop_index',$drop_res,"drop index");

  print "create index: $limits{'create_index'}\n";
  print "drop index: $limits{'drop_index'}\n";
}

# check if we can have 'NULL' as a key
check_and_report("null in index","null_in_index",
		 [create_table("crash_q",["a char(10)"],["(a)"]),
		  "insert into crash_q values (NULL)"],
		 "select * from crash_q",
		 ["drop table crash_q $drop_attr"],
		 undef(),4);

if ($limits{'unique_in_create'} eq 'yes')
{
  report("null in unique index",'null_in_unique',
          create_table("crash_q",["q integer"],["unique(q)"]),
	 "insert into crash_q (q) values(NULL)",
	 "insert into crash_q (q) values(NULL)",
	 "drop table crash_q $drop_attr");
  report("null combination in unique index",'nulls_in_unique',
          create_table("crash_q",["q integer,q1 integer"],["unique(q,q1)"]),
	 "insert into crash_q (q,q1) values(1,NULL)",
	 "insert into crash_q (q,q1) values(1,NULL)",
	 "drop table crash_q $drop_attr");
}

if ($limits{'null_in_unique'} eq 'yes')
{
  report("null in unique index",'multi_null_in_unique',
          create_table("crash_q",["q integer, x integer"],["unique(q)"]),
	 "insert into crash_q(x) values(1)",
	 "insert into crash_q(x) values(2)",
	 "drop table crash_q $drop_attr");
}

if ($limits{'create_index'} ne 'no')
{
  $end_drop=$end_drop_keyword;
  $end_drop =~ s/%i/crash_q/;
  $end_drop =~ s/%t/crash_me/;
  report("index on column part (extension)","index_parts",,
	 "create index crash_q on crash_me (b(5))",
	 $end_drop);
  $end_drop=$end_drop_keyword;
  $end_drop =~ s/%i/crash_me/;
  $end_drop =~ s/%t/crash_me/;
  report("different namespace for index",
	 "index_namespace",
	 "create index crash_me on crash_me (b)",
	 $end_drop);
}

if (!report("case independent table names","table_name_case",
	    "create table crash_q (q integer)",
	    "drop table CRASH_Q $drop_attr"))
{
  safe_query("drop table crash_q $drop_attr");
}

if (!report("case independent field names","field_name_case",
	    "create table crash_q (q integer)",
	    "insert into crash_q(Q) values (1)",
	    "drop table crash_q $drop_attr"))
{
  safe_query("drop table crash_q $drop_attr");
}

if (!report("drop table if exists","drop_if_exists",
	    "create table crash_q (q integer)",
	    "drop table if exists crash_q $drop_attr"))
{
  safe_query("drop table crash_q $drop_attr");
}

report("create table if not exists","create_if_not_exists",
       "create table crash_q (q integer)",
       "create table if not exists crash_q (q integer)");
safe_query("drop table crash_q $drop_attr");

#
# test of different join types
#

assert("create table crash_me2 (a integer not null,b char(10) not null,".
       " c1 integer)");
assert("insert into crash_me2 (a,b,c1) values (1,'b',1)");
assert("create table crash_me3 (a integer not null,b char(10) not null)");
assert("insert into crash_me3 (a,b) values (1,'b')");

report("inner join","inner_join",
       "select crash_me.a from crash_me inner join crash_me2 ON ".
       "crash_me.a=crash_me2.a");
report("left outer join","left_outer_join",
       "select crash_me.a from crash_me left join crash_me2 ON ".
       "crash_me.a=crash_me2.a");
report("natural left outer join","natural_left_outer_join",
       "select c1 from crash_me natural left join crash_me2");
report("left outer join using","left_outer_join_using",
       "select c1 from crash_me left join crash_me2 using (a)");
report("left outer join odbc style","odbc_left_outer_join",
       "select crash_me.a from { oj crash_me left outer join crash_me2 ON".
       " crash_me.a=crash_me2.a }");
report("right outer join","right_outer_join",
       "select crash_me.a from crash_me right join crash_me2 ON ".
       "crash_me.a=crash_me2.a");
report("full outer join","full_outer_join",
       "select crash_me.a from crash_me full join crash_me2 ON "."
       crash_me.a=crash_me2.a");
report("cross join (same as from a,b)","cross_join",
       "select crash_me.a from crash_me cross join crash_me3");
report("natural join","natural_join",
       "select * from crash_me natural join crash_me3");
report("union","union",
       "select * from crash_me union select a,b from crash_me3");
report("union all","union_all",
       "select * from crash_me union all select a,b from crash_me3");
report("intersect","intersect",
       "select * from crash_me intersect select * from crash_me3");
report("intersect all","intersect_all",
       "select * from crash_me intersect all select * from crash_me3");
report("except","except",
       "select * from crash_me except select * from crash_me3");
report("except all","except_all",
       "select * from crash_me except all select * from crash_me3");
report("except","except",
       "select * from crash_me except select * from crash_me3");
report("except all","except_all",
       "select * from crash_me except all select * from crash_me3");
report("minus","minus",
       "select * from crash_me minus select * from crash_me3"); # oracle ...

report("natural join (incompatible lists)","natural_join_incompat",
       "select c1 from crash_me natural join crash_me2");
report("union (incompatible lists)","union_incompat",
       "select * from crash_me union select a,b from crash_me2");
report("union all (incompatible lists)","union_all_incompat",
       "select * from crash_me union all select a,b from crash_me2");
report("intersect (incompatible lists)","intersect_incompat",
       "select * from crash_me intersect select * from crash_me2");
report("intersect all (incompatible lists)","intersect_all_incompat",
       "select * from crash_me intersect all select * from crash_me2");
report("except (incompatible lists)","except_incompat",
       "select * from crash_me except select * from crash_me2");
report("except all (incompatible lists)","except_all_incompat",
       "select * from crash_me except all select * from crash_me2");
report("except (incompatible lists)","except_incompat",
       "select * from crash_me except select * from crash_me2");
report("except all (incompatible lists)","except_all_incompat",
       "select * from crash_me except all select * from crash_me2");
report("minus (incompatible lists)","minus_incompat",
       "select * from crash_me minus select * from crash_me2"); # oracle ...

if ($limits{'union'} eq 'yes') {
  assert('delete from crash_me3');
  assert("insert into crash_me3 (a,b) values (1,'100')");
  assert("insert into crash_me3 (a,b) values (2,'200')");
  report("union with different column types","union_diff_types",
         "select a from crash_me union select b from crash_me3");
}

assert("drop table crash_me2 $drop_attr");
assert("drop table crash_me3 $drop_attr");

# somethings to be added here ....
# FOR UNION - INTERSECT - EXCEPT -> CORRESPONDING [ BY ]
# after subqueries:
# >ALL | ANY | SOME - EXISTS - UNIQUE

if (report("subqueries","subqueries",
	   "select a from crash_me where crash_me.a in ".
	   "(select max(a) from crash_me)"))
{
    assert("create table crash_me_t1 (a int,b int,c char(3))");
    assert("create table crash_me_t2 (a int,b int,c char(3))");

    assert("insert into crash_me_t1 values (1,1,'abc')");
    assert("insert into crash_me_t1 values (1,2,'bca')");
    assert("insert into crash_me_t1 values (1,3,'cba')");

    assert("insert into crash_me_t2 values (1,1,'abc')");
    assert("insert into crash_me_t2 values (1,2,'abc')");
    assert("insert into crash_me_t2 values (2,1,'abc')");

#1. What can a subquery be in:

    report("SUBQUERIES in SELECT LIST - Uncorrelated", "subqueries_1.1.1",
           "select (select max(a) from crash_me_t2 where b=1 group by b) as x,b from crash_me_t1 where b=1");

    report("SUBQUERIES in SELECT LIST - Correlated", "subqueries_1.1.2",
           "select avg((select max(b) from crash_me_t1 where crash_me_t1.b=crash_me_t2.b)) as x from crash_me_t2");

    report("SUBQUERIES in SELECT LIST - Correlated, references on alias", "subqueries_1.1.3",
           "select a+b as d, (select max(b) from crash_me_t2 where a=d) as e from crash_me_t1 where b=1");

    report("SUBQUERIES in WHERE - Uncorrelated", "subqueries_1.2.1",
           "select * from crash_me_t1 where (select crash_me_t2.c from crash_me_t2 where crash_me_t2.b=2 ) = 'abc'");

    report("SUBQUERIES in WHERE - Correlated", "subqueries_1.2.2",
           "select * from crash_me_t1 where ( select crash_me_t2.c from crash_me_t2 where crash_me_t2.b=crash_me_t1.b group by crash_me_t2.c ) = 'abc'");

    report("SUBQUERIES in GROUP BY - Uncorrelated","subqueries_1.3.1",
           "select max(a) from crash_me_t1 group by (select min(a) from crash_me_t1)");

    report("SUBQUERIES in GROUP BY - Correlated","subqueries_1.3.2",
           "select max(a) from crash_me_t1 group by (select min(crash_me_t2.a) from crash_me_t2 where crash_me_t2.b<crash_me_t1.b)");

    report("SUBQUERIES in HAVING - Uncorrelated","subqueries_1.4.1",
           "select crash_me_t1.b, max(crash_me_t1.a) as m from crash_me_t1 group by crash_me_t1.b having 10 > (select max(crash_me_t2.a) from crash_me_t2 where crash_me_t2.b=2)");

    report("SUBQUERIES in HAVING - Correlated","subqueries_1.4.2",
           "select crash_me_t1.b, max(crash_me_t1.a) as m from crash_me_t1 group by crash_me_t1.b having 10 > (select max(crash_me_t2.a) from crash_me_t2 where crash_me_t2.b=crash_me_t1.b)");

    report("SUBQUERIES in ORDER BY - Uncorrelated","subqueries_1.5.1",
           "select * from crash_me_t1 order by (select max(crash_me_t2.a) from crash_me_t2) * crash_me_t1.b");

    report("SUBQUERIES in ORDER BY - Correlated","subqueries_1.5.2",
           "select a from crash_me_t1 order by (select max(crash_me_t2.a) from crash_me_t2 where crash_me_t2.b<crash_me_t1.b)");

    report("SUBQUERIES in ON","subqueries_1.6.1",
           "select crash_me_t1.a from crash_me_t1 left join crash_me_t2 ON crash_me_t2.c IN (select c from crash_me_t1 where crash_me_t2.b=crash_me_t1.b)");

    report("SUBQUERIES in UNION","subqueries_1.7.1","select a from crash_me_t1 where (select max(crash_me_t1.b) from crash_me_t1,crash_me_t2 where crash_me_t1.a=crash_me_t2.a) union select (select max(a) from crash_me_t1)");

#2. ROWS SUBQUERIES

    report("Test for ()","subqueries_2.1.1",
           "select a from crash_me_t1 where (crash_me_t1.b,1) = (1,1)");

    report("Test for ROW()","subqueries_2.1.2",
           "select a from crash_me_t1 where ROW(b,1) = ROW(1,1)");

    report("test of '<' operation for ROW()","subqueries_2.2.1",
           "select ROW(1,2,3)<ROW(1+1,2,3) from crash_me_t1");

    report("test of '>' operation for ROW()","subqueries_2.2.2",
           "select ROW(1,2,3)>ROW(1+1,2,3) from crash_me_t1 ");

    report("test of '<=' operation for ROW()","subqueries_2.2.2",
           "select ROW(1,2,3)<=ROW(1+1,2,3) from crash_me_t1");

    report("test of '>=' operation for ROW()","subqueries_2.2.3",
           "select ROW(1,2,3)>=ROW(1+1,2,3) from crash_me_t1");

    report("test of '<>' operation for ROW()","subqueries_2.2.4",
           "select ROW(1,2,3)<>ROW(1+1,2,3) from crash_me_t1");

    report("test of '=' operation for ROW()","subqueries_2.2.5",
           "select ROW(1,2,3)<>ROW(1+1,2,3) from crash_me_t1");

    report("test of nested ROW()","subqueries_2.2.6",
           "select ROW(1,ROW(2,2),1)=ROW(1,ROW(2,2),1) from crash_me_t1");

    report("subselect in ROW()","subqueries_2.2.7",
           "select c from crash_me_t1 where (a, b) = (select min(a),min(b) from crash_me_t2)");

    report("IN in ROW()","subqueries_2.2.8",
           "select crash_me_t1.c from crash_me_t1 where row(1,2,crash_me_t1.a,crash_me_t1.b) IN (row(1,2,1,2), row(1,2,1,4))");

#3. TABLE SUBQUERIES

    report("SUBQUERIES in FROM - Uncorrelated","subqueries_3.1.1",
           "select max(crash_me_t1.b) from crash_me_t1,(select a as y from crash_me_t2 where b=1) as t3 where crash_me_t1.b = t3.y");

    report("SUBQUERIES in FROM - Correlated","subqueries_3.1.2",
           "select max(crash_me_t1.b) from crash_me_t1 where (select max(t3.a) from (select * from crash_me_t2 where crash_me_t2.a=crash_me_t1.b) as t3) > 0");

#3.2 QUANTIFIED COMPARISON
#3.2.1. ALL, SOME, ANY, IN, [NOT] EXISTS, UNIQUES

    report("SUBQUERIES - ALL","subqueries_3.2.1",
           "select * from crash_me_t1 where b <> all (select b from crash_me_t2)");

    report("SUBQUERIES - SOME","subqueries_3.2.2",
           "select * from crash_me_t1 where c = some (select c from crash_me_t2)");

    report("SUBQUERIES - ANY","subqueries_3.2.3",
           "select * from crash_me_t1 where c = any (select c from crash_me_t2)");

    report("SUBQUERIES - EXISTS","subqueries_3.2.4",
           "select * from crash_me_t1 where exists (select b from crash_me_t2)");

    report("SUBQUERIES - NOT EXISTS","subqueries_3.2.5",
           "select * from crash_me_t1 where not exists (select b from crash_me_t2)");

#4. What can be in a subquery

    report("UNION in SUBQUERY","subqueries_4.1",
           "select crash_me_t1.c from crash_me_t1,crash_me_t2 where crash_me_t1.b=crash_me_t2.b and crash_me_t1.b in (select a from crash_me_t1 where a<5 union select a from crash_me_t2 where a>5)");

    report("DISTINCT in SUBQUERY","subqueries_4.2",
           "select crash_me_t1.c from crash_me_t1,crash_me_t2 where crash_me_t1.b=crash_me_t2.b and crash_me_t1.b in (select distinct a from crash_me_t1)");

    report("AGGREGATE FUNCS in SUBQUERY","subqueries_4.3",
           "select c from crash_me_t1 where crash_me_t1.b in (select max(b) from crash_me_t2 group by a)");

    report("JOIN in SUBQUERIES","subqueries_4.4",
           "select c from crash_me_t1 where b in (select b from crash_me_t2 LEFT JOIN crash_me_t1 USING(a))");


    report("LIMIT IN SUBQUERIES","subqueries_4.6.1",
           "select (select a from crash_me_t2 LIMIT 1) as x,b from crash_me_t1;");

#5. SUBQUERIES IN OTHER STATEMENTS

    assert("create table crash_me_t10 (a int, b int)");

    report("SUBQUERIES in INSERT","subqueries_5.1.1",
           "insert into crash_me_t10 values ((select max(a) from crash_me_t2),(select max(b) from crash_me_t2))");

    report("SUBQUERIES in UPDATE","subqueries_5.2.1",
           "update crash_me_t10 set b= (select max(crash_me_t2.b) from crash_me_t2)");

    report("SUBQUERIES in REPLACE","subqueries_5.3.1",
           "replace into crash_me_t10 values ((select max(a) from crash_me_t2),(select max(b) from crash_me_t2))");

    report("SUBQUERIES in DELETE","subqueries_5.4.1",
           "delete from crash_me_t10 where crash_me_t10.b= (select max(crash_me_t2.b) from crash_me_t2)");

    report("SUBQUERIES in CHECK","subqueries_5.5.1",
           "CREATE TABLE crash_me_t11 (a INT, CHECK (a IN (SELECT a FROM crash_me_t10)));");

#6. SUBQUERIES LIMITS

    report("LIMIT N,M in SUBQUERIES","subqueries_6.1.1",
           "select a from crash_me_t1 where b=(SELECT b from crash_me_t2 LIMIT 1)");

    report("LIMIT in IN/ANY/ALL SUBQUERIES","subqueries_6.1.2",
           "select a from crash_me_t1 where b IN (SELECT b from crash_me_t2 LIMIT 1)");

    report("Name resolutions in SUBQUERIES","subqueries_6.2.1",
           "update crash_me_t2 set b= (select max(b) from crash_me_t2);");

    assert("create table crash_me_t21 (a int)");
    assert("create table crash_me_t22 (aa int)");
    assert("create table crash_me_t23 (aaa int)");

    report("Name scope in SUBQUERIES","subqueries_6.2.2",
           "SELECT a FROM crash_me_t21 WHERE a = (SELECT a FROM crash_me_t22 WHERE a = (SELECT a from crash_me_t23))");

    $tmp=new query_repeat([],"select a from crash_me","","",
			  " where a in (select a from crash_me",")",
			  "",[],$max_join_tables);
    find_limit("recursive subqueries", "recursive_subqueries",$tmp);


    assert("drop table crash_me_t21 $drop_attr");
    assert("drop table crash_me_t22 $drop_attr");
    assert("drop table crash_me_t23 $drop_attr");

    assert("drop table crash_me_t10 $drop_attr");
    assert("drop table crash_me_t11 $drop_attr");
    assert("drop table crash_me_t1 $drop_attr");
    assert("drop table crash_me_t2 $drop_attr");
}

report("insert INTO ... SELECT ...","insert_select",
       "create table crash_q (a int)",
       "insert into crash_q (a) SELECT crash_me.a from crash_me",
       "drop table crash_q $drop_attr");

if (!defined($limits{"transactions"}))
{
  my ($limit,$type);
  $limit="transactions";
  $limit_r="rollback_metadata";
  my $type = "";
  print "$limit: ";
  undef($limits{$limit});
  if (!report_trans($limit,
			   [create_table("crash_q",["a integer not null"],[],
					 $type)],
			    ["insert into crash_q values (1)"],
			   "select * from crash_q",
			   "drop table crash_q $drop_attr"
			  ))
  {
    report_rollback($limit_r,
              [create_table("crash_q",["a integer not null"],[],
				 $type)],
			    "insert into crash_q values (1)",
			   "drop table crash_q $drop_attr" );
  };
  print "$limits{$limit}\n";
  print "$limit_r: $limits{$limit_r}\n";
}

report("atomic updates","atomic_updates",
       create_table("crash_q",["a integer not null"],["primary key (a)"]),
       "insert into crash_q values (2)",
       "insert into crash_q values (3)",
       "insert into crash_q values (1)",
       "update crash_q set a=a+1",
       "drop table crash_q $drop_attr");

if ($limits{'atomic_updates'} eq 'yes')
{
  report_fail("atomic_updates_with_rollback","atomic_updates_with_rollback",
	      create_table("crash_q",["a integer not null"],
			   ["primary key (a)"]),
	      "insert into crash_q values (2)",
	      "insert into crash_q values (3)",
	      "insert into crash_q values (1)",
	      "update crash_q set a=a+1 where a < 3",
	      "drop table crash_q $drop_attr");
}

{
  $limit="views";
  my $limit  = 'views';
  my $prompt = 'Views';
  my $result = "?";
  print "$prompt: ";

  if (defined($limits{$limit}))
  {
    print "$limits{$limit} (cached)\n";
  }
  else
  {
    save_incomplete($limit,$prompt);
    
    #Ensure that based table didn't exist
    safe_query_l($limit, "drop table crash_t1");

    if (not safe_query_l($limit,["CREATE TABLE crash_t1 (id1 INTEGER, id2 INTEGER)",  
				 "CREATE VIEW crash_v1 AS SELECT id1, id2 FROM crash_t1"]))
    {
      $result='no';
    }
    elsif (not safe_query_l($limit,"CREATE VIEW crash_v2 AS SELECT id1, id2 FROM crash_t1 ORDER BY id1"))
    {
      $result='yes,without ORDER BY';
    }
    else
    {
      safe_query_l($limit,["INSERT INTO crash_t1 VALUES (3,-2)",  
   			 "INSERT INTO crash_t1 VALUES (2,-1)",
   			 "INSERT INTO crash_t1 VALUES (1,-1)",
   			 "INSERT INTO crash_t1 VALUES (0,-2)",
   			 "INSERT INTO crash_t1 VALUES (7,-1)"]);

      # SELECT from the view   
      my $rs = get_recordset($limit,"SELECT * FROM crash_v2");
      print_recordset($limit,$rs);
      
      # If the above query returns five rows ordered {0,1,2,3,7}  
      # for the first column, then announce "views work and work  
      # with ORDER BY"; else announce "views work but not with  
      # ORDER BY" and skip the rest of the test. */  
      
      if ( ($rs->[0]->[0] eq 0) and
   	 ($rs->[1]->[0] eq 1) and
   	 ($rs->[2]->[0] eq 2) and
   	 ($rs->[3]->[0] eq 3) and
   	 ($rs->[4]->[0] eq 7) ) 
      {
        $result = 'yes, with ORDER BY';
      
        # SELECT from the view again */  
        my $rs1 = get_recordset($limit,"SELECT id1, id2 FROM crash_v2 ORDER BY id2");  
        print_recordset($limit, $rs1);
      
        # If the above query returns five rows ordered {0,3,1,2,7}  
        # in the first row, then announce "merging"; otherwise if  
        # the rows are ordered {0,1,2,3,7} then announce "view  
        # overrides"; else announce "main query overrides". */  
      
        if ( ($rs1->[0]->[0] eq 0) and
             ($rs1->[1]->[0] eq 3) and
   	     ($rs1->[2]->[0] eq 1) and
   	     ($rs1->[3]->[0] eq 2) and
   	     ($rs1->[4]->[0] eq 7) ) 
        {
          $result .= ', merging';
        } 
        elsif (($rs1->[0]->[0] eq 0) and
   	    ($rs1->[1]->[0] eq 1) and
   	    ($rs1->[2]->[0] eq 2) and
   	    ($rs1->[3]->[0] eq 3) and
   	    ($rs1->[4]->[0] eq 7) ) 
        { 
          $result .= ', overrides';
        }
        else
        {
          $result .= ', main query overrides';
        }
      }
      else
      {
        $result = 'yes, without ORDER BY';
      }
    }
    # Cleanup   
    safe_query_l($limit,["DROP VIEW crash_v2 $drop_attr",
                         "DROP VIEW crash_v1 $drop_attr"]);

    save_config_data($limit,$result,$prompt);
    print "$result\n";
    
  }  # if cached
    
  if ($limits{$limit} ne 'no')
  {
    check_and_report("CREATE or REPLACE VIEW extension", 
                     "view_create_or_replace",[],
                     "create or replace view crash_v1 as select * from crash_t1",
                     ["drop view crash_v1"],"",8);
    $result1='no';
    $result2='no';
    $result3='no';

    if (defined($limits{'view_with_check_option'}) && 
        defined($limits{'view_with_local_check_option'}) &&
        defined($limits{'view_with_cascade_check_option'}))
    {
      print $limits{'view_with_check_option'}," (cached)\n";
      print $limits{'view_with_local_check_option'}," (cached)\n";
      print $limits{'view_with_cascade_check_option'}," (cached)\n";
    }
    else
    {
      save_incomplete('view_with_check_option',"CREATE VIEW ... WITH CHECK OPTION");
      if (safe_query_l("view_with_check_option",
                     ["create view crash_v1 as select id1 from crash_t1 where id1 < 2 with check option"]))
      {
        $result1= safe_query_l('view_with_check_option', 
                             ['insert into crash_v1 values (2)']) ? "syntax only" : "yes";
      }
      save_config_data('view_with_check_option',$result1,"CREATE VIEW ... WITH CHECK OPTION");      

      save_incomplete('view_with_local_check_option',
                      "CREATE VIEW ... WITH LOCAL CHECK OPTION");
      if (safe_query_l('view_with_local_check_option',
                       ["create view crash_v2 as select id1 from crash_v1 where id1 > 0 with local check option"]))
      {
        $result2= safe_query_l('view_with_local_check_option', 
                              ['insert into crash_v2 values (-2)']) ? "syntax only" : "yes";
      }
      save_config_data('view_with_local_check_option',$result2,"CREATE VIEW ... WITH LOCAL CHECK OPTION");

      save_incomplete('view_with_cascade_check_option',
                      "CREATE VIEW ... WITH CASCADE CHECK OPTION");

      if (safe_query_l('view_with_cascaded_check_option',
                      ["create view crash_v3 as select id1 from crash_v2 where id1 > 0 with cascaded check option"]))
      {
        $result3= safe_query_l('view_with_cascade_check_option', 
                               ['insert into crash_v3 values (2)']) ? "syntax only" : "yes";
      }
      save_config_data('view_with_cascade_check_option',$result3,"CREATE VIEW ... WITH CASCADE CHECK OPTION");

      safe_query_l('view_with_check_option',["drop view crash_v3",
                                             "drop view crash_v2",
                                             "drop view crash_v1"]);
    }
    
    report ("CREATE VIEW from subquery in the FROM clause", 
            "view_from_subq_in_from",
            "create view crash_v1 as select * from (select id1 from crash_t1) as crash_t2",
            "drop view crash_v1");
            
    $select_ending= $limits{'select_without_from'} eq 'yes' ? 
                    "" : "from crash_t1";

    check_and_report("CREATE VIEW from const table", 
                     "view_from_const_table", [],
                     "create view crash_v1 as select 1 $select_ending",
                     ["drop view crash_v1"],"",8);

    check_and_report("SELECT with LIMIT in VIEW definition",
                     "view_select_with_limit",[],
                     "CREATE VIEW crash_v1 AS select id1 FROM crash_t1 limit 10",
                     ["drop view crash_v1"],"",8);

    check_and_report("SELECT with LIMIT # OFFSET # in VIEW definition",
                     "view_select_with_limit_offset",[],
                     "CREATE VIEW crash_v1 AS select id1 FROM crash_t1 limit 10,5",
                     ["drop view crash_v1"],"",8);

    check_and_report("View updatability: simple view",
                     "view_upd_simple",
                     ["create view crash_v1 (id1) as select id1 from crash_t1"],
                     "update crash_v1 set id1 = 5",
                     ["drop view crash_v1"],"",8);    
    
    safe_query(["drop table crash_t11", "drop table crash_t12",
                "create table crash_t11(id integer, b integer,c char)",
                "create table crash_t12(id integer, b integer,c char)",
                "insert into crash_t11 values (1,1,'a')",
                "insert into crash_t11 values (5,10,'b')",
                "insert into crash_t12 values (2,3,'d')",
                "insert into crash_t12 values (4,6,'b')"]);

    check_and_report("View updatability: DERIVED COLUMNS IN THE SELECT LIST",
                     "view_upd_derived_columns",
                     ["create view crash_v11 as select id, b*5 as b from crash_t11"],
                     "update crash_v11 set id = 5",
                     ["drop view crash_v11"],"",8);

    report("View updatability: view based on union",
           "view_upd_union",
           "create view crash_v11 as select id from crash_t11 union select b from crash_t12",
           "update crash_v11 set t11a = 10",
           "update crash_v11 set t12b = 20",
           "update crash_v11 set t11a = 30, t12b=40",
           "drop view crash_v11");

    report("View updatability: view based on join",
           "view_upd_join",
           "create view crash_v11(t11id,t12b) as select crash_t11.id, crash_t12.b 
                                                 from crash_t11,crash_t12 
                                                 where crash_t11.c=crash_t12.c",
           "update crash_v11 set t11id = 11",
           "update crash_v11 set t12b = 21",
           "update crash_v11 set t11id = 31, t12b=41",
           "drop view crash_v11");

    if ($limit{'subquery'})
    {
      report("View updatability: view based on subquery",
             "view_upd_subquery",
             "create view crash_v11 (t12b) as select b from crash_t12 
                                              where t12a in (select t11a from crash_t11)",
             "update crash_v11 set t12b = 33",
             "drop view crash_v11");
    }

    report("drop view","drop_view",
           "create table crash_q (q integer)",
           "create view crash_v (q) as select * from crash_q",
           "drop view crash_v $drop_attr",
           "drop table crash_q $drop_attr");

    if (!report("drop view if exists","drop_view_if_exists",
                "create table crash_q (q integer)",
                "create view crash_v (q) as select q from crash_q",
                "drop view if exists crash_v $drop_attr",
                "drop table crash_q $drop_attr"))
    {
      safe_query_l("drop_view_if_exists",["drop view crash_v",
                                          "drop table crash_q $drop_attr"]);
    }

    if (!defined($limits{'drop_view_cascade'}))
    {
      #TODO: Check that drop success and crash_v2 droped 
      save_incomplete("drop_view_cascade","drop view .. cascade");
      $result='no';
      
      if (safe_query_l("drop_view_cascade",
                              ["create table crash_q (q integer)",
                              "create view crash_v1 (q) as select q from crash_q",
                              "create view crash_v2 (q) as select q from crash_v1",
                              "drop view crash_v1 cascade"]))
      {
         $result=safe_query_l("drop_view_cascade",["drop view crash_v2"]) ? "syntax only" : "yes";
      }
      save_config_data("drop_view_cascade",$result,"drop view .. cascade");
    }

    if (!defined($limits{'drop_view_restrict'}))
    {
      #TODO: Check that drop success and crash_v2 droped 
      save_incomplete("drop_view_restrict","drop view .. restrict");
      $result='no';
      
      #TODO: Check that drop fail and crash_v1 exists
      if (!safe_query_l("drop_view_restrict",
           ["create table crash_q (q integer)",
           "create view crash_v1 (q) as select q from crash_q",
           "create view crash_v2 (q) as select q from crash_v1",
           "drop view crash_v1 restrict"]))
      {
        $result="yes";
      }
      save_config_data("drop_view_restrict",$result,"drop view .. restrict");
      safe_query_l("drop_view_restrict",["drop view crash_v2",
                   "drop view crash_v1",
                   "drop table crash_q"]);
    }

    report("altering of view's definition","alter_view",
           "create table crash_q (id integer, b integer)",
           "create view crash_v1 (id,b) as select id, id+1 from crash_q",
           "alter view crash_v1 (b) as select id+3 from crash_q",
           "drop view crash_v1", "drop table crash_q");

    #TODO: Add check for correctess of results after 
    #      changing of view definition on WITH CHECK OPTION
    report("altering of view's definition: WITH CHECK OPTION",
           "alter_view_with_check_option",
           "create table crash_q (id integer)",
           "create view crash_v1 (id) as select id from crash_q",
           "alter view crash_v1 as select id from crash_q with check option",
           "drop view crash_v1", "drop table crash_q");   

    report("altering of view's definition: WITH LOCAL CHECK OPTION",
           "alter_view_with_check_option",
           "create table crash_q (id integer)",
           "create view crash_v1 (id) as select id from crash_q",
           "alter view crash_v1 as select id from crash_q with local check option",
           "drop view crash_v1", "drop table crash_q");   

    report("altering of view's definition: WITH CASCADE CHECK OPTION",
           "alter_view_with_check_option",
           "create table crash_q (id integer)",
           "create view crash_v1 (id) as select id from crash_q",
           "alter view crash_v1 as select id from crash_q with cascade check option",
           "drop view crash_v1", "drop table crash_q");

  #Clean up
  safe_query_l("views",["drop table crash_t1",
                        "drop table crash_t11",
                        "drop table crash_t12"]);    
  }
}  # test views

#partitions test 
{
  @partition_by_types=(["partition_by_range","PARTITION BY RANGE",
                        "CREATE TABLE crash_t1 (id integer not null, b char(9)) 
                          PARTITION BY RANGE (id) 
                          (PARTITION p0 VALUES LESS THAN (10),
                          PARTITION p1 VALUES LESS THAN (20))",""],
                       ["partition_by_list","PARTITION BY LIST",
                          "CREATE TABLE crash_t1 (id integer not null, b char(9)) 
                           PARTITION BY LIST (id) 
                           (PARTITION p0 VALUES IN (10,20), 
                           PARTITION p1 VALUES IN (NULL,40))",""],
                       ["partition_by_hash","PARTITION BY HASH",
                          "CREATE TABLE crash_t1 (id integer not null, b char(9)) 
                           PARTITION BY HASH (id) PARTITIONS 2",""],
                       ["partition_by_key","PARTITION BY KEY",
                          "CREATE TABLE crash_t1 (id integer not null, b char(9)) 
                           PARTITION BY KEY (id) PARTITIONS 2",""]);

  @partition_by_range_tests=(["partition_by_range_maxvalue",
                              "PARTITION BY RANGE with MAXVALUE",
                              "CREATE TABLE crash_t1 (id integer not null, b char(9))
                                PARTITION BY RANGE (id)
                                 (PARTITION p0 VALUES LESS THAN (10),
                                  PARTITION p1 VALUES LESS THAN MAXVALUE)",
                              "partition_by_range"],
                             ["partition_by_range_expressions",
                              "PARTITION BY RANGE with EXPRESSIONS",
                              "CREATE TABLE crash_t1 (id integer not null, b char(9))
                                PARTITION BY RANGE (id)
                                 (PARTITION p0 VALUES LESS THAN (10+2),
                                  PARTITION p1 VALUES LESS THAN (20))",
                              "partition_by_range"]);

  @partition_by_list_tests=(["partition_by_list_expressions",
                               "PARTITION BY LIST with EXPRESSIONS",
                               "CREATE TABLE crash_t1 (id integer not null, b char(9))
                                PARTITION BY LIST (id)
                                (PARTITION p0 VALUES IN (10+2, 20),
                                 PARTITION p1 VALUES IN (NULL,40))",
                              "partition_by_list"]);

  @partition_by_hash_tests=(["partition_by_hash_expressions",
                               "PARTITION BY HASH with EXPRESSIONS",
                                "CREATE TABLE crash_t1 (id integer not null, b integer)
                                 PARTITION BY HASH (id+0) PARTITIONS 2",
                              "partition_by_hash"],
                              ["partition_by_hash_linear",
                               "PARTITION BY LINEAR HASH",
                               "CREATE TABLE crash_t1 (id integer not null, b integer)
                                PARTITION BY LINEAR HASH (id) PARTITIONS 2",
                               "partition_by_hash"],
                              ["partition_by_hash_expressions",
                               "PARTITION BY HASH adn UNIQUE KEY",
                               "CREATE TABLE crash_t1 (id integer not null, b integer, unique (id,b)
                                PARTITION BY HASH (id) PARTITIONS 2",
                                 "partition_by_hash"]);

  @partition_by_key_tests=(["partition_by_key_linear",
                              "PARTITION BY LINEAR KEY",
                              "CREATE TABLE crash_t1 (id integer not null, b integer)
                               PARTITION BY LINEAR KEY (id) PARTITIONS 2",
                               "partition_by_key"],
                             ["partition_by_key_zero_columns_primary",
                              "PARTITION BY KEY without column uses PRIMARY KEY",
                              "CREATE TABLE crash_t1 (id integer not null, b integer, primary key a,
                               PARTITION BY KEY () PARTITIONS 2",
                               "partition_by_key"],
                             ["partition_by_key_zero_columns_unique",
                              "PARTITION BY KEY without column uses UNIQUE KEY",
                              "CREATE TABLE crash_t1 (id integer not null, b integer, UNIQUE(id)
                               PARTITION BY KEY () PARTITIONS 2",
                               "partition_by_key"]);



  @subpartitions_tests=(["partition_by_range_subpart_by_hash",
                         "PARTITION BY RANGE SUBPARTIONED BY HASH",
                         "CREATE TABLE crash_t1 (id integer not null, b integer)
                          PARTITION BY RANGE(id)
                           SUBPARTITION BY HASH(b)
                             SUBPARTITIONS 2 (
                               PARTITION p0 VALUES LESS THAN (10),
                               PARTITION p1 VALUES LESS THAN (100))"],
                        ["partition_by_range_subpart_by_key",
                         "PARTITION BY RANGE SUBPARTIONED BY KEY",
                         "CREATE TABLE crash_t1 (id integer not null, b integer)
                          PARTITION BY RANGE( id )
                           SUBPARTITION BY KEY( b )
                             SUBPARTITIONS 2 (
                               PARTITION p0 VALUES LESS THAN (10),
                               PARTITION p1 VALUES LESS THAN (30))"],
                        ["partition_by_list_subpart_by_hash",
                         "PARTITION BY LIST SUBPARTIONED BY HASH",
                         "CREATE TABLE crash_t1 (id integer not null, b integer)
                           PARTITION BY LIST( id )
                            SUBPARTITION BY HASH( b )
                              SUBPARTITIONS 2 (
                              PARTITION p0 VALUES IN (10),
                              PARTITION p1 VALUES IN (100))"],
                        ["partition_by_list_subpart_by_key",
                         "PARTITION BY LIST SUBPARTIONED BY KEY",
                         "CREATE TABLE crash_t1 (id integer not null, b integer)
                          PARTITION BY LIST( id )
                           SUBPARTITION BY KEY( b )
                             SUBPARTITIONS 2 (
                             PARTITION p0 VALUES IN (10),
                             PARTITION p1 VALUES IN (100))"]);

  my $drop_stmt="drop table ". 
                ($limits{drop_if_exists} eq 'yes' ? "if exists " : '').
                "crash_t1";

  @partition_tests=(@partition_by_types, @partition_by_range_tests, 
                    @partition_by_list_tests, @partition_by_hash_tests);

  foreach my $partition_test (@partition_tests)
  {
     my $key=@{$partition_test}[3];
     my $limit=@{$partition_test}[0];        
     my $prompt=@{$partition_test}[1];
     my $query=@{$partition_test}[2];

     if ($key eq '' || ($key ne '' && $limits{$key} eq 'yes'))
     {
       check_and_report($prompt, $limit, [$drop_stmt], $query, 
                        [$drop_stmt], "",8);
     }
   }

  foreach my $subpartitions_test (@subpartitions_tests)
  {
     my $limit=@{$subpartitions_test}[0];
     my $prompt=@{$subpartitions_test}[1];
     my $query=@{$subpartitions_test}[2];

     check_and_report($prompt, $limit, [$drop_stmt], $query, 
                        [$drop_stmt], "",8);
  }

  if (!report_fail("Subpartition names unicity across table",
                   "partition_subpart_name_unicity",
                   "CREATE TABLE crash_t1 (id integer, b int)
                      PARTITION BY RANGE( id )
                       SUBPARTITION BY HASH( b ) (
                        PARTITION p0 VALUES LESS THAN (1990) (
                         SUBPARTITION s0,
                         SUBPARTITION s1),
                      PARTITION p1 VALUES LESS THAN (2000),
                        PARTITION p2 VALUES LESS THAN MAXVALUE (
                         SUBPARTITION s0,
                         SUBPARTITION s1))"))
  {
    assert("drop table crash_t1");
  }

  if (report("Different number of subpartitions across table",
                   "partition_subpart_different_number",
                   "CREATE TABLE crash_t1 (id integer, b integer)
                      PARTITION BY RANGE( id )
                       SUBPARTITION BY HASH( b ) (
                        PARTITION p0 VALUES LESS THAN (1990) (
                          SUBPARTITION s0,
                          SUBPARTITION s1),
                        PARTITION p1 VALUES LESS THAN (2000),
                        PARTITION p2 VALUES LESS THAN MAXVALUE (
                          SUBPARTITION s2,
                          SUBPARTITION s3,
                          SUBPARTITION s4))"))
  {
    assert("drop table crash_t1");
  }

  assert("CREATE TABLE crash_t1 (id integer not null)");
  assert("CREATE TABLE crash_t2 (id integer not null)");

  if ($limits{'partition_by_range'} || $limits{'partition_by_list'})
  {
    my ($part_by,$condition);
    if ($limits{'partition_by_range'})
    {
      $part_by="RANGE";
      $condition="LESS THAN";
    }
    else
    {
      $part_by="LIST";
      $condition="IN";
    }
   
    report("ALTER ... PARTITION BY syntax for RANGE and LIST",
           "alter_partition_by_for_range_list",
           "ALTER TABLE crash_t1 PARTITION BY $part_by (id) 
                       (PARTITION p0 VALUES $condition (10),
                        PARTITION p1 VALUES $condition (20))");

    report("ALTER ... ADD PARTITION syntax for RANGE and LIST",
           "alter_add_partition_for_range_list",
           "ALTER TABLE crash_t1 ADD PARTITION (partition p2 VALUES $condition (30))");

    report("ALTER ... DROP PARTITION  syntax",
           "alter_drop_partition",
           "ALTER TABLE crash_t1 DROP PARTITION p2"); 

    report("ALTER ... REORGANIZE PARTITION  syntax",
           "alter_reorganize_partition",
           "ALTER TABLE crash_t1 REORGANIZE PARTITION p0,p1 INTO 
              ( PARTITION m0 VALUES $condition (1500),
                PARTITION m1 VALUES $condition (15000))"); 
  }

  if ($limits{'partition_by_hash'} || $limits{'partition_by_key'})
  {
    my $part_by;
    if ($limits{'partition_by_hash'})
    {
      $part_by="hash";
    }
    else
    {
      $part_by="key";
    }
    report("ALTER ... PARTITION BY syntax for HASH and KEY",
           "alter_partition_by_for_hash_key",
           "ALTER TABLE crash_t2 PARTITION BY $part_by (id) PARTITIONS 2");

    report("ALTER ... ADD PARTITION syntax for HASH and KEY",
           "alter_add_partition_for_hash_key",
           "ALTER TABLE crash_t2 ADD PARTITION PARTITIONS 4");
   
    report("ALTER ... COALESCE PARTITION syntax",
           "alter_coalese_partition",
           "ALTER TABLE crash_t2 COALESCE PARTITION 1"); 
  }

  assert("drop table crash_t1");
  assert("drop table crash_t2") ;
}  # partition tests

#  Test: foreign key
{
 my $result = 'undefined';
 my $error;
 print "foreign keys: ";
 save_incomplete('foreign_key','foreign keys');

# 1) check if foreign keys are supported
 safe_query_l('foreign_key',
	      create_table("crash_me_qf",
			   ["a integer not null"],
			   ["primary key (a)"]));
 $error= safe_query_l('foreign_key',
		      create_table("crash_me_qf2",
				   ["a integer not null",
				    "foreign key (a) references crash_me_qf (a)"],
				   ["index (a)"]));

 if ($error == 1)         # OK  -- syntax is supported 
 {
   $result = 'error';
   # now check if foreign key really works
   safe_query_l('foreign_key', "insert into crash_me_qf values (1)");
   if (safe_query_l('foreign_key', "insert into crash_me_qf2 values (2)") eq 1)
   {
     $result = 'syntax only';
   }
   else
   {
     $result = 'yes';
   }
 }
 else
 {
   $result = "no";
 }
 safe_query_l('foreign_key', "drop table crash_me_qf2 $drop_attr");
 safe_query_l('foreign_key', "drop table crash_me_qf $drop_attr");
 print "$result\n";
 save_config_data('foreign_key',$result,"foreign keys");
}

if ($limits{'foreign_key'} eq 'yes')
{
  report("allows to update of foreign key values",'foreign_update',
   create_table("crash_me1",["a int not null"],["primary key (a)"]),
   create_table("crash_me2",
       ["a int not null","foreign key (a) references crash_me1 (a)"],
       ["index (a)"]),
   "insert into crash_me1 values (1)",
   "insert into crash_me2 values (1)",
   "update crash_me1 set a = 2",       ## <- must fail 
   "drop table crash_me2 $drop_attr", 
   "drop table crash_me1 $drop_attr" 
  );

  # check if foreign key requires explicit indexes; We
  # do the sane as in FK check, but without indexes
  my $key = 'fk_req_explicit_index';
  my $prompt = 'foreign keys require explicit indexes';
  print $prompt,": ";
  if (! defined($limits{$key}) )
  {
     add_log($key,' When we tested FK, we created tables with explicit indexes.');
     add_log($key,' Now we repeat that test but tables will be created without indexes.');
     save_incomplete($key,$prompt);
     safe_query_l($key,
	      create_table("crash_me_qf",
			   ["a integer not null"]));
     unless  ( safe_query_l($key,
		      create_table("crash_me_qf2",
				   ["a integer not null",
				    "foreign key (a) references crash_me_qf (a)"]))) {
        # we even cannot create second table. No need to test more..				    
	$result = 'yes';			    
     }  
     else 
     {

       $result = 'error';
       # now check if foreign key really works
       safe_query_l($key, "insert into crash_me_qf values (1)");
       if (safe_query_l($key, "insert into crash_me_qf2 values (2)") eq 1)
       {
         $result = 'yes'; # DBMS allowed us to insert illegal value.
         # it means explicit indexes is required.
       }
       else
       {
         $result = 'no';
       }
       safe_query_l($key, "drop table crash_me_qf2 $drop_attr");
    }
     safe_query_l($key, "drop table crash_me_qf $drop_attr");

     save_config_data($key,$result,$prompt);
  } else {
     print $limits{$key}, "(cached)\n";
  }
}


report("Create SCHEMA","create_schema",
       "create schema crash_schema create table crash_q (a int) ".
       "create table crash_q2(b int)",
       "drop schema crash_schema cascade");

if ($limits{'foreign_key'} eq 'yes')
{
  if ($limits{'create_schema'} eq 'yes')
  {
    report("Circular foreign keys","foreign_key_circular",
           "create schema crash_schema create table crash_q ".
	   "(a int primary key, b int, foreign key (b) references ".
	   "crash_q2(a)) create table crash_q2(a int, b int, ".
	   "primary key(a), foreign key (b) references crash_q(a))",
           "drop schema crash_schema cascade");
  }
}

if ($limits{'func_sql_character_length'} eq 'yes')
{
  my $result = 'error';
  my ($resultset);
  my $key = 'length_of_varchar_field';
  my $prompt='CHARACTER_LENGTH(varchar_field)';
  print $prompt," = ";
  if (!defined($limits{$key})) {
    save_incomplete($key,$prompt);
    safe_query_l($key,[
		       "CREATE TABLE crash_me1 (S1 VARCHAR(100))",
		       "INSERT INTO crash_me1 VALUES ('X')"
		       ]);
    my $recset = get_recordset($key,
			       "SELECT CHARACTER_LENGTH(S1) FROM crash_me1");
    print_recordset($key,$recset);
    if (defined($recset)){
      if ( $recset->[0][0] eq 1 ) {
		$result = 'actual length';
	      } elsif( $recset->[0][0] eq 100 ) {
		$result = 'defined length';
	      };
    } else {
      add_log($key,$DBI::errstr);
    }
    safe_query_l($key, "drop table crash_me1 $drop_attr");
    save_config_data($key,$result,$prompt);
  } else {
    $result = $limits{$key};
  };
  print "$result\n";
}


check_constraint("CHECK column constraint","column_CHECK_constraint_test",
           "create table crash_q (a int check (a>0))",
           "insert into crash_q values(0)",
           "drop table crash_q $drop_attr");


check_constraint("CHECK table constraint","table_CHECK_constraint_test",
       "create table crash_q (a int, b int, check (a>b))",
       "insert into crash_q values(0,0)",
       "drop table crash_q $drop_attr");

report("Named column constraint","named_column_constraint_test",
       "create table crash_q (a int constraint acheck check (a>0), b int)",
       "drop table crash_q $drop_attr");


report("Named table constraint","named_table_constraint_test",
       "create table crash_q (a int, b int, constraint abc check (a>b))",
       "drop table crash_q $drop_attr");


check_constraint("NOT NULL column constraint","column_NOT_NULL_constraint_test",
       "create table crash_q (a int not null)",
       "insert into crash_q values(null)",
       "drop table crash_q $drop_attr");

check_constraint("NOT NULL table constraint","table_NOT_NULL_constraint_test",
       "create table crash_q (a int, b int, check (a is not null))",
       "insert into crash_q values(null,0)",
       "drop table crash_q $drop_attr");

check_constraint("NULL constraint (Sybase style)","NULL_constraint_test",
       "create table crash_q (a int null)",
       "insert into crash_q values(null)",
       "drop table crash_q $drop_attr");



report("Triggers (ANSI SQL)","psm_trigger",
       "create table crash_q (a int ,b int)",
       "create trigger crash_trigger after insert on crash_q referencing ".
       "new table as new_a when (localtime > time '18:00:00') ".
       "begin atomic end",
       "insert into crash_q values(1,2)",
       "drop trigger crash_trigger",
       "drop table crash_q $drop_attr");

report("PSM procedures (ANSI SQL)","psm_procedures",
       "create table crash_q (a int,b int)",
       "create procedure crash_proc(in a1 int, in b1 int) language ".
       "sql modifies sql data begin declare c1 int; set c1 = a1 + b1;".
       " insert into crash_q(a,b) values (a1,c1); end",
       "call crash_proc(1,10)",
       "drop procedure crash_proc",
       "drop table crash_q $drop_attr");

report("PSM modules (ANSI SQL)","psm_modules",
       "create table crash_q (a int,b int)",
       "create module crash_m declare procedure ".
         "crash_proc(in a1 int, in b1 int) language sql modifies sql ".
         "data begin declare c1 int; set c1 = a1 + b1; ".
         "insert into crash_q(a,b) values (a1,c1); end; ".
         "declare procedure crash_proc2(INOUT a int, in b int) ".
         "contains sql set a = b + 10; end module",
       "call crash_proc(1,10)",
       "drop module crash_m cascade",
       "drop table crash_q cascade $drop_attr");

report("PSM functions (ANSI SQL)","psm_functions",
       "create table crash_q (a int)",
       "create function crash_func(in a1 int, in b1 int) returns int".
         " language sql deterministic contains sql ".
	 " begin return a1 * b1; end",
       "insert into crash_q values(crash_func(2,4))",
       "select a,crash_func(a,2) from crash_q",
       "drop function crash_func cascade",
       "drop table crash_q $drop_attr");

report("Domains (ANSI SQL)","domains",
       "create domain crash_d as varchar(10) default 'Empty' ".
         "check (value <> 'abcd')",
       "create table crash_q(a crash_d, b int)",
       "insert into crash_q(a,b) values('xyz',10)",
       "insert into crash_q(b) values(10)",
       "drop table crash_q $drop_attr",
       "drop domain crash_d");


if (!defined($limits{'lock_tables'}))
{
  report("lock table","lock_tables",
	 "lock table crash_me READ",
	 "unlock tables");
  if ($limits{'lock_tables'} eq 'no')
  {
    delete $limits{'lock_tables'};
    report("lock table","lock_tables",
	   "lock table crash_me IN SHARE MODE");
  }
}

if (!report("many tables to drop table","multi_drop",
	   "create table crash_q (a int)",
	   "create table crash_q2 (a int)",
	   "drop table crash_q,crash_q2 $drop_attr"))
{
  $dbh->do("drop table crash_q $drop_attr");
  $dbh->do("drop table crash_q2 $drop_attr");
}

if (!report("drop table with cascade/restrict","drop_restrict",
	   "create table crash_q (a int)",
	   "drop table crash_q restrict"))
{
  $dbh->do("drop table crash_q $drop_attr");
}


report("-- as comment (ANSI)","comment_--",
       "select * from crash_me -- Testing of comments");

if ($limits{'comment_--'}  eq 'yes')
{
  report_fail('after -- space is required','space_after_--',
       "select * from crash_me --Testing of comments");
}      

report("// as comment","comment_//",
       "select * from crash_me // Testing of comments");
report("# as comment","comment_#",
       "select * from crash_me # Testing of comments");
report("/* */ as comment","comment_/**/",
       "select * from crash_me /* Testing of comments */");

#
# Check things that fails one some servers
#

# Empress can't insert empty strings in a char() field
report("insert empty string","insert_empty_string",
       create_table("crash_q",["a char(10) not null,b char(10)"],[]),
       "insert into crash_q values ('','')",
       "drop table crash_q $drop_attr");

report("Having with alias","having_with_alias",
       create_table("crash_q",["a integer"],[]),
       "insert into crash_q values (10)",
       "select sum(a) as b from crash_q group by a having b > 0",
       "drop table crash_q $drop_attr");

#
# test name limits
#

find_limit("table name length","max_table_name",
	   new query_many(["create table crash_q%s (q integer)",
			   "insert into crash_q%s values(1)"],
			   "select * from crash_q%s",1,
			   ["drop table crash_q%s $drop_attr"],
			   $max_name_length,7,1));

find_limit("column name length","max_column_name",
	   new query_many(["create table crash_q (q%s integer)",
			  "insert into crash_q (q%s) values(1)"],
			  "select q%s from crash_q",1,
			  ["drop table crash_q $drop_attr"],
			   $max_name_length,1));

if ($limits{'column_alias'} eq 'yes')
{
  find_limit("select alias name length","max_select_alias_name",
	   new query_many(undef,
			  "select b as %s from crash_me",undef,
			  undef, $max_name_length));
}

find_limit("table alias name length","max_table_alias_name",
	   new query_many(undef,
			  "select %s.b from crash_me %s",
			  undef,
			  undef, $max_name_length));

$end_drop_keyword = "drop index %i" if (!$end_drop_keyword);
$end_drop=$end_drop_keyword;
$end_drop =~ s/%i/crash_q%s/;
$end_drop =~ s/%t/crash_me/;

if ($limits{'create_index'} ne 'no')
{
  find_limit("index name length","max_index_name",
	     new query_many(["create index crash_q%s on crash_me (a)"],
			    undef,undef,
			    [$end_drop],
			    $max_name_length,7));
}

find_limit("max char() size","max_char_size",
	   new query_many(["create table crash_q (q char(%d))",
			   "insert into crash_q values ('%s')"],
			  "select * from crash_q","%s",
			  ["drop table crash_q $drop_attr"],
			  min($max_string_size,$limits{'query_size'})));

if ($limits{'type_sql_varchar(1_arg)'} eq 'yes')
{
  find_limit("max varchar() size","max_varchar_size",
	     new query_many(["create table crash_q (q varchar(%d))",
			     "insert into crash_q values ('%s')"],
			    "select * from crash_q","%s",
			    ["drop table crash_q $drop_attr"],
			    min($max_string_size,$limits{'query_size'})));
}

$found=undef;
foreach $type (('mediumtext','text','text()','blob','long'))
{
  if ($limits{"type_extra_$type"} eq 'yes')
  {
    $found=$type;
    last;
  }
}
if (defined($found))
{
  $found =~ s/\(\)/\(%d\)/;
  find_limit("max text or blob size","max_text_size",
	     new query_many(["create table crash_q (q $found)",
			     "insert into crash_q values ('%s')"],
			    "select * from crash_q","%s",
			    ["drop table crash_q $drop_attr"],
			    min($max_string_size,$limits{'query_size'}-30)));

}

$tmp=new query_repeat([],"create table crash_q (a integer","","",
		      ",a%d integer","",")",["drop table crash_q $drop_attr"],
		      $max_columns);
$tmp->{'offset'}=1;
find_limit("Columns in table","max_columns",$tmp);

# Make a field definition to be used when testing keys

$key_definitions="q0 integer not null";
$key_fields="q0";
for ($i=1; $i < min($limits{'max_columns'},$max_keys) ; $i++)
{
  $key_definitions.=",q$i integer not null";
  $key_fields.=",q$i";
}
$key_values="1," x $i;
chop($key_values);

if ($limits{'unique_in_create'} eq 'yes')
{
  find_limit("unique indexes","max_unique_index",
	     new query_table("create table crash_q (q integer",
			     ",q%d integer not null,unique (q%d)",")",
			     ["insert into crash_q (q,%f) values (1,%v)"],
			     "select q from crash_q",1,
			     "drop table crash_q $drop_attr",
			     $max_keys,0));

  find_limit("index parts","max_index_parts",
	     new query_table("create table crash_q ".
	         "($key_definitions,unique (q0",
			     ",q%d","))",
 	     ["insert into crash_q ($key_fields) values ($key_values)"],
	     "select q0 from crash_q",1,
	     "drop table crash_q $drop_attr",
	     $max_keys,1));

  find_limit("max index part length","max_index_part_length",
	     new query_many(["create table crash_q (q char(%d) not null,".
	           "unique(q))",
		     "insert into crash_q (q) values ('%s')"],
		    "select q from crash_q","%s",
		    ["drop table crash_q $drop_attr"],
		    $limits{'max_char_size'},0));

  if ($limits{'type_sql_varchar(1_arg)'} eq 'yes')
  {
    find_limit("index varchar part length","max_index_varchar_part_length",
	     new query_many(["create table crash_q (q varchar(%d) not null,".
	                "unique(q))",
			 "insert into crash_q (q) values ('%s')"],
			"select q from crash_q","%s",
			["drop table crash_q $drop_attr"],
			$limits{'max_varchar_size'},0));
  }
}


if ($limits{'create_index'} ne 'no')
{
  if ($limits{'create_index'} eq 'ignored' ||
      $limits{'unique_in_create'} eq 'yes')
  {                                     # This should be true
    add_log('max_index',
     " max_unique_index=$limits{'max_unique_index'} ,".
     "so max_index must be same");
    save_config_data('max_index',$limits{'max_unique_index'},"max index");
    print "indexes: $limits{'max_index'}\n";
  }
  else
  {
    if (!defined($limits{'max_index'}))
    {
      safe_query_l('max_index',"create table crash_q ($key_definitions)");
      for ($i=1; $i <= min($limits{'max_columns'},$max_keys) ; $i++)
      {
	last if (!safe_query_l('max_index',
	     "create index crash_q$i on crash_q (q$i)"));
      }
      save_config_data('max_index',$i == $max_keys ? $max_keys : $i,
		       "max index");
      while ( --$i > 0)
      {
	$end_drop=$end_drop_keyword;
	$end_drop =~ s/%i/crash_q$i/;
	$end_drop =~ s/%t/crash_q/;
	assert($end_drop);
      }
      assert("drop table crash_q $drop_attr");
    }
    print "indexs: $limits{'max_index'}\n";
    if (!defined($limits{'max_unique_index'}))
    {
      safe_query_l('max_unique_index',
           "create table crash_q ($key_definitions)");
      for ($i=0; $i < min($limits{'max_columns'},$max_keys) ; $i++)
      {
	last if (!safe_query_l('max_unique_index',
	    "create unique index crash_q$i on crash_q (q$i)"));
      }
      save_config_data('max_unique_index',$i == $max_keys ? $max_keys : $i,
		       "max unique index");
      while ( --$i >= 0)
      {
	$end_drop=$end_drop_keyword;
	$end_drop =~ s/%i/crash_q$i/;
	$end_drop =~ s/%t/crash_q/;
	assert($end_drop);
      }
      assert("drop table crash_q $drop_attr");
    }
    print "unique indexes: $limits{'max_unique_index'}\n";
    if (!defined($limits{'max_index_parts'}))
    {
      safe_query_l('max_index_parts',
            "create table crash_q ($key_definitions)");
      $end_drop=$end_drop_keyword;
      $end_drop =~ s/%i/crash_q1%d/;
      $end_drop =~ s/%t/crash_q/;
      find_limit("index parts","max_index_parts",
		 new query_table("create index crash_q1%d on crash_q (q0",
				 ",q%d",")",
				 [],
				 undef,undef,
				 $end_drop,
				 $max_keys,1));
      assert("drop table crash_q $drop_attr");
    }
    else
    {
      print "index parts: $limits{'max_index_parts'}\n";
    }
    $end_drop=$end_drop_keyword;
    $end_drop =~ s/%i/crash_q2%d/;
    $end_drop =~ s/%t/crash_me/;

    find_limit("index part length","max_index_part_length",
	       new query_many(["create table crash_q (q char(%d))",
			       "create index crash_q2%d on crash_q (q)",
			       "insert into crash_q values('%s')"],
			      "select q from crash_q",
			      "%s",
			      [ $end_drop,
			       "drop table crash_q $drop_attr"],
			      min($limits{'max_char_size'},"+8192")));
  }
}

find_limit("index length","max_index_length",
	   new query_index_length("create table crash_q ",
				  "drop table crash_q $drop_attr",
				  $max_key_length));

find_limit("max table row length (without blobs)","max_row_length",
	   new query_row_length("crash_q ",
				"not null",
				"drop table crash_q $drop_attr",
				min($max_row_length,
				    $limits{'max_columns'}*
				    min($limits{'max_char_size'},255))));

find_limit("table row length with nulls (without blobs)",
	   "max_row_length_with_null",
	   new query_row_length("crash_q ",
				"",
				"drop table crash_q $drop_attr",
				$limits{'max_row_length'}*2));

find_limit("number of columns in order by","columns_in_order_by",
	   new query_many(["create table crash_q (%F)",
			   "insert into crash_q values(%v)",
			   "insert into crash_q values(%v)"],
			  "select * from crash_q order by %f",
			  undef(),
			  ["drop table crash_q $drop_attr"],
			  $max_order_by));

find_limit("number of columns in group by","columns_in_group_by",
	   new query_many(["create table crash_q (%F)",
			   "insert into crash_q values(%v)",
			   "insert into crash_q values(%v)"],
			  "select %f from crash_q group by %f",
			  undef(),
			  ["drop table crash_q $drop_attr"],
			  $max_order_by));




#-- E031-01 "Delimited identifiers"
report_fail("Delimited identifiers","delimited_identifiers",
'CREATE TABLE "crashme_e031_01" ("s2" INT)',
'SELECT * FROM CRASHME_E031_01 WHERE S2 = 5',
'drop table "crashme_e031_01"');
#/* Pass if: error return */

# Safe arithmetic test

$prompt="safe decimal arithmetic";
$key="safe_decimal_arithmetic";
if (!defined($limits{$key}))
{
   print "$prompt=";
   save_incomplete($key,$prompt);	
   if (!safe_query_l($key,$server->create("crash_me_a",
         ["a decimal(10,2)","b decimal(10,2)"]))) 
   {
     #print DBI->errstr();
     #die "Can't create table 'crash_me_a' $DBI::errstr\n";
     add_log($key,
             "Can't create table 'crash_me_a' $DBI::errstr\n");
   }
   
   if (!safe_query_l($key,
       ["insert into crash_me_a (a,b) values (11.4,18.9)"]))
   {
      #die "Can't insert into table 'crash_me_a' a  record: $DBI::errstr\n";
      add_log($key,
             "Can't insert into table 'crash_me_a' a  record: $DBI::errstr\n");
   }
     
   $arithmetic_safe = 'no'; 
   $arithmetic_safe = 'yes' 
   if ( (safe_query_result_l($key,
            'select count(*) from crash_me_a where a+b=30.3',1,0) == 0) 
      and (safe_query_result_l($key,
            'select count(*) from crash_me_a where a+b-30.3 = 0',1,0) == 0)  
      and (safe_query_result_l($key,
            'select count(*) from crash_me_a where a+b-30.3 < 0',0,0) == 0)
      and (safe_query_result_l($key,
            'select count(*) from crash_me_a where a+b-30.3 > 0',0,0) == 0));
   save_config_data($key,$arithmetic_safe,$prompt);
   print "$arithmetic_safe\n";
   assert("drop table crash_me_a $drop_attr");
}
 else
{
  print "$prompt=$limits{$key} (cached)\n";
}

# Check where is null values in sorted recordset
if (!safe_query($server->create("crash_me_n",["i integer","r integer"]))) 
{
  #print DBI->errstr();
  #die "Can't create table 'crash_me_n' $DBI::errstr\n";
  add_log("position_of_null",
          "Can't create table 'crash_me_n' $DBI::errstr\n");
}
 
safe_query_l("position_of_null",["insert into crash_me_n (i) values(1)",
"insert into crash_me_n values(2,2)",
"insert into crash_me_n values(3,3)",
"insert into crash_me_n values(4,4)",
"insert into crash_me_n (i) values(5)"]);

$key = "position_of_null";
$prompt ="Where is null values in sorted recordset";
if (!defined($limits{$key}))
{
 my $limit='error';
 save_incomplete($key,$prompt);	
 print "$prompt=";
 $sth=$dbh->prepare("select r from crash_me_n order by r ");
 $sth->execute;
 add_log($key,"< select r from crash_me_n order by r ");
 $limit_asc= detect_null_position($key,$sth);
 $sth->finish;

 $sth=$dbh->prepare("select r from crash_me_n order by r desc");
 $sth->execute;
 add_log($key,"< select r from crash_me_n order by r  desc");
 $limit_desc = detect_null_position($key,$sth);
 $sth->finish;
 
 $limit = 'first' if ( ($limit_asc eq "first") and ($limit_desc eq "first") );
 $limit = 'last'  if ( ($limit_asc eq "last") and ($limit_desc eq "last") );
 $limit = 'greatest' if ( ($limit_asc eq "last") and ($limit_desc eq "first") );
 $limit = 'least' if ( ($limit_asc eq "first") and ($limit_desc eq "last") );
 
 print "$limit\n";
 save_config_data($key,$limit,$prompt);
} else {
  print "$prompt=$limits{$key} (cache)\n";
}


assert("drop table  crash_me_n $drop_attr");



$key = 'sorted_group_by';
$prompt = 'Group by always sorted';
if (!defined($limits{$key}))
{
 save_incomplete($key,$prompt);
 print "$prompt=";
 safe_query_l($key,[  
			 "create table crash_me_t1 (a int not null, b int not null)",
			 "insert into crash_me_t1 values (1,1)",
			 "insert into crash_me_t1 values (1,2)",
			 "insert into crash_me_t1 values (3,1)",
			 "insert into crash_me_t1 values (3,2)",
			 "insert into crash_me_t1 values (2,2)",
			 "insert into crash_me_t1 values (2,1)",
			 "create table crash_me_t2 (a int not null, b int not null)",
			 "create index crash_me_t2_ind on crash_me_t2 (a)",
			 "insert into crash_me_t2 values (1,3)",
			 "insert into crash_me_t2 values (3,1)",
			 "insert into crash_me_t2 values (2,2)",
			 "insert into crash_me_t2 values (1,1)"]);

 my $bigqry = "select crash_me_t1.a,crash_me_t2.b from ".
	     "crash_me_t1,crash_me_t2 where crash_me_t1.a=crash_me_t2.a ".
	     "group by crash_me_t1.a,crash_me_t2.b";

 my $limit='no';
 my $rs = get_recordset($key,$bigqry);
 print_recordset($key,$rs); 
 if ( defined ($rs)) { 
   if (compare_recordset($key,$rs,[[1,1],[1,3],[2,2],[3,1]]) eq 0)
   {
     $limit='yes'
   }
 } else {
  add_log($key,"error: ".$DBI::errstr);
 } 

 print "$limit\n";
 safe_query_l($key,["drop table crash_me_t1",
		       "drop table crash_me_t2"]);
 save_config_data($key,$limit,$prompt);	        
 
} else {
 print "$prompt=$limits{$key} (cashed)\n";
}


#
# End of test
#

$dbh->do("drop table crash_me $drop_attr");        # Remove temporary table

print "crash-me safe: $limits{'crash_me_safe'}\n";
print "reconnected $reconnect_count times\n";

$dbh->disconnect || warn $dbh->errstr;
save_all_config_data();
exit 0;

# End of test
#

$dbh->do("drop table crash_me $drop_attr");        # Remove temporary table

print "crash-me safe: $limits{'crash_me_safe'}\n";
print "reconnected $reconnect_count times\n";

$dbh->disconnect || warn $dbh->errstr;
save_all_config_data();
exit 0;

# Check where is nulls in the sorted result (for)
# it expects exactly 5 rows in the result

sub detect_null_position
{
  my $key = shift;
  my $sth = shift;
  my ($z,$r1,$r2,$r3,$r4,$r5);
 $r1 = $sth->fetchrow_array; add_log($key,"> $r1");
 $r2 = $sth->fetchrow_array; add_log($key,"> $r2");
 $r3 = $sth->fetchrow_array; add_log($key,"> $r3");
 $r4 = $sth->fetchrow_array; add_log($key,"> $r4");
 $r5 = $sth->fetchrow_array; add_log($key,"> $r5");
 return "first" if ( !defined($r1) && !defined($r2) && defined($r3));
 return "last" if ( !defined($r5) && !defined($r4) && defined($r3));
 return "random";
}

sub check_parenthesis {
 my $prefix=shift;
 my $fn=shift;
 my $result='no';
 my $param_name=$prefix.lc($fn);
 my $r;
 
 save_incomplete($param_name,$fn);
 $r = safe_query("select $fn $end_query"); 
 add_log($param_name,$safe_query_log);
 if ($r == 1)
  {
    $result="yes";
  } 
  else{
   $r = safe_query("select $fn() $end_query");
   add_log($param_name,$safe_query_log);
   if ( $r  == 1)   
    {
       $result="needs_parentheses";
    }
  }

  save_config_data($param_name,$result,$fn);
}

sub check_constraint {
 my $prompt = shift;
 my $key = shift;
 my $create = shift;
 my $check = shift;
 my $drop = shift;
 save_incomplete($key,$prompt);
 print "$prompt=";
 my $res = 'no';
 my $t;
 $t=safe_query($create);
 add_log($key,$safe_query_log);
 if ( $t == 1)
 {
   $res='yes';
   $t= safe_query($check);
   add_log($key,$safe_query_log);
   if ($t == 1)
   {
     $res='syntax only';
   }
 }        
 safe_query($drop);
 add_log($key,$safe_query_log);
 
 save_config_data($key,$res,$prompt);
 print "$res\n";
}

sub make_time_r {
  my $hour=shift;
  my $minute=shift;
  my $second=shift;
  $_ = $limits{'time_format_inresult'};
  return sprintf "%02d:%02d:%02d", ($hour%24),$minute,$second if (/^iso$/);
  return sprintf "%02d.%02d.%02d", ($hour%24),$minute,$second if (/^euro/);
  return sprintf "%02d:%02d %s", 
        ($hour >= 13? ($hour-12) : $hour),$minute,($hour >=13 ? 'PM':'AM') 
	                if (/^usa/);
  return sprintf "%02d%02d%02d", ($hour%24),$minute,$second if (/^HHMMSS/);
  return sprintf "%04d%02d%02d", ($hour%24),$minute,$second if (/^HHHHMMSS/);
  return "UNKNOWN FORMAT";
}

sub make_time {
  my $hour=shift;
  my $minute=shift;
  my $second=shift;
  return sprintf "%02d:%02d:%02d", ($hour%24),$minute,$second 
      if ($limits{'time_format_ISO'} eq "yes");
  return sprintf "%02d.%02d.%02d", ($hour%24),$minute,$second 
      if ($limits{'time_format_EUR'} eq "yes");
  return sprintf "%02d:%02d %s", 
        ($hour >= 13? ($hour-12) : $hour),$minute,($hour >=13 ? 'PM':'AM') 
      if ($limits{'time_format_USA'} eq "yes");
  return sprintf "%02d%02d%02d", ($hour%24),$minute,$second 
      if ($limits{'time_format_HHMMSS'} eq "yes");
  return sprintf "%04d%02d%02d", ($hour%24),$minute,$second 
      if ($limits{'time_format_HHHHMMSS'} eq "yes");
  return "UNKNOWN FORMAT";
}

sub make_date_r {
  my $year=shift;
  my $month=shift;
  my $day=shift;
  $_ = $limits{'date_format_inresult'};
  return sprintf "%02d-%02d-%02d", ($year%100),$month,$day if (/^short iso$/);
  return sprintf "%04d-%02d-%02d", $year,$month,$day if (/^iso/);
  return sprintf "%02d.%02d.%02d", $day,$month,($year%100) if (/^short euro/);
  return sprintf "%02d.%02d.%04d", $day,$month,$year if (/^euro/);
  return sprintf "%02d/%02d/%02d", $month,$day,($year%100) if (/^short usa/);
  return sprintf "%02d/%02d/%04d", $month,$day,$year if (/^usa/);
  return sprintf "%04d%02d%02d", $year,$month,$day if (/^YYYYMMDD/);
  return "UNKNOWN FORMAT";
}


sub make_date {
  my $year=shift;
  my $month=shift;
  my $day=shift;
  return sprintf "'%04d-%02d-%02d'", $year,$month,$day 
      if ($limits{'date_format_ISO'} eq yes);
  return sprintf "DATE '%04d-%02d-%02d'", $year,$month,$day 
      if ($limits{'date_format_ISO_with_date'} eq yes);
  return sprintf "'%02d.%02d.%04d'", $day,$month,$year 
      if ($limits{'date_format_EUR'} eq 'yes');
  return sprintf "DATE '%02d.%02d.%04d'", $day,$month,$year 
      if ($limits{'date_format_EUR_with_date'} eq 'yes');
  return sprintf "'%02d/%02d/%04d'", $month,$day,$year 
      if ($limits{'date_format_USA'} eq 'yes');
  return sprintf "DATE '%02d/%02d/%04d'", $month,$day,$year 
      if ($limits{'date_format_USA_with_date'} eq 'yes');
  return sprintf "'%04d%02d%02d'", $year,$month,$day 
      if ($limits{'date_format_YYYYMMDD'} eq 'yes');
  return sprintf "DATE '%04d%02d%02d'", $year,$month,$day 
      if ($limits{'date_format_YYYYMMDD_with_date'} eq 'yes');
  return "UNKNOWN FORMAT";
}


sub print_recordset{
  my ($key,$recset) = @_;
  my $rec;
  foreach $rec (@$recset)
  {
    add_log($key, " > ".join(',', map(repr($_), @$rec)));
  }
}

#
# read result recordset from sql server. 
# returns arrayref to (arrayref to) values
# or undef (in case of sql errors)
#
sub get_recordset{
  my ($key,$query) = @_;
  add_log($key, "< $query");
  return $dbh->selectall_arrayref($query);
}

# function for comparing recordset (that was returned by get_recordset)
# and arrayref of (arrayref of) values.
#
# returns : zero if recordset equal that array, 1 if it doesn't equal
#
# parameters:
# $key - current operation (for logging)
# $recset - recordset
# $mustbe - array of values that we expect
#
# example: $a=get_recordset('some_parameter','select a,b from c');
# if (compare_recordset('some_parameter',$a,[[1,1],[1,2],[1,3]]) neq 0) 
# {
#   print "unexpected result\n";
# } ;
#
sub compare_recordset {
  my ($key,$recset,$mustbe) = @_;
  my $rec,$recno,$fld,$fldno,$fcount;
  add_log($key,"\n Check recordset:");
  $recno=0;
  foreach $rec (@$recset)
  {
    add_log($key," " . join(',', map(repr($_),@$rec)) . " expected: " .
	    join(',', map(repr($_), @{$mustbe->[$recno]} ) ));
    $fcount = @$rec;
    $fcount--;
    foreach $fldno (0 .. $fcount )
    {
      if ($mustbe->[$recno][$fldno] ne $rec->[$fldno])
      {
	add_log($key," Recordset doesn't correspond with template");
	return 1;
      };
    }
    $recno++;
  }
  add_log($key," Recordset corresponds with template");
  return 0;
}

#
# converts inner perl value to printable representation
# for example: undef maps to 'NULL',
# string -> 'string'
# int -> int
# 
sub repr {
  my $s = shift;
  return "'$s'"if ($s =~ /\D/);
  return 'NULL'if ( not defined($s));
  return $s;
}


sub version
{
  print "$0  Ver $version\n";
}


sub usage
{
  version();
    print <<EOF;

This program tries to find all limits and capabilities for a SQL
server.  As it will use the server in some 'unexpected' ways, one
shouldn\'t have anything important running on it at the same time this
program runs!  There is a slight chance that something unexpected may
happen....

As all used queries are legal according to some SQL standard. any
reasonable SQL server should be able to run this test without any
problems.

All questions is cached in $opt_dir/'server_name'[-suffix].cfg that
future runs will use limits found in previous runs. Remove this file
if you want to find the current limits for your version of the
database server.

This program uses some table names while testing things. If you have any
tables with the name of 'crash_me' or 'crash_qxxxx' where 'x' is a number,
they will be deleted by this test!

$0 takes the following options:

--help 
  Shows this help

--batch-mode
  Don\'t ask any questions, quit on errors.

--config-file='filename'
  Read limit results from specific file

--comment='some comment'
  Add this comment to the crash-me limit file

--check-server
  Do a new connection to the server every time crash-me checks if the server
  is alive.  This can help in cases where the server starts returning wrong
  data because of an earlier select.

--connect-options='some connect options'
  Additional options to be used when DBI connects to the server.
  Examples:
  --connect-options=mysql_read_default_file=/etc/my.cnf
  --connect-options=mysql_socket=/tmp/mysql.sock

--database='database' (Default $opt_database)
  Create test tables in this database.

--dir='limits'
  Save crash-me output in this directory

--debug
  Lots of printing to help debugging if something goes wrong.

--fix-limit-file
  Reformat the crash-me limit file.  crash-me is not run!

--force
  Start test at once, without a warning screen and without questions.
  This is a option for the very brave.
  Use this in your cron scripts to test your database every night.

--log-all-queries
  Prints all queries that are executed. Mostly used for debugging crash-me.

--log-queries-to-file='filename'
  Log full queries to file.

--host='hostname' (Default $opt_host)
  Run tests on this host.

--odbc
  Use the ODBC DBI driver to connect to the database server.

--password='password'
  Password for the current user.
   
--restart
  Save states during each limit tests. This will make it possible to continue
  by restarting with the same options if there is some bug in the DBI or
  DBD driver that caused $0 to die!

--server='server name'  (Default $opt_server)
  Run the test on the given server.
  Known servers names are: Access, Adabas, AdabasD, Empress, Oracle, 
  Informix, DB2, Mimer, mSQL, MS-SQL, MySQL, Pg, Solid or Sybase.
  For others $0 can\'t report the server version.

--socket='filename'
  If the database server supports connecting through a Unix socket file,
  use this socket file to connect.

--suffix='suffix' (Default '')
  Add suffix to the output filename. For instance if you run crash-me like
  "crash-me --suffix="myisam",
  then output filename will look "mysql-myisam.cfg".

--user='user_name'
  User name to log into the SQL server.

--db-start-cmd='command to restart server'
  Automaticly restarts server with this command if the database server dies.

--sleep='time in seconds' (Default $opt_sleep)
  Wait this long before restarting server.

--verbose
--noverbose
  Log into the result file queries performed for determination parameter value

EOF
  exit(0);
}


sub server_info
{
  my ($ok,$tmp);
  $ok=0;
  print "\nNOTE: You should be familiar with '$0 --help' before continuing!\n\n";
  if (lc($opt_server) eq "mysql")
  {
    $ok=1;
    print <<EOF;
This test should not crash MySQL if it was distributed together with the
running MySQL version.
If this is the case you can probably continue without having to worry about
destroying something.
EOF
  }
  elsif (lc($opt_server) eq "msql")
  {
    print <<EOF;
This test will take down mSQL repeatedly while finding limits.
To make this test easier, start mSQL in another terminal with something like:

while (true); do /usr/local/mSQL/bin/msql2d ; done

You should be sure that no one is doing anything important with mSQL and that
you have privileges to restart it!
It may take awhile to determinate the number of joinable tables, so prepare to
wait!
EOF
  }
  elsif (lc($opt_server) eq "solid")
  {
    print <<EOF;
This test will take down Solid server repeatedly while finding limits.
You should be sure that no one is doing anything important with Solid
and that you have privileges to restart it!

If you are running Solid without logging and/or backup YOU WILL LOSE!
Solid does not write data from the cache often enough. So if you continue
you may lose tables and data that you entered hours ago!

Solid will also take a lot of memory running this test. You will nead
at least 234M free!

When doing the connect test Solid server or the perl api will hang when
freeing connections. Kill this program and restart it to continue with the
test. You don\'t have to use --restart for this case.
EOF
    if (!$opt_restart)
    {
      print "\nWhen DBI/Solid dies you should run this program repeatedly\n";
      print "with --restart until all tests have completed\n";
    }
  }
  elsif (lc($opt_server) eq "pg")
  {
    print <<EOF;
This test will crash postgreSQL when calculating the number of joinable tables!
You should be sure that no one is doing anything important with postgreSQL
and that you have privileges to restart it!
EOF
  }
  else
  {
    print <<EOF;
This test may crash $opt_server repeatedly while finding limits!
You should be sure that no one is doing anything important with $opt_server
and that you have privileges to restart it!
EOF
  }
  print <<EOF;

Some of the tests you are about to execute may require a lot of
memory.  Your tests WILL adversely affect system performance. It\'s
not uncommon that either this crash-me test program, or the actual
database back-end, will DIE with an out-of-memory error. So might
any other program on your system if it requests more memory at the
wrong time.

Note also that while crash-me tries to find limits for the database server
it will make a lot of queries that can\'t be categorized as \'normal\'.  It\'s
not unlikely that crash-me finds some limit bug in your server so if you
run this test you have to be prepared that your server may die during it!

We, the creators of this utility, are not responsible in any way if your
database server unexpectedly crashes while this program tries to find the
limitations of your server. By accepting the following question with \'yes\',
you agree to the above!

You have been warned!

EOF

  #
  # No default reply here so no one can blame us for starting the test
  # automaticly.
  #
  for (;;)
  {
    print "Start test (yes/no) ? ";
    $tmp=<STDIN>; chomp($tmp); $tmp=lc($tmp);
    last if ($tmp =~ /^yes$/i);
    exit 1 if ($tmp =~ /^n/i);
    print "\n";
  }
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


#
# Help functions that we need
#

sub safe_connect
{
  my ($object)=@_;
  my ($dbh,$tmp);

  for (;;)
  {
    if (($dbh=DBI->connect($server->{'data_source'},$opt_user,$opt_password,
			   { PrintError => 0, AutoCommit => 1})))
    {
      $dbh->{LongReadLen}= 16000000; # Set max retrieval buffer
      return $dbh;
    }
    print "Error: $DBI::errstr;  $server->{'data_source'} ".
        " - '$opt_user' - '$opt_password'\n";
    print "I got the above error when connecting to $opt_server\n";
    if (defined($object) && defined($object->{'limit'}))
    {
      print "This check was done with limit: $object->{'limit'}.".
          "\nNext check will be done with a smaller limit!\n";
      $object=undef();
    }
    save_config_data('crash_me_safe','no',"crash me safe");
    if ($opt_db_start_cmd)
    {
      print "Restarting the db server with:\n'$opt_db_start_cmd'\n";
      system("$opt_db_start_cmd");
      print "Waiting $opt_sleep seconds so the server can initialize\n";
      sleep $opt_sleep;
    }
    else
    {
      exit(1) if ($opt_batch_mode);
      print "Can you check/restart it so I can continue testing?\n";
      for (;;)
      {
	print "Continue test (yes/no) ? [yes] ";
	$tmp=<STDIN>; chomp($tmp); $tmp=lc($tmp);
	$tmp = "yes" if ($tmp eq "");
	last if (index("yes",$tmp) >= 0);
	exit 1 if (index("no",$tmp) >= 0);
	print "\n";
      }
    }
  }
}

#
# Test connecting a couple of times before giving an error
# This is needed to get the server time to free old connections
# after the connect test
#

sub retry_connect
{
  my ($dbh, $i);
  for ($i=0 ; $i < 10 ; $i++)
  {
    if (($dbh=DBI->connect($server->{'data_source'},$opt_user,$opt_password,
			 { PrintError => 0, AutoCommit => 1})))
    {
      $dbh->{LongReadLen}= 16000000; # Set max retrieval buffer
      return $dbh;
    }
    sleep(1);
  }
  return safe_connect();
}

#
# Check if the server is up and running. If not, ask the user to restart it
#

sub check_connect
{
  my ($object)=@_;
  my ($sth);
  print "Checking connection\n" if ($opt_log_all_queries);
  # The following line will not work properly with interbase
  if ($opt_check_server && defined($check_connect) && $dbh->{AutoCommit} != 0)
  {
    
    $dbh->disconnect;
    $dbh=safe_connect($object);
    return;
  }
  return if (defined($check_connect) && defined($dbh->do($check_connect)));
  $dbh->disconnect || warn $dbh->errstr;
  print "\nreconnecting\n" if ($opt_debug);
  $reconnect_count++;
  undef($dbh);
  $dbh=safe_connect($object);
}

#
# print query if debugging
#
sub repr_query {
  my $query=shift;
 if (length($query) > 130)
 {
   $query=substr($query,0,120) . "...(" . (length($query)-120) . ")";
 }
 return $query;
}  

sub print_query
{
  my ($query)=@_;
  $last_error=$DBI::errstr;
  if ($opt_debug)
  {
    if (length($query) > 130)
    {
      $query=substr($query,0,120) . "...(" . (length($query)-120) . ")";
    }
    printf "\nGot error from query: '%s'\n%s\n",$query,$DBI::errstr;
  }
}

#
# Do one or many queries. Return 1 if all was ok
# Note that all rows are executed 
# (to ensure that we execute drop table commands)
#

sub safe_query_l {
  my $key = shift;
  my $q = shift;
  my $r = safe_query($q);
  add_log($key,$safe_query_log);
  return $r;
}

sub safe_query
{
  my($queries)=@_;
  my($query,$ok,$retry_ok,$retry,@tmp,$sth);
  $safe_query_log="";
  $ok=1;
  if (ref($queries) ne "ARRAY")
  {
    push(@tmp,$queries);
    $queries= \@tmp;
  }
  foreach $query (@$queries)
  {
    printf "query1: %-80.80s ...(%d - %d)\n",$query,
          length($query),$retry_limit  if ($opt_log_all_queries);
    print LOG "$query;\n" if ($opt_log);
    $safe_query_log .= "< $query\n";
    if (length($query) > $query_size)
    {
      $ok=0;
      $safe_query_log .= "Query is too long\n";
      next;
    }

    $retry_ok=0;
    for ($retry=0; $retry < $retry_limit ; $retry++)
    {
      if (! ($sth=$dbh->prepare($query)))
      {
	print_query($query);
        $safe_query_log .= "> couldn't prepare:". $dbh->errstr. "\n";
	$retry=100 if (!$server->abort_if_fatal_error());
	# Force a reconnect because of Access drop table bug!
	if ($retry == $retry_limit-2)
	{
	  print "Forcing disconnect to retry query\n" if ($opt_debug);
	  $dbh->disconnect || warn $dbh->errstr;
	}
	check_connect();        # Check that server is still up
      }
      else
      {
        if (!$sth->execute())
        {
 	  print_query($query);
          $safe_query_log .= "> execute error:". $dbh->errstr. "\n";
	  $retry=100 if (!$server->abort_if_fatal_error());
	  # Force a reconnect because of Access drop table bug!
	  if ($retry == $retry_limit-2)
	  {
	    print "Forcing disconnect to retry query\n" if ($opt_debug);
	    $dbh->disconnect || warn $dbh->errstr;
	  }
	  check_connect();        # Check that server is still up
        }
        else
        {
	  $retry = $retry_limit;
	  $retry_ok = 1;
          $safe_query_log .= "> OK\n";
        }
        $sth->finish;
      }
    }
    $ok=0 if (!$retry_ok);
    if ($query =~ /create/i && $server->reconnect_on_errors())
    {
      print "Forcing disconnect to retry query\n" if ($opt_debug);
      $dbh->disconnect || warn $dbh->errstr;
      $dbh=safe_connect();
    }
  }
  return $ok;
}

sub check_reserved_words
# For this reserved keyword test:
#   -- A return of "SQL:1986-1989" (0) means the keyword was a reserved word in SQL:1986
#      and SQL:1989, but was made a non-reserved word with SQL:1992. A DBMS that
#      does not treat the keyword as a reserved word complies with the current version
#      of the SQL Standard (SQL:2003). The keywords "FORTRAN" and "PASCAL" are, however,
#      reserved keywords in ODBC 3.0.
#   -- A return of "SQL:1986-1992" (1) means the keyword was a reserved word in SQL:1986,
#      SQL:1989, and SQL:1992, but was removed as a keyword entirely with SQL:1999. A
#      DBMS that does not treat the keyword as a reserved word complies with the current
#      version of the SQL Standard (SQL:2003). The keywords "SQLCODE" and "SQLERROR" are,
#      however, reserved keywords in ODBC 3.0.
#   -- A return of "SQL:1986-2003" (2) means the keyword has been a reserved word in every
#      version of the SQL Standard. A DBMS that does not treat the keyword as a
#      reserved word does not comply with standard SQL.
#   -- A return of "SQL:1989-1999" (3) means the keyword was added as a reserved word with
#      SQL:1989. It remained as a reserved word in SQL:1992 and SQL:1999, but
#      but was made a non-reserved word with SQL:2003. A DBMS that does not treat the
#      keyword as a reserved word complies with the current version of the SQL Standard
#      (SQL:2003).
#   -- A return of "SQL:1989-2003" (4) means the keyword was added as a reserved word with
#      SQL:1989 and has been a reserved word in every subsequent version of the SQL
#      Standard. A DBMS that does not treat the keyword as a reserved word does not comply
#      with standard SQL.
#   -- A return of "SQL:1992-1999" (5) means the keyword was added as a reserved word with
#      SQL:1992. It remained as a reserved word in SQL:1999, but was made a non-reserved
#      word with SQL:2003. A DBMS that does not treat the keyword as a reserved word
#      complies with the current version of the SQL Standard (SQL:2003).
#   -- A return of "SQL:1992-2003" (6) means the keyword was added as a reserved word with
#      SQL:1992 and has been a reserved word in every subsequent version of the SQL
#      Standard. A DBMS that does not treat the keyword as a reserved word does not comply
#      with standard SQL.
#   -- A return of "SQL:1999-2003" (7) means the keyword was added as a reserved word with
#      SQL:1999 and has been a reserved word in every subsequent version of the SQL
#      Standard. A DBMS that does not treat the keyword as a reserved word does not comply
#      with standard SQL.
#   -- A return of "SQL:2003" (8) means the keyword was added as a reserved word with
#      SQL:2003. A DBMS that does not treat the keyword as a reserved word does not comply
#      with the current version of the SQL Standard.
#   -- A return of "ODBC3" (9) means ODBC 3.0 considers the word to be a reserved keyword
#      even though the keyword is not a reserved word in standard SQL. This is a small list
#      because standard SQL and ODBC generally have the same set of restricted keywords.
#   -- A return of "MySQL" (10) means the keyword is an SQL extension that is treated as
#      an additional reserved word by MySQL (version 4.x).
#   -- A return of "IBM_DB2" (11) means the keyword is an SQL extension that is treated as
#      an additional reserved word by IBM DB2 Universal Database (version 8.x).
#   -- A return of "MS_SQL" (12) means the keyword is an SQL extension that is treated
#      as an additional reserved word by Microsoft SQL Server 2000.
#   -- A return of "Oracle" (13) means the keyword is an SQL extension that is treated
#      as an additional reserved word by Oracle Database (release 10g).
{
  my ($dbh)= @_;

  my $answer, $prompt, $config, $keyword_type;

  my @keywords_ext  = ( "SQL:1986-1989", "SQL:1986-1992", "SQL:1986-2003",
                        "SQL:1989-1999", "SQL:1989-2003", "SQL:1992-1999",
                        "SQL:1992-2003", "SQL:1999-2003", "SQL:2003","ODBC3",
                        "MySQL", "IBM_DB2", "MS_SQL", "Oracle");


  my %reserved_words = (
                'ABS' =>  7,           'ABSOLUTE' =>  5, 'ACCESS' => 13,
             'ACTION' =>  5,                'ADA' =>  9, 'ADD' =>  5,
              'AFTER' => 11,              'ALIAS' => 11, 'ALL' =>  2,
           'ALLOCATE' =>  6,              'ALLOW' => 11, 'ALTER' =>  6,
            'ANALYZE' => 10,                'AND' =>  2, 'ANY' =>  2,
        'APPLICATION' => 11,              'ARRAY' =>  7, 'ARE' =>  6,
                 'AS' =>  2,                'ASC' =>  9, 'ASENSITIVE' =>  8,
          'ASSERTION' =>  5,          'ASSOCIATE' => 11, 'ASYMMETRIC' =>  8,
            'ASUTIME' => 11,                 'AT' =>  6, 'ATOMIC' =>  8,
              'AUDIT' => 11,      'AUTHORIZATION' =>  2, 'AUX' => 11,
          'AUXILIARY' => 11,                'AVG' =>  2, 'BACKUP' => 12,
              'BEGIN' =>  2,            'BETWEEN' =>  2, 'BIGINT' =>  8,
             'BINARY' =>  7,                'BIT' =>  9, 'BIT_LENGTH' =>  9,
               'BLOB' =>  7,            'BOOLEAN' =>  7, 'BOTH' =>  6,
              'BREAK' => 12,             'BROWSE' => 12, 'BTREE' => 10,
         'BUFFERPOOL' => 11,               'BULK' => 12, 'BY' =>  2,
              'CACHE' => 11,               'CALL' =>  7, 'CALLED' =>  8,
            'CAPTURE' => 11,        'CARDINALITY' =>  7, 'CASCADE' =>  5,
           'CASCADED' =>  6,               'CASE' =>  6, 'CAST' =>  6,
            'CATALOG' =>  5,              'CCSID' => 11, 'CEIL' =>  8,
            'CEILING' =>  8,             'CHANGE' => 10, 'CHAR' =>  2,
        'CHAR_LENGTH' =>  6,          'CHARACTER' =>  2, 'CHARACTER_LENGTH' =>  6,
              'CHECK' =>  2,         'CHECKPOINT' => 12, 'CLOB' =>  7,
              'CLOSE' =>  2,            'CLUSTER' => 11, 'CLUSTERED' => 12,
           'COALESCE' =>  6,              'COBOL' =>  0, 'COLLATE' =>  6,
          'COLLATION' =>  5,            'COLLECT' =>  8, 'COLLECTION' => 11,
             'COLLID' => 11,             'COLUMN' =>  6, 'COLUMNS' => 10,
            'COMMENT' => 11,             'COMMIT' =>  2, 'COMPRESS' => 13,
            'COMPUTE' => 12,             'CONCAT' => 11, 'CONDITION' =>  8,
            'CONNECT' =>  6,         'CONNECTION' =>  5, 'CONSTRAINT' =>  6,
        'CONSTRAINTS' =>  5,           'CONTAINS' => 11, 'CONTAINSTABLE' => 12,
           'CONTINUE' =>  9,            'CONVERT' =>  6, 'CORR' =>  8,
      'CORRESPONDING' =>  6,              'COUNT' =>  2, 'COUNT_BIG' => 11,
          'COVAR_POP' =>  8,         'COVAR_SAMP' =>  8, 'CREATE' =>  2,
              'CROSS' =>  6,               'CUBE' =>  7, 'CUME_DIST' =>  8,
            'CURRENT' =>  2,       'CURRENT_DATE' =>  6, 'CURRENT_DEFAULT_TRANSFORM_GROUP' =>  8,
   'CURRENT_LC_CTYPE' => 11,       'CURRENT_PATH' =>  7, 'CURRENT_SERVER' => 11,
       'CURRENT_ROLE' =>  7,       'CURRENT_TIME' =>  6, 'CURRENT_TIMESTAMP' =>  6,
   'CURRENT_TIMEZONE' => 11, 'CURRENT_TRANSFORM_GROUP_FOR_TYPE' =>  8, 'CURRENT_USER' =>  6,
             'CURSOR' =>  2,              'CYCLE' =>  7, 'DATA' => 11,
           'DATABASE' => 10,          'DATABASES' => 10, 'DATE' =>  6,
                'DAY' =>  6,               'DAYS' => 11, 'DAY_HOUR' => 10,
    'DAY_MICROSECOND' => 10,         'DAY_MINUTE' => 10, 'DAY_SECOND' => 10,
         'DB2GENERAL' => 11,           'DB2GENRL' => 11, 'DB2SQL' => 11,
            'DB2INFO' => 11,               'DBCC' => 12, 'DEALLOCATE' =>  6,
                'DEC' =>  2,            'DECIMAL' =>  2, 'DECLARE' =>  2,
            'DEFAULT' =>  4,           'DEFAULTS' => 11, 'DEFERRABLE' =>  5,
           'DEFERRED' =>  5,         'DEFINITION' => 11, 'DELAYED' => 10,
             'DELETE' =>  2,         'DENSE_RANK' =>  8, 'DENY' => 12,
              'DEREF' =>  7,               'DESC' =>  9, 'DESCRIBE' =>  6,
         'DESCRIPTOR' =>  5,      'DETERMINISTIC' =>  7, 'DIAGNOSTICS' =>  5,
           'DISALLOW' => 11,         'DISCONNECT' =>  6, 'DISK' => 12,
           'DISTINCT' =>  2,        'DISTINCTROW' => 10, 'DISTRIBUTED' => 12,
                'DIV' => 10,                 'DO' => 11, 'DOMAIN' =>  5,
             'DOUBLE' =>  2,               'DROP' =>  6, 'DSNHATTR' => 11,
             'DSSIZE' => 11,              'DUMMY' => 12, 'DUMP' => 12,
            'DYNAMIC' =>  7,               'EACH' =>  7, 'EDITPROC' => 11,
            'ELEMENT' =>  8,               'ELSE' =>  6, 'ENCLOSED' => 10,
           'ENCODING' => 11,                'END' =>  2, 'END-EXEC' =>  6,
          'END-EXEC1' => 11,              'ERASE' => 11, 'ERRLVL' => 12,
             'ERRORS' => 10,             'ESCAPE' =>  2, 'ESCAPED' => 10,
              'EVERY' =>  7,             'EXCEPT' =>  6, 'EXCEPTION' =>  5,
          'EXCLUDING' => 11,          'EXCLUSIVE' => 13, 'EXEC' =>  2,
            'EXECUTE' =>  6,             'EXISTS' =>  2, 'EXIT' => 12,
                'EXP' =>  8,            'EXPLAIN' => 10, 'EXTERNAL' =>  6,
            'EXTRACT' =>  6,              'FALSE' =>  6, 'FENCED' => 11,
              'FETCH' =>  2,          'FIELDPROC' => 11, 'FIELDS' => 10,
               'FILE' => 11,         'FILLFACTOR' => 12, 'FILTER' =>  8,
              'FINAL' => 11,              'FIRST' =>  5, 'FLOAT' =>  2,
              'FLOOR' =>  8,                'FOR' =>  2, 'FORCE' => 10,
            'FOREIGN' =>  4,            'FORTRAN' =>  0, 'FOUND' =>  9,
        'FRAC_SECOND' => 10,               'FREE' =>  7, 'FREETEXT' => 12,
      'FREETEXTTABLE' => 12,               'FROM' =>  2, 'FULL' =>  6,
           'FULLTEXT' => 10,           'FUNCTION' =>  7, 'FUSION' =>  8,
            'GENERAL' => 11,          'GENERATED' => 11, 'GET' =>  6,
             'GLOBAL' =>  6,                 'GO' =>  9, 'GOTO' =>  9,
              'GRANT' =>  2,            'GRAPHIC' => 11, 'GROUP' =>  2,
           'GROUPING' =>  7,            'HANDLER' => 11, 'HASH' => 10,
             'HAVING' =>  2,      'HIGH_PRIORITY' => 10, 'HOLD' =>  7,
           'HOLDLOCK' => 12,               'HOUR' =>  6, 'HOUR_MICROSECOND' => 10,
        'HOUR_MINUTE' => 10,        'HOUR_SECOND' => 10, 'HOURS' => 11,
         'IDENTIFIED' => 13,           'IDENTITY' =>  6, 'IDENTITY_INSERT' => 12,
        'IDENTITYCOL' => 12,                 'IF' => 10, 'IGNORE' => 10,
          'IMMEDIATE' =>  5,                 'IN' =>  2, 'INCLUDE' =>  9,
          'INCLUDING' => 11,          'INCREMENT' => 11, 'INDEX' =>  9,
          'INDICATOR' =>  2,             'INFILE' => 10, 'INHERIT' => 11,
            'INITIAL' => 13,          'INITIALLY' =>  5, 'INNER' =>  6,
              'INOUT' =>  7,              'INPUT' =>  5, 'INSENSITIVE' =>  6,
             'INSERT' =>  2,                'INT' =>  2, 'INTEGER' =>  2,
          'INTEGRITY' => 11,          'INTERSECT' =>  6, 'INTERSECTION' =>  8,
           'INTERVAL' =>  6,               'INTO' =>  2, 'IS' =>  2,
             'ISOBID' => 11,          'ISOLATION' =>  5, 'JAR' => 11,
               'JAVA' => 11,               'JOIN' =>  6, 'KEY' =>  3,
               'KEYS' => 10,               'KILL' => 10, 'LABEL' => 11,
           'LANGUAGE' =>  2,              'LARGE' =>  7, 'LAST' =>  5,
            'LATERAL' =>  7,           'LC_CTYPE' => 11, 'LEADING' =>  6,
               'LEFT' =>  6,              'LEVEL' =>  5, 'LIKE' =>  2,
              'LIMIT' => 10,             'LINENO' => 12, 'LINES' => 10,
           'LINKTYPE' => 11,                 'LN' =>  8, 'LOAD' => 10,
              'LOCAL' =>  6,             'LOCALE' => 11, 'LOCALTIME' =>  7,
     'LOCALTIMESTAMP' =>  7,            'LOCATOR' => 11, 'LOCATORS' => 11,
               'LOCK' => 13,            'LOCKMAX' => 11, 'LOCKSIZE' => 11,
               'LONG' => 13,           'LONGBLOB' => 10, 'LONGTEXT' => 10,
       'LOW_PRIORITY' => 10,              'LOWER' =>  6, 'MASTER_SERVER_ID' => 10,
              'MATCH' =>  6,                'MAX' =>  2, 'MAXEXTENTS' => 13,
           'MAXVALUE' => 11,         'MEDIUMBLOB' => 10, 'MEDIUMINT' => 10,
         'MEDIUMTEXT' => 10,             'MEMBER' =>  8, 'MERGE' =>  8,
             'METHOD' =>  8,        'MICROSECOND' => 11, 'MICROSECONDS' => 11,
          'MIDDLEINT' => 10,                'MIN' =>  2, 'MINUS' => 13,
             'MINUTE' =>  6, 'MINUTE_MICROSECOND' => 10, 'MINUTE_SECOND' => 10,
            'MINUTES' => 11,             'MINVAL' => 11, 'MLSLABEL' => 13,
                'MOD' =>  7,               'MODE' => 11, 'MODIFIES' =>  7,
             'MODIFY' => 13,             'MODULE' =>  2, 'MONTH' =>  6,
             'MONTHS' => 11,           'MULTISET' =>  8, 'NAMES' =>  5,
           'NATIONAL' =>  6,            'NATURAL' =>  6, 'NCHAR' =>  6,
              'NCLOB' =>  7,                'NEW' =>  7, 'NEW_TABLE' => 11,
               'NEXT' =>  5,                 'NO' =>  6, 'NO_WRITE_TO_BINLOG' => 10,
            'NOAUDIT' => 13,            'NOCACHE' => 11, 'NOCHECK' => 12,
         'NOCOMPRESS' => 13,            'NOCYCLE' => 11, 'NODENAME' => 11,
         'NODENUMBER' => 11,         'NOMAXVALUE' => 11, 'NOMINVALUE' => 11,
       'NONCLUSTERED' => 12,               'NONE' =>  7, 'NOORDER' => 11,
          'NORMALIZE' =>  8,                'NOT' =>  2, 'NOWAIT' => 13,
               'NULL' =>  2,             'NULLIF' =>  6, 'NULLS' => 11,
             'NUMBER' => 13,            'NUMERIC' =>  2, 'NUMPARTS' => 11,
               'OBID' => 11,       'OCTET_LENGTH' =>  6, 'OF' =>  2,
                'OFF' => 12,            'OFFLINE' => 13, 'OFFSETS' => 12,
                'OLD' =>  7,          'OLD_TABLE' => 11, 'ON' =>  2,
             'ONLINE' => 13,               'ONLY' =>  6, 'OPEN' =>  2,
     'OPENDATASOURCE' => 12,          'OPENQUERY' => 12, 'OPENROWSET' => 12,
            'OPENXML' => 12,       'OPTIMIZATION' => 11, 'OPTIMIZE' => 10,
             'OPTION' =>  9,         'OPTIONALLY' => 10, 'OR' =>  2,
              'ORDER' =>  2,                'OUT' =>  7, 'OUTER' =>  6,
            'OUTFILE' => 10,             'OUTPUT' =>  5, 'OVER' =>  8,
           'OVERLAPS' =>  6,            'OVERLAY' =>  7, 'OVERRIDING' => 11,
            'PACKAGE' => 11,                'PAD' =>  5, 'PARAMETER' =>  7,
               'PART' => 11,            'PARTIAL' =>  5, 'PARTITION' =>  8,
             'PASCAL' =>  0,               'PATH' => 11, 'PCTFREE' => 13,
            'PERCENT' => 12,       'PERCENT_RANK' =>  8, 'PERCENTILE_CONT' =>  8,
    'PERCENTILE_DISC' =>  8,          'PIECESIZE' => 11, 'PLAN' => 11,
                'PLI' =>  0,           'POSITION' =>  6, 'POWER' =>  8,
          'PRECISION' =>  2,            'PREPARE' =>  6, 'PRESERVE' =>  5,
            'PRIMARY' =>  4,              'PRINT' => 12, 'PRIOR' =>  5,
             'PRIQTY' => 11,         'PRIVILEGES' =>  9, 'PROC' => 12,
          'PROCEDURE' =>  2,            'PROGRAM' => 11, 'PSID' => 11,
             'PUBLIC' =>  9,              'PURGE' => 10, 'QUERYNO' => 11,
          'RAISERROR' => 12,              'RANGE' =>  8, 'RANK' =>  8,
                'RAW' => 13,               'READ' =>  5, 'READS' =>  7,
           'READTEXT' => 12,               'REAL' =>  2, 'RECONFIGURE' => 12,
           'RECOVERY' => 11,          'RECURSIVE' =>  7, 'REF' =>  7,
         'REFERENCES' =>  4,        'REFERENCING' =>  7, 'REGEXP' => 10,
          'REGR_AVGX' =>  8,          'REGR_AVGY' =>  8, 'REGR_COUNT' =>  8,
     'REGR_INTERCEPT' =>  8,            'REGR_R2' =>  8, 'REGR_SLOPE' =>  8,
           'REGR_SXX' =>  8,           'REGR_SXY' =>  8, 'REGR_SYY' =>  8,
           'RELATIVE' =>  5,            'RELEASE' =>  8, 'RENAME' => 13,
            'REPLACE' => 10,        'REPLICATION' => 12, 'REQUIRE' => 10,
              'RESET' => 11,           'RESIGNAL' => 11, 'RESOURCE' => 13,
            'RESTART' => 11,            'RESTORE' => 12, 'RESTRICT' =>  5,
             'RESULT' =>  7, 'RESULT_SET_LOCATOR' => 11, 'RETURN' =>  7,
            'RETURNS' =>  7,             'REVOKE' =>  6, 'RIGHT' =>  6,
              'RLIKE' => 10,           'ROLLBACK' =>  2, 'ROLLUP' =>  7,
            'ROUTINE' => 11,                'ROW' =>  7, 'ROW_NUMBER' =>  8,
           'ROWCOUNT' => 12,         'ROWGUIDCOL' => 12, 'ROWID' => 13,
             'ROWNUM' => 13,               'ROWS' =>  6, 'RRN' => 11,
              'RTREE' => 10,               'RULE' => 12, 'RUN' => 11,
               'SAVE' => 12,          'SAVEPOINT' =>  7, 'SCHEMA' =>  9,
              'SCOPE' =>  7,         'SCRATCHPAD' => 11, 'SCROLL' =>  6,
             'SEARCH' =>  7,             'SECOND' =>  6, 'SECOND_MICROSECOND' => 10,
            'SECONDS' => 11,             'SECQTY' => 11, 'SECTION' =>  9,
           'SECURITY' => 11,             'SELECT' =>  2, 'SENSITIVE' =>  7,
          'SEPARATOR' => 10,            'SESSION' =>  5, 'SESSION_USER' =>  6,
                'SET' =>  2,            'SETUSER' => 12, 'SHARE' => 13,
           'SHUTDOWN' => 12,               'SHOW' => 10, 'SIGNAL' => 11,
            'SIMILAR' =>  7,             'SIMPLE' => 11, 'SIZE' =>  5,
           'SMALLINT' =>  2,               'SOME' =>  2, 'SONAME' => 10,
             'SOURCE' => 11,              'SPACE' =>  5, 'SPATIAL' => 10,
           'SPECIFIC' =>  7,       'SPECIFICTYPE' =>  7, 'SQL' =>  2,
     'SQL_BIG_RESULT' => 10, 'SQL_CALC_FOUND_ROWS' => 10, 'SQL_SMALL_RESULT' => 10,
'SQL_TSI_FRAC_SECOND' => 10,              'SQLCA' =>  9, 'SQLCODE' =>  1,
           'SQLERROR' =>  1,       'SQLEXCEPTION' =>  7, 'SQLID' => 11,
           'SQLSTATE' =>  6,         'SQLWARNING' =>  7, 'SQRT' =>  8,
                'SSL' => 10,           'STANDARD' => 11, 'START' =>  7,
           'STARTING' => 10,             'STATIC' =>  7, 'STATISTICS' => 12,
               'STAY' => 11,         'STDDEV_POP' =>  8, 'STDDEV_SAMP' =>  8,
           'STOGROUP' => 11,             'STORES' => 11, 'STRAIGHT_JOIN' => 10,
              'STYLE' => 11,        'SUBMULTISET' =>  8, 'SUBPAGES' => 11,
          'SUBSTRING' =>  6,         'SUCCESSFUL' => 13, 'SUM' =>  2,
          'SYMMETRIC' =>  8,            'SYNONYM' => 11, 'SYSDATE' => 13,
             'SYSFUN' => 11,             'SYSIBM' => 11, 'SYSPROC' => 11,
             'SYSTEM' =>  8,        'SYSTEM_USER' =>  6, 'TABLE' =>  2,
             'TABLES' => 10,        'TABLESAMPLE' =>  8, 'TABLESPACE' => 11,
          'TEMPORARY' =>  5,         'TERMINATED' => 10, 'TEXTSIZE' => 12,
               'THEN' =>  6,               'TIME' =>  6, 'TIMESTAMP' =>  6,
      'TIMEZONE_HOUR' =>  6,    'TIMEZONE_MINUTE' =>  6, 'TINYBLOB' => 10,
            'TINYINT' => 10,           'TINYTEXT' => 10, 'TO' =>  2,
                'TOP' => 12,           'TRAILING' =>  6, 'TRAN' => 12,
        'TRANSACTION' =>  5,          'TRANSLATE' =>  6, 'TRANSLATION' =>  6,
              'TREAT' =>  7,            'TRIGGER' =>  7, 'TRIM' =>  6,
               'TRUE' =>  6,           'TRUNCATE' => 12, 'TSEQUAL' => 12,
               'TYPE' => 11,              'TYPES' => 10, 'UESCAPE' =>  8,
                'UID' => 13,              'UNION' =>  2, 'UNIQUE' =>  2,
            'UNKNOWN' =>  6,             'UNLOCK' => 10, 'UNNEST' =>  7,
           'UNSIGNED' => 10,              'UNTIL' => 11, 'UPDATE' =>  2,
         'UPDATETEXT' => 12,              'UPPER' =>  6, 'USAGE' =>  5,
                'USE' => 10,               'USER' =>  2, 'USING' =>  6,
           'UTC_DATE' => 10,           'UTC_TIME' => 10, 'UTC_TIMESTAMP' => 10,
           'VALIDATE' => 13,          'VALIDPROC' => 11, 'VALUE' =>  6,
             'VALUES' =>  2,            'VAR_POP' =>  8, 'VAR_SAMP' =>  8,
          'VARBINARY' => 10,            'VARCHAR' =>  6, 'VARCHAR2' => 13,
       'VARCHARACTER' => 10,           'VARIABLE' => 11, 'VARIANT' => 11,
            'VARYING' =>  6,               'VCAT' => 11, 'VIEW' =>  9,
            'VOLUMES' => 11,            'WAITFOR' => 12, 'WARNINGS' => 10,
               'WHEN' =>  6,           'WHENEVER' =>  2, 'WHERE' =>  2,
              'WHILE' => 12,       'WIDTH_BUCKET' =>  8, 'WINDOW' =>  8,
               'WITH' =>  2,             'WITHIN' =>  8, 'WITHOUT' =>  7,
                'WLM' => 11,               'WORK' =>  9, 'WRITE' =>  5,
          'WRITETEXT' => 12,                'XOR' => 10, 'YEAR' =>  6,
         'YEAR_MONTH' => 10,              'YEARS' => 11, 'ZEROFILL' => 10,
               'ZONE' =>  5
);


  safe_query("drop table crash_me10 $drop_attr");

  foreach my $keyword (sort {$a cmp $b} keys %reserved_words)
  {
    $keyword_type= $reserved_words{$keyword};

    $prompt= "Keyword ".$keyword;
    $config=  $keywords_ext[$keyword_type]."_"."reserved_word_".lc($keyword);

    report_fail($prompt,$config,
      "create table crash_me10 ($keyword int not null)",
      "drop table crash_me10 $drop_attr"
    );
  }
}

#
# Do a query on a query package object.
#

sub limit_query
{
  my($object,$limit)=@_;
  my ($query,$result,$retry,$sth);

  $query=$object->query($limit);
  $result=safe_query($query);
  if (!$result)
  {
    $object->cleanup();
    return 0;
  }
  if (defined($query=$object->check_query()))
  {
    for ($retry=0 ; $retry < $retry_limit ; $retry++)
    {
      printf "query2: %-80.80s\n",$query if ($opt_log_all_queries);
      print LOG "$query;\n" if ($opt_log);
      if (($sth= $dbh->prepare($query)))
      {
	if ($sth->execute)
	{
	  $result= $object->check($sth);
	  $sth->finish;
	  $object->cleanup();
	  return $result;
	}
	print_query($query);
	$sth->finish;
      }
      else
      {
	print_query($query);
      }
      $retry=100 if (!$server->abort_if_fatal_error()); # No need to continue
      if ($retry == $retry_limit-2)
      {
	print "Forcing discoennect to retry query\n" if ($opt_debug);
	$dbh->disconnect || warn $dbh->errstr;
      }
      check_connect($object);   # Check that server is still up
    }
    $result=0;                  # Query failed
  }
  $object->cleanup();
  return $result;               # Server couldn't handle the query
}


sub report
{
  my ($prompt,$limit,@queries)=@_;
  print "$prompt: ";
  if (!defined($limits{$limit}))
  {
    my $queries_result = safe_query(\@queries);
    add_log($limit, $safe_query_log);
    my $report_result;
    if ( $queries_result) {
      $report_result= "yes";
      add_log($limit,"All statements returned OK, feature supported");
    } else {
      $report_result= "no";
      add_log($limit,"Some statements did not return OK, feature not wholly supported");
    } 
    save_config_data($limit,$report_result,$prompt);
  }
  print "$limits{$limit}\n";
  return $limits{$limit} ne "no";
}

sub report_fail
{
  my ($prompt,$limit,@queries)=@_;
  print "$prompt: ";
  if (!defined($limits{$limit}))
  {
    my $queries_result = safe_query(\@queries);
    add_log($limit, $safe_query_log);
    my $report_result;
    if ( $queries_result) {
      $report_result= "no";
      add_log($limit,"Errors not correctly returned; feature not wholly supported");
    } else {
      $report_result= "yes";
      add_log($limit,"Statements correctly rejected, feature supported");
    } 
    save_config_data($limit,$report_result,$prompt);
  }
  print "$limits{$limit}\n";
  return $limits{$limit} ne "no";
}


# Return true if one of the queries is ok

sub report_one
{
  my ($prompt,$limit,$queries)=@_;
  my ($query,$res,$result);
  print "$prompt: ";
  if (!defined($limits{$limit}))
  {
    save_incomplete($limit,$prompt);
    $result="no";
    foreach $query (@$queries)
    {
      if (safe_query_l($limit,$query->[0]))
      {
	$result= $query->[1];
	last;
      }
    }
    save_config_data($limit,$result,$prompt);
  }
  print "$limits{$limit}\n";
  return $limits{$limit} ne "no";
}


# Execute query and save result as limit value.

sub report_result
{
  my ($prompt,$limit,$query)=@_;
  my($error);
  print "$prompt: ";
  if (!defined($limits{$limit}))
  {
    save_incomplete($limit,$prompt);
    $error=safe_query_result($query,"1",2);
    add_log($limit,$safe_query_result_log);
    save_config_data($limit,$error ? "not supported" :$last_result,$prompt);
  }
  print "$limits{$limit}\n";
  return $limits{$limit} ne "not supported";
}

sub report_trans
{
  my ($limit,$metadata,$queries,$check,$clear)=@_;
  if (!defined($limits{$limit}))
  {
    save_incomplete($limit,$prompt);
    eval {undef($dbh->{AutoCommit})};
    add_log($limit," switch off autocommit");
    if (!$@)
    {
      if (! safe_query_l($limit,\@$metadata))
      {
         add_log($limit,"Couldnt create tables ?? ");
         save_config_data($limit,"no",$limit);
      }  else {
        $dbh->commit;
        if (safe_query_l($limit,\@$queries))
        {
	    $dbh->rollback;
	    add_log($limit," rollback"); 
            $dbh->{AutoCommit} = 1;
            if ( safe_query_result_l($limit,$check,"",8) eq  0 ) {
	        save_config_data($limit,"yes",$limit);
	      } else {
	        save_config_data($limit,"no",$limit);
  	      }
#	    safe_query_l($limit,$clear);
        } else {
          save_config_data($limit,"error",$limit);
        }
      }
      $dbh->{AutoCommit} = 1;
    }
    else
    {
      add_log($limit,"Couldnt undef autocommit ?? ");
      save_config_data($limit,"no",$limit);
    }
    safe_query_l($limit,$clear);
  }
  return $limits{$limit} ne "yes";
}

sub report_rollback
{
  my ($limit,$queries,$check,$clear)=@_;
  if (!defined($limits{$limit}))
  {
    save_incomplete($limit,$prompt);
    eval {undef($dbh->{AutoCommit})};
    add_log($limit," switch off autocommit");
    if (!$@)
    {
      if (safe_query_l($limit,\@$queries))
      {
	  $dbh->rollback;
	  add_log($limit," rollback");
           $dbh->{AutoCommit} = 1;
           if (safe_query_l($limit,$check)) {
	      save_config_data($limit,"no",$limit);
	    }  else  {
	      save_config_data($limit,"yes",$limit);
	    };
	    safe_query_l($limit,$clear);
      } else {
        save_config_data($limit,"error",$limit);
      }
    }
    else
    {
      add_log($limit,'Couldnt undef Autocommit??');
      save_config_data($limit,"error",$limit);
    }
    safe_query_l($limit,$clear);
  }
  $dbh->{AutoCommit} = 1;
  return $limits{$limit} ne "yes";
}


sub check_and_report
{
  my ($prompt,$limit,$pre,$query,$post,$answer,$string_type,$skip_prompt,
      $function)=@_;
  my ($tmp);
  $function=0 if (!defined($function));

  print "$prompt: " if (!defined($skip_prompt));
  if (!defined($limits{$limit}))
  {
    save_incomplete($limit,$prompt);
    $tmp=1-safe_query(\@$pre);
    add_log($limit,$safe_query_log);
    if (!$tmp) 
    {
        $tmp=safe_query_result($query,$answer,$string_type) ;
        add_log($limit,$safe_query_result_log);
    };	
    safe_query(\@$post);
    add_log($limit,$safe_query_log);
    delete $limits{$limit};
    if ($function == 3)		# Report error as 'no'.
    {
      $function=0;
      $tmp= -$tmp;
    }
    if ($function == 0 ||
	$tmp != 0 && $function == 1 ||
	$tmp == 0 && $function== 2)
    {
      save_config_data($limit, $tmp == 0 ? "yes" : $tmp == 1 ? "no" : "error",
		       $prompt);
      print "$limits{$limit}\n";
      return $function == 0 ? $limits{$limit} eq "yes" : 0;
    }
    return 1;			# more things to check
  }
  print "$limits{$limit}\n";
  return 0 if ($function);
  return $limits{$limit} eq "yes";
}


sub try_and_report
{
  my ($prompt,$limit,@tests)=@_;
  my ($tmp,$test,$type);

  print "$prompt: ";

  if (!defined($limits{$limit}))
  {
    save_incomplete($limit,$prompt);
    $type="no";			# Not supported
    foreach $test (@tests)
    {
      my $tmp_type= shift(@$test);
      if (safe_query_l($limit,\@$test))
      {
	$type=$tmp_type;
	goto outer;
      }
    }
  outer:
    save_config_data($limit, $type, $prompt);
  }
  print "$limits{$limit}\n";
  return $limits{$limit} ne "no";
}

#
# Just execute the query and check values;  Returns 1 if ok
#

sub execute_and_check
{
  my ($key,$pre,$query,$post,$answer,$string_type)=@_;
  my ($tmp);

  $tmp=safe_query_l($key,\@$pre);

  $tmp=safe_query_result_l($key,$query,$answer,$string_type) == 0 if ($tmp);
  safe_query_l($key,\@$post);
  return $tmp;
}


# returns 0 if ok, 1 if error, -1 if wrong answer
# Sets $last_result to value of query
sub safe_query_result_l{
  my ($key,$query,$answer,$result_type)=@_;
  my $r = safe_query_result($query,$answer,$result_type);
  add_log($key,$safe_query_result_log);
  return $r;
}  

sub safe_query_result
{
# result type can be 
#  8 (must be empty), 2 (Any value), 0 (number)
#  1 (char, endspaces can differ), 3 (exact char), 4 (NULL)
#  5 (char with prefix), 6 (exact, errors are ignored)
#  7 (array of numbers)
  my ($query,$answer,$result_type)=@_;
  my ($sth,$row,$result,$retry);
  undef($last_result);
  $safe_query_result_log="";
  
  printf "\nquery3: %-80.80s\n",$query  if ($opt_log_all_queries);
  print LOG "$query;\n" if ($opt_log);
  $safe_query_result_log="<".$query."\n";

  for ($retry=0; $retry < $retry_limit ; $retry++)
  {
    if (!($sth=$dbh->prepare($query)))
    {
      print_query($query);
      $safe_query_result_log .= "> prepare failed:".$dbh->errstr."\n";
      
      if ($server->abort_if_fatal_error())
      {
	check_connect();	# Check that server is still up
	next;			# Retry again
      }
      check_connect();		# Check that server is still up
      return 1;
    }
    if (!$sth->execute)
    {
      print_query($query);
      $safe_query_result_log .= "> execute failed:".$dbh->errstr."\n";
      if ($server->abort_if_fatal_error())
      {
	check_connect();	# Check that server is still up
	next;			# Retry again
      }
      check_connect();		# Check that server is still up
      return 1;
    }
    else
    {
      last;
    }
  }
  if (!($row=$sth->fetchrow_arrayref))
  {
    print "\nquery: $query didn't return any result\n" if ($opt_debug);
    $safe_query_result_log .= "> didn't return any result:".$dbh->errstr."\n";    
    $sth->finish;
    return ($result_type == 8) ? 0 : 1;
  }
  if ($result_type == 8)
  {
    
    $safe_query_result_log .= "> resultset must be empty, but it contains some data (".$row->[0].")\n";    
    $sth->finish;
    return 1;
  }
  $result=0;                  	# Ok
  $last_result= $row->[0];	# Save for report_result;
  $safe_query_result_log .= ">".$last_result."\n";    
  # Note:
  # if ($result_type == 2)        We accept any return value as answer

  if ($result_type == 0)	# Compare numbers
  {
    $row->[0] =~ s/,/./;	# Fix if ',' is used instead of '.'
    if ($row->[0] != $answer && (abs($row->[0]- $answer)/
				 (abs($row->[0]) + abs($answer))) > 0.01)
    {
      $result=-1;
      $safe_query_result_log .= 
          "We expected '$answer' but got '$last_result' \n";    
    }
  }
  elsif ($result_type == 1)	# Compare where end space may differ
  {
    $row->[0] =~ s/\s+$//;
    if ($row->[0] ne $answer)
    {
     $result=-1;
     $safe_query_result_log .= 
         "We expected '$answer' but got '$last_result' \n";    
    } ;
  }
  elsif ($result_type == 3)	# This should be a exact match
  {
     if ($row->[0] ne $answer)
     { 
      $result= -1; 
      $safe_query_result_log .= 
          "We expected '$answer' but got '$last_result' \n";    
    };
  }
  elsif ($result_type == 4)	# If results should be NULL
  {
    if (defined($row->[0]))
    { 
     $result= -1; 
     $safe_query_result_log .= 
         "We expected NULL but got '$last_result' \n";    
    };
  }
  elsif ($result_type == 5)	# Result should have given prefix
  {
     if (length($row->[0]) < length($answer) &&
		    substr($row->[0],1,length($answer)) ne $answer)
     { 
      $result= -1 ;
      $safe_query_result_log .= 
        "Result must have prefix '$answer', but  '$last_result' \n";    
     };
  }
  elsif ($result_type == 6)	# Exact match but ignore errors
  {
    if ($row->[0] ne $answer)    
    { $result= 1;
      $safe_query_result_log .= 
          "We expected '$answer' but got '$last_result' \n";    
    } ;
  }
  elsif ($result_type == 7)	# Compare against array of numbers
  {
    if ($row->[0] != $answer->[0])
    {
      $safe_query_result_log .= "must be '$answer->[0]' \n";    
      $result= -1;
    }
    else
    {
      my ($value);
      shift @$answer;
      while (($row=$sth->fetchrow_arrayref))
      {
       $safe_query_result_log .= ">$row\n";    

	$value=shift(@$answer);
	if (!defined($value))
	{
	  print "\nquery: $query returned to many results\n"
	    if ($opt_debug);
          $safe_query_result_log .= "It returned to many results \n";    	    
	  $result= 1;
	  last;
	}
	if ($row->[0] != $value)
	{
          $safe_query_result_log .= "Must return $value here \n";    	    
	  $result= -1;
	  last;
	}
      }
      if ($#$answer != -1)
      {
	print "\nquery: $query returned too few results\n"
	  if ($opt_debug);
        $safe_query_result_log .= "It returned too few results \n";    	    
	$result= 1;
      }
    }
  }
  $sth->finish;
  print "\nquery: '$query' returned '$row->[0]' instead of '$answer'\n"
    if ($opt_debug && $result && $result_type != 7);
  return $result;
}

#
# Find limit using binary search.  This is a weighed binary search that
# will prefere lower limits to get the server to crash as 
# few times as possible


sub find_limit()
{
  my ($prompt,$limit,$query)=@_;
  my ($first,$end,$i,$tmp,@tmp_array, $queries);
  print "$prompt: ";
  if (defined($end=$limits{$limit}))
  {
    print "$end (cache)\n";
    return $end;
  }
  save_incomplete($limit,$prompt);
  add_log($limit,"We are trying (example with N=5):");
  $queries = $query->query(5);
  if (ref($queries) ne "ARRAY")
  {
    push(@tmp_array,$queries);
    $queries= \@tmp_array;
  }
  foreach $tmp (@$queries)
  {   add_log($limit,repr_query($tmp));  }    

  if (defined($queries = $query->check_query()))
  { 
    if (ref($queries) ne "ARRAY")
    {
      @tmp_array=();
      push(@tmp_array,$queries); 
      $queries= \@tmp_array;
    }
    foreach $tmp (@$queries)
      {   add_log($limit,repr_query($tmp));  }    
  }
  if (defined($query->{'init'}) && !defined($end=$limits{'restart'}{'tohigh'}))
  {
    if (!safe_query_l($limit,$query->{'init'}))
    {
      $query->cleanup();
      return "error";
    }
  }

  if (!limit_query($query,1))           # This must work
  {
    print "\nMaybe fatal error: Can't check '$prompt' for limit=1\n".
    "error: $last_error\n";
    return "error";
  }

  $first=0;
  $first=$limits{'restart'}{'low'} if ($limits{'restart'}{'low'});

  if (defined($end=$limits{'restart'}{'tohigh'}))
  {
    $end--;
    print "\nRestarting this with low limit: $first and high limit: $end\n";
    delete $limits{'restart'};
    $i=$first+int(($end-$first+4)/5);           # Prefere lower on errors
  }
  else
  {
    $end= $query->max_limit();
    $i=int(($end+$first)/2);
  }
  my $log_str = "";
  unless(limit_query($query,0+$end)) {
    while ($first < $end)
    {
      print "." if ($opt_debug);
      save_config_data("restart",$i,"") if ($opt_restart);
      if (limit_query($query,$i))
      {
        $first=$i;
	$log_str .= " $i:OK";
        $i=$first+int(($end-$first+1)/2); # to be a bit faster to go up
      }
      else
      { 
        $end=$i-1;
	$log_str .= " $i:FAIL";
        $i=$first+int(($end-$first+4)/5); # Prefere lower on errors
      }
    }
  }
  $end+=$query->{'offset'} if ($end && defined($query->{'offset'}));
  if ($end >= $query->{'max_limit'} &&
      substr($query->{'max_limit'},0,1) eq '+')
  {
    $end= $query->{'max_limit'};
  }
  print "$end\n";
  add_log($limit,$log_str);
  save_config_data($limit,$end,$prompt);
  delete $limits{'restart'};
  return $end;
}

#
# Check that the query works!
#

sub assert
{
  my($query)=@_;

  if (!safe_query($query))
  {
    $query=join("; ",@$query) if (ref($query) eq "ARRAY");
    print "\nFatal error:\nquery: '$query'\nerror: $DBI::errstr\n";
    exit 1;
  }
}


sub read_config_data
{
  my ($key,$limit,$prompt);
  if (-e $opt_config_file)
  {
    open(CONFIG_FILE,"+<$opt_config_file") ||
      die "Can't open configure file $opt_config_file\n";
    print "Reading old values from cache: $opt_config_file\n";
  }
  else
  {
    open(CONFIG_FILE,"+>>$opt_config_file") ||
      die "Can't create configure file $opt_config_file: $!\n";
  }
  select CONFIG_FILE;
  $|=1;
  select STDOUT;
  while (<CONFIG_FILE>)
  {
    chomp;
    if (/^(\S+)=([^\#]*[^\#\s])\s*(\# .*)*$/)
    {
      $key=$1; $limit=$2 ; $prompt=$3;
      if (!$opt_quick || $limit =~ /\d/ || $key =~ /crash_me/)
      {
	if ($key !~ /restart/i)
	{
	  $limits{$key}=$limit eq "null"? undef : $limit;
	  $prompts{$key}=length($prompt) ? substr($prompt,2) : "";
	  $last_read=$key;
	  delete $limits{'restart'};
	}
	else
	{
	  $limit_changed=1;
	  if ($limit > $limits{'restart'}{'tohigh'})
	  {
	    $limits{'restart'}{'low'} = $limits{'restart'}{'tohigh'};
	  }
	  $limits{'restart'}{'tohigh'} = $limit;
	}
      }
    }
    elsif (/\s*###(.*)$/)    # log line
    {
       # add log line for previously read key
       $log{$last_read} .= "$1\n";
    }
    elsif (!/^\s*$/ && !/^\#/)
    {
      die "Wrong config row: $_\n";
    }
  }
}


sub save_config_data
{
  my ($key,$limit,$prompt)=@_;
  $prompts{$key}=$prompt;
  return if (defined($limits{$key}) && $limits{$key} eq $limit);
  if (!defined($limit) || $limit eq "")
  {
#    die "Undefined limit for $key\n";
     $limit = 'null'; 
  }
  print CONFIG_FILE "$key=$limit\t# $prompt\n";
  $limits{$key}=$limit;
  $limit_changed=1;
# now write log lines (immediatelly after limits)
  my $line;
  my $last_line_was_empty=0;
  foreach $line (split /\n/, $log{$key})
  {
    print CONFIG_FILE "   ###$line\n" 
	unless ( ($last_line_was_empty eq 1)  
	         && ($line =~ /^\s+$/)  );
    $last_line_was_empty= ($line =~ /^\s+$/)?1:0;
  };     

  if (($opt_restart && $limits{'operating_system'} =~ /windows/i) ||
		       ($limits{'operating_system'} =~ /NT/))
  {
    # If perl crashes in windows, everything is lost (Wonder why? :)
    close CONFIG_FILE;
    open(CONFIG_FILE,"+>>$opt_config_file") ||
      die "Can't reopen configure file $opt_config_file: $!\n";
  }
}

sub add_log
{
  my $key = shift;
  my $line = shift;
  $log{$key} .= $line . "\n" if ($opt_verbose);;  
}

sub save_all_config_data
{
  my ($key,$tmp);
  close CONFIG_FILE;
  return if (!$limit_changed);
  open(CONFIG_FILE,">$opt_config_file") ||
    die "Can't create configure file $opt_config_file: $!\n";
  select CONFIG_FILE;
  $|=1;
  select STDOUT;
  delete $limits{'restart'};

  print CONFIG_FILE 
       "#This file is automaticly generated by crash-me $version\n\n";
  foreach $key (sort keys %limits)
  {
    $tmp="$key=$limits{$key}";
    print CONFIG_FILE $tmp . ("\t" x (int((32-min(length($tmp),32)+7)/8)+1)) .
      "# $prompts{$key}\n";
     my $line;
     my $last_line_was_empty=0;
     foreach $line (split /\n/, $log{$key})
     {
        print CONFIG_FILE "   ###$line\n" unless 
	      ( ($last_line_was_empty eq 1) && ($line =~ /^\s*$/));
        $last_line_was_empty= ($line =~ /^\s*$/)?1:0;
     };     
  }
  close CONFIG_FILE;
}

#
# Save 'incomplete' in the limits file to be able to continue if
# crash-me dies because of a bug in perl/DBI

sub save_incomplete
{
  my ($limit,$prompt)= @_;
  save_config_data($limit,"incompleted",$prompt) if ($opt_restart);
}


sub check_repeat
{
  my ($sth,$limit)=@_;
  my ($row);

  return 0 if (!($row=$sth->fetchrow_arrayref));
  return (defined($row->[0]) && ('a' x $limit) eq $row->[0]) ? 1 : 0;
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

sub sql_concat
{
  my ($a,$b)= @_;
  return "$a || $b" if ($limits{'func_sql_concat_as_||'} eq 'yes');
  return "concat($a,$b)" if ($limits{'func_odbc_concat'} eq 'yes');
  return "$a + $b" if ($limits{'func_extra_concat_as_+'} eq 'yes');
  return undef;
}

#
# Returns a list of statements to create a table in a portable manner
# but still utilizing features in the databases.
#

sub create_table
{
  my($table_name,$fields,$index,$extra) = @_;
  my($query,$nr,$parts,@queries,@index);

  $extra="" if (!defined($extra));

  $query="create table $table_name (";
  $nr=0;
  foreach $field (@$fields)
  {
    $query.= $field . ',';
  }
  foreach $index (@$index)
  {
    $index =~ /\(([^\(]*)\)$/i;
    $parts=$1;
    if ($index =~ /^primary key/)
    {
      if ($limits{'primary_key_in_create'} eq 'yes')
      {
	$query.= $index . ',';
      }
      else
      {
	push(@queries,
	     "create unique index ${table_name}_prim on $table_name ($parts)");
      }
    }
    elsif ($index =~ /^unique/)
    {
      if ($limits{'unique_in_create'} eq 'yes')
      {
	$query.= "unique ($parts),";
      }
      else
      {
	$nr++;
	push(@queries,
	     "create unique index ${table_name}_$nr on $table_name ($parts)");

      }
    }
    else
    {
      if ($limits{'index_in_create'} eq 'yes')
      {
	$query.= "index ($parts),";
      }
      else
      {
	$nr++;
	push(@queries,
	     "create index ${table_name}_$nr on $table_name ($1)");
      }
    }
  }
  chop($query);
  $query.= ") $extra";
  unshift(@queries,$query);
  return @queries;
}


#
# This is used by some query packages to change:
# %d -> limit
# %s -> 'a' x limit
# %v -> "1,1,1,1,1" where there are 'limit' number of ones
# %f -> q1,q2,q3....
# %F -> q1 integer,q2 integer,q3 integer....

sub fix_query
{
  my ($query,$limit)=@_;
  my ($repeat,$i);

  return $query if !(defined($query));
  $query =~ s/%d/$limit/g;
  if ($query =~ /%s/)
  {
    $repeat= 'a' x $limit;
    $query =~ s/%s/$repeat/g;
  }
  if ($query =~ /%v/)
  {
    $repeat= '1,' x $limit;
    chop($repeat);
    $query =~ s/%v/$repeat/g;
  }
  if ($query =~ /%f/)
  {
    $repeat="";
    for ($i=1 ; $i <= $limit ; $i++)
    {
      $repeat.="q$i,";
    }
    chop($repeat);
    $query =~ s/%f/$repeat/g;
  }
  if ($query =~ /%F/)
  {
    $repeat="";
    for ($i=1 ; $i <= $limit ; $i++)
    {
      $repeat.="q$i integer,";
    }
    chop($repeat);
    $query =~ s/%F/$repeat/g;
  }
  return $query;
}


#
# Different query packages
#

package query_repeat;

sub new
{
  my ($type,$init,$query,$add1,$add_mid,$add,$add_end,$end_query,$cleanup,
      $max_limit, $check, $offset)=@_;
  my $self={};
  if (defined($init) && $#$init != -1)
  {
    $self->{'init'}=$init;
  }
  $self->{'query'}=$query;
  $self->{'add1'}=$add1;
  $self->{'add_mid'}=$add_mid;
  $self->{'add'}=$add;
  $self->{'add_end'}=$add_end;
  $self->{'end_query'}=$end_query;
  $self->{'cleanup'}=$cleanup;
  $self->{'max_limit'}=(defined($max_limit) ? $max_limit : $main::query_size);
  $self->{'check'}=$check;
  $self->{'offset'}=$offset;
  $self->{'printf'}= ($add =~ /%d/);
  bless $self;
}

sub query
{
  my ($self,$limit)=@_;
  if (!$self->{'printf'})
  {
    return $self->{'query'} . ($self->{'add'} x $limit) .
      ($self->{'add_end'} x $limit) . $self->{'end_query'};
  }
  my ($tmp,$tmp2,$tmp3,$i);
  $tmp=$self->{'query'};
  if ($self->{'add1'})
  {
    for ($i=0; $i < $limit ; $i++)
    {
      $tmp3 = $self->{'add1'};
      $tmp3 =~ s/%d/$i/g;
      $tmp  .= $tmp3;
    }
  }
  $tmp .= " ".$self->{'add_mid'};
  if ($self->{'add'})
  {
    for ($i=0; $i < $limit ; $i++)
    {
      $tmp2 = $self->{'add'};
      $tmp2 =~ s/%d/$i/g;
      $tmp  .= $tmp2;
    }
  }
  return ($tmp .
	  ($self->{'add_end'} x $limit) . $self->{'end_query'});
}

sub max_limit
{
  my ($self)=@_;
  my $tmp;
  $tmp=int(($main::limits{"query_size"}-length($self->{'query'})
	    -length($self->{'add_mid'})-length($self->{'end_query'}))/
	   (length($self->{'add1'})+
	   length($self->{'add'})+length($self->{'add_end'})));
  return main::min($self->{'max_limit'},$tmp);
}


sub cleanup
{
  my ($self)=@_;
  my($tmp,$statement);
  $tmp=$self->{'cleanup'};
  foreach $statement (@$tmp)
  {
    main::safe_query($statement) if (defined($statement) && length($statement));
  }
}

sub check
{
  my ($self,$sth)=@_;
  my $check=$self->{'check'};
  return &$check($sth,$self->{'limit'}) if (defined($check));
  return 1;
}

sub check_query
{
  return undef;
}


package query_num;

sub new
{
  my ($type,$query,$end_query,$cleanup,$max_limit,$check)=@_;
  my $self={};
  $self->{'query'}=$query;
  $self->{'end_query'}=$end_query;
  $self->{'cleanup'}=$cleanup;
  $self->{'max_limit'}=$max_limit;
  $self->{'check'}=$check;
  bless $self;
}

sub query
{
  my ($self,$i)=@_;
  $self->{'limit'}=$i;
  return "$self->{'query'}$i$self->{'end_query'}";
}

sub max_limit
{
  my ($self)=@_;
  return $self->{'max_limit'};
}

sub cleanup
{
  my ($self)=@_;
  my($statement);
  foreach $statement ($self->{'$cleanup'})
  {
    main::safe_query($statement) if (defined($statement) && length($statement));
  }
}


sub check
{
  my ($self,$sth)=@_;
  my $check=$self->{'check'};
  return &$check($sth,$self->{'limit'}) if (defined($check));
  return 1;
}

sub check_query
{
  return undef;
}

#
# This package is used when testing CREATE TABLE!
#

package query_table;

sub new
{
  my ($type,$query, $add, $end_query, $extra_init, $safe_query, $check,
      $cleanup, $max_limit, $offset)=@_;
  my $self={};
  $self->{'query'}=$query;
  $self->{'add'}=$add;
  $self->{'end_query'}=$end_query;
  $self->{'extra_init'}=$extra_init;
  $self->{'safe_query'}=$safe_query;
  $self->{'check'}=$check;
  $self->{'cleanup'}=$cleanup;
  $self->{'max_limit'}=$max_limit;
  $self->{'offset'}=$offset;
  bless $self;
}


sub query
{
  my ($self,$limit)=@_;
  $self->{'limit'}=$limit;
  $self->cleanup();     # Drop table before create

  my ($tmp,$tmp2,$i,$query,@res);
  $tmp =$self->{'query'};
  $tmp =~ s/%d/$limit/g;
  for ($i=1; $i <= $limit ; $i++)
  {
    $tmp2 = $self->{'add'};
    $tmp2 =~ s/%d/$i/g;
    $tmp  .= $tmp2;
  }
  push(@res,$tmp . $self->{'end_query'});
  $tmp=$self->{'extra_init'};
  foreach $query (@$tmp)
  {
    push(@res,main::fix_query($query,$limit));
  }
  return \@res;
}


sub max_limit
{
  my ($self)=@_;
  return $self->{'max_limit'};
}


sub check_query
{
  my ($self)=@_;
  return main::fix_query($self->{'safe_query'},$self->{'limit'});
}

sub check
{
  my ($self,$sth)=@_;
  my $check=$self->{'check'};
  return 0 if (!($row=$sth->fetchrow_arrayref));
  if (defined($check))
  {
    return (defined($row->[0]) &&
	    $row->[0] eq main::fix_query($check,$self->{'limit'})) ? 1 : 0;
  }
  return 1;
}


# Remove table before and after create table query

sub cleanup()
{
  my ($self)=@_;
  main::safe_query(main::fix_query($self->{'cleanup'},$self->{'limit'}));
}

#
# Package to do many queries with %d, and %s substitution
#

package query_many;

sub new
{
  my ($type,$query,$safe_query,$check_result,$cleanup,$max_limit,$offset,
      $safe_cleanup)=@_;
  my $self={};
  $self->{'query'}=$query;
  $self->{'safe_query'}=$safe_query;
  $self->{'check'}=$check_result;
  $self->{'cleanup'}=$cleanup;
  $self->{'max_limit'}=$max_limit;
  $self->{'offset'}=$offset;
  $self->{'safe_cleanup'}=$safe_cleanup;
  bless $self;
}


sub query
{
  my ($self,$limit)=@_;
  my ($queries,$query,@res);
  $self->{'limit'}=$limit;
  $self->cleanup() if (defined($self->{'safe_cleanup'}));
  $queries=$self->{'query'};
  foreach $query (@$queries)
  {
    push(@res,main::fix_query($query,$limit));
  }
  return \@res;
}

sub check_query
{
  my ($self)=@_;
  return main::fix_query($self->{'safe_query'},$self->{'limit'});
}

sub cleanup
{
  my ($self)=@_;
  my($tmp,$statement);
  return if (!defined($self->{'cleanup'}));
  $tmp=$self->{'cleanup'};
  foreach $statement (@$tmp)
  {
    if (defined($statement) && length($statement))
    {
      main::safe_query(main::fix_query($statement,$self->{'limit'}));
    }
  }
}


sub check
{
  my ($self,$sth)=@_;
  my ($check,$row);
  return 0 if (!($row=$sth->fetchrow_arrayref));
  $check=$self->{'check'};
  if (defined($check))
  {
    return (defined($row->[0]) &&
	    $row->[0] eq main::fix_query($check,$self->{'limit'})) ? 1 : 0;
  }
  return 1;
}

sub max_limit
{
  my ($self)=@_;
  return $self->{'max_limit'};
}

#
# Used to find max supported row length
#

package query_row_length;

sub new
{
  my ($type,$create,$null,$drop,$max_limit)=@_;
  my $self={};
  $self->{'table_name'}=$create;
  $self->{'null'}=$null;
  $self->{'cleanup'}=$drop;
  $self->{'max_limit'}=$max_limit;
  bless $self;
}


sub query
{
  my ($self,$limit)=@_;
  my ($res,$values,$size,$length,$i);
  $self->{'limit'}=$limit;

  $res="";
  $size=main::min($main::limits{'max_char_size'},255);
  $size = 255 if (!$size); # Safety
  for ($length=$i=0; $length + $size <= $limit ; $length+=$size, $i++)
  {
    $res.= "q$i char($size) $self->{'null'},";
    $values.="'" . ('a' x $size) . "',";
  }
  if ($length < $limit)
  {
    $size=$limit-$length;
    $res.= "q$i char($size) $self->{'null'},";
    $values.="'" . ('a' x $size) . "',";
  }
  chop($res);
  chop($values);
  return ["create table " . $self->{'table_name'} . " ($res)",
	  "insert into " . $self->{'table_name'} . " values ($values)"];
}

sub max_limit
{
  my ($self)=@_;
  return $self->{'max_limit'};
}

sub cleanup
{
  my ($self)=@_;
  main::safe_query($self->{'cleanup'});
}


sub check
{
  return 1;
}

sub check_query
{
  return undef;
}

#
# Used to find max supported index length
#

package query_index_length;

sub new
{
  my ($type,$create,$drop,$max_limit)=@_;
  my $self={};
  $self->{'create'}=$create;
  $self->{'cleanup'}=$drop;
  $self->{'max_limit'}=$max_limit;
  bless $self;
}


sub query
{
  my ($self,$limit)=@_;
  my ($res,$size,$length,$i,$parts,$values);
  $self->{'limit'}=$limit;

  $res=$parts=$values="";
  $size=main::min($main::limits{'max_index_part_length'},
       $main::limits{'max_char_size'});
  $size=1 if ($size == 0);	# Avoid infinite loop errors
  for ($length=$i=0; $length + $size <= $limit ; $length+=$size, $i++)
  {
    $res.= "q$i char($size) not null,";
    $parts.= "q$i,";
    $values.= "'" . ('a' x $size) . "',";
  }
  if ($length < $limit)
  {
    $size=$limit-$length;
    $res.= "q$i char($size) not null,";
    $parts.="q$i,";
    $values.= "'" . ('a' x $size) . "',";
  }
  chop($parts);
  chop($res);
  chop($values);
  if ($main::limits{'unique_in_create'} eq 'yes')
  {
    return [$self->{'create'} . "($res,unique ($parts))",
	    "insert into crash_q values($values)"];
  }
  return [$self->{'create'} . "($res)",
	  "create index crash_q_index on crash_q ($parts)",
	  "insert into crash_q values($values)"];
}

sub max_limit
{
  my ($self)=@_;
  return $self->{'max_limit'};
}

sub cleanup
{
  my ($self)=@_;
  main::safe_query($self->{'cleanup'});
}


sub check
{
  return 1;
}

sub check_query
{
  return undef;
}



### TODO:
# OID test instead of / in addition to _rowid
