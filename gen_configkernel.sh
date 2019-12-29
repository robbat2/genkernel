#!/bin/bash
# $Id$

# Fills variable KERNEL_CONFIG
determine_kernel_config_file() {
	print_info 2 "Checking for suitable kernel configuration ..."

	if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" != "default" ]
	then
		KERNEL_CONFIG=$(expand_file "${CMD_KERNEL_CONFIG}")
		if [ -z "${KERNEL_CONFIG}" ]
		then
			gen_die "--kernel-config value '${CMD_KERNEL_CONFIG}' failed to expand!"
		elif [ ! -e "${KERNEL_CONFIG}" ]
		then
			gen_die "--kernel-config file '${KERNEL_CONFIG}' does not exist!"
		fi

		if isTrue "$(is_gzipped "${KERNEL_CONFIG}")"
		then
			local CONFGREP=zgrep
		else
			local CONFGREP=grep
		fi

		if ! ${CONFGREP} -qE '^CONFIG_.*=' "${KERNEL_CONFIG}" &>/dev/null
		then
			gen_die "--kernel-config file '${KERNEL_CONFIG}' does not look like a valid kernel config: File does not contain any CONFIG_* value!"
		fi
	else
		local -a kconfig_candidates

		local -a gk_kconfig_candidates
		gk_kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/kernel-config-${KV}" )
		gk_kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/kernel-config-${VER}.${PAT}" )
		gk_kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/generated-config" )
		gk_kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/kernel-config" )
		gk_kconfig_candidates+=( "${DEFAULT_KERNEL_CONFIG}" )

		if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ]
		then
			print_info 1 "Default configuration was forced. Will ignore any user kernel configuration!"
			kconfig_candidates=( ${gk_kconfig_candidates[@]} )
		else
			local -a user_kconfig_candidates

			# Always prefer kernel config based on actual $KV reading
			user_kconfig_candidates+=( "/etc/kernels/${GK_FILENAME_CONFIG}" )

			if [ -n "${KERNEL_LOCALVERSION}" -a "${KERNEL_LOCALVERSION}" != "UNSET" ]
			then
				# Look for kernel config based on KERNEL_LOCALVERSION
				# which we are going to use, too.
				# This will allow user to copy previous kernel config file
				# which includes LOV by default to new version when doing
				# kernel upgrade since we add $ARCH to $LOV by default.
				local user_kconfig="/etc/kernels/kernel-config-${VER}.${PAT}.${SUB}${EXV}${KERNEL_LOCALVERSION}"

				# Don't check same file twice
				if [[ "${user_kconfig_candidates[@]} " != *"${user_kconfig} "* ]]
				then
					user_kconfig_candidates+=( ${user_kconfig} )
				fi
			fi

			# Look for genkernel-3.x configs for backward compatibility, too
			user_kconfig_candidates+=( "/etc/kernels/kernel-config-${ARCH}-${KV}" )

			kconfig_candidates=(
				 ${user_kconfig_candidates[@]}
				 ${gk_kconfig_candidates[@]}
			)
		fi

		local f
		for f in "${kconfig_candidates[@]}"
		do
			[ -z "${f}" ] && continue

			if [ -f "${f}" ]
			then
				if grep -sq THIS_CONFIG_IS_BROKEN "$f"
				then
					print_info 2 "$(get_indent 1)- '${f}' is marked as broken; Skipping ..."
				else
					KERNEL_CONFIG="$f" && break
				fi
			else
					print_info 2 "$(get_indent 1)- '${f}' not found; Skipping ..."
			fi
		done

		if [ -z "${KERNEL_CONFIG}" ]
		then
			gen_die 'No kernel .config specified, or file not found!'
		fi
	fi

	KERNEL_CONFIG="$(readlink -f "${KERNEL_CONFIG}")"

	# Validate the symlink result if any
	if [ -z "${KERNEL_CONFIG}" -o ! -f "${KERNEL_CONFIG}" ]
	then
		if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" != "default" ]
		then
			error_msg="No kernel .config: File '${CMD_KERNEL_CONFIG}' not found! "
			error_msg+="Check --kernel-config value or unset "
			error_msg+="to use default kernel config provided by genkernel."
			gen_die "${error_msg}"
		else
			gen_die "No kernel .config: symlinked file '${KERNEL_CONFIG}' not found!"
		fi
	fi
}

config_kernel() {
	local diff_cmd="$(which zdiff 2>/dev/null)"
	if [ -z "${diff_cmd}" ]
	then
		print_warning 5 "zdiff is not available."
		diff_cmd="diff"
	fi

	cd "${KERNEL_DIR}" || gen_die "Failed to chdir to '${KERNEL_DIR}'!"

	print_info 1 "kernel: >> Initializing ..."

	if isTrue "${CLEAN}" && isTrue "${MRPROPER}"
	then
		print_info 2 "$(get_indent 1)>> --mrproper is set; Skipping 'make clean' ..."
	elif isTrue "${CLEAN}" && ! isTrue "${MRPROPER}"
	then
		print_info 1 "$(get_indent 1)>> Running 'make clean' ..."
		compile_generic clean kernel
	else
		print_info 1 "$(get_indent 1)>> --no-clean is set; Skipping 'make clean' ..."
	fi

	if isTrue "${MRPROPER}" || [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ]
	then
		# Backup current kernel .config
		if [ -f "${KERNEL_OUTPUTDIR}/.config" ]
		then
			# Current .config is different then one we are going to use
			if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ] \
				|| ! "${diff_cmd}" -q "${KERNEL_OUTPUTDIR}"/.config "${KERNEL_CONFIG}" >/dev/null
			then
				NOW=$(date +--%Y-%m-%d--%H-%M-%S)
				cp "${KERNEL_OUTPUTDIR}/.config" "${KERNEL_OUTPUTDIR}/.config${NOW}.bak" \
					|| gen_die "Could not backup kernel config (${KERNEL_OUTPUTDIR}/.config)"
				print_info 1 "$(get_indent 1)>> Previous config backed up to .config${NOW}.bak"

				if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ]
				then
					print_info 3 "$(get_indent 1)>> Default kernel config was forced; Deleting existing kernel config '${KERNEL_OUTPUTDIR}/.config' ..."
					rm "${KERNEL_OUTPUTDIR}/.config" >/dev/null \
						|| gen_die "Failed to delete '${KERNEL_OUTPUTDIR}/.config'!"
				fi
			fi
		fi
	fi

	if isTrue "${MRPROPER}"
	then
		print_info 1 "$(get_indent 1)>> Running 'make mrproper' ..."
		compile_generic mrproper kernel
	else
		print_info 1 "$(get_indent 1)>> --no-mrproper is set; Skipping 'make mrproper' ..."
	fi

	if [ ! -f "${KERNEL_OUTPUTDIR}/.config" ]
	then
		# We always need a kernel config file...
		print_info 3 "$(get_indent 1)>> Copying '${KERNEL_CONFIG}' to '${KERNEL_OUTPUTDIR}/.config' ..."

		local message="Failed to copy kernel config file '${KERNEL_CONFIG}' to '${KERNEL_OUTPUTDIR}/.config'!"
		if isTrue "$(is_gzipped "${KERNEL_CONFIG}")"
		then
			# Support --kernel-config=/proc/config.gz, mainly
			zcat "${KERNEL_CONFIG}" > "${KERNEL_OUTPUTDIR}/.config" || gen_die "${message}"
		else
			cp -aL "${KERNEL_CONFIG}" "${KERNEL_OUTPUTDIR}/.config" || gen_die "${message}"
		fi
	else
		if ! "${diff_cmd}" -q "${KERNEL_OUTPUTDIR}"/.config "${KERNEL_CONFIG}" >/dev/null
		then
			print_warning 1 "$(get_indent 1)>> Will ignore kernel config from '${KERNEL_CONFIG}'"
			print_warning 1 "$(get_indent 1)   in favor of already existing but different kernel config"
			print_warning 1 "$(get_indent 1)   found in '${KERNEL_OUTPUTDIR}/.config' ..."
		else
			print_info 3 "$(get_indent 1)>> Can keep using already existing '${KERNEL_OUTPUTDIR}/.config' which is identical to --kernel-config file  ..."
		fi
	fi

	if isTrue "${OLDCONFIG}"
	then
		print_info 1 "$(get_indent 1)>> Running 'make oldconfig' ..."
		yes '' 2>/dev/null | compile_generic oldconfig kernel 2>/dev/null
	else
		print_info 1 "$(get_indent 1)>> --no-oldconfig is set; Skipping 'make oldconfig' ..."
	fi

	local add_config
	if isTrue "${MENUCONFIG}"
	then
		add_config=menuconfig
	elif isTrue "${CMD_NCONFIG}"
	then
		add_config=nconfig
	elif isTrue "${CMD_GCONFIG}"
	then
		add_config=gconfig
	elif isTrue "${CMD_XCONFIG}"
	then
		add_config=xconfig
	fi

	if [ -n "${add_config}" ]
	then
		print_info 1 "$(get_indent 1)>> Invoking ${add_config} ..."
		compile_generic ${add_config} kernelruntask
	fi

	local -a required_kernel_options
	[ -f "${KCONFIG_MODIFIED_MARKER}" ] && rm "${KCONFIG_MODIFIED_MARKER}"

	# --integrated-initramfs handling
	if isTrue "${INTEGRATED_INITRAMFS}"
	then
		local cfg_CONFIG_INITRAMFS_SOURCE=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INITRAMFS_SOURCE")
		if [[ -n "${cfg_CONFIG_INITRAMFS_SOURCE}" && ${#cfg_CONFIG_INITRAMFS_SOURCE} -gt 2 ]]
		then
			# Checking value length to allow 'CONFIG_INITRAMFS_SOURCE=' and 'CONFIG_INITRAMFS_SOURCE=""'
			print_info 2 "$(get_indent 1)>> CONFIG_INITRAMFS_SOURCE is already set; Unsetting to avoid clashing with --integrated-initramfs ..."
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INITRAMFS_SOURCE" ""
		fi
	fi

	# Force this on if we are using --genzimage
	if isTrue "${CMD_GENZIMAGE}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for --genzimage are set ..."
		# Make sure Ext2 support is on...
		local cfg_CONFIG_EXT2_FS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT2_FS")
		if ! isTrue "${cfg_CONFIG_EXT2_FS}"
		then
			local cfg_CONFIG_EXT4_USE_FOR_EXT2=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT4_USE_FOR_EXT2")
			if ! isTrue "${cfg_CONFIG_EXT4_USE_FOR_EXT2}"
			then
				local cfg_CONFIG_EXT4_FS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT4_FS")
				if isTrue "${cfg_CONFIG_EXT4_FS}"
				then
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT4_USE_FOR_EXT2" "y" \
						&& required_kernel_options+=( 'CONFIG_EXT4_USE_FOR_EXT2' )
				else
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT2_FS" "y" \
						&& required_kernel_options+=( 'CONFIG_EXT2_FS' )
				fi
			fi
		fi
	fi

	# --kernel-localversion handling
	if [ -n "${KERNEL_LOCALVERSION}" ]
	then
		local cfg_CONFIG_LOCALVERSION=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_LOCALVERSION")
		case "${KERNEL_LOCALVERSION}" in
			UNSET)
				print_info 2 "$(get_indent 1)>> Ensure that CONFIG_LOCALVERSION is unset ..."
				if [ -n "${cfg_CONFIG_LOCALVERSION}" ]
				then
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_LOCALVERSION" ""
				fi
				;;
			*)
				print_info 2 "$(get_indent 1)>> Ensure that CONFIG_LOCALVERSION is set ..."
				kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_LOCALVERSION" "\"${KERNEL_LOCALVERSION}\""
				;;
		esac
	fi

	# Do we support modules at all?
	local cfg_CONFIG_MODULES=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MODULES")
	if isTrue "${cfg_CONFIG_MODULES}"
	then
		# yes, we support modules, set 'm' for new stuff.
		local newcfg_setting='m'
		# Compare the kernel module compression vs the depmod module compression support
		# WARNING: if the buildhost has +XZ but the target machine has -XZ, you will get failures!
		local cfg_CONFIG_MODULE_COMPRESS_GZIP=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MODULE_COMPRESS_GZIP")
		local cfg_CONFIG_MODULE_COMPRESS_XZ=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MODULE_COMPRESS_XZ")
		if isTrue "${cfg_CONFIG_MODULE_COMPRESS_GZIP}"
		then
			depmod_GZIP=$(/sbin/depmod -V | tr ' ' '\n' | awk '/ZLIB/{print $1; exit}')
			if [[ "${depmod_GZIP}" != "+ZLIB" ]]
			then
				gen_die 'depmod does not support ZLIB/GZIP, cannot build with CONFIG_MODULE_COMPRESS_GZIP'
			fi
		elif isTrue "${cfg_CONFIG_MODULE_COMPRESS_XZ}"
		then
			depmod_XZ=$(/sbin/depmod -V | tr ' ' '\n' | awk '/XZ/{print $1; exit}')
			if [[ "${depmod_XZ}" != "+XZ" ]]
			then
				gen_die 'depmod does not support XZ, cannot build with CONFIG_MODULE_COMPRESS_XZ'
			fi
		fi
	else
		# no, we do NOT support modules, set 'y' for new stuff.
		newcfg_setting='y'

		if ! isTrue "${BUILD_STATIC}"
		then
			local _no_modules_support_warning="$(get_indent 1)>> Forcing --static"
			if isTrue "${BUILD_RAMDISK}" && isTrue "${RAMDISKMODULES}"
			then
				_no_modules_support_warning+=" and --no-ramdisk-modules"
				RAMDISKMODULES="no"
			fi

			_no_modules_support_warning+=" to avoid genkernel failures because kernel does NOT support modules ..."

			print_warning 1 "${_no_modules_support_warning}"
			BUILD_STATIC="yes"
		fi
	fi

	if isTrue "${BUILD_RAMDISK}"
	then
		# We really need this or we will fail to boot
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for genkernel's initramfs usage are set ..."
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_TTY" "y" \
			&& required_kernel_options+=( 'CONFIG_TTY' )

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UNIX98_PTYS" "y" \
			&& required_kernel_options+=( 'CONFIG_UNIX98_PTYS' )
	fi

	# If the user has configured DM as built-in, we need to respect that.
	local cfg_CONFIG_BLK_DEV_DM=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM")
	case "${cfg_CONFIG_BLK_DEV_DM}" in
		y|m) ;; # Do nothing
		*) cfg_CONFIG_BLK_DEV_DM=${newcfg_setting}
	esac

	# Make sure all modules required bcache are enabled in the kernel, if --bcache
	if isTrue "${CMD_BCACHE}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for bcache support are set ..."
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BCACHE" "${newcfg_setting}" \
			&& required_kernel_options+=( 'CONFIG_BCACHE' )
	fi

	# Make sure all modues required for MD raid are enabled in the kernel, if --mdadm
	if isTrue "${CMD_MDADM}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for MDADM support are set ..."
		local cfg_CONFIG_BLK_DEV_MD=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_MD")
		case "${cfg_CONFIG_BLK_DEV_MD}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_BLK_DEV_MD=${newcfg_setting}
		esac

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" \
			&& required_kernel_options+=( 'CONFIG_BLK_DEV_DM' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_MD" "${cfg_CONFIG_BLK_DEV_MD}" \
			&& required_kernel_options+=( 'CONFIG_BLK_DEV_MD' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD_LINEAR" "${cfg_CONFIG_BLK_DEV_MD}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD_RAID0" "${cfg_CONFIG_BLK_DEV_MD}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD_RAID1" "${cfg_CONFIG_BLK_DEV_MD}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD_RAID10" "${cfg_CONFIG_BLK_DEV_MD}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD_RAID456" "${cfg_CONFIG_BLK_DEV_MD}"
	fi

	# Make sure lvm modules are enabled in the kernel, if --lvm
	if isTrue "${CMD_LVM}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for LVM support are set ..."
		local cfg_CONFIG_DM_SNAPSHOT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_SNAPSHOT")
		case "${cfg_CONFIG_DM_SNAPSHOT}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_SNAPSHOT=${newcfg_setting}
		esac
		local cfg_CONFIG_DM_MIRROR=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MIRROR")
		case "${cfg_CONFIG_DM_MIRROR}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_MIRROR=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" \
			&& required_kernel_options+=( 'CONFIG_BLK_DEV_DM' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_SNAPSHOT" "${cfg_CONFIG_DM_SNAPSHOT}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MIRROR" "${cfg_CONFIG_DM_MIRROR}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FILE_LOCKING" "y" \
			&& required_kernel_options+=( 'CONFIG_FILE_LOCKING' )
	fi

	# Make sure all modules required for cryptsetup/LUKS are enabled in the kernel, if --luks
	if isTrue "${CMD_LUKS}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for LUKS support are set ..."
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" \
			&& required_kernel_options+=( 'CONFIG_BLK_DEV_DM' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_CRYPT" "${cfg_CONFIG_BLK_DEV_DM}" \
			&& required_kernel_options+=( 'CONFIG_DM_CRYPT' )

		local cfg_CONFIG_CRYPTO_AES=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_AES")
		case "${cfg_CONFIG_CRYPTO_AES}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_CRYPTO_AES=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_XTS" "${cfg_CONFIG_CRYPTO_AES}" \
			&& required_kernel_options+=( 'CONFIG_CRYPTO_XTS' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_SHA256" "${cfg_CONFIG_CRYPTO_AES}" \
			&& required_kernel_options+=( 'CONFIG_CRYPTO_SHA256' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_AES" "${cfg_CONFIG_CRYPTO_AES}" \
			&& required_kernel_options+=( 'CONFIG_CRYPTO_AES' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_USER_API_HASH" "${cfg_CONFIG_CRYPTO_AES}" \
			&& required_kernel_options+=( 'CONFIG_CRYPTO_USER_API_HASH' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_USER_API_SKCIPHER" "${cfg_CONFIG_CRYPTO_AES}" \
			&& required_kernel_options+=( 'CONFIG_CRYPTO_USER_API_SKCIPHER' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_USER_API_AEAD" "${cfg_CONFIG_CRYPTO_AES}"

		local cfg_CONFIG_X86=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86")
		case "${cfg_CONFIG_X86}" in
			y|m)
				cfg_CONFIG_X86=yes
				;;
			*)
				cfg_CONFIG_X86=no
				;;
		esac

		local cfg_CONFIG_64BIT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_64BIT")
		case "${cfg_CONFIG_64BIT}" in
			y|m)
				cfg_CONFIG_64BIT=yes
				;;
			*)
				cfg_CONFIG_64BIT=no
				;;
		esac

		if isTrue "${cfg_CONFIG_X86}"
		then
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_AES_NI_INTEL" "${cfg_CONFIG_CRYPTO_AES}"

			if isTrue "${cfg_CONFIG_64BIT}"
			then
				kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_SHA1_SSSE3" "${cfg_CONFIG_CRYPTO_AES}"
				kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_SHA256_SSSE3" "${cfg_CONFIG_CRYPTO_AES}"
				kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_AES_X86_64" "${cfg_CONFIG_CRYPTO_AES}"
			else
				kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_AES_586" "${cfg_CONFIG_CRYPTO_AES}"
			fi
		fi
	fi

	# Make sure multipath modules are enabled in the kernel, if --multipath
	if isTrue "${CMD_MULTIPATH}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for multipath support are set ..."
		local cfg_CONFIG_DM_MULTIPATH=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH")
		case "${cfg_CONFIG_DM_MULTIPATH}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_MULTIPATH=${newcfg_setting}
		esac
		local cfg_CONFIG_DM_MULTIPATH_RDAC=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH_RDAC")
		case "${cfg_CONFIG_DM_MULTIPATH_RDAC}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_MULTIPATH_RDAC=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" \
			&& required_kernel_options+=( 'CONFIG_BLK_DEV_DM' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH" "${cfg_CONFIG_DM_MULTIPATH}" \
			&& required_kernel_options+=( 'CONFIG_DM_MULTIPATH' )
	fi

	# Make sure dmraid modules are enabled in the kernel, if --dmraid
	if isTrue "${CMD_DMRAID}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for DMRAID support are set ..."
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" \
			&& required_kernel_options+=( 'CONFIG_BLK_DEV_DM' )
	fi

	# Make sure iSCSI modules are enabled in the kernel, if --iscsi
	if isTrue "${CMD_ISCSI}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for iSCSI support are set ..."
		local cfg_CONFIG_ISCSI_BOOT_SYSFS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_BOOT_SYSFS")
		case "${cfg_CONFIG_ISCSI_BOOT_SYSFS}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_ISCSI_BOOT_SYSFS=${newcfg_setting}
		esac
		local cfg_CONFIG_ISCSI_TCP=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_TCP")
		case "${cfg_CONFIG_ISCSI_TCP}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_ISCSI_TCP=${newcfg_setting}
		esac
		local cfg_CONFIG_SCSI_ISCSI_ATTRS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_ISCSI_ATTRS")
		case "${cfg_CONFIG_SCSI_ISCSI_ATTRS}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI_ISCSI_ATTRS=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INET" "y"

		local cfg_CONFIG_SCSI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI")
		case "${cfg_CONFIG_SCSI}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI" "${cfg_CONFIG_SCSI}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_LOWLEVEL" "y"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_BOOT_SYSFS" "${cfg_CONFIG_ISCSI_BOOT_SYSFS}" \
			&& required_kernel_options+=( 'CONFIG_ISCSI_BOOT_SYSFS' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_TCP" "${cfg_CONFIG_ISCSI_TCP}" \
			&& required_kernel_options+=( 'CONFIG_ISCSI_TCP' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_ISCSI_ATTRS" "${cfg_CONFIG_SCSI_ISCSI_ATTRS}" \
			&& required_kernel_options+=( 'CONFIG_SCSI_ISCSI_ATTRS' )
	fi

	# Make sure Hyper-V modules are enabled in the kernel, if --hyperv
	if isTrue "${CMD_HYPERV}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for Hyper-V support are set ..."
		# Hyper-V deps
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ACPI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86_LOCAL_APIC" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERVISOR_GUEST" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET" "y"

		local cfg_CONFIG_CONNECTOR=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CONNECTOR")
		case "${cfg_CONFIG_CONNECTOR}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_CONNECTOR=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CONNECTOR" "${cfg_CONFIG_CONNECTOR}"

		local cfg_CONFIG_NLS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NLS")
		case "${cfg_CONFIG_NLS}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_NLS=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NLS" "${cfg_CONFIG_NLS}"

		local cfg_CONFIG_SCSI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI")
		case "${cfg_CONFIG_SCSI}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI" "${cfg_CONFIG_SCSI}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_LOWLEVEL" "y"

		local cfg_CONFIG_SCSI_FC_ATTRS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_FC_ATTRS")
		case "${cfg_CONFIG_SCSI_FC_ATTRS}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI_FC_ATTRS=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_FC_ATTRS" "${cfg_CONFIG_SCSI_FC_ATTRS}"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NETDEVICES" "y"

		local cfg_CONFIG_SERIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SERIO")
		case "${cfg_CONFIG_SERIO}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SERIO=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SERIO" "${cfg_CONFIG_SERIO}"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI_MSI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI_MSI_IRQ_DOMAIN" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86_64" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HAS_IOMEM" "y"

		local cfg_CONFIG_FB=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB")
		case "${cfg_CONFIG_FB}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_FB=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB" "${cfg_CONFIG_FB}"

		local cfg_CONFIG_INPUT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT")
		case "${cfg_CONFIG_INPUT}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_INPUT=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT" "${cfg_CONFIG_INPUT}"

		local cfg_CONFIG_HID=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HID")
		case "${cfg_CONFIG_HID}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_HID=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HID" "${cfg_CONFIG_HID}"

		local cfg_CONFIG_UIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UIO")
		case "${cfg_CONFIG_UIO}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_UIO=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UIO" "${cfg_CONFIG_UIO}"

		# Hyper-V modules, activate in order!
		local cfg_CONFIG_HYPERV=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV")
		case "${cfg_CONFIG_HYPERV}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_HYPERV=${newcfg_setting}
		esac

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV" "${cfg_CONFIG_HYPERV}" \
			&& required_kernel_options+=( 'CONFIG_HYPERV' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_UTILS" "${cfg_CONFIG_HYPERV}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_BALLOON" "${cfg_CONFIG_HYPERV}" \
			&& required_kernel_options+=( 'CONFIG_HYPERV_BALLOON' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_STORAGE" "${cfg_CONFIG_HYPERV}" \
			&& required_kernel_options+=( 'CONFIG_HYPERV_STORAGE' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_NET" "${cfg_CONFIG_HYPERV}" \
			&& required_kernel_options+=( 'CONFIG_HYPERV_NET' )

		if [ ${KV_NUMERIC} -ge 4014 ]
		then
			local cfg_CONFIG_VSOCKETS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS")
			case "${cfg_CONFIG_VSOCKETS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_VSOCKETS=${newcfg_setting}
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS" "${cfg_CONFIG_VSOCKETS}"

			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_VSOCKETS" "${cfg_CONFIG_HYPERV}"
		fi

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_KEYBOARD" "${cfg_CONFIG_HYPERV}"

		[ ${KV_NUMERIC} -ge 4006 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI_HYPERV" "${cfg_CONFIG_HYPERV}"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB_HYPERV" "${cfg_CONFIG_HYPERV}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HID_HYPERV_MOUSE" "${cfg_CONFIG_HYPERV}"

		[ ${KV_NUMERIC} -ge 4010 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UIO_HV_GENERIC" "${cfg_CONFIG_HYPERV}"

		[ ${KV_NUMERIC} -ge 4012 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_TSCPAGE" "y"
	fi

	# Make sure kernel supports Splash, if --splash
	if isTrue "${SPLASH}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for Splash support are set ..."
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB_SPLASH" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VT" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_TTY" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FRAMEBUFFER_CONSOLE" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB_CON_DECOR" "y"
	fi

	# Make sure VirtIO modules are enabled in the kernel, if --virtio
	if isTrue "${CMD_VIRTIO}"
	then
		print_info 2 "$(get_indent 1)>> Ensure that required kernel options for VirtIO support are set ..."
		# VirtIO deps
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_HW" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MMU" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NETDEVICES" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET_CORE" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HAS_IOMEM" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HAS_DMA" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_TTY" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PARAVIRT_GUEST" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SYSFS" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HAS_IOPORT_MAP" "y"

		local cfg_CONFIG_SCSI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI")
		case "${cfg_CONFIG_SCSI}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI" "${cfg_CONFIG_SCSI}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_LOWLEVEL" "y"

		local cfg_CONFIG_DRM=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DRM")
		case "${cfg_CONFIG_DRM}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DRM=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DRM" "${cfg_CONFIG_DRM}"

		local cfg_CONFIG_HW_RANDOM=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HW_RANDOM")
		case "${cfg_CONFIG_HW_RANDOM}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_HW_RANDOM=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HW_RANDOM" "${cfg_CONFIG_HW_RANDOM}"

		local cfg_CONFIG_INPUT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT")
		case "${cfg_CONFIG_INPUT}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_INPUT=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT" "${cfg_CONFIG_INPUT}"

		local cfg_CONFIG_VHOST_NET=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VHOST_NET")
		case "${cfg_CONFIG_VHOST_NET}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_VHOST_NET=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VHOST_NET" "${cfg_CONFIG_VHOST_NET}"

		if [ ${KV_NUMERIC} -ge 4006 ]
		then
			local cfg_CONFIG_FW_CFG_SYSFS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FW_CFG_SYSFS")
			case "${cfg_CONFIG_FW_CFG_SYSFS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_FW_CFG_SYSFS=${newcfg_setting}
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FW_CFG_SYSFS" "${cfg_CONFIG_FW_CFG_SYSFS}"
		fi

		local cfg_CONFIG_VIRTIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO")
		local cfg_CONFIG_SCSI_VIRTIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_VIRTIO")
		local cfg_CONFIG_VIRTIO_BLK=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_BLK")
		local cfg_CONFIG_VIRTIO_NET=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_NET")
		local cfg_CONFIG_VIRTIO_PCI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_PCI")
		if \
			isTrue "${cfg_CONFIG_VIRTIO}" || \
			isTrue "${cfg_CONFIG_SCSI_VIRTIO}" || \
			isTrue "${cfg_CONFIG_VIRTIO_BLK}" || \
			isTrue "${cfg_CONFIG_VIRTIO_NET}" || \
			isTrue "${cfg_CONFIG_VIRTIO_PCI}"
		then
			# If the user has configured VirtIO as built-in, we need to respect that.
			local newvirtio_setting="y"
		else
			local newvirtio_setting=${newcfg_setting}
		fi

		# VirtIO modules, activate in order!
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO" "${newvirtio_setting}" \
			&& required_kernel_options+=( 'CONFIG_VIRTIO' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_MENU" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_VIRTIO" "${newvirtio_setting}" \
			&& required_kernel_options+=( 'CONFIG_SCSI_VIRTIO' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_BLK" "${newvirtio_setting}" \
			&& required_kernel_options+=( 'CONFIG_VIRTIO_BLK' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_NET" "${newvirtio_setting}" \
			&& required_kernel_options+=( 'CONFIG_VIRTIO_NET' )
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_PCI" "${newvirtio_setting}"

		if [ ${KV_NUMERIC} -ge 4011 ]
		then
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_BLK_SCSI" "y"
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_MQ_VIRTIO" "y"
		fi

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_BALLOON" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_CONSOLE" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_INPUT" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DRM_VIRTIO_GPU" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HW_RANDOM_VIRTIO" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_MMIO" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES" "y"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET_9P" "${newvirtio_setting}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET_9P_VIRTIO" "${newvirtio_setting}"

		if [ ${KV_NUMERIC} -ge 4008 ]
		then
			local cfg_CONFIG_VSOCKETS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS")
			case "${cfg_CONFIG_VSOCKETS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_VSOCKETS=${newcfg_setting}
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS" "${cfg_CONFIG_VSOCKETS}"

			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_VSOCKETS" "${newvirtio_setting}"
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_VSOCKETS_COMMON" "${newvirtio_setting}"
		fi

		[ ${KV_NUMERIC} -ge 4010 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_DEV_VIRTIO" "${newvirtio_setting}"

		if [ ${KV_NUMERIC} -ge 5004 ]
		then
			local cfg_CONFIG_FUSE_FS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FUSE_FS")
			case "${cfg_CONFIG_FUSE_FS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_FUSE_FS=${newvirtio_setting}
			esac

			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FUSE_FS" "${cfg_CONFIG_FUSE_FS}"
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_FS" "${cfg_CONFIG_FUSE_FS}"
		fi
	fi

	# Microcode setting, intended for early microcode loading, if --microcode
	if [[ -n "${MICROCODE}" ]]
	then
		if isTrue "${KERNEL_SUPPORT_MICROCODE}"
		then
			local -a kconfigs_microcode
			local -a kconfigs_microcode_amd
			local -a kconfigs_microcode_intel

			print_info 2 "$(get_indent 1)>> Ensure that required kernel options for early microcode loading support are set ..."
			kconfigs_microcode+=( 'CONFIG_MICROCODE' )
			kconfigs_microcode+=( 'CONFIG_MICROCODE_OLD_INTERFACE' )
			[ ${KV_NUMERIC} -le 4003 ] && kconfigs_microcode+=( 'CONFIG_MICROCODE_EARLY' )

			# Intel
			kconfigs_microcode_intel+=( 'CONFIG_MICROCODE_INTEL' )
			[ ${KV_NUMERIC} -le 4003 ] && kconfigs_microcode_intel+=( 'CONFIG_MICROCODE_INTEL_EARLY' )

			# AMD
			kconfigs_microcode_amd=( 'CONFIG_MICROCODE_AMD' )
			[ ${KV_NUMERIC} -le 4003 ] && kconfigs_microcode_amd+=( 'CONFIG_MICROCODE_AMD_EARLY' )

			[[ "${MICROCODE}" == all ]]   && kconfigs_microcode+=( ${kconfigs_microcode_amd[@]} ${kconfigs_microcode_intel[@]} )
			[[ "${MICROCODE}" == amd ]]   && kconfigs_microcode+=( ${kconfigs_microcode_amd[@]} )
			[[ "${MICROCODE}" == intel ]] && kconfigs_microcode+=( ${kconfigs_microcode_intel[@]} )

			local k
			for k in "${kconfigs_microcode[@]}"
			do
				local cfg=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "$k")
				case "${cfg}" in
					y) ;; # Do nothing
					*) cfg='y'
				esac
				kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "$k" "${cfg}"
			done

			required_kernel_options+=( 'CONFIG_MICROCODE' )
			case "${MICROCODE}" in
				amd)
					required_kernel_options+=( 'CONFIG_MICROCODE_AMD' )
					;;
				intel)
					required_kernel_options+=( 'CONFIG_MICROCODE_INTEL' )
					;;
				all)
					required_kernel_options+=( 'CONFIG_MICROCODE_AMD' )
					required_kernel_options+=( 'CONFIG_MICROCODE_INTEL' )
					;;
			esac
		else
			print_info 1 "$(get_indent 1)>> Ignoring --microcode parameter; Architecture does not support microcode loading ..."
		fi
	fi

	if [ -f "${KCONFIG_MODIFIED_MARKER}" ]
	then
		if isTrue "${OLDCONFIG}"
		then
			print_info 1 "$(get_indent 1)>> Re-running 'make oldconfig' due to changed kernel options ..."
			yes '' 2>/dev/null | compile_generic oldconfig kernel 2>/dev/null
		else
			print_info 1 "$(get_indent 1)>> Running 'make olddefconfig' due to changed kernel options ..."
			compile_generic olddefconfig kernel 2>/dev/null
		fi

		print_info 2 "$(get_indent 1)>> Checking if required kernel options are still present ..."
		local required_kernel_option=
		for required_kernel_option in "${required_kernel_options[@]}"
		do
			local optval=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "${required_kernel_option}")
			if [ -z "${optval}" ]
			then
				gen_die "Something went wrong: Required kernel option '${required_kernel_option}' which genkernel tried to set is missing!"
			else
				print_info 3 "$(get_indent 2) - '${required_kernel_option}' is set to '${optval}'"
			fi
		done
	else
		print_info 2 "$(get_indent 1)>> genkernel did not need to add/modify any kernel options."
	fi
}
