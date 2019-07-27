#!/bin/bash
# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

__module_main() {
	_unpack_main
}

_unpack_main() {
	if [[ -z "${UNPACK_FILE}" ]]
	then
		die "Unable to unpack: UNPACK_FILE not set!"
	elif [[ ! -e "${UNPACK_FILE}" ]]
	then
		die "Unable to unpack: UNPACK_FILE '${UNPACK_FILE}' does NOT exist!"
	elif [[ -z "${UNPACK_DIR}" ]]
	then
		die "Unable to unpack: UNPACK_DIR not set!"
	elif [[ ! -d "${UNPACK_DIR}" ]]
	then
		mkdir -p "${UNPACK_DIR}" || die "Failed to create '${UNPACK_DIR}'!"
	fi

	"${TAR_COMMAND}" -xaf "${UNPACK_FILE}" --directory "${UNPACK_DIR}" \
		|| die "Failed to unpack '${UNPACK_FILE}' to '${UNPACK_DIR}'!"
}
