package My::Timer;
use vars qw(@ISA @EXPORT $VERSION);
use Exporter;
use Benchmark;

$VERSION=1.00;
@ISA=qw(Exporter);
@EXPORT=qw(get_timer timestr $use_hires);

# Flag, that shows if we must use hi res timer
$My::Timer::use_hires; 

sub get_timer {
 my $bench_result;                   # result of Benchmark timer
 my $hi_result;                      # result of HiRes timer
 # 1) read hires timer if we can use hires timer
 $hi_result = Time::HiRes::gettimeofday() if ( $My::Timer::use_hires);
 # 2) read benchmark timer
 $bench_result = new Benchmark;
 # 3) Compose them and return
 $bench_result->[0] = $hi_result if ( $My::Timer::use_hires);
 return $bench_result;
}

# Changed version of timestr from Benchmark module
sub timestr {
    my($tr) = @_;
    my @t = @$tr;
    warn "bad time value (@t)"  unless @t==6;
    my($r, $pu, $ps, $cu, $cs, $n) = @t;
    my($pt, $ct, $tt) = ($tr->cpu_p, $tr->cpu_c, $tr->cpu_a);
    my $f='5.2f';
    $s=sprintf("%.3f wallclock secs (%$f usr %$f sys + %$f cusr %$f csys = %$f CPU)",
			    $r,$pu,$ps,$cu,$cs,$tt);
    $s;
}

1;

# For work we need a Time:Hires module. But If this module 
# is absent, we use just Benchmark
# Well, try to load Hires

BEGIN {
  if ( eval "require Time::HiRes")
  {
    Time::HiRes->import();
    $My::Timer::use_hires=1;    
  } else {
    $My::Timer::use_hires=0;
  }
}
