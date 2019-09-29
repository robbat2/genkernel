# This file is sourced before the arch-specific configs.
# $Id$
#
# Arch-specific options that normally shouldn't be changed (and should be set in the arch-specific configs)
#
KERNEL_MAKE_DIRECTIVE="--INVALID--"
# since "" is allowed (this will translate in `make `, which is nice
# for xen-based kernels, the default value of
# KERNEL_MAKE_DIRECTIVE_OVERRIDE cannot be ""
DEFAULT_KERNEL_MAKE_DIRECTIVE_OVERRIDE="--INVALID--"
KERNEL_MAKE_DIRECTIVE_OVERRIDE="${KERNEL_MAKE_DIRECTIVE_OVERRIDE:-${DEFAULT_KERNEL_MAKE_DIRECTIVE_OVERRIDE}}"
KERNEL_MAKE_DIRECTIVE_2=""
KERNEL_BINARY="--INVALID--"
KERNEL_SUPPORT_MICROCODE=no

# At a bare minimum, every arch MUST override these two options:
# KERNEL_MAKE_DIRECTIVE
# KERNEL_BINARY

#
# Arch-specific defaults that can be overridden in the config file or on the
# command line.
#
DEFAULT_INITRAMFS_FILENAME="initramfs-%%KV%%.img"
DEFAULT_INITRAMFS_SYMLINK_NAME="initramfs"
DEFAULT_KERNEL_FILENAME="vmlinuz-%%KV%%"
DEFAULT_KERNEL_SYMLINK_NAME="kernel"
DEFAULT_SYSTEMMAP_FILENAME="System.map-%%KV%%"
DEFAULT_SYSTEMMAP_SYMLINK_NAME="System.map"

DEFAULT_COMPRESS_INITRD=yes
DEFAULT_COMPRESS_INITRD_TYPE=best

PORTAGE_MAKEOPTS="$(portageq envvar MAKEOPTS)"
DEFAULT_MAKEOPTS="${PORTAGE_MAKEOPTS:- -j2}"

DEFAULT_KERNEL_MAKE=make
DEFAULT_UTILS_MAKE=make

DEFAULT_KERNEL_CC=gcc
DEFAULT_KERNEL_AS=as
DEFAULT_KERNEL_LD=ld

DEFAULT_UTILS_CFLAGS="-Os -pipe -fomit-frame-pointer"
DEFAULT_UTILS_CC=gcc
DEFAULT_UTILS_CXX=g++
DEFAULT_UTILS_AS=as
DEFAULT_UTILS_LD=ld
