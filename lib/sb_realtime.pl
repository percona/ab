use Getopt::Long;

#$line="[1303395486] [   1s] threads: 5, tps: 1655.75, reads/s: 23180.55, writes/s: 0.00";

$opt_file=$opt_get_ts=$opt_get_data="";

GetOptions("file=s","get-ts","get-data");

die "ERROR: Filename with sysbench data is required. Specify one with --file options\n\n" unless $opt_file;

open(FIN,"$opt_file") or die "Can't open file: $opt_file";

while(<FIN>)
{
  $line=$_;
  if ($line=~/^\[(\d+)\] \[.+tps: ([\d\.]+), reads\/s: ([\d\.]+), writes\/s: ([\d\.]+)/)
  {
    if (!$header)
    {
       $header=1;
       $start_time=$1;
       if ($opt_get_ts)
       {
         print "$start_time\n";
         exit 0;
       }
    }
#    print $1," ",$2," ",$3," ",$4,"\n";
    print $2," ",$3," ",$4,"\n";
  }
}


