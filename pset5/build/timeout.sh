#! /bin/sh

usage () {
	echo "Usage: timeout [-s signal] seconds program [args]" 2>&1
	exit 1
}

signal=SIGTERM
if [ "$1" = '-s' ]; then
	[ "$#" -lt 2 ] && usage
	signal="$2"
	shift 2
fi
signal=`echo "$signal" | sed 's/^SIG//'`

[ $# -lt 2 ] && usage

timeout="$1"
shift

( sleep "$timeout" ; kill -"$signal" $$ >/dev/null 2>&1 ) &
exec "$@"
