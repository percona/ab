#!/bin/sh

#
# This file is released under the terms of the Artistic License.
# Please see the file LICENSE, included in this package, for details.
#
# Copyright (C) 2004 Mark Wong & Open Source Development Lab, Inc.
#

VMINFILE="vmstat.out"
IOINFILE="iostatx.out"
OUTDIR="."
VMDATAFILE="vmstat.data"
IODATAFILE="iostat.data"


X_UNITS="Minutes"

while getopts "v:i:o:x:" opt; do
	case $opt in
		v)
			VMINFILE=$OPTARG
			;;
		i)
			IOINFILE=$OPTARG
			;;
		o)
			OUTDIR=$OPTARG
			;;
		x)
			X_UNITS=$OPTARG
			;;
	esac
done

if [ ! -f "$VMINFILE" ]; then
	echo "$VMINFILE does not exist."
	exit 1
fi

if [ ! -f "$IOINFILE" ]; then
	echo "$IOINFILE does not exist."
	exit 1
fi


# Blindly create the output directory.
mkdir -p $OUTDIR

# This is based off vmstat with a header like:

#procs -----------memory---------- ---swap-- -----io---- --system-- ----cpu----
# r  b   swpd   free   buff  cache   si   so    bi    bo   in    cs us sy id wa

# Make 0 the first point for each graph
# Also add another column at the end to represent total processor utilization.
echo "0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0" > ${OUTDIR}/${VMDATAFILE}
cat ${VMINFILE} | grep -v '^procs ' | grep -v '^ r  b ' | awk '{ print NR, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $13+$14+$16 }' >> ${OUTDIR}/${VMDATAFILE}

echo "0 0" > ${OUTDIR}/${IODATAFILE}
cat iostatx.out | grep -v '^Device\|^Linux' | grep -v '^$' | awk '{ print  NR, $12 }' >> ${OUTDIR}/${IODATAFILE}

INPUT_FILENAME="${NAME}.input"
INPUT_FILE="$OUTDIR/${INPUT_FILENAME}"
PNG_FILE="$OUTDIR/vmio_stat-`date +\"%Y%m%d%H%M%S\"`.png"

echo "set term png small size 1280, 1024 crop" >> $INPUT_FILE 
echo "set output \"$PNG_FILE\"" >> $INPUT_FILE
echo "set autoscale" >> $INPUT_FILE
echo "set multiplot" >> $INPUT_FILE
echo "set origin 0.0, 0.0" >> $INPUT_FILE
echo "set size 0.5,0.5" >> $INPUT_FILE
echo "set grid xtics ytics" >> $INPUT_FILE
echo "set title \"IO and CS\"" >> $INPUT_FILE
echo "set grid xtics ytics" >> $INPUT_FILE
echo "set xlabel \"Elapsed Time ($X_UNITS)\"" >> $INPUT_FILE
echo "set ylabel \"Blocks per Second\"" >> $INPUT_FILE
echo "set yrange [0:]" >> $INPUT_FILE
echo "plot \"$VMDATAFILE\" using 1:10 title \"received from device\" with lines, \\" >> $INPUT_FILE
echo "     \"$VMDATAFILE\" using 1:11 title \"sent to device\" with lines, \\" >> $INPUT_FILE
echo "     \"$VMDATAFILE\" using 1:13 title \"context switches\" with lines " >> $INPUT_FILE
echo "set origin 0.5, 0.0" >> $INPUT_FILE
echo "set size 0.5,0.5" >> $INPUT_FILE
echo "set title \"IO utilization\"" >> $INPUT_FILE
echo "set grid xtics ytics" >> $INPUT_FILE
echo "set xlabel \"Elapsed Time ($X_UNITS)\"" >> $INPUT_FILE
echo "set ylabel \"%\"" >> $INPUT_FILE
echo "set yrange [0:]" >> $INPUT_FILE
echo "plot \"$IODATAFILE\" using 1:2 title \"IO utilization\" with lines" >> $INPUT_FILE
(cd ${OUTDIR}; gnuplot ${INPUT_FILENAME})

exit 0
