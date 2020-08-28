#!/bin/sh

echo 'Generating "/run/initramfs/gksosreport.txt" ...'

if [ ! -d /run/initramfs ]
then
	mkdir -p /run/initramfs
	chmod 0750 /run/initramfs
fi

exec >/run/initramfs/gksosreport.txt 2>&1

PWFILTER='s/\(ftp:\/\/.*\):.*@/\1:*******@/g;s/\(cifs:\/\/.*\):.*@/\1:*******@/g;s/cifspass=[^ ]*/cifspass=*******/g;s/iscsi:.*@/iscsi:******@/g;s/rd.iscsi.password=[^ ]*/rd.iscsi.password=******/g;s/rd.iscsi.in.password=[^ ]*/rd.iscsi.in.password=******/g'

echo "Genkernel SOS report from $(date +'%Y-%m-%d %H:%M:%S'):"

set -x

cat /lib/dracut/dracut-gk-version.info

cat /lib/dracut/build-parameter.txt

cat /proc/cmdline | sed -e "${PWFILTER}"

[ -f /etc/cmdline ] && cat /etc/cmdline | sed -e "${PWFILTER}"

lspci -k

lsmod

find /lib/modules/$(uname -r) -type f

cat /proc/self/mountinfo
cat /proc/mounts

blkid
blkid -o udev

ls -l /dev/disk/by*

if hash lvm >/dev/null 2>/dev/null
then
	lvm pvdisplay
	lvm vgdisplay
	lvm lvdisplay
fi

if hash dmsetup >/dev/null 2>/dev/null
then
	dmsetup ls --tree
fi

if [ -e /proc/mdstat ]
then
	cat /proc/mdstat
fi

if hash cryptsetup >/dev/null 2>/dev/null
then
	if [ -e /dev/mapper/root ]
	then
		cryptsetup status /dev/mapper/root
	fi
fi

if hash ip >/dev/null 2>/dev/null
then
	ip link
	ip addr
fi

dmesg | sed -e "${PWFILTER}"

[ -f /run/initramfs/init.log ] && cat /run/initramfs/init.log | sed -e "${PWFILTER}"
