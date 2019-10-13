# $Id$

set_bootloader() {
	print_info 1 ''

	# When adding/removing supported bootloaders, do NOT forget
	# to update print_warning in genkernel file as well.
	case "${BOOTLOADER}" in
		grub)
			set_bootloader_grub
			;;
		grub2)
			set_bootloader_grub2
			;;
		no)
			print_info 1 "--no-bootloader set; Skipping bootloader update ..."
			;;
		*)
			print_warning 1 "Bootloader '${BOOTLOADER}' is currently not supported; Skipping bootloader update ..."
			;;
	esac
}

set_bootloader_read_fstab() {
	local ROOTFS=$(awk 'BEGIN{RS="((#[^\n]*)?\n)"}( $2 == "/" ) { print $1; exit }' /etc/fstab)
	local BOOTFS=$(awk 'BEGIN{RS="((#[^\n]*)?\n)"}( $2 == "'${BOOTDIR}'") { print $1; exit }' /etc/fstab)

	# If ${BOOTDIR} is not defined in /etc/fstab, it must be the same as /
	[ -z "${BOOTFS}" ] && BOOTFS=${ROOTFS}

	echo "${ROOTFS} ${BOOTFS}"
}

set_bootloader_grub2() {
	local GRUB_CONF
	for candidate in \
		"${BOOTDIR}/grub/grub.cfg" \
		"${BOOTDIR}/grub2/grub.cfg" \
	; do
		if [[ -e "${candidate}" ]]
		then
			GRUB_CONF=${candidate}
			break
		fi
	done

	if [[ -z "${GRUB_CONF}" ]]
	then
		print_error 1 "Error! Grub2 configuration file does not exist, please ensure grub2 is correctly setup first."
		return 0
	fi

	print_info 1 "You can customize Grub2 parameters in /etc/default/grub."
	print_info 1 "Running grub-mkconfig to create '${GRUB_CONF}' ..."
	grub-mkconfig -o "${GRUB_CONF}" 2>/dev/null \
		|| grub2-mkconfig -o "${GRUB_CONF}" 2>/dev/null \
		|| gen_die "grub-mkconfig failed!"

	isTrue "${BUILD_RAMDISK}" && sed -i 's/ro single/ro debug/' "${GRUB_CONF}"
}

set_bootloader_grub() {
	local GRUB_CONF="${BOOTDIR}/grub/grub.conf"

	print_info 1 "Adding kernel to '${GRUB_CONF}' ..."

	if [ ! -e ${GRUB_CONF} ]
	then
		print_warning 1 "No ${GRUB_CONF} found, generating!"
		local GRUB_BOOTFS
		if [ -n "${BOOTFS}" ]
		then
			GRUB_BOOTFS=$BOOTFS
		else
			GRUB_BOOTFS=$(set_bootloader_read_fstab | cut -d' ' -f2)
		fi

		# Get the GRUB mapping for our device
		echo "quit" | grub --batch --device-map="${TEMP}/grub.map" &>/dev/null

		local GRUB_BOOT_DISK1=$(echo ${GRUB_BOOTFS} | sed -e 's#\(/dev/.\+\)[[:digit:]]\+#\1#')
		local GRUB_BOOT_DISK=$(awk '{if ($2 == "'${GRUB_BOOT_DISK1}'") {gsub(/(\(|\))/, "", $1); print $1;}}' "${TEMP}/grub.map")
		local GRUB_BOOT_PARTITION=$(($(echo ${GRUB_BOOTFS} | sed -e 's#/dev/.\+\([[:digit:]]?*\)#\1#') - 1))

		if [ -n "${GRUB_BOOT_DISK}" -a -n "${GRUB_BOOT_PARTITION}" ]
		then

			# Create grub configuration directory and file if it doesn't exist.
			local GRUB_CONF_DIR=$(dirname "${GRUB_CONF}")
			if [ ! -d "${GRUB_CONF_DIR}" ]
			then
				mkdir -p "${GRUB_CONF_DIR}" \
					|| gen_die "Failed to create GRUB config directory '${GRUB_CONF_DIR}'!"
			fi

			touch ${GRUB_CONF}
			echo 'default 0' >> ${GRUB_CONF}
			echo 'timeout 5' >> ${GRUB_CONF}
			echo "root (${GRUB_BOOT_DISK},${GRUB_BOOT_PARTITION})" >> ${GRUB_CONF}
			echo >> ${GRUB_CONF}

			# Add grub configuration to grub.conf
			echo "# Genkernel generated entry, see GRUB documentation for details" >> ${GRUB_CONF}
			echo "title=Gentoo Linux ($KV)" >> ${GRUB_CONF}
			printf "%b\n" "\tkernel /${GK_FILENAME_KERNEL} root=${GRUB_ROOTFS}" >> ${GRUB_CONF}
			if isTrue "${BUILD_RAMDISK}"
			then
				if [ "${PAT}" -gt '4' ]
				then
					printf "%b\n" "\tinitrd /${GK_FILENAME_INITRAMFS}" >> ${GRUB_CONF}
				fi
			fi
			echo >> ${GRUB_CONF}
		else
			print_error 1 "Error! ${BOOTDIR}/grub/grub.conf does not exist and the correct settings can not be automatically detected."
			print_error 1 "Please manually create your ${BOOTDIR}/grub/grub.conf file."
		fi

	else
		# The grub.conf already exists, so let's try to duplicate the default entry
		if set_bootloader_grub_check_for_existing_entry "${GRUB_CONF}"; then
			print_warning 1 "An entry was already found for a kernel/initramfs with this name; Skipping update ..."
			return 0
		fi

		set_bootloader_grub_duplicate_default "${GRUB_CONF}"
	fi

}

set_bootloader_grub_duplicate_default_replace_kernel_initrd() {
	sed -r -e "s/(^[[:space:]]*kernel[[:space:]=]*\/)(${GK_FILENAME_KERNEL%%-*}|${GK_FILENAME_KERNEL_SYMLINK%%-*}|kernel)(-[[:alnum:][:punct:]]+)?/\1${GK_FILENAME_KERNEL}/" - |
	sed -r -e "s/(^[[:space:]]*initrd[[:space:]=]*\/)(${GK_FILENAME_INITRAMFS%%-*}|${GK_FILENAME_INITRAMFS_SYMLINK%%-*}|initrd|initramfs)(-[[:alnum:][:punct:]]+)?/\1${GK_FILENAME_INITRAMFS}/"
}

set_bootloader_grub_check_for_existing_entry() {
	local GRUB_CONF=$1
	if grep -q "^[[:space:]]*kernel[[:space:]=]*/${GK_FILENAME_KERNEL}\([[:space:]]\|$\)" "${GRUB_CONF}" &&
		grep -q "^[[:space:]]*initrd[[:space:]=]*/${GK_FILENAME_INITRAMFS}\([[:space:]]\|$\)" "${GRUB_CONF}"
	then
		return 0
	fi
	return 1
}

set_bootloader_grub_duplicate_default() {
	local GRUB_CONF=$1
	local GRUB_CONF_TMP="${GRUB_CONF}.tmp"

	line_count=$(wc -l < "${GRUB_CONF}")
	line_nums="$(grep -n "^title" "${GRUB_CONF}" | cut -d: -f1)"
	if [ -z "${line_nums}" ]; then
		print_error 1 "No current 'title' entries found in your grub.conf; Skipping update ..."
		return 0
	fi
	line_nums="${line_nums} $((${line_count}+1))"

	# Find default entry
	default=$(sed -rn '/^[[:space:]]*default[[:space:]=]/s/^.*default[[:space:]=]+([[:alnum:]]+).*$/\1/p' "${GRUB_CONF}")
	if [ -z "${default}" ]
	then
		print_warning 1 "No default entry found; Assuming 0 ..."
		default=0
	fi
	if ! echo ${default} | grep -q '^[0-9]\+$'; then
		print_error 1 "We don't support non-numeric (such as 'saved') default values; Skipping update ..."
		return 0
	fi

	# Grub defaults are 0 based, cut is 1 based
	# Figure out where the default entry lives
	startstop=$(echo ${line_nums} | cut -d" " -f$((${default}+1))-$((${default}+2)))
	startline=$(echo ${startstop} | cut -d" " -f1)
	stopline=$(echo ${startstop} | cut -d" " -f2)

	# Write out the bits before the default entry
	sed -n 1,$((${startline}-1))p "${GRUB_CONF}" > "${GRUB_CONF_TMP}"

	# Put in our title
	echo "title=Gentoo Linux (${KV})" >> "${GRUB_CONF_TMP}"

	# Pass the default entry (minus the title) through to the replacement function and pipe the output to GRUB_CONF_TMP
	sed -n $((${startline}+1)),$((${stopline}-1))p "${GRUB_CONF}" | set_bootloader_grub_duplicate_default_replace_kernel_initrd >> "${GRUB_CONF_TMP}"

	# Finish off with everything including the previous default entry
	sed -n ${startline},${line_count}p "${GRUB_CONF}" >> "${GRUB_CONF_TMP}"

	cp "${GRUB_CONF}" "${GRUB_CONF}.bak"
	cp "${GRUB_CONF_TMP}" "${GRUB_CONF}"
	rm "${GRUB_CONF_TMP}"
}
