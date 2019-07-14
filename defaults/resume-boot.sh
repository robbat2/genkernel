#!/bin/sh

. /etc/initrd.defaults

if [ -s "${GK_SHELL_LOCKFILE}" ]
then
	kill -9 "$(cat "${GK_SHELL_LOCKFILE}")"
fi

if [ -f "${GK_SSHD_LOCKFILE}" ]
then
	rm "${GK_SSHD_LOCKFILE}"
fi

exit 0
