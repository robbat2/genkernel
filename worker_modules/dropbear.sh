#!/bin/bash
# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

__module_main() {
	if [[ -z "${DROPBEAR_COMMAND}" ]]
	then
		die "Do not know which dropbear command should run: DROPBEAR_COMMAND not set!"
	elif [[ -z "${DROPBEAR_KEY_FILE}" ]]
	then
		die "Unable to create new dropbear host key: DROPBEAR_KEY_FILE not set!"
	elif [[ -z "${DROPBEAR_KEY_TYPE}" ]]
	then
		die "Unable to create new dropbear host key: DROPBEAR_KEY_TYPE not set!"
	elif [[ -z "${TEMP}" ]]
	then
		die "Unable to do work: TEMP is not set!"
	fi

	local real_main_function=
	case "${DROPBEAR_COMMAND}" in
		*dropbearconvert)
			if [[ -n "${DROPBEAR_KEY_INFO_FILE}" ]]
			then
				real_main_function=_dropbear_create_key_info_file
			else
				real_main_function=_dropbear_create_from_host
			fi
			;;
		*dropbearkey)
			real_main_function=_dropbear_create_new
			;;
		*)
			die "Unknown DROPBEAR_COMMAND '${DROPBEAR_COMMAND}' set!"
			;;
	esac

	local dropbear_temp=$(mktemp -d -p "${TEMP}" dropbear.XXXXXXXX 2>/dev/null)
	[ -z "${dropbear_temp}" ] && die "mktemp failed!"

	cd "${dropbear_temp}" || die "Failed to chdir to '${dropbear_temp}'!"

	addwrite "/dev/random:/dev/urandom"

	${real_main_function}
}

_dropbear_create_from_host() {
	local keyname="dropbear_${DROPBEAR_KEY_TYPE}.key"

	local ssh_host_key=/etc/ssh/
	case "${DROPBEAR_KEY_TYPE}" in
		dss)
			ssh_host_key+=ssh_host_dsa_key
			;;
		ecdsa)
			ssh_host_key+=ssh_host_ecdsa_key
			;;
		ed25519)
			ssh_host_key+=ssh_host_ed25519_key
			;;
		rsa)
			ssh_host_key+=ssh_host_rsa_key
			;;
		*)
			die "Dropbear key type '${DROPBEAR_KEY_TYPE}' is unknown!"
			;;
	esac

	local ssh_host_keyname=$(basename "${ssh_host_key}")
	if [ -z "${ssh_host_keyname}" ]
	then
		die "Failed to get basename from '${ssh_host_key}'!"
	fi

	cp -aL "${ssh_host_key}" . || die "Failed to copy '${ssh_host_key}' to '$(pwd)'!"

	# Dropbear doesn't support RFC4716 format yet -- luckily ssh-keygen
	# can be used to convert existing key ...
	local command=( "ssh-keygen -p -P '' -N '' -m PEM -f ${ssh_host_keyname} &>/dev/null" )
	gkexec "${command[*]}"

	# Now we can convert using dropbearconvert ...
	command=( "${DROPBEAR_COMMAND} openssh dropbear ${ssh_host_keyname} ${keyname} &>/dev/null" )
	gkexec "${command[*]}"

	_dropbear_install "${keyname}"
}

_dropbear_create_key_info_file() {
	local ssh_key_file=
	case "${DROPBEAR_KEY_TYPE}" in
		dss)
			ssh_key_file=ssh_host_dsa_key
			;;
		ecdsa)
			ssh_key_file=ssh_host_ecdsa_key
			;;
		ed25519)
			ssh_key_file=ssh_host_ed25519_key
			;;
		rsa)
			ssh_key_file=ssh_host_rsa_key
			;;
		*)
			die "Dropbear key type '${DROPBEAR_KEY_TYPE}' is unknown!"
			;;
	esac

	local ssh_key_info_file="${ssh_key_file}.info"

	# Convert to SSH key format because dropbear only supports its own SHA1 implementation ...
	local command=( "${DROPBEAR_COMMAND} dropbear openssh ${DROPBEAR_KEY_FILE} ${ssh_key_file}" )
	gkexec "${command[*]}"

	# MD5
	ssh-keygen -l -E md5 -f ${ssh_key_file} > ${ssh_key_info_file} 2>/dev/null \
		|| die "Failed to extract MD5 fingerprint from SSH key '${ssh_key_file}'!"

	# SHA256
	ssh-keygen -l -E sha256 -f ${ssh_key_file} >> ${ssh_key_info_file} 2>/dev/null \
		|| die "Failed to extract MD5 fingerprint from SSH key '${ssh_key_file}'!"

	sed -i \
		-e 's/no comment //' \
		"${ssh_key_info_file}" \
		|| die "Failed to remove comment from '${ssh_key_info_file}'!"

	DROPBEAR_KEY_FILE=${DROPBEAR_KEY_INFO_FILE}
	_dropbear_install "${ssh_key_info_file}"
}

_dropbear_create_new() {
	local keyname="dropbear_${DROPBEAR_KEY_TYPE}.key"

	local command=( "${DROPBEAR_COMMAND} -t ${DROPBEAR_KEY_TYPE} -f ${keyname} &>/dev/null" )
	gkexec "${command[*]}"

	_dropbear_install "${keyname}"
}

_dropbear_install() {
	local keyfile=${1}
	if [[ -z "${keyfile}" || ! -f "${keyfile}" ]]
	then
		die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Keyfile '${keyfile}' is invalid!"
	fi

	local key_destdir=$(dirname "${DROPBEAR_KEY_FILE}")
	addwrite "${key_destdir}"

	if [[ ! -d "${key_destdir}" ]]
	then
		mkdir -p "${key_destdir}" || die "Failed to create '${key_destdir}'!"
	fi

	cp -a "${keyfile}" "${DROPBEAR_KEY_FILE}" || die "Failed copy '${keyfile}' to '${DROPBEAR_KEY_FILE}'!"

	# end here -- sandbox is open!
	exit 0
}
