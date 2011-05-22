#!/bin/sh

linky() {
	out=$1
	shift
	if [ "$*" = "statically linked" ]
	then
		echo "static"
		return
	elif [ "$*" = "not a dynamic executable" ]
	then
		echo "static"
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
	#echo "libsrcpath $libsrcpath"
	#echo "libname $libname"
	#echo "libnewpath $libnewpath"
	if [ -L $libsrcpath ]; then
		linkdest=$(readlink $libsrcpath)
		#[ ! -L $libnewpath ] && 
		echo "ln -sf $linkdest $libnewpath"
	else
		#[ ! -e $libnewpath ] && 
		echo "cp $libsrcpath $libnewpath"
		dynagrab $libsrcpath $out
	fi
}

dynagrab() {
	ldd $1 | while read line; do
		linky $2 $line
	done
}

binarygrab() {
	[ ! -e $2/bin ] && echo "install -d $2/bin"
	[ ! -e $2/lib ] && echo "install -d $2/lib"
	echo "cp $1 $2/bin"
	dynagrab $1 $2/lib
}

# grab all shared libs required by binary $1 and copy to destination chroot/initramfs root $2:
binarygrab $1 $2
