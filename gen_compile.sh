#!/bin/bash
# $Id$

compile_external_modules() {
	local command="emerge --quiet @module-rebuild 2>&1"

	if ! isTrue "${CMD_MODULEREBUILD}"
	then
		print_info 3 "$(get_indent 1)>> --no-module-rebuild set; Skipping 'emerge @module-rebuild' ..."
		return
	fi

	if isTrue "$(tc-is-cross-compiler)"
	then
		print_info 3 "$(get_indent 1)>> Cross-compilation detected; Skipping 'emerge @module-rebuild' ..."
		return
	fi

	if ! isTrue "${CMD_INSTALL}"
	then
		print_info 3 "$(get_indent 1)>> --no-install set; Skipping 'emerge @module-rebuild' ..."
		return
	fi

	if [ -n "${INSTALL_MOD_PATH}" ]
	then
		# emerge would install to a different location
		print_warning 1 "$(get_indent 1)>> INSTALL_MOD_PATH set; Skipping 'emerge @module-rebuild' ..."
		return
	fi

	local modulesdb_file="/var/lib/module-rebuild/moduledb"
	if [ ! -s "${modulesdb_file}" ]
	then
		print_info 2 "$(get_indent 1)>> '${modulesdb_file}' does not exist or is empty; Skipping 'emerge @module-rebuild' ..."
		return
	fi

	local -x KV_OUT_DIR="${KERNEL_OUTPUTDIR}"

	print_info 1 "$(get_indent 1)>> Compiling out-of-tree module(s) ..."
	print_info 3 "COMMAND: ${command}" 1 0 1

	if [ "${LOGLEVEL}" -gt 3 ]
	then
		# Output to stdout and logfile
		eval ${command} | tee -a "${LOGFILE}"
		RET=${PIPESTATUS[0]}
	else
		# Output to logfile only
		eval ${command} >> "${LOGFILE}"
		RET=$?
	fi

	[ ${RET} -ne 0 ] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")${FUNCNAME}() failed to compile out-of-tree-modules!"
}

compile_gen_init_cpio() {
	local gen_init_cpio_SRC="${KERNEL_DIR}/usr/gen_init_cpio.c"
	local gen_init_cpio_DIR="${KERNEL_OUTPUTDIR}/usr"

	print_info 2 "$(get_indent 2)>> Compiling gen_init_cpio ..."

	[ ! -e "${gen_init_cpio_SRC}" ] && gen_die "'${gen_init_cpio_SRC}' is missing. Cannot compile gen_init_cpio!"
	if [ ! -d "${gen_init_cpio_DIR}" ]
	then
		mkdir -p "${gen_init_cpio_DIR}" || gen_die "Failed to create '${gen_init_cpio_DIR}'!"
	fi

	local CC=$(tc-getBUILD_CC)

	${CC} -O2 "${KERNEL_DIR}/usr/gen_init_cpio.c" -o "${KERNEL_OUTPUTDIR}/usr/gen_init_cpio" -Wl,--no-as-needed \
		|| gen_die 'Failed to compile gen_init_cpio!'
}

compile_generic() {
	[[ ${#} -ne 2 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly two arguments (${#} given)!"

	local target=${1}
	local argstype=${2}
	local RET

	case "${argstype}" in
		kernel|kernelruntask)
			if [ -z "${KERNEL_MAKE}" ]
			then
				gen_die "KERNEL_MAKE undefined - I don't know how to compile a kernel for this arch!"
			else
				local MAKE=${KERNEL_MAKE}
			fi

			# Build kernel compile parameter.
			local ARGS=""

			# Allow for CC/LD... user override!
			local -a kernel_vars
			kernel_vars+=( 'ARCH' )
			kernel_vars+=( 'AS' )
			kernel_vars+=( 'CC' )
			kernel_vars+=( 'LD' )

			local kernel_var=
			for kernel_var in "${kernel_vars[@]}"
			do
				local kernel_varname="KERNEL_${kernel_var}"
				local kernel_default_varname="DEFAULT_${kernel_varname}"

				if [[ -z "${!kernel_default_varname}" ]] \
					|| [[ -n "${!kernel_default_varname}" ]] \
					&& [[ "${!kernel_varname}" != "${!kernel_default_varname}" ]]
				then
					ARGS="${ARGS} ${kernel_var}=\"${!kernel_varname}\""
				fi
			done
			unset kernel_var kernel_vars kernel_varname kernel_default_varname

			if isTrue "$(tc-is-cross-compiler)"
			then
				local can_tc_cross_compile=no
				local cpu_cbuild=${CBUILD%%-*}
				local cpu_chost=${CHOST%%-*}

				case "${cpu_cbuild}" in
					powerpc64*)
						if [[ "${cpu_chost}" == "powerpc" ]]
						then
							can_tc_cross_compile=yes
						fi
						;;
					x86_64*)
						if [[ "${cpu_chost}" == "i686" ]]
						then
							can_tc_cross_compile=yes
						fi
						;;
				esac

				if isTrue "${can_tc_cross_compile}"
				then
					local -a kernel_vars
					kernel_vars+=( 'AS' )
					kernel_vars+=( 'CC' )
					kernel_vars+=( 'LD' )

					local kernel_var=
					for kernel_var in "${kernel_vars[@]}"
					do
						if [[ "${ARGS}" == *${kernel_var}=* ]]
						then
							# User wants to run specific program ...
							continue
						else
							ARGS="${ARGS} ${kernel_var}=\"$(tc-get${kernel_var})\""
						fi
					done
					unset kernel_var kernel_vars
				else
					ARGS="${ARGS} CROSS_COMPILE=\"${CHOST}-\""
				fi
				unset can_tc_cross_compile cpu_cbuild cpu_chost
			fi

			if [ -n "${KERNEL_OUTPUTDIR}" -a "${KERNEL_OUTPUTDIR}" != "${KERNEL_DIR}" ]
			then
				if [ -f "${KERNEL_DIR}/.config" -o -d "${KERNEL_DIR}/include/config" ]
				then
					# Kernel's build system doesn't remove all files
					# even when "make clean" was called which will cause
					# build failures when KERNEL_OUTPUTDIR will change.
					#
					# See https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Makefile?h=v5.0#n1067 for details
					error_message="'${KERNEL_DIR}' is tainted and cannot be used"
					error_message+=" to compile a kernel with different KERNEL_OUTPUTDIR set."
					error_message+=" Please re-install a fresh kernel source!"
					gen_die "${error_message}"
				else
					ARGS="${ARGS} O=\"${KERNEL_OUTPUTDIR}\""
				fi
			fi
			;;
		*)
			local error_msg="${FUNCNAME[1]}(): Unsupported compile type '${argstype}'"
			error_msg+=" for ${FUNCNAME}() specified!"
			gen_die "${error_msg}"
			;;
	esac
	shift 2

	if [ ${NICE} -ne 0 ]
	then
		NICEOPTS="nice -n${NICE} "
	else
		NICEOPTS=""
	fi

	# the eval usage is needed in the next set of code
	# as ARGS can contain spaces and quotes, eg:
	# ARGS='CC="ccache gcc"'
	if [ "${argstype}" == 'kernelruntask' ]
	then
		# Silent operation, forced -j1
		print_info 3 "COMMAND: ${NICEOPTS}${MAKE} ${MAKEOPTS} -j1 ${ARGS} ${target} $*" 1 0 1
		eval ${NICEOPTS}${MAKE} -s ${MAKEOPTS} -j1 ${ARGS} ${target} $*
		RET=$?
	elif [ "${LOGLEVEL}" -gt 3 ]
	then
		# Output to stdout and logfile
		print_info 3 "COMMAND: ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $*" 1 0 1
		eval ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $* 2>&1 | tee -a "${LOGFILE}"
		RET=${PIPESTATUS[0]}
	else
		# Output to logfile only
		print_info 3 "COMMAND: ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $*" 1 0 1
		eval ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $* >> "${LOGFILE}" 2>&1
		RET=$?
	fi

	[ ${RET} -ne 0 ] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")${FUNCNAME}() failed to compile the \"${target}\" target!"
}

compile_modules() {
	print_info 1 "$(get_indent 1)>> Compiling ${KV} modules ..."

	cd "${KERNEL_DIR}" || gen_die "Failed to chdir to '${KERNEL_DIR}'!"

	# required for modutils
	local -x UNAME_MACHINE="${ARCH}"

	compile_generic modules kernel

	[ -n "${INSTALL_MOD_PATH}" ] && local -x INSTALL_MOD_PATH="${INSTALL_MOD_PATH}"
	if [ "${CMD_STRIP_TYPE}" == "all" -o "${CMD_STRIP_TYPE}" == "modules" ]
	then
		print_info 1 "$(get_indent 1)>> Installing ${KV} modules (and stripping) ..."
		local -x INSTALL_MOD_STRIP=1
	else
		print_info 1 "$(get_indent 1)>> Installing ${KV} modules ..."
		unset INSTALL_MOD_STRIP
	fi

	compile_generic "modules_install" kernel

	print_info 1 "$(get_indent 1)>> Generating module dependency data ..."
	if [ -n "${INSTALL_MOD_PATH}" ]
	then
		depmod -a -e -F "${KERNEL_OUTPUTDIR}"/System.map -b "${INSTALL_MOD_PATH}" ${KV} \
			|| gen_die "depmod (INSTALL_MOD_PATH=${INSTALL_MOD_PATH}) failed!"
	else
		depmod -a -e -F "${KERNEL_OUTPUTDIR}"/System.map ${KV} \
			|| gen_die "depmod failed!"
	fi
}

compile_kernel() {
	[ -z "${KERNEL_MAKE}" ] \
		&& gen_die "KERNEL_MAKE undefined - I don't know how to compile a kernel for this arch!"

	cd "${KERNEL_DIR}" || gen_die "Failed to chdir to '${KERNEL_DIR}'!"

	local kernel_make_directive="${KERNEL_MAKE_DIRECTIVE}"
	if [ "${KERNEL_MAKE_DIRECTIVE_OVERRIDE}" != "${DEFAULT_KERNEL_MAKE_DIRECTIVE_OVERRIDE}" ]; then
		kernel_make_directive="${KERNEL_MAKE_DIRECTIVE_OVERRIDE}"
	fi

	print_info 1 "$(get_indent 1)>> Compiling ${KV} ${kernel_make_directive/_install/ [ install ]/} ..."
	compile_generic "${kernel_make_directive}" kernel

	if [ -n "${KERNEL_MAKE_DIRECTIVE_2}" ]
	then
		print_info 1 "$(get_indent 1)>> Starting supplimental compile of ${KV}: ${KERNEL_MAKE_DIRECTIVE_2} ..."
		compile_generic "${KERNEL_MAKE_DIRECTIVE_2}" kernel
	fi

	if isTrue "${FIRMWARE_INSTALL}" && [ ${KV_NUMERIC} -ge 4014 ]
	then
		# Kernel v4.14 removed firmware from the kernel sources
		print_warning 1 "$(get_indent 1)>> Linux v4.14 removed in-kernel firmware, you MUST install the sys-kernel/linux-firmware package!"
	elif isTrue "${FIRMWARE_INSTALL}"
	then
		local cfg_CONFIG_FIRMWARE_IN_KERNEL=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" CONFIG_FIRMWARE_IN_KERNEL)
		if isTrue "$cfg_CONFIG_FIRMWARE_IN_KERNEL"
		then
			print_info 1 "$(get_indent 1)>> Not installing firmware as it's included in the kernel already (CONFIG_FIRMWARE_IN_KERNEL=y) ..."
		else
			print_info 1 "$(get_indent 1)>> Installing firmware ('make firmware_install') due to CONFIG_FIRMWARE_IN_KERNEL != y ..."
			[ "${INSTALL_MOD_PATH}" != '' ] && export INSTALL_MOD_PATH
			[ "${INSTALL_FW_PATH}" != '' ] && export INSTALL_FW_PATH
			MAKEOPTS="${MAKEOPTS} -j1" compile_generic "firmware_install" kernel
		fi
	elif [ ${KV_NUMERIC} -lt 4014 ]
	then
		print_info 1 "$(get_indent 1)>> Skipping installation of bundled firmware due to --no-firmware-install ..."
	fi

	local tmp_kernel_binary=$(find_kernel_binary ${KERNEL_BINARY_OVERRIDE:-${KERNEL_BINARY}})
	local tmp_kernel_binary2=$(find_kernel_binary ${KERNEL_BINARY_2})
	if [ -z "${tmp_kernel_binary}" ]
	then
		gen_die "Cannot locate kernel binary"
	fi

	# if source != outputdir, we need this:
	tmp_kernel_binary="${KERNEL_OUTPUTDIR}"/"${tmp_kernel_binary}"
	tmp_kernel_binary2="${KERNEL_OUTPUTDIR}"/"${tmp_kernel_binary2}"
	local tmp_systemmap="${KERNEL_OUTPUTDIR}"/System.map

	if isTrue "${CMD_INSTALL}"
	then
		copy_image_with_preserve \
			"${GK_FILENAME_KERNEL_SYMLINK}" \
			"${tmp_kernel_binary}" \
			"${GK_FILENAME_KERNEL}"

		copy_image_with_preserve \
			"${GK_FILENAME_SYSTEMMAP_SYMLINK}" \
			"${tmp_systemmap}" \
			"${GK_FILENAME_SYSTEMMAP}"

		if isTrue "${GENZIMAGE}"
		then
			copy_image_with_preserve \
				"kernelz" \
				"${tmp_kernel_binary2}" \
				"${GK_FILENAME_KERNELZ}"
		fi
	else
		cp "${tmp_kernel_binary}" "${TMPDIR}/${GK_FILENAME_TEMP_KERNEL}" \
			|| gen_die "Could not copy kernel binary '${tmp_kernel_binary}' to '${TMPDIR}'!"

		cp "${tmp_systemmap}" "${TMPDIR}/${GK_FILENAME_TEMP_SYSTEMMAP}" \
			|| gen_die "Could not copy System.map '${tmp_systemmap}' to '${TMPDIR}'!"

		if isTrue "${GENZIMAGE}"
		then
			cp "${tmp_kernel_binary2}" "${TMPDIR}/${GK_FILENAME_TEMP_KERNELZ}" \
				|| gen_die "Could not copy kernelz binary '${tmp_kernel_binary2}' to '${TMPDIR}'!"
		fi
	fi
}

determine_busybox_config_file() {
	if [ -n "${BUSYBOX_CONFIG}" ]
	then
		print_info 2 "$(get_indent 2)busybox: >> Using user-specified busybox configuration from '${BUSYBOX_CONFIG}' ..."
		return
	fi

	print_info 2 "$(get_indent 2)busybox: >> Checking for suitable busybox configuration ..."

	local -a bbconfig_candidates=()
	local busybox_version=$(get_gkpkg_version busybox)

	if isTrue "${NETBOOT}"
	then
		bbconfig_candidates+=( "$(arch_replace "${GK_SHARE}/arch/%%ARCH%%/netboot-busy-config-${busybox_version}")" )
		bbconfig_candidates+=( "$(arch_replace "${GK_SHARE}/arch/%%ARCH%%/netboot-busy-config")" )
		bbconfig_candidates+=( "${GK_SHARE}/netboot/busy-config-${busybox_version}" )
		bbconfig_candidates+=( "${GK_SHARE}/netboot/busy-config" )
	fi
	bbconfig_candidates+=( "$(arch_replace "${GK_SHARE}/arch/%%ARCH%%/busy-config-${busybox_version}")" )
	bbconfig_candidates+=( "$(arch_replace "${GK_SHARE}/arch/%%ARCH%%/busy-config")" )
	bbconfig_candidates+=( "${GK_SHARE}/defaults/busy-config-${busybox_version}" )
	bbconfig_candidates+=( "${GK_SHARE}/defaults/busy-config" )

	local f
	for f in "${bbconfig_candidates[@]}"
	do
		[ -z "${f}" ] && continue

		if [ -f "${f}" ]
		then
			BUSYBOX_CONFIG="$f"
			break
		else
			print_info 3 "$(get_indent 3)- '${f}' not found; Skipping ..."
		fi
	done

	if [ -z "${BUSYBOX_CONFIG}" ]
	then
		# Sanity check
		gen_die 'No busybox .config specified or file not found!'
	fi
}

populate_binpkg() {
	[[ ${#} -gt 2 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at most two arguments (${#} given)!"

	[[ ${#} -lt 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at least one argument (${#} given)!"

	local PN=${1}
	[[ -z "${PN}" ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): No package specified!"

	local PV=$(get_gkpkg_version "${PN}")
	local P=${PN}-${PV}

	local BINPKG=$(get_gkpkg_binpkg "${PN}")

	local -a GKBUILD_CANDIDATES=( "${GK_SHARE}"/gkbuilds/${P}.gkbuild )
	GKBUILD_CANDIDATES+=( "${GK_SHARE}"/gkbuilds/${PN}.gkbuild )

	if [[ ${#} -eq 1 ]]
	then
		local CHECK_LEVEL_CURRENT=0
		local CHECK_LEVEL_PARENT=0
		local CHECK_LEVEL_NEXT=${CHECK_LEVEL_CURRENT}
	else
		local CHECK_LEVEL_PARENT=${2}
		local CHECK_LEVEL_CURRENT=$[${CHECK_LEVEL_PARENT}+1]
		local CHECK_LEVEL_NEXT=${CHECK_LEVEL_CURRENT}
	fi

	local REQUIRED_BINPKGS_PARENT_VARNAME="CHECK_L${CHECK_LEVEL_PARENT}_REQUIRED_BINPKGS"
	local REQUIRED_BINPKGS_CURRENT_VARNAME="CHECK_L${CHECK_LEVEL_CURRENT}_REQUIRED_BINPKGS"
	local -n REQUIRED_BINPKGS_CURRENT_VARNAME_ref="${REQUIRED_BINPKGS_CURRENT_VARNAME}"

	# Make sure we start with an empty array just in case ...
	eval declare -ga ${REQUIRED_BINPKGS_CURRENT_VARNAME}=\(\)

	local CHECK_LEVEL_PREFIX=
	local i=0
	while [[ ${i} < ${CHECK_LEVEL_CURRENT} ]]
	do
		CHECK_LEVEL_PREFIX="${CHECK_LEVEL_PREFIX% }> "
		i=$[${i}+1]
	done
	unset i

	local -a pkg_deps=( $(get_gkpkg_deps "${PN}") )
	if [[ ${#pkg_deps[@]} -gt 0 ]]
	then
		print_info 3 "${CHECK_LEVEL_PREFIX}Checking for binpkg(s) required for ${P} (L${CHECK_LEVEL_CURRENT}) ..."

		local pkg_dep=
		for pkg_dep in "${pkg_deps[@]}"
		do
			populate_binpkg ${pkg_dep} ${CHECK_LEVEL_NEXT}
		done
		unset pkg_dep
	else
		print_info 3 "${CHECK_LEVEL_PREFIX}${P} has no dependencies. (L${CHECK_LEVEL_CURRENT})"
	fi
	unset pkg_deps

	if [[ "${PN}" == 'busybox' ]]
	then
		determine_busybox_config_file

		# Apply config-based tweaks to the busybox config.
		# This needs to be done before cache validation.
		cp "${BUSYBOX_CONFIG}" "${TEMP}/busybox-config" \
			|| gen_die "Failed to copy '${BUSYBOX_CONFIG}' to '${TEMP}/busybox-config'!"

		# If you want mount.nfs to work on older than 2.6.something, you might need to turn this on.
		#isTrue "${NFS}" && nfs_opt='y'
		local nfs_opt='n'
		kconfig_set_opt "${TEMP}/busybox-config" CONFIG_FEATURE_MOUNT_NFS ${nfs_opt}

		# Delete cache if stored config's MD5 does not match one to be used
		# This exactly just the .config.gk_orig file, and compares it again the
		# current .config.
		if [[ -f "${BINPKG}" ]]
		then
			local oldconfig_md5="$("${TAR_COMMAND}" -xaf "${BINPKG}" -O ./configs/.config.gk_orig 2>/dev/null | md5sum)"
			local newconfig_md5="$(md5sum < "${TEMP}"/busybox-config)"
			if [[ "${oldconfig_md5}" != "${newconfig_md5}" ]]
			then
				print_info 3 "$(get_indent 2)${PN}: >> Busybox config has changed since binpkg was created; Removing stale ${P} binpkg ..."
				rm "${BINPKG}" \
					|| gen_die "Failed to remove stale binpkg '${BINPKG}'!"
			fi
		fi
	fi

	if [[ -f "${BINPKG}" ]]
	then
		local GKBUILD=
		for GKBUILD in "${GKBUILD_CANDIDATES[@]}"
		do
			if [[ ! -f "${GKBUILD}" ]]
			then
				print_info 3 "${CHECK_LEVEL_PREFIX}GKBUILD '${GKBUILD}' does NOT exist; Skipping ..."
				continue
			fi

			if [[ "${BINPKG}" -ot "${GKBUILD}" ]]
			then
				print_info 3 "${CHECK_LEVEL_PREFIX}GKBUILD '${GKBUILD}' is newer than us; Removing stale ${P} binpkg ..."
				rm "${BINPKG}" || gen_die "Failed to remove stale binpkg '${BINPKG}'!"
				break
			fi

			print_info 3 "${CHECK_LEVEL_PREFIX}Existing ${P} binpkg is newer than '${GKBUILD}'; Skipping ..."
		done
	fi

	if [[ -f "${BINPKG}" ]]
	then
		local required_binpkg=
		for required_binpkg in "${REQUIRED_BINPKGS_CURRENT_VARNAME_ref[@]}"
		do
			# Create shorter variable value so we do not clutter output
			local required_binpkg_filename=$(basename "${required_binpkg}")

			if [[ "${BINPKG}" -ot "${required_binpkg}" ]]
			then
				print_info 3 "${CHECK_LEVEL_PREFIX}Required binpkg '${required_binpkg_filename}' is newer than us; Removing stale ${P} binpkg ..."
				rm "${BINPKG}" || gen_die "Failed to remove stale binpkg '${BINPKG}'!"
				break
			fi

			print_info 3 "${CHECK_LEVEL_PREFIX}Existing ${P} binpkg is newer than '${required_binpkg_filename}'; Skipping ..."
		done
		unset required_binpkg required_binpkg_filename
	fi

	if [[ -f "${BINPKG}" ]]
	then
		local patchdir="${GK_SHARE}/patches/${PN}/${PV}"
		local patch
		for patch in "${patchdir}"/*{diff,patch}
		do
			[ -f "${patch}" ] || continue
			if [[ "${BINPKG}" -ot "${patch}" ]]
			then
				print_info 3 "${CHECK_LEVEL_PREFIX}Patch '${patch}' is newer than us; Removing stale ${P} binpkg ..."
				rm "${BINPKG}" || gen_die "Failed to remove stale binpkg '${BINPKG}'!"
				break
			fi

			print_info 3 "${CHECK_LEVEL_PREFIX}Existing ${P} binpkg is newer than '${patch}'; Skipping ..."
		done
		unset patch patchdir
	fi

	if [[ ! -f "${BINPKG}" ]]
	then
		print_info 3 "${CHECK_LEVEL_PREFIX}Binpkg '${BINPKG}' does NOT exist; Need to build ${P} ..."

		local required_binpkgs=
		local required_binpkg=
		for required_binpkg in "${REQUIRED_BINPKGS_CURRENT_VARNAME_ref[@]}"
		do
			required_binpkgs+="${required_binpkg};"
		done
		unset required_binpkg required_binpkg_filename

		gkbuild \
			${PN} \
			${PV} \
			$(get_gkpkg_srcdir "${PN}") \
			$(get_gkpkg_srctar "${PN}") \
			"${BINPKG}" \
			"${required_binpkgs}"
	else
		print_info 3 "${CHECK_LEVEL_PREFIX}Can keep using existing ${P} binpkg from '${BINPKG}'!"
		[[ ${CHECK_LEVEL_CURRENT} -eq 0 ]] && print_info 2 "$(get_indent 2)${PN}: >> Using ${P} binpkg ..."
	fi

	if [[ ${CHECK_LEVEL_CURRENT} -eq 0 ]]
	then
		# Fertig
		# REQUIRED_BINPKGS_PARENT_VARNAME
		unset CHECK_L${CHECK_LEVEL_PARENT}_REQUIRED_BINPKGS
	else
		print_info 3 "${CHECK_LEVEL_PREFIX}Binpkg of ${P} is ready; Adding to list '${REQUIRED_BINPKGS_PARENT_VARNAME}' ..."
		eval ${REQUIRED_BINPKGS_PARENT_VARNAME}+=\( \"${BINPKG}\" \)
	fi

	# REQUIRED_BINPKGS_CURRENT_VARNAME
	unset CHECK_L${CHECK_LEVEL_CURRENT}_REQUIRED_BINPKGS
}
