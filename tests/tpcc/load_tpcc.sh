#!/bin/bash
#export LD_LIBRARY_PATH=/usr/local/mysql/lib/mysql/
DBNAME=$1
WH=$2
SERVER_HOST=127.0.0.1
SERVER_PORT=3306
STEP=100

HOST="$SERVER_HOST:$SERVER_PORT"

FAIL=0
SN=$0

ODIR=`dirname $SN`

date
mysql -uroot -h $SERVER_HOST -P $SERVER_PORT -e "create database if not exists $DBNAME"
mysql -uroot -h $SERVER_HOST -P $SERVER_PORT $DBNAME  < $ODIR/create_table.sql

$ODIR/tpcc_load $HOST $DBNAME root "" $WH 1 1 $WH >> $TEST_OUTDIR/1.out &

date
x=1

while [ $x -le $WH ]
do
 echo $x $(( $x + $STEP - 1 ))
$ODIR/tpcc_load $HOST $DBNAME root "" $WH 2 $x $(( $x + $STEP - 1 ))  >> $TEST_OUTDIR/2_$x.out &
$ODIR/tpcc_load $HOST $DBNAME root "" $WH 3 $x $(( $x + $STEP - 1 ))  >> $TEST_OUTDIR/3_$x.out &
$ODIR/tpcc_load $HOST $DBNAME root "" $WH 4 $x $(( $x + $STEP - 1 ))  >> $TEST_OUTDIR/4_$x.out &
 x=$(( $x + $STEP ))
done

for job in `jobs -p`
do
echo $job
    wait $job || let "FAIL+=1"
done

echo $FAIL

if [ "$FAIL" == "0" ];
then
echo "YAY!"
else
echo "FAIL! ($FAIL)"
fi

date
mysql -uroot -h $SERVER_HOST -P $SERVER_PORT $DBNAME  < $ODIR/add_fkey_idx.sql

date

