#!/bin/bash
# $Id$

compile_kernel_args() {
	local ARGS

	ARGS=''
	if [ "${KERNEL_CROSS_COMPILE}" != '' ]
	then
		ARGS="${ARGS} CROSS_COMPILE=\"${KERNEL_CROSS_COMPILE}\""
	fi
	if [ "${KERNEL_CC}" != '' ]
	then
		ARGS="CC=\"${KERNEL_CC}\""
	fi
	if [ "${KERNEL_LD}" != '' ]
	then
		ARGS="${ARGS} LD=\"${KERNEL_LD}\""
	fi
	if [ "${KERNEL_AS}" != '' ]
	then
		ARGS="${ARGS} AS=\"${KERNEL_AS}\""
	fi
	if [ -n "${KERNEL_ARCH}" ]
	then
		ARGS="${ARGS} ARCH=\"${KERNEL_ARCH}\""
	fi
	if [ -n "${KERNEL_OUTPUTDIR}" -a "${KERNEL_OUTPUTDIR}" != "${KERNEL_DIR}" ]
	then
		ARGS="${ARGS} O=\"${KERNEL_OUTPUTDIR}\""
	fi
	printf "%s" "${ARGS}"
}

compile_utils_args()
{
	local ARGS
	ARGS=''

	if [ -n "${UTILS_CROSS_COMPILE}" ]
	then
		UTILS_CC="${UTILS_CROSS_COMPILE}gcc"
		UTILS_LD="${UTILS_CROSS_COMPILE}ld"
		UTILS_AS="${UTILS_CROSS_COMPILE}as"
	fi

	if [ "${UTILS_ARCH}" != '' ]
	then
		ARGS="ARCH=\"${UTILS_ARCH}\""
	fi
	if [ "${UTILS_CC}" != '' ]
	then
		ARGS="CC=\"${UTILS_CC}\""
	fi
	if [ "${UTILS_LD}" != '' ]
	then
		ARGS="${ARGS} LD=\"${UTILS_LD}\""
	fi
	if [ "${UTILS_AS}" != '' ]
	then
		ARGS="${ARGS} AS=\"${UTILS_AS}\""
	fi

	printf "%s" "${ARGS}"
}

export_utils_args()
{
	save_args
	if [ "${UTILS_ARCH}" != '' ]
	then
		export ARCH="${UTILS_ARCH}"
	fi
	if [ "${UTILS_CC}" != '' ]
	then
		export CC="${UTILS_CC}"
	fi
	if [ "${UTILS_LD}" != '' ]
	then
		export LD="${UTILS_LD}"
	fi
	if [ "${UTILS_AS}" != '' ]
	then
		export AS="${UTILS_AS}"
	fi
	if [ "${UTILS_CROSS_COMPILE}" != '' ]
	then
		export CROSS_COMPILE="${UTILS_CROSS_COMPILE}"
	fi
}

unset_utils_args()
{
	if [ "${UTILS_ARCH}" != '' ]
	then
		unset ARCH
	fi
	if [ "${UTILS_CC}" != '' ]
	then
		unset CC
	fi
	if [ "${UTILS_LD}" != '' ]
	then
		unset LD
	fi
	if [ "${UTILS_AS}" != '' ]
	then
		unset AS
	fi
	if [ "${UTILS_CROSS_COMPILE}" != '' ]
	then
		unset CROSS_COMPILE
	fi
	reset_args
}

export_kernel_args()
{
	if [ "${KERNEL_CC}" != '' ]
	then
		export CC="${KERNEL_CC}"
	fi
	if [ "${KERNEL_LD}" != '' ]
	then
		export LD="${KERNEL_LD}"
	fi
	if [ "${KERNEL_AS}" != '' ]
	then
		export AS="${KERNEL_AS}"
	fi
	if [ "${KERNEL_CROSS_COMPILE}" != '' ]
	then
		export CROSS_COMPILE="${KERNEL_CROSS_COMPILE}"
	fi
}

unset_kernel_args()
{
	if [ "${KERNEL_CC}" != '' ]
	then
		unset CC
	fi
	if [ "${KERNEL_LD}" != '' ]
	then
		unset LD
	fi
	if [ "${KERNEL_AS}" != '' ]
	then
		unset AS
	fi
	if [ "${KERNEL_CROSS_COMPILE}" != '' ]
	then
		unset CROSS_COMPILE
	fi
}
save_args()
{
	if [ "${ARCH}" != '' ]
	then
		export ORIG_ARCH="${ARCH}"
	fi
	if [ "${CC}" != '' ]
	then
		export ORIG_CC="${CC}"
	fi
	if [ "${LD}" != '' ]
	then
		export ORIG_LD="${LD}"
	fi
	if [ "${AS}" != '' ]
	then
		export ORIG_AS="${AS}"
	fi
	if [ "${CROSS_COMPILE}" != '' ]
	then
		export ORIG_CROSS_COMPILE="${CROSS_COMPILE}"
	fi
}
reset_args()
{
	if [ "${ORIG_ARCH}" != '' ]
	then
		export ARCH="${ORIG_ARCH}"
		unset ORIG_ARCH
	fi
	if [ "${ORIG_CC}" != '' ]
	then
		export CC="${ORIG_CC}"
		unset ORIG_CC
	fi
	if [ "${ORIG_LD}" != '' ]
	then
		export LD="${ORIG_LD}"
		unset ORIG_LD
	fi
	if [ "${ORIG_AS}" != '' ]
	then
		export AS="${ORIG_AS}"
		unset ORIG_AS
	fi
	if [ "${ORIG_CROSS_COMPILE}" != '' ]
	then
		export CROSS_COMPILE="${ORIG_CROSS_COMPILE}"
		unset ORIG_CROSS_COMPILE
	fi
}

apply_patches() {
	util=$1
	version=$2
	patchdir=${GK_SHARE}/patches/${util}/${version}

	if [ -d "${patchdir}" ]
	then
		local silent="-s "
		if [[ "${LOGLEVEL}" -gt 1 ]]; then
			silent=
		fi

		print_info 1 "$(getIndent 2)${util}: >> Applying patches ..."
		for i in ${patchdir}/*{diff,patch}
		do
			[ -f "${i}" ] || continue
			patch_success=0
			for j in $(seq 0 5)
			do
				patch -p${j} --backup-if-mismatch -f < "${i}" --dry-run >/dev/null && \
					patch ${silent}-p${j} --backup-if-mismatch -f < "${i}"
				if [ $? = 0 ]
				then
					patch_success=1
					break
				fi
			done
			if [ ${patch_success} -eq 1 ]
			then
				print_info 2 "$(getIndent 3) - $(basename "${i}")"
			else
				gen_die "Failed to apply patch '${i}' for '${util}-${version}'!"
			fi
		done
	else
		print_info 1 "$(getIndent 2)${util}: >> No patches found in $patchdir ..."
	fi
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
		print_info 2 "COMMAND: ${NICEOPTS}${MAKE} ${MAKEOPTS} -j1 ${ARGS} ${target} $*" 1 0 1
		eval ${NICEOPTS}${MAKE} -s ${MAKEOPTS} -j1 ${ARGS} ${target} $*
		RET=$?
	elif [ "${LOGLEVEL}" -gt 3 ]
	then
		# Output to stdout and logfile
		print_info 2 "COMMAND: ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $*" 1 0 1
		eval ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $* 2>&1 | tee -a "${LOGFILE}"
		RET=${PIPESTATUS[0]}
	else
		# Output to logfile only
		print_info 2 "COMMAND: ${NICEOPTS}${MAKE} ${MAKEOPTS} ${ARGS} ${target} $*" 1 0 1
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
		local -x INSTALL_MOD_STRIP=0
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

	if isTrue "${FIRMWARE_INSTALL}" && [ $((${KV_MAJOR} * 1000 + ${KV_MINOR})) -ge 4014 ]
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
	elif [ $((${KV_MAJOR} * 1000 + ${KV_MINOR})) -lt 4014 ]
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
	systemmap="${KERNEL_OUTPUTDIR}"/System.map

	if isTrue "${CMD_INSTALL}"
	then
		copy_image_with_preserve \
			"kernel" \
			"${tmp_kernel_binary}" \
			"kernel-${KNAME}-${ARCH}-${KV}"

		copy_image_with_preserve \
			"System.map" \
			"${systemmap}" \
			"System.map-${KNAME}-${ARCH}-${KV}"

		if isTrue "${GENZIMAGE}"
		then
			copy_image_with_preserve \
				"kernelz" \
				"${tmp_kernel_binary2}" \
				"kernelz-${KV}"
		fi
	else
		cp "${tmp_kernel_binary}" "${TMPDIR}/kernel-${KNAME}-${ARCH}-${KV}" \
			|| gen_die "Could not copy the kernel binary to '${TMPDIR}'!"

		cp "${systemmap}" "${TMPDIR}/System.map-${KNAME}-${ARCH}-${KV}" \
			|| gen_die "Could not copy System.map to '${TMPDIR}'!"

		if isTrue "${GENZIMAGE}"
		then
			cp "${tmp_kernel_binary2}" "${TMPDIR}/kernelz-${KV}" \
				|| gen_die "Could not copy the kernelz binary to '${TMPDIR}'!"
		fi
	fi
}

compile_mdadm() {
	if [ -f "${MDADM_BINCACHE}" ]
	then
		print_info 1 "$(getIndent 2)mdadm: >> Using cache ..."
	else
		[ -f "${MDADM_SRCTAR}" ] ||
			gen_die "Could not find MDADM source tarball: ${MDADM_SRCTAR}! Please place it there, or place another version, changing /etc/genkernel.conf as necessary!"
		cd "${TEMP}"
		rm -rf "${MDADM_DIR}" > /dev/null
		/bin/tar -xpf "${MDADM_SRCTAR}" ||
			gen_die 'Could not extract MDADM source tarball!'
		[ -d "${MDADM_DIR}" ] ||
			gen_die "MDADM directory ${MDADM_DIR} is invalid!"

		cd "${MDADM_DIR}"
		apply_patches mdadm ${MDADM_VER}
		defs='-DNO_DLM -DNO_COROSYNC'
		sed -i \
			-e "/^CFLAGS = /s:^CFLAGS = \(.*\)$:CFLAGS = -Os ${defs}:" \
			-e "/^CXFLAGS = /s:^CXFLAGS = \(.*\)$:CXFLAGS = -Os ${defs}:" \
			-e "/^CWFLAGS = /s:^CWFLAGS = \(.*\)$:CWFLAGS = -Wall:" \
			-e "s/^# LDFLAGS = -static/LDFLAGS = -static/" \
			Makefile || gen_die "Failed to sed mdadm Makefile"

		print_info 1 "$(getIndent 2)mdadm: >> Compiling ..."
		compile_generic 'mdadm mdmon' utils

		mkdir -p "${TEMP}/mdadm/sbin"
		install -m 0755 -s mdadm "${TEMP}/mdadm/sbin/mdadm" || gen_die "Failed mdadm install"
		install -m 0755 -s mdmon "${TEMP}/mdadm/sbin/mdmon" || gen_die "Failed mdmon install"
		print_info 1 "$(getIndent 2)mdadm: >> Copying to bincache ..."
		cd "${TEMP}/mdadm"
		${UTILS_CROSS_COMPILE}strip "sbin/mdadm" "sbin/mdmon" ||
			gen_die 'Could not strip mdadm binaries!'
		/bin/tar -cjf "${MDADM_BINCACHE}" sbin/mdadm sbin/mdmon ||
			gen_die 'Could not create binary cache'

		cd "${TEMP}"
		isTrue "${CMD_DEBUGCLEANUP}" && rm -rf "${MDADM_DIR}" mdadm
		return 0
	fi
}

compile_dmraid() {
	compile_device_mapper

	if [[ -f "${DMRAID_BINCACHE}" && "${DMRAID_BINCACHE}" -nt "${LVM_BINCACHE}" ]]
	then
		print_info 1 "$(getIndent 2)dmraid: >> Using cache ..."
	else
		[ -f "${DMRAID_SRCTAR}" ] ||
			gen_die "Could not find DMRAID source tarball: ${DMRAID_SRCTAR}! Please place it there, or place another version, changing /etc/genkernel.conf as necessary!"
		cd "${TEMP}"
		rm -rf ${DMRAID_DIR} > /dev/null
		/bin/tar -xpf ${DMRAID_SRCTAR} ||
			gen_die 'Could not extract DMRAID source tarball!'
		[ -d "${DMRAID_DIR}" ] ||
			gen_die "DMRAID directory ${DMRAID_DIR} is invalid!"

		rm -rf "${TEMP}/lvm" > /dev/null
		mkdir -p "${TEMP}/lvm"
		/bin/tar -xpf "${LVM_BINCACHE}" -C "${TEMP}/lvm" ||
			gen_die "Could not extract LVM2 binary cache!";

		cd "${DMRAID_DIR}" || gen_die "cannot chdir into '${DMRAID_DIR}'"
		apply_patches dmraid ${DMRAID_VER}

		print_info 1 "$(getIndent 2)dmraid: >> Configuring ..."
		DEVMAPPEREVENT_CFLAGS="-I${TEMP}/lvm/include" \
		LIBS="-lm -lrt -lpthread" \
		./configure --enable-static_link \
			--with-devmapper-prefix="${TEMP}/lvm" \
			--prefix=${TEMP}/dmraid >> ${LOGFILE} 2>&1 ||
			gen_die 'Configure of dmraid failed!'

		# We dont necessarily have selinux installed yet... look into
		# selinux global support in the future.
		sed -i tools/Makefile -e "/DMRAID_LIBS +=/s|-lselinux||g"
		###echo "DMRAIDLIBS += -lselinux -lsepol" >> tools/Makefile
		mkdir -p "${TEMP}/dmraid"
		print_info 1 "$(getIndent 2)dmraid: >> Compiling ..."
		compile_generic '' utils
		#compile_generic 'install' utils
		mkdir ${TEMP}/dmraid/sbin
		install -m 0755 -s tools/dmraid "${TEMP}/dmraid/sbin/dmraid"

		print_info 1 "$(getIndent 2)dmraid: >> Copying to bincache ..."
		cd "${TEMP}/dmraid" || gen_die "cannot chdir into '${TEMP}/dmraid'"
		/bin/tar -cjf "${DMRAID_BINCACHE}" sbin/dmraid ||
			gen_die 'Could not create binary cache'

		cd "${TEMP}"
		isTrue "${CMD_DEBUGCLEANUP}" && rm -rf "${TEMP}/lvm" > /dev/null
		isTrue "${CMD_DEBUGCLEANUP}" && rm -rf "${DMRAID_DIR}" dmraid
		return 0
	fi
}

determine_busybox_config_file() {
	print_info 2 "$(get_indent 3)busybox: >> Checking for suitable busybox configuration ..."

	if [ -n "${CMD_BUSYBOX_CONFIG}" ]
	then
		BUSYBOX_CONFIG=$(expand_file "${CMD_BUSYBOX_CONFIG}")
		if [ -z "${BUSYBOX_CONFIG}" ]
		then
			error_msg="No busybox .config: Cannot use '${CMD_BUSYBOX_CONFIG}' value. "
			error_msg+="Check --busybox-config value or unset "
			error_msg+="to use default busybox config provided by genkernel."
			gen_die "${error_msg}"
		fi
	else
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
				print_info 3 "$(get_indent 1)- '${f}' not found; Skipping ..."
			fi
		done

		if [ -z "${BUSYBOX_CONFIG}" ]
		then
			gen_die 'No busybox .config specified, or file not found!'
		fi
	fi

	BUSYBOX_CONFIG="$(readlink -f "${BUSYBOX_CONFIG}")"

	# Validate the symlink result if any
	if [ -z "${BUSYBOX_CONFIG}" -o ! -f "${BUSYBOX_CONFIG}" ]
	then
		if [ -n "${CMD_BUSYBOX_CONFIG}" ]
		then
			error_msg="No busybox .config: File '${CMD_BUSYBOX_CONFIG}' not found! "
			error_msg+="Check --busybox-config value or unset "
			error_msg+="to use default busybox config provided by genkernel."
			gen_die "${error_msg}"
		else
			gen_die "No busybox .config: symlinked file '${BUSYBOX_CONFIG}' not found!"
		fi
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
	local REQUIRED_BINPKGS_CURRENT_VARNAME_SEPARATE_WORD="${REQUIRED_BINPKGS_CURRENT_VARNAME}[@]"
	local REQUIRED_BINPKGS_CURRENT_VARNAME_SINGLE_WORD="${REQUIRED_BINPKGS_CURRENT_VARNAME}[*]"

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
			local oldconfig_md5="$(tar -xaf "${BINPKG}" -O ./configs/.config.gk_orig 2>/dev/null | md5sum)"
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
		for required_binpkg in "${!REQUIRED_BINPKGS_CURRENT_VARNAME_SEPARATE_WORD}"
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
		unset required_binpkg REQUIRED_BINPKGS_CURRENT_VARNAME_SEPARATE_WORD required_binpkg_filename
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
		gkbuild \
			${PN} \
			${PV} \
			$(get_gkpkg_srcdir "${PN}") \
			$(get_gkpkg_srctar "${PN}") \
			"${BINPKG}" \
			"${!REQUIRED_BINPKGS_CURRENT_VARNAME_SINGLE_WORD}"
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
		eval ${REQUIRED_BINPKGS_PARENT_VARNAME}+=\( "${BINPKG}" \)
	fi

	# REQUIRED_BINPKGS_CURRENT_VARNAME
	unset CHECK_L${CHECK_LEVEL_CURRENT}_REQUIRED_BINPKGS
}
