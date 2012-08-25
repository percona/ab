#!/bin/bash

TST_BASEDIR=$1
TST_OUTDIR=$2
RUN_NUMBER=0
if [ -f "$TST_BASEDIR/.run_number" ]; then
  read RUN_NUMBER < "$TST_BASEDIR/.run_number"
  if [ $RUN_NUMBER -gt 0 ]; then
    RUN_NUMBER=`expr $RUN_NUMBER - 1`
    if [ -d "$TST_BASEDIR/output/$RUN_NUMBER" -a -d "$TST_OUTDIR" ] ; then
      mv $TST_BASEDIR/output/$RUN_NUMBER $TST_OUTDIR/dbt2-raw-data-$RUN_NUMBER
     fi
  else
    if [ -d "$TST_BASEDIR/output" -a -d  "$TST_OUTDIR" ] ; then
      mv $TST_BASEDIR/output/$RUN_NUMBER $TST_OUTDIR/dbt2-raw-data-0
      rm -f $TST_BASEDIR/.run_number
    fi
  fi
fi
