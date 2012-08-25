#!/usr/bin/perl 

use Data::Dumper; 
use Getopt::Long;

$opt_server_id="";
$opt_skip_avg=0;
$opt_report_mode="summary";
$opt_mix_analyzer=$opt_fs=$opt_hw="";
$opt_verbose="";
$opt_time=$opt_bg_time="";
$opt_skip_res_info=1;

%TEST_TYPES=();
@BASEDIRS=();
@include_ids=();
@merge_ids=();
@exclude_ids=();

GetOptions("server_id=s", "basedir=s" =>\@BASEDIRS,
           "report-mode=s", "gnuplot", "mix-analyzer=s",
           "fs=s","hw=s","time","bg-time","merge-id=s" =>\@merge_ids,
           "exclude-id=s" => \@exclude_ids, "id=s" => \@include_ids,
           "verbose", "test-type=s"=>\@TEST_TYPES)|| usage();
%data=();
%plot=();

@DIR=@ARGV;
@TEST_TYPES= split(/,/,join(',',@TEST_TYPES));

foreach $test_type (@TEST_TYPES)
{
  $TEST_TYPES{$test_type}=1;
}  

if (@BASEDIRS)
{
  foreach $basedir (@BASEDIRS)
  {
    opendir(DIR,$basedir);
    push (@BDIR,map { "$basedir/$_"  } grep {!/^\./} readdir(DIR));
    close(DIR);
  }
}

push (@DIR,@BDIR) if (@BDIR);


if (@DIR)
{
SERVER_ID:
  foreach $dir (sort {($a=~ /\#(\d+)-(.+)/)[1] <=> ($b=~/\#(\d+)-(.+)/)[1] } sort {$a cmp $b} @DIR)
  {
    if ($dir !~ /^\.\./ && -d $dir)
    {
      $cdir=`basename $dir`;
      chomp($cdir);
      $bdir=`dirname $dir`;
      chomp($bdir);

      %result=( server_id=>'', engine=>'', test_name=>'', threads=>'',
                result=>'', type=>'', comments=>'', hostname=>'');
      
      parse_results($dir,\%result);

      if ($opt_report_mode eq 'single')
      {
        $result{result}= ($result{result} ne '') ? $result{result} : "Result N/A";
        print $result{result},"\n";
        exit;
      }

      if (!keys (%TEST_TYPES) || defined($TEST_TYPES{$result{type}}))
      {
        if (!$result{server_id})
        {
          $result{server_id}= $opt_server_id ? $opt_server_id : "MySQL version ???";
        }

        if ($cdir=~ /#(\d+)-(.+)-/)
        {
          $server_id="";
          $result_set_id=$2;
          
          if (@include_ids)
          { 
            next SERVER_ID  unless ( grep { /\b$result_set_id\b/ } @include_ids);
          }
          
          next SERVER_ID  if (grep { /\b$result_set_id\b/ } @exclude_ids);
          
          foreach $merge_id (@merge_ids)
          {
            if ($merge_id =~/\b$result_set_id\b/)
            {
              $server_id="merged_".$merge_id;
            }
          }
          
          if ($server_id eq '')
          {
            $result{server_id}=$result{server_id}."_${result_set_id}_".$result{comments};
          }
          else
          {
            $result{server_id}=$result{server_id}."_${server_id}_";           
          }
        }

        if ($result{engine} eq '' || $result{test_name} eq '' || $result{threads} eq '')
        {
          push @bad_results,$dir;
        }
        else
        {

          if ($opt_report_mode eq 'bm')
          {
            $plot3{$result{type}}->{$result{hostname}}->{$result{test_name}}->
            {$result{server_id}}->{$result{engine}}->{$result{threads}}->{sum}+=$result{result};;

            $plot3{$result{type}}->{$result{hostname}}->{$result{test_name}}->
            {$result{server_id}}->{$result{engine}}->{$result{threads}}->{count}++;
          }
          else
          {
            push @{$plot{$result{type}}->{$result{test_name}}->
                   {$result{threads}}->{$result{server_id}}->{$result{engine}}->{data}
                  },$result{result};

            $key=$plot{$result{type}}->{$result{test_name}}->{$result{threads}}->{$result{server_id}}->{$result{engine}};
            $key2=$plot{$result{type}}->{$result{test_name}}->{$result{threads}};
            
            if (!exists($plot2{$result{type}}->{$result{test_name}}->{threads}->{$result{server_id}}->{$result{engine}}))
            {
              $plot2{$result{type}}->{$result{test_name}}->{threads}->{$result{server_id}}->{$result{engine}}=0;
            }

            if ($result{result} ne '')
            {
              $key->{summary}->{sum}+=$result{result};
              $key->{summary}->{count}++;
              $plot2{$result{type}}->{$result{test_name}}->{threads}->{$result{server_id}}->{$result{engine}}++;
            }
            $key->{summary}->{total}++;

            if (exists($key2->{max_row}))
            {
              if ($key2->{max_row} < $key->{summary}->{total})
              {
                 $key2->{max_row} = $key->{summary}->{total};
              }
            }
            else
            {
              $key2->{max_row}= $key->{summary}->{total};
            }
          }
        }
      }
    }      
  }
}   



if ($opt_report_mode eq 'bm')
{
  report_bm_db();
}
else
{
  report();
} 





sub report_bm_db()
{

foreach my $test_type (keys %plot3)
{
  $data=$plot3{$test_type};
  foreach my $hostname (keys %{$data})
  {
    foreach my $test_name (sort{($b=~/(.+)_.*/)[0] cmp ($a=~/(.+)_.*/)[0]} keys %{$data->{$hostname}})
    {
      ($t_name,$r_type)=split(":",$test_name);
      foreach $s (sort {$a cmp $b} keys %{$data->{$hostname}->{$test_name}})
      {
        foreach $e (sort {$a cmp $b} keys %{$data->{$hostname}->{$test_name}->{$s}})  
        {
                 print <<DATAEOF;
Test: ${test_type}_${t_name}
Host: $hostname
Build: $s
Engine: $e
R_Type: $r_type
DATAEOF
           $numrun=0;
           foreach $t (sort {$a<=>$b} keys %{$data->{$hostname}->{$test_name}->{$s}->{$e}})
           {
              my $res=$data->{$hostname}->{$test_name}->{$s}->{$e}->{$t};

              if (!$numrun)
              {
                 $numrun=$res->{count};
                 print "NumRun: ",$numrun,"\n";
              }
              print "Thread: $t\n";
              print "Result: ",$res->{sum}/$res->{count},"\n";
           }
        }
        print "\n";
      }
    }
  }
}
}


sub report()
{

foreach my $test_type (keys %plot)
{
  $data=$plot{$test_type};
  $data2=$plot2{$test_type};
  
  print "\nResults for test suite $test_type:\n\n";

  foreach my $test_name (sort{($b=~/(.+)_.*/)[0] cmp ($a=~/(.+)_.*/)[0]} keys %{$data})
  {
    print  "#\n# Test: $test_name\n#\n";
    #Print header
    $i=1;
    $server_with_data=0;
    $line="";
    foreach $s (sort {$a cmp $b} keys %{$data2->{$test_name}->{threads}})
    {
      $num_engines=0;
      $server_suffix="";
      foreach $e (sort {$a cmp $b} keys %{$data2->{$test_name}->{threads}->{$s}})
      {
        $num_engines++ if ($data2->{$test_name}->{threads}->{$s}->{$e});
        $server_suffix.=" $e:$data2->{$test_name}->{threads}->{$s}->{$e}";
      }

      if ($num_engines)
      {
        $server_width=10*$num_engines;
        $line=$line.sprintf("%${server_width}s","      #$i");
        $server_with_data++;
      }
      else 
      { 
        $server_suffix="Results not found" 
      }
      if ($num_engines || $opt_verbose)
      {
        print "# #$i - $s $server_suffix\n";
        $i++;
      }
    }
    if ($num_engines)
    {
#      print "#\n# Results are average values\n" if ($opt_report_mode eq 'summary');
      print "#\n#           $line\n"; 
      print (($opt_report_mode eq 'summary') ? "# Thread    " : "#           ");
    
      foreach $s (sort {$a cmp $b} keys %{$data2->{$test_name}->{threads}})
      {
        foreach $e (sort {$a cmp $b} keys %{$data2->{$test_name}->{threads}->{$s}})
        {
          printf("%10s",$e) if ($data2->{$test_name}->{threads}->{$s}->{$e})
        }
      }
    }
    print  "\n";
    $header=1;

    #If we have servers with data for test - print results
    if ($server_with_data)
    {
      foreach $thread (sort {$a <=> $b} keys %{$data->{$test_name}})
      {
        print (($opt_report_mode eq 'summary') ? "       " : "#Thread");
        printf  ("%4d ",$thread);
        print (($opt_report_mode eq 'summary') ? "" : "\n");
      
        $max_row=$data->{$test_name}->{$thread}->{max_row};
      
        #Skip avg for 1 result row
        $max_row++ unless ($max_row==1 && $opt_report_mode ne 'summary');

        $start_value=0;
        $start_value=$max_row-1 if ($opt_report_mode eq 'summary');
        $row_avg=0;      

        for ($row=$start_value;$row<$max_row;$row++)
        {
          $row_avg=1 if ($row==$max_row-1 && $max_row>1);
          if ($opt_report_mode ne 'summary')
          {
            print $row_avg ? "        Avg " : "          ".($row+1)." ";          
          }
          foreach $server_id (sort {$a cmp $b} keys %{$data2->{$test_name}->{threads}})
          {
            foreach $engine (sort {$a cmp $b} keys %{$data2->{$test_name}->{threads}->{$server_id}})
            {
              if ($data2->{$test_name}->{threads}->{$server_id}->{$engine})
              {
                $tmp=$data->{$test_name}->{$thread}->{$server_id}->{$engine};
                if (!$row_avg)
                {
                  if (defined(${$tmp->{data}}[$row]) && ${$tmp->{data}}[$row] ne '')
                  {
                    printf("%10.2f", ${$tmp->{data}}[$row] );
                  }
                  else
                  {
                    printf("%10s","nan");
                  }
                }
                else
                {
                  if (defined($tmp->{summary}->{sum}) )
                  {
                    printf("%10.2f", $tmp->{summary}->{sum}/$tmp->{summary}->{count});
                  }
                  else
                  {  
                    printf("%10s","nan");
                  }
                }
              }
            }
          }
          print "\n";
        }
      }
    }
    else
    {
#     print "\nWARNING: No results for this test were found\n\n";
    }
  }
}
}


sub parse_results
{
  my ($dir,$res)=@_;

  my @meta=();
  my %data=();
  my %meta=( test_name=>'', engine=>'', threads=>'', comments=>'', type=>'', result=>'', hostname=>'');

  my %result = ( 'result'         => { value => "",
                                       type => "throughput, "},
                 'result_time'    => { value => "",
                                       type => "time, sec"},
                 'result_bg_time' => { value => "",
                                       type => "bg_time, sec"});

  if (-f "$dir/readme.txt")
  {
    open(META,"$dir/readme.txt");
    @meta=<META>;
    close(META);

    #Get server version and use it as server_id
    @r = map {(/version(|\(CS\)): (.+$)/)[1]} @meta;
    $meta{server_id}=$r[0];
    $meta{server_id}=~s/\s+//g;
    
    foreach $line (@meta)
    {
      if ($line =~ /engine(| name):(.+)$/i)
      {
        $meta{engine}=$2;
        $meta{engine}=~ s/\s+//g;
      }
      if ($line =~ /test name: (.+)$/i)
      {
        $meta{test_name}=$1;
        $meta{test_name}=~ s/\s+//g;
      }
      if ($line =~ /Hostname: (.+)$/i)
      {
        $meta{hostname}=$1;
        $meta{hostname}=~ s/\s+//g;
      }
      if ($line =~ /Connections: (.+)$/i)
      {
        $meta{threads}=$1;
        $meta{threads}=~ s/\s+//g;
      }
      if ($line =~ /comments: (.+)$/i)
      {
        $meta{comments}=$1;
        $meta{comments}=~ s/\s+/\_/g;
      }
      if ($line =~ /Test suite name:\s+(.+)$/)
      {
        $meta{type}=$1;
        $meta{type}=~ s/\s+//g;
        if ($meta{type} =~ /sysbench/)
        {
          $meta{type}='sysbench';
        }
        elsif($meta{type} =~ /dbt2/)
        {
          $meta{type}='dbt2';
        }
        elsif($meta{type} =~ /tpcc/)
        {
          $meta{type}='tpcc';
        }
      }
      if ($line =~ /MySQL server key:\s+(.+)$/)
      {
        $meta{server_key}=$1;
        $meta{server_key}=~ s/\s+//g;
      }
      if ($line =~ /Date of test:\s+(.+)$/)
      {
        $meta{test_date}=$1;
        $meta{test_date}=~ s/\s+//g;
      }
      if ($line =~ /Filesystems:\s+(.+)$/)
      {
        $meta{fs}=$1;
        $meta{fs}=~ s/\s+//g;
      }
      if ($line =~ /Hardware:\s+(.+)$/)
      {
        $meta{hw}=$1;
        $meta{hw}=~ s/\s+//g;
      }
      if ($line =~ /Kernel:\s+(.+)$/)
      {
        $meta{kernel}=$1;
        $meta{kernel}=~ s/\s+//g;
      }
      if ($line =~ /OS:\s+(.+)$/)
      {
        $meta{os}=$1;
        $meta{os}=~ s/\s+//g;
      }
      if ($line =~ /Arch:\s+(.+)$/)
      {
        $meta{arch}=$1;
        $meta{arch}=~ s/\s+//g;
      }
      if ($line =~ /Elapsed time for stage RUN:\s+(\d+)$/i)
      {
        $result{result_time}->{value}=$1;
      }
#       if ($opt_bg_time && $line =~ /Elapsed time for stage BG_TASK:\s+(\d+)$/i)
      if ($line =~ /BG_TASK: Elapsed time:\s+(\d+)$/i)
      {
        $result{result_bg_time}->{value}=$1;
      }
    }
  }

  if (-f "$dir/run-result.out" && -s "$dir/run-result.out")
  {
    open(DATA,"$dir/run-result.out");
    @data=<DATA>;
    close(DATA);
  
    $data{type}="sysbench" if (grep{/sysbench/ig} @data);
    $data{type}="dbt2" if (grep{/dbt2/ig} @data);
    $data{type}="tpcc" if (grep{/tpcc/ig} @data);
    $data{type}="mysql-bench" if (grep{/run-all-tests/ig} @data);

    if ($meta{type} eq 'dbt2' || $data{type} eq 'dbt2')
    {
      foreach $line (@data)
      {
        if ($line =~ /^([\d\.]+) new-order transactions per minute/)
        {
          $result{result}->{value}=$1;
          $result{result}->{type}.="TPM";
        }
        if ($line =~ /^([\d\.]+) minute duration/)
        {
          $data{duration}=$1;
        }
      }
    } 

    if ($meta{type} eq 'tpcc' || $data{type} eq 'tpcc')
    {
      foreach $line (@data)
      {
        if ($line =~ /^\s+([\d\.]+) TpmC$/)
        {
          $result{result}->{value}=$1;
          $result{result}->{type}.="TPM";
        }
        if ($line =~ / in ([\d]+)\ssec\./)
        {
          $data{duration}=$1;
        }
      }  
    } 

    if ($meta{type} eq 'sysbench' || $data{type} eq 'sysbench')
    { 
      $data{transactions}=0;
      $data{rw_requests}=0;

      foreach $line (@data)
      {
        if ($line =~ /transactions:\s+\d+\s+\((.+) per/)
        {
          $data{transactions}=$1;
        }
        if ($line =~ /write\srequests:\s+\d+\s+\((.+) per/)
        {
          $data{rw_requests}=$1;
        }
        if ($line =~ /threads:\s(\d+)$/)
        {
          $data{threads}=$1;
        }
        if ($engine eq '' && $line =~ /-engine=(.+?)\s/)
        {
          $data{engine}=$1;
        }
        if ($meta{test_name} eq '')
        {
          @test_name= map { /--(oltp.+?=.+?)\s/g } $line;
          $data{test_name}=join(":",@test_name);
        }
      }
      if ($data{transactions})
      {
        $result{result}->{value}=$data{transactions};
        $result{result}->{type}.="TPS";
      }
      elsif($data{rw_requests})
      {
        $result{result}->{value}=$data{rw_requests};
        $result{result}->{type}.="QPS";
      }
    }
  }
  else
  {    
    #print "$dir $res->{result}\n";
    #FIXME: take into account $opt_test_type!
    if ($meta{type} eq 'dbt2'  && !$opt_time &&!$opt_bg_time)
    {
      #trying to fix
      $dbt2_driver_dir=`ls -1d $dir/dbt2*/driver 2>/dev/null`;
      chomp($dbt2_driver_dir);
      print "\nProcessing dir - $dir\n";
      print "Trying to extract raw dbt2 data from $dbt2_driver_dir/mix.log \n";
      print "ERROR: Specify path to mix_analyzer.pl from dbt2 suite\n\n" if (!$opt_mix_analyzer);
      if ($dbt2_driver_dir ne '' && $opt_mix_analyzer ne '' && -f $opt_mix_analyzer )
      {
        $mix_log="$dbt2_driver_dir/mix.log";
        #`echo "Exctracted result from raw log files >> $dir/run-result.out`;
        system("perl $opt_mix_analyzer --infile $mix_log --outdir $dbt2_driver_dir >> $dir/run-result.out ");
        unless(open (DATA,"$dir/run-result.out")) { $data{result}='' }
        while(<DATA>)
        {
          chomp;
          if (/^([0-9.]+)\s+new-order transactions per minute \(NOTPM\)$/) 
          { 
            $result{result}->{value}=$1;
            $result{result}->{type}.="TPM";
          }
            elsif (/^(\d+)\s+total unknown errors$/) { $data{error} = $1; }
        }
      }
    }
  }

  if ($meta{type} eq 'mysql-bench' || $data{type} eq 'mysql-bench')
  {
    $filename=`ls -1 $results_dir/RUN* 2>/dev/null`;
    
    if ($filename && -f $filename)
    {
    open(TMP, "$filename") || die "Can't open $filename: $!\n";
    @data= <TMP>;
    close(TMP);

    $header = 1;
    foreach (@data)
    {
      chomp;
      s/\r//g;
      if ($header == 1) 
      {
        if (/Server version:\s+(\S+.*)/i)
        {
          $data->{server} = $1;
        }
        elsif (/Running tests on:\s+(.+)/i)
        {
          $data->{env}=$1;
        }
        elsif (/Arguments:\s+(.+)/i)
        {
          $arguments= $1;
     	# Remove some standard, not informative arguments
     	#FIXME: --socket
     	$arguments =~ s/--force|--log|--use-old\S*|--server=\S+|--user=\S+|--pass=\S+|--machine=\S+|--dir=\S+|--socket=\S+//g;
     	if (($tmp=index($arguments,"--comment")) >= 0)
     	{
     	  if (($end=index($arguments,$tmp+2,"--")) >= 0)
     	  {
     	    substr($arguments,$tmp,($end-$tmp))="";
     	  }
     	  else
     	  {
     	    $arguments=substr($arguments,0,$tmp);
     	  }
     	}
     	$arguments =~ s/\s+/ /g;
     	$data->{arguments}=$arguments;
        }
        elsif (/Comments:\s+(.+)/i) {
          $data->{comments} = $1;
        }
        elsif (/Vendor:\s+(.+)/i) {
          $data->{vendor} = $1;
        }
        elsif (/Optimiztaion:\s+(.+)/i) {
          $data->{optimization} = $1;
        }
        elsif (/Hardware:\s+(.+)/i) {
          $data->{hw} = $1;
        }
        elsif (/Filesystem:\s+(.+)/i) {
          $data->{fs} = $1;
        }
        elsif (/Benchmark DBD suite:\s+(.+)/i) {
          $data->{suite} = $1;
        }
        elsif (/Date of test:\s+(.+)/i) {
          ($data->{date}) = split(/\s/,$1);
        }
        elsif (/^(\S+):\s*Done:\s*([\d.]+)\s*tests\s(estimated\s|)total\stime:\s+([\d.]+)\s+(wallclock\s|)secs/i)
        {
          #Parse test group information
     	$tmp = $1; $tmp =~ s/://;
     	$result_data->{0}->{$tmp} = [ $4, (length($3) ? "+" : "")];
        } 
        elsif (/Totals per operation:/i) {
     	$header = 0;
     	next;
        }
      }
      elsif ($header == 0)
      {
        if (/^(\S+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*([+|?])*/)
        {
          $tmp=$1;
          if ($tmp =~ /TOTALS/i)
          {
            $result_data->{2}->{$tmp} = [$2,$6,$7];
          }
          else
          {
            $result_data->{1}->{$tmp} = [$2,$6,$7];
          }
        }
      }
    }
    
    if ($data->{arguments} ne "" && $data->{arguments}!~ /^\s*$/ )
    {
      if ($data->{comments} ne "" && $data->{comments}!~ /^\s*$/)
      {
        $data->{desc}=$data->{arguments}.",".$data->{comments};
      }
      else
      {
        $data->{desc}=$data->{arguments};
      }
    }
    elsif($data->{comments} ne "")
    {
      $data->{desc}=$data->{comments};
    }
   
    #Table type detection 
    if ($data->{comments} =~ /Table type:\s(\S+)?\b/)
    {
      $data->{engine}=$1;
      $data->{server}.="/$1";
    }
    }
  }

  if ($opt_time)
  {
    $primary_result="result_time";
  }
  elsif ($opt_bg_time)
  {
    $primary_result="result_bg_time";
  }
  else
  {
    $primary_result="result";
  }

  @available_results=();
  for $result_type (result,result_time,result_bg_time)
  {
    if (exists($result{$result_type}->{value}) && $result{$result_type}->{value} ne '')
    {
       if ($result_type eq $primary_result)
       {
         $meta{result}=$result{$result_type}->{value};
         $meta{test_name}.=":".$result{$result_type}->{type};
       }
       push @available_results,$result{$result_type}->{type};
    }
  }
  if (@available_results)
  {
    if (!opt_skip_res_info)
    {
      $meta{test_name}.=" # Available results: ". join(" | ",@available_results);
    }
  }
  else
  { 
    $meta{test_name}.=" # No results were found"
  }

  # $result_key= $opt_time ? 'stage_run_time' : 'result' ;
  #$result_key='result';
  my @keys=(server_id,engine,test_name,threads,number,result,type,comments,hostname);

  for my $key (@keys)
  {
    if (exists($meta{$key}) && exists($data{$key}) && $meta{$key} ne '' && $data{$key} ne '')
    {
      if ($meta{$key} eq $data{$key} || $opt_time || $opt_bg_time)
      {
        $res->{$key}=$meta{$key};
      }
      else 
      { 
        print "WARNING: $dir meta{$key} != data{$key}",$meta{$key},"!=",$data{$key},"\n"; 
      }
    }
    elsif (exists($meta{$key}) && $meta{$key} ne '')
    {
      $res->{$key}=$meta{$key};
    }
    elsif (exists($meta{$key}) && $data{$key} ne '')
    {
      $res->{$key}=$data{$key};
      #print "WARNING: $dir Using data for key $key from data file ",$data{$key},"\n"
    }
  }
#  if ($meta{type} eq 'sysbench' || $data{type} eq 'sysbench')
#  {    
#  print "$dir",Dumper($res),"\n";
#  print "meta",Dumper(\%meta),"\n";
#  print "data",Dumper(\%data),"\n";  
#  }
#  exit;
#  return $server_id,$engine,$test_name,$threads,$number,$result,$type,$comments;

}

sub usage
{
print <<EOF;

  perl r.pl [<options>] [<results dir1> <results dir2> ...]

  --basedir <dir>=<server_id> 
    specify autobench <dir> that contains directories with results. You should define name of server 
    that will be associatefd with  results. 

  --test-type=<dbt2|sysbench|mysql-bench>
    process only results for test that was specified

  --server_id=<server_id>
    define name of server that will be associatefd with results
    TODO: make it possible to extarct and use various data from meta file and add it server_ver key 
    like this:
    server_id_key=comments,datadir,fs,cpu... 

  --report-mode=[single|summary|detail|xls|db|gnuplot] (Default: summary)
    - single  - will process very first dir with results and print only result value to STDOUT
    - summary - will process all specified directories and provide summary report
                where results are avg values
    - detail  - will process all specified directories and provide detail report 
                including all results
    - bm
    - xls     (in progress)
    - db      (in progress)
    - gnuplot (in progress)

  --id=[result_id,[result_id],...] 
    List of results id's to include in report
    
  --exclude-id=[result_id,[result_id],...] 
    List of results id's to exclude from report

  --merge-id=[result_id,[result_id],...]
    List of results id's which header will be merged

  --time
    Show elapsed time for the test 
  --bg-time
    Show elapsed time for the background task 

  --verbose 
    Include in report details for runs without results

EOF
  exit;
}


