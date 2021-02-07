#!/bin/sh

. /etc/initrd.defaults
. /etc/initrd.scripts

GK_INIT_LOG_PREFIX=${0}
if [ -n "${SSH_CLIENT_IP}" ] && [ -n "${SSH_CLIENT_PORT}" ]
then
	GK_INIT_LOG_PREFIX="${0}[${SSH_CLIENT_IP}:${SSH_CLIENT_PORT}]"
fi

# We don't want to kill init script (PID 1),
# ourselves and parent process yet...
pids_to_keep="1 ${$} ${PPID}"

for pid in $(pgrep sh)
do
	if ! echo " ${pids_to_keep} " | grep -q " ${pid} "
	then
		kill -9 ${pid} &>/dev/null
	fi
done

good_msg "Resuming boot process ..."
[ -f "${GK_SSHD_LOCKFILE}" ] && run rm "${GK_SSHD_LOCKFILE}"
[ "${PPID}" != '1' ] && kill -9 ${PPID} &>/dev/null

exit 0
