
for dir in  tachion ; do
for bp in 100 200 ; do

./ab.sh --test=conf/tpcc/ab_tpccw2500.cnf --servers=/data/opt/alexey.s/bin64_5525a-ps/ \
--autobench-datadir=/mnt/${dir}/data --threads=32,64,128 --duration=3600 --mode=run \
--engine=innodb,defaults-file=conf/tpcc/tpccw2500-innodb.no_restore.cnf,innodb_buffer_pool_size=${bp}G,innodb_io_capacity=10000,comment=$dir.ibp${bp}G.capa10k --start-and-exit

./ab.sh --test=conf/tpcc/ab_tpccw2500.cnf --servers=/data/opt/alexey.s/bin64_5525a-ps/ \
--autobench-datadir=/mnt/${dir}/data --threads=64 --duration=1800 --extern --mode=run,cleanup \
--engine=innodb,defaults-file=conf/tpcc/tpccw2500-innodb.no_restore.cnf,innodb_buffer_pool_size=${bp}G,innodb_io_capacity=10000,comment=$dir.ibp${bp}G.capa10k.warmup

./ab.sh --test=conf/tpcc/ab_tpccw2500.cnf --servers=/data/opt/alexey.s/bin64_5525a-ps/ \
--autobench-datadir=/mnt/${dir}/data --threads=32,64,128 --duration=3600 --extern --mode=run,cleanup \
--engine=innodb,defaults-file=conf/tpcc/tpccw2500-innodb.no_restore.cnf,innodb_buffer_pool_size=${bp}G,innodb_io_capacity=10000,comment=$dir.ibp${bp}G.capa10k

done
done


for s in /data/opt/alexey.s/bin64_566m9 ; do 
for dir in fio tachion ; do
for bp in 100 200 ; do

./ab.sh --test=conf/tpcc/ab_tpccw2500.cnf --servers=${s} \
--autobench-datadir=/mnt/${dir}/data --threads=32,64,128 --duration=3600 --mode=run \
--engine=innodb,defaults-file=conf/tpcc/tpccw2500-innodb.mysql.cnf,innodb_buffer_pool_size=${bp}G,innodb_io_capacity=10000,comment=$dir.ibp${bp}G.capa10k --start-and-exit

./ab.sh --test=conf/tpcc/ab_tpccw2500.cnf  \
--autobench-datadir=/mnt/${dir}/data --threads=64 --duration=1800 --extern --mode=run,cleanup \
--engine=innodb,defaults-file=conf/tpcc/tpccw2500-innodb.mysql.cnf,innodb_buffer_pool_size=${bp}G,innodb_io_capacity=10000,comment=$dir.ibp${bp}G.capa10k.warmup

./ab.sh --test=conf/tpcc/ab_tpccw2500.cnf  \
--autobench-datadir=/mnt/${dir}/data --threads=32,64,128 --duration=3600 --extern --mode=run,cleanup \
--engine=innodb,defaults-file=conf/tpcc/tpccw2500-innodb.mysql.cnf,innodb_buffer_pool_size=${bp}G,innodb_io_capacity=10000,comment=$dir.ibp${bp}G.capa10k

done
done
done

