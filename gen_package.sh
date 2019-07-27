#!/bin/bash
# $Id$

gen_minkernpackage() {
	print_info 1 "minkernpkg: >> Creating minimal kernel package in '${MINKERNPACKAGE}' ..."
	rm -rf "${TEMP}/minkernpackage" >/dev/null 2>&1
	mkdir "${TEMP}/minkernpackage" || gen_die "Failed to create '${TEMP}/minkernpackage'!"
	if [ -n "${KERNCACHE}" ]
	then
		"${TAR_COMMAND}" -x -C "${TEMP}"/minkernpackage -f "${KERNCACHE}" kernel-${ARCH}-${KV} \
			|| gen_die "Failed to extract 'kernel-${ARCH}-${KV}' from '${KERNCACHE}' to '${TEMP}/minkernpackage'!"

		mv "${TEMP}"/minkernpackage/{kernel-${ARCH}-${KV},kernel-${KNAME}-${ARCH}-${KV}} \
			|| gen_die "Failed to rename '${TEMP}/minkernpackage/kernel-${ARCH}-${KV}' to 'kernel-${KNAME}-${ARCH}-${KV}'!"

		"${TAR_COMMAND}" -x -C "${TEMP}"/minkernpackage -f "${KERNCACHE}" System.map-${ARCH}-${KV} \
			|| gen_die "Failed to extract 'System.map-${ARCH}-${KV}' from '${KERNCACHE}' to '${TEMP}/minkernpackage'!"

		mv "${TEMP}"/minkernpackage/{System.map-${ARCH}-${KV},System.map-${KNAME}-${ARCH}-${KV}} \
			|| gen_die "Failed to rename '${TEMP}/minkernpackage/System.map-${ARCH}-${KV}' to 'System.map-${KNAME}-${ARCH}-${KV}'!"

		"${TAR_COMMAND}" -x -C "${TEMP}"/minkernpackage -f "${KERNCACHE}" config-${ARCH}-${KV} \
			|| gen_die "Failed to extract 'config-${ARCH}-${KV}' from '${KERNCACHE}' to '${TEMP}/minkernpackage'!"

		mv "${TEMP}"/minkernpackage/{config-${ARCH}-${KV},config-${KNAME}-${ARCH}-${KV}} \
			|| gen_die "Failed to rename '${TEMP}/minkernpackage/config-${ARCH}-${KV}' to 'config-${KNAME}-${ARCH}-${KV}'!"

		if isTrue "${GENZIMAGE}"
		then
			"${TAR_COMMAND}" -x -C "${TEMP}"/minkernpackage -f "${KERNCACHE}" kernelz-${ARCH}-${KV} \
				|| gen_die "Failed to extract 'kernelz-${ARCH}-${KV}' from '${KERNCACHE}' to '${TEMP}/minkernpackage'!"

			mv "${TEMP}"/minkernpackage/{kernelz-${ARCH}-${KV},kernelz-${KNAME}-${ARCH}-${KV}} \
				|| gen_die "Failed to rename '${TEMP}/minkernpackage/kernelz-${ARCH}-${KV}' to 'kernelz-${KNAME}-${ARCH}-${KV}'!"
		fi
	else
		local tmp_kernel_binary=$(find_kernel_binary ${KERNEL_BINARY})
		if [ -z "${tmp_kernel_binary}" ]
		then
			gen_die "Failed to locate kernel binary '${KERNEL_BINARY}'!"
		fi

		cd "${KERNEL_OUTPUTDIR}" || gen_die "Failed to chdir to '${KERNEL_OUTPUTDIR}'!"

		cp "${tmp_kernel_binary}" "${TEMP}/minkernpackage/kernel-${KNAME}-${ARCH}-${KV}" \
			|| gen_die "Could not copy the kernel binary '${tmp_kernel_binary}' for the min kernel package!"

		cp "System.map" "${TEMP}/minkernpackage/System.map-${KNAME}-${ARCH}-${KV}" \
			|| gen_die "Could not copy '${KERNEL_OUTPUTDIR}/System.map' for the min kernel package!"

		cp ".config" "${TEMP}/minkernpackage/config-${KNAME}-${ARCH}-${KV}" \
			|| gen_die "Could not copy the kernel config '${KERNEL_OUTPUTDIR}/.config' for the min kernel package!"

		if isTrue "${GENZIMAGE}"
		then
			local tmp_kernel_binary2=$(find_kernel_binary ${KERNEL_BINARY_2})
			if [ -z "${tmp_kernel_binary2}" ]
			then
				gen_die "Failed to locate kernel binary '${KERNEL_BINARY_2}'!"
			fi

			cp "${tmp_kernel_binary2}" "${TEMP}/minkernpackage/kernelz-${KNAME}-${ARCH}-${KV}" \
				|| gen_die "Could not copy the kernelz binary '${tmp_kernel_binary2}' for the min kernel package!"
		fi
	fi

	if ! isTrue "${INTEGRATED_INITRAMFS}"
	then
		if isTrue "${BUILD_RAMDISK}"
		then
			cp "${TMPDIR}/initramfs-${KV}" "${TEMP}/minkernpackage/initramfs-${KNAME}-${ARCH}-${KV}" \
				|| gen_die "Could not copy the initramfs '${TMPDIR}/initramfs-${KV}' for the min kernel package!"
		fi
	fi

	cd "${TEMP}/minkernpackage" || gen_die "Failed to chdir to '${TEMP}/minkernpackage'!"

	local -a tar_cmd=( "$(get_tar_cmd "${MINKERNPACKAGE}")" )
	tar_cmd+=( '*' )

	print_info 3 "COMMAND: ${tar_cmd[*]}" 1 0 1
	eval "${tar_cmd[@]}" || gen_die "Failed to create compressed min kernel package '${MINKERNPACKAGE}'!"
}

gen_modulespackage() {
	if [ -d "${INSTALL_MOD_PATH}/lib/modules/${KV}" ]
	then
		print_info 1 "modulespkg: >> Creating modules package in '${MODULESPACKAGE}' ..."
		rm -rf "${TEMP}/modulespackage" >/dev/null 2>&1
		mkdir "${TEMP}/modulespackage" || gen_die "Failed to create '${TEMP}/modulespackage'!"

		mkdir -p "${TEMP}/modulespackage/lib/modules" || gen_die "Failed to create '${TEMP}/modulespackage/lib/modules'!"
		cp -arP "${INSTALL_MOD_PATH}/lib/modules/${KV}" "${TEMP}/modulespackage/lib/modules"

		cd "${TEMP}/modulespackage" || gen_die "Failed to chdir to '${TEMP}/modulespackage'!"

		local -a tar_cmd=( "$(get_tar_cmd "${MODULESPACKAGE}")" )
		tar_cmd+=( '*' )

		print_info 3 "COMMAND: ${tar_cmd[*]}" 1 0 1
		eval "${tar_cmd[@]}" || gen_die "Failed to create compressed modules package '${MODULESPACKAGE}'!"
	else
		print_info 1 "modulespkg: >> '${INSTALL_MOD_PATH}/lib/modules/${KV}' was not found; Skipping creation of modules package in '${MODULESPACKAGE}' ..."
	fi
}

gen_kerncache() {
	print_info 1 "kerncache: >> Creating kernel cache in '${KERNCACHE}' ..."
	rm -rf "${TEMP}/kerncache" >/dev/null 2>&1
	mkdir "${TEMP}/kerncache" || gen_die "Failed to create '${TEMP}/kerncache'!"

	local tmp_kernel_binary=$(find_kernel_binary ${KERNEL_BINARY})
	if [ -z "${tmp_kernel_binary}" ]
	then
		gen_die "Failed locate kernel binary '${KERNEL_BINARY}'!"
	fi

	cd "${KERNEL_OUTPUTDIR}" || gen_die "Failed to chdir to '${KERNEL_OUTPUTDIR}'!"

	cp -aL "${tmp_kernel_binary}" "${TEMP}/kerncache/kernel-${ARCH}-${KV}" \
		|| gen_die  "Could not copy the kernel binary '${tmp_kernel_binary}' for the kernel package!"

	cp -aL "${KERNEL_OUTPUTDIR}/.config" "${TEMP}/kerncache/config-${ARCH}-${KV}" \
		|| gen_die "Could not copy the kernel config '${KERNEL_OUTPUTDIR}/.config' for the kernel package!"

	if isTrue "$(is_gzipped "${KERNEL_CONFIG}")"
	then
		# Support --kernel-config=/proc/config.gz, mainly
		zcat "${KERNEL_CONFIG}" > "${TEMP}/kerncache/config-${ARCH}-${KV}.orig" \
			|| gen_die "Could not copy the kernel config '${KERNEL_CONFIG}' for the kernel package!"
	else
		cp -aL "${KERNEL_CONFIG}" "${TEMP}/kerncache/config-${ARCH}-${KV}.orig" \
			|| gen_die "Could not copy the kernel config '${KERNEL_CONFIG}' for the kernel package!"
	fi

	cp -aL "${KERNEL_OUTPUTDIR}/System.map" "${TEMP}/kerncache/System.map-${ARCH}-${KV}" \
		|| gen_die "Could not copy the System.map '${KERNEL_OUTPUTDIR}/System.map' for the kernel package!"

	if isTrue "${GENZIMAGE}"
	then
		local tmp_kernel_binary2=$(find_kernel_binary ${KERNEL_BINARY_2})
		if [ -z "${tmp_kernel_binary2}" ]
		then
			gen_die "Failed locate kernelz binary '${KERNEL_BINARY_2}'!"
		fi

		cp -aL "${tmp_kernel_binary2}" "${TEMP}/kerncache/kernelz-${ARCH}-${KV}" \
			|| gen_die "Could not copy the kernelz '${tmp_kernel_binary2}' for the kernel package!"
	fi

	echo "VERSION = ${VER}" > "${TEMP}/kerncache/kerncache.config" \
		|| gen_die "Failed to write to '${TEMP}/kerncache/kerncache.config'!"

	echo "PATCHLEVEL = ${PAT}" >> "${TEMP}/kerncache/kerncache.config"
	echo "SUBLEVEL = ${SUB}" >> "${TEMP}/kerncache/kerncache.config"
	echo "EXTRAVERSION = ${EXV}" >> "${TEMP}/kerncache/kerncache.config"
	echo "CONFIG_LOCALVERSION = ${LOV}" >> "${TEMP}/kerncache/kerncache.config"

	mkdir -p "${TEMP}/kerncache/lib/modules/" \
		|| gen_die "Failed to create '${TEMP}/kerncache/lib/modules'"

	if [ -d "${INSTALL_MOD_PATH}/lib/modules/${KV}" ]
	then
		cp -arP "${INSTALL_MOD_PATH}/lib/modules/${KV}" "${TEMP}/kerncache/lib/modules"
	fi

	cd "${TEMP}/kerncache" || gen_die "Failed to chdir to '${TEMP}/kerncache'!"

	local -a tar_cmd=( "$(get_tar_cmd "${KERNCACHE}")" )
	tar_cmd+=( '*' )

	print_info 3 "COMMAND: ${tar_cmd[*]}" 1 0 1
	eval "${tar_cmd[@]}" || gen_die "Failed to create compressed kernel package '${KERNCACHE}'!"
}

gen_kerncache_extract_kernel() {
	print_info 1 "Extracting kerncache kernel from '${KERNCACHE}' ..."
	"${TAR_COMMAND}" -xf "${KERNCACHE}" -C "${TEMP}" \
		|| gen_die "Failed to extract '${KERNCACHE}' to '${TEMP}'!"

	copy_image_with_preserve \
		"kernel" \
		"${TEMP}/kernel-${ARCH}-${KV}" \
		"kernel-${KNAME}-${ARCH}-${KV}"

	if isTrue "${GENZIMAGE}"
	then
		copy_image_with_preserve \
			"kernelz" \
			"${TEMP}/kernelz-${ARCH}-${KV}" \
			"kernelz-${KNAME}-${ARCH}-${KV}"
	fi

	copy_image_with_preserve \
		"System.map" \
		"${TEMP}/System.map-${ARCH}-${KV}" \
		"System.map-${KNAME}-${ARCH}-${KV}"
}

gen_kerncache_extract_modules() {
	print_info 1 "Extracting kerncache kernel modules from '${KERNCACHE}' ..."
	if [ -n "${INSTALL_MOD_PATH}" ]
	then
		"${TAR_COMMAND}" -xf "${KERNCACHE}" --strip-components 1 -C "${INSTALL_MOD_PATH}"/lib \
			|| gen_die "Failed to extract kerncache modules from '${KERNCACHE}' to '${INSTALL_MOD_PATH}/lib'!"
	else
		"${TAR_COMMAND}" -xf "${KERNCACHE}" --strip-components 1 -C /lib \
			|| gen_die "Failed to extract kerncache modules from '${KERNCACHE}' to '${INSTALL_MOD_PATH}/lib'!"
	fi
}

gen_kerncache_extract_config() {
	print_info 1 "Extracting kerncache config from '${KERNCACHE}' to /etc/kernels ..."

	if [ ! -d '/etc/kernels' ]
	then
		mkdir -p /etc/kernels || gen_die "Failed to create '/etc/kernels'!"
	fi

	"${TAR_COMMAND}" -xf "${KERNCACHE}" -C /etc/kernels config-${ARCH}-${KV} \
		|| gen_die "Failed to extract kerncache config 'config-${ARCH}-${KV}' from '${KERNCACHE}' to '/etc/kernels'!"

	mv /etc/kernels/config-${ARCH}-${KV} /etc/kernels/kernel-config-${ARCH}-${KV} \
		|| gen_die "Failed to rename kernelcache config '/etc/kernels/config-${ARCH}-${KV}' to '/etc/kernels/kernel-config-${ARCH}-${KV}'!"
}

gen_kerncache_is_valid() {
	KERNCACHE_IS_VALID="no"

	if [ -e "${KERNCACHE}" ]
	then
		"${TAR_COMMAND}" -xf "${KERNCACHE}" -C "${TEMP}" \
			|| gen_die "Failed to extract '${KERNCACHE}' to '${TEMP}'!"

		if ! isTrue "${KERNEL_SOURCES}"
		then
			BUILD_KERNEL="no"
			# Can make this more secure ....

			if [ -e "${TEMP}/config-${ARCH}-${KV}" -a -e "${TEMP}/kernel-${ARCH}-${KV}" ]
			then
				print_info 1 '' 1 0
				print_info 1 'Valid kerncache found; No sources will be used ...'
				KERNCACHE_IS_VALID="yes"
			fi
		else
			if [ -e "${TEMP}/config-${ARCH}-${KV}" -a -e "${KERNEL_CONFIG}" ]
			then
				if [ -e "${TEMP}/config-${ARCH}-${KV}.orig" ]
				then
					local test1=$(grep -v "^#" "${TEMP}/config-${ARCH}-${KV}.orig" | md5sum | cut -d " " -f 1)
				else
					local test1=$(grep -v "^#" "${TEMP}/config-${ARCH}-${KV}" | md5sum | cut -d " " -f 1)
				fi

				if isTrue "$(is_gzipped "${KERNEL_CONFIG}")"
				then
					# Support --kernel-config=/proc/config.gz, mainly
					local CONFGREP=zgrep
				else
					local CONFGREP=grep
				fi
				local test2=$("${CONFGREP}" -v "^#" "${KERNEL_CONFIG}" | md5sum | cut -d " " -f 1)

				if [[ "${test1}" == "${test2}" ]]
				then
					print_info 1 '' 1 0
					print_info 1 "Valid kerncache '${KERNCACHE}' found; Will skip kernel build step ..."
					KERNCACHE_IS_VALID="yes"
				else
					print_info 1 '' 1 0
					print_info 1 "Kerncache kernel config differs from '${KERNEL_CONFIG}'; Ignoring outdated kerncache '${KERNCACHE}' ..."
				fi
			else
				local invalid_reason="Kerncache does not contain kernel config"
				if [ ! -e "${KERNEL_CONFIG}" ]
				then
					invalid_reason="Kernel config '${KERNEL_CONFIG}' does not exist -- cannot validate kerncache"
				fi

				print_info 1 '' 1 0
				print_info 1 "${invalid_reason}; Ignorning kerncache '${KERNCACHE}' ..."
			fi
		fi
	else
		print_warning 1 '' 1 0
		print_warning 1 "Kerncache '${KERNCACHE}' does not exist (yet?); Ignoring ..."
	fi

	export KERNCACHE_IS_VALID
}
