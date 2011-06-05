#!/bin/sh

run() {
	if [ -n "$DRYRUN" ]
	then
		echo $*
	else	
		echo $*
		$*
	fi
}

linky() {
	out=$1
	libout=$2
	shift
	shift
	if [ "$*" = "statically linked" ]
	then
		return
	elif [ "$*" = "not a dynamic executable" ]
	then
		return
	elif [ "${1:0:1}" == "/" ]
	then
		src="$1"
	elif [ "${3:0:1}" == "(" ]
	then
		# no target
		return
	else
		src=$3
	fi
	dynagrab $src $out $libout
}

dynagrab() {
	out=$2
	libout=$3
	if [ ! -L $1 ]; then
		# normal file - copy it over to $out:
		if [ ! -e $out/${1##*/} ]; then
			run "cp $1 $out"
		else
			echo "# $out/${1##*/} exists, skipping..."
		fi
		ldd $1 | while read line; do
			linky $libout $libout $line
		done
	else
		# symlink - create symlink in $libout:
		linkdest=$(readlink $1)
		if [ ! -L $libout/${1##*/} ];
		then
			run "ln -sf $linkdest $libout/${1##*/}"
		else
			echo "# $libout/${1##*/} exists, skipping..."
		fi
		# recurse on target of original symlink, so we can grab everything:
		recurse_on="${1%/*}/${linkdest}"
		dynagrab $recurse_on $libout $libout 
	fi
}

# grab all shared libs required by binary $1 and copy to destination chroot/initramfs root $2:
[ "$2" = "" ] && echo "Please specify a target chroot as a second argument. Exiting" && exit 1
[ ! -e $2/bin ] && run "install -d $2/bin"
[ ! -e $2/lib ] && run "install -d $2/lib"
dynagrab $1 $2/bin $2/lib
