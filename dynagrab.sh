#!/bin/sh

linky() {
	out=$1
	shift
	case $1 in
	  */ld-linux*.so.2)
	  	if [ ! -e $out/$1 ]; then
			echo "cp $1 $out"
			return
		fi
		;;
	esac
	lib=$3
	while [ 1 ]
	do
		if [ -L $lib ]; then
			realfile=$(readlink $lib)
			echo "ln -sf $realfile $out/${lib##*/}"
			lib=$(readlink -f $lib)
		else
			echo "cp $lib $out"
			break
		fi
	done
}

dynagrab() {
	ldd $1 | grep -v 'linux-vdso\.so\.1' | while read line; do
		linky $2 $line
	done
}

# grab all shared libs required by binary $1 and copy to destination directory $2:
dynagrab $1 $2
