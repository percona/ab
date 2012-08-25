wich ()
{
  IFS="${IFS=   }"; save_ifs="$IFS"; IFS=':'
  for file
  do
    file=$(basename $file)
    for dir in $PATH
    do
      if test -f $dir/$file
      then
        echo "$dir/$file"
        continue 2
      fi
    done
    #echo "Fatal error: Cannot find program $file in $PATH" 1>&2
    exit 1
  done
  IFS="$save_ifs"
  exit 0
}

if [ `wich vgcc-config` ]; then echo "OK"; fi

