#!/bin/sh
# vim: set noexpandtab:

. /etc/initrd.defaults
. /etc/initrd.scripts
. "${CRYPT_ENV_FILE}"

splash() {
	return 0
}

[ -e /etc/initrd.splash ] && . /etc/initrd.splash

receivefile() {
	case ${1} in
		root)
			file=${CRYPT_KEYFILE_ROOT}
			;;
		swap)
			file=${CRYPT_KEYFILE_SWAP}
			;;
		*)
			bad_msg "Unknown '${1}' keyfile received." ${CRYPT_SILENT}
			exit 1
			;;
	esac

	# limit maximum stored bytes to 1M to avoid killing the server
	dd of=${file} count=1k bs=1k 2>/dev/null
	return $?
}



if [ "x${1}" = "x-c" ]
then
	command=$(echo ${2} | awk -F" " '{print $1}')
	type=$(echo ${2} | awk -F" " '{print $2}')

	case ${command} in 
		post)
			receivefile ${type}
			if [ $? -eq 0 ]
			then
				unlock-luks ${type}
				if [ $? -eq 0 ]
				then
					if [ "${type}" = 'root' ]
					then
						# this is required to keep scripted unlock working
						# without requring an additional command.
						resume-boot
					fi

					exit 0
				else
					exit 1
				fi
			else
				bad_msg "Keyfile was not properly received!" ${CRYPT_SILENT}
				exit 1
			fi
			;;
		*)
			bad_msg "Command '${command}' is not supported!" ${CRYPT_SILENT}
			exit 1
	esac
else
	export PS1='remote rescueshell \w \# '
	touch "${GK_SSHD_LOCKFILE}"
	good_msg "The lockfile '${GK_SSHD_LOCKFILE}' was created."
	good_msg "In order to resume boot process, run 'resume-boot'."
	good_msg "Be aware that it will kill your connection which means"
	good_msg "you will no longer be able work in this shell."

	if [ -n "${CRYPT_ROOT}" -a ! -f "${CRYPT_ROOT_OPENED_LOCKFILE}" ]
	then
		good_msg "To remote unlock LUKS-encrypted root device, run 'unlock-luks root'."
	fi

	if [ -n "${CRYPT_SWAP}" -a ! -f "${CRYPT_ROOT_OPENED_LOCKFILE}" ]
	then
		good_msg "To remote unlock LUKS-encrypted swap device, run 'unlock-luks swap'."
	fi

	[ -x /bin/sh ] && SH=/bin/sh || SH=/bin/ash
	exec ${SH} --login
fi

exit 0
