#!/bin/sh

run() {
	if [ -n "$DRYRUN" ]
	then
		echo $*
	elif [ -n "$DEBUG" ]
	then
		echo $*
		$*
	fi
}

linky() {
	out=$1
	shift
	if [ "$*" = "statically linked" ]
	then
		echo "# static"
		return
	elif [ "$*" = "not a dynamic executable" ]
	then
		echo "# static"
		return
	elif [ "${1:0:1}" == "/" ]
	then
		libsrcpath="$1"
	elif [ "${3:0:1}" == "(" ]
	then
		# no target
		return
	else
		libsrcpath=$3
	fi
	libname=${libsrcpath##*/}
	libnewpath=$out/${libname}
	if [ -L $libsrcpath ]; then
		linkdest=$(readlink $libsrcpath)
		if [ ! -L $libnewpath ]; then
			run "ln -sf $linkdest $libnewpath"
		else
			echo "# $libnewpath exists, skipping"	
		fi
	else
		if [ ! -e $libnewpath ]; then
			run "cp $libsrcpath $libnewpath"
		else
			echo "# $libnewpath exists, skipping"
		fi
		dynagrab $libsrcpath $out
	fi
}

dynagrab() {
	ldd $1 | while read line; do
		linky $2 $line
	done
}

binarygrab() {
	[ ! -e $2/bin ] && run "install -d $2/bin"
	[ ! -e $2/lib ] && run "install -d $2/lib"
	run "cp $1 $2/bin"
	dynagrab $1 $2/lib
}
export DRYRUN=1
# grab all shared libs required by binary $1 and copy to destination chroot/initramfs root $2:
[ "$2" = "" ] && echo "Please specify a target chroot as a second argument. Exiting" && exit 1
binarygrab $1 $2
