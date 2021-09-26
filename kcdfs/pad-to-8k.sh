#!/bin/bash
if [ "$1" = "" ];then
	echo "Pass in the file to pad out"
	exit
fi
F="$1"
TMP=/tmp/`basename $0`.$$
SIZE="`ls -l $1 |awk '{print $5}'`"
PAD=$((8192-SIZE))
dd if=/dev/zero bs=1 count=$PAD of=$TMP
cat $F $TMP >$F.rom
rm -f $TMP


