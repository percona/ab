#!/usr/bin/perl

use Data::Dumper;

$dir=$ARGV[0];
#[  10s] threads: 20, tps: 3396.24, reads/s: 47566.12, writes/s: 13585.15 response time: 14.56ms (99%)


%r=();

open(SB_OUT1,">>sb.index.out");

foreach $dir (@ARGV)
{

#$file="$dir/run-result.out";
$file="$dir/readme.txt";
#$file="$dir/vmstat.out";

@r=();
%t=();

rdm("$dir/readme.txt",\%t);

#print Dumper(\%t),"\n";

$r{$t{rid}}->{$t{name}}->{$t{conn}}={ rnum=> $t{rnum},  tm=>$t{time},  vm=>[],   sb=>[], ver=>$t{ver}, comm=>$t{comm}};
vm("$dir/vmstat.out",$r{$t{rid}}->{$t{name}}->{$t{conn}}->{vm});
#sb("$dir/run-result.out",$r{$t{rid}}->{$t{name}}->{$t{conn}}->{sb});
tpcc("$dir/run-result.out",$r{$t{rid}}->{$t{name}}->{$t{conn}}->{sb});

#print Dumper(\%r),"\n";

#print join ("###", keys %{$r{13}->{OLTP_RW}}),"\n";

#print Dumper(vm($file,\@r)),"\n";
#print Dumper(sb($file,\@r)),"\n";
}


@vmm=();
@sbb=();

#print "Adding results in order: ";

foreach $rid (keys %r)
{
#   print "$rid ";
   print SB_OUT1 "$rid,";
   foreach $test (keys %{$r{$rid}})
   {
      #print Dumper($r{$rid}->{$test}),"\n";

#      print "$test ";
      print SB_OUT1 "$test,";
      foreach $conn (sort {$a <=> $b} keys %{$r{$rid}->{$test}})
      {
          print SB_OUT1 "$conn\n";
#         print $conn," ";
#         $idx=0;
#         foreach $vm (@{$r{$rid}->{$test}->{$conn}->{vm}})
#         {
#            push @{$vmm[$idx]},$vm;
#            $idx++;
#         }

         $idx=0;
         foreach $sb (@{$r{$rid}->{$test}->{$conn}->{sb}})
         {
#            push @{$sbb[$idx]},$sb;
            print $r{$rid}->{$test}->{$conn}->{comm},",",$r{$rid}->{$test}->{$conn}->{ver},",",$rid,",",$test,",",$conn,",",join (",",@{$sb}),"\n";
            $idx++;
         }
      }
#      print "\n";
   }
}
close(SB_OUT1);
exit;

$idx=0;
foreach $sbb (@sbb)
{
  print $idx+1," ";
  foreach $sbbb (@{$sbb[$idx]})
  {
     print $sbbb->[1]," ";
  }
  $idx++;
  print "\n";
}


#print Dumper(\@sbb),"\n";

sub tpcc
{
  my ($file,$r)=@_;

  open(IN,"$file") or die "Can't open file $file: $!";
  while(<IN>)
  {
    $line=$_;
    chomp($line);
    if ($line)
    {
#     print "LINE: $line\n";
      if ($line =~ /^\s*([\d]+)\, ([\d]+)\(\d\)\:([\d\.]+)\|([\d\.]+)\,/)
      {
#        print $1," ",$2," ",$3," ",$4,"\n";
#        $data{notps}+=$2*1;
#        $data{rtime}+=$3*1;
#        $data{rtime_max}+=$4*1;
        push  @${r},[$1,$2,$3];
#        $cnt++;
      }
    }
  }
}


sub sb
{
  my ($file,$r)=@_;

  open(IN,"$file") or die "Can't open file $file: $!";
  while(<IN>)
  {
    $line=$_;
    if ($line=~/^\[\s*?(\d+)s\].*tps:\s([\d\.]+).*?\s([\d\.]+).*?\s([\d\.]+).*?\s([\d\.]+)/)
    {
      #print $1," ",$2," ",$3," ",$4," ",$5,"\n";
      push @${r},[$1,$2,$5];
    }
  }
}


sub vm
{
  my ($file,$r)=@_;

  open(IN,"$file") or die "Can't open file $file: $!";
  while(<IN>)
  {
    $line=$_;
    if ($line !~ /^(procs | r  b)/)
    {
      # bi/bo cs us sy id wa
      # 8/9   10/11/12/13/14
      @s=split(/\s+/,$line);
      push @${r},[$s[9],$s[10],$s[12],$s[13],$s[14],$s[15],$s[16]];
    }
  }
}


sub rdm
{
  my ($file,$t)=@_;

  open(IN,"$file") or die "Can't open file $file: $!";
  while(<IN>)
  {
    $line=$_;
    if ($line =~ /Run ID:\s+(\d+)/)        { $t->{rid}=$1;}
    elsif ($line =~ /Run number:\s+(\d+)/) { $t->{rnum}=$1; }
    elsif ($line =~ /Test name:\s+(\S+)/)  { $t->{name}=$1; }
    elsif ($line =~ /Test Duration\(seconds\):\s+(\d+)/) { $t->{time}=$1 }
    elsif ($line =~ /Database Connections:\s+(\d+)/)     { $t->{conn}=$1 }
    elsif ($line =~ /Comments:\s+(.+)/) { t->{comm}=$1  }
    elsif ($line =~ /MySQL server version:\s+(.+?)\s/) { t->{ver}=$1  }
  }
}

