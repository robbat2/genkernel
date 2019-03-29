#!/bin/bash
# $Id$

# Fills variable KERNEL_CONFIG
determine_config_file() {
	print_info 2 "Checking for suitable kernel configuration..."

	if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" != "default" ]
	then
		KERNEL_CONFIG=$(expand_file "${CMD_KERNEL_CONFIG}")
		if [ -z "${KERNEL_CONFIG}" ]
		then
			error_msg="No kernel .config: Cannot use '${CMD_KERNEL_CONFIG}' value. "
			error_msg+="Check --kernel-config value or unset "
			error_msg+="to use default kernel config provided by genkernel."
			gen_die "${error_msg}"
		fi
	else
		local -a kconfig_candidates
		kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/kernel-config-${KV}" )
		kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/kernel-config-${VER}.${PAT}" )
		kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/generated-config" )
		kconfig_candidates+=( "${GK_SHARE}/arch/${ARCH}/kernel-config" )
		kconfig_candidates+=( "${DEFAULT_KERNEL_CONFIG}" )

		if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ]
		then
			print_info 1 "Default configuration was forced. Will ignore any user kernel configuration!"
		else
			kconfig_candidates=( "/etc/kernels/kernel-config-${ARCH}-${KV}" ${kconfig_candidates[@]} )
		fi

		for f in "${kconfig_candidates[@]}"
		do
			[ -z "${f}" ] && continue

			if [ -f "${f}" ]
			then
				if grep -sq THIS_CONFIG_IS_BROKEN "$f"
				then
					print_info 2 "$(getIndent 1)- '${f}' is marked as broken; Skipping..."
				else
					KERNEL_CONFIG="$f" && break
				fi
			else
					print_info 2 "$(getIndent 1)- '${f}' not found; Skipping..."
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
	cd "${KERNEL_DIR}" || gen_die 'Could not switch to the kernel directory!'

	print_info 1 "kernel: >> Initializing..."

	if isTrue "${CLEAN}" && isTrue "${MRPROPER}"
	then
		print_info 1 "$(getIndent 1)>> Skipping 'make clean' -- will run 'make mrproper' later"
	elif isTrue "${CLEAN}" && ! isTrue "${MRPROPER}"
	then
		print_info 1 "$(getIndent 1)>> Cleaning..."
		compile_generic clean kernel
	else
		print_info 1 "$(getIndent 1)>> --clean is disabled; not running 'make clean'."
	fi

	if isTrue "${MRPROPER}" || [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ]
	then
		# Backup current kernel .config
		if [ -f "${KERNEL_OUTPUTDIR}/.config" ]
		then
			# Current .config is different then one we are going to use
			if [ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ] || \
				! diff -q "${KERNEL_OUTPUTDIR}"/.config "${KERNEL_CONFIG}" > /dev/null
			then
				NOW=`date +--%Y-%m-%d--%H-%M-%S`
				cp "${KERNEL_OUTPUTDIR}/.config" "${KERNEL_OUTPUTDIR}/.config${NOW}.bak" \
					|| gen_die "Could not backup kernel config (${KERNEL_OUTPUTDIR}/.config)"
				print_info 1 "$(getIndent 1)>> Previous config backed up to .config${NOW}.bak"

				[ -n "${CMD_KERNEL_CONFIG}" -a "${CMD_KERNEL_CONFIG}" = "default" ] &&
					rm "${KERNEL_OUTPUTDIR}/.config" > /dev/null
			fi
		fi
	fi

	if isTrue "${MRPROPER}"
	then
		print_info 1 "$(getIndent 1)>> Running mrproper..."
		compile_generic mrproper kernel
	else
		if [ -f "${KERNEL_OUTPUTDIR}/.config" ]
		then
			print_info 1 "$(getIndent 1)>> Using config from ${KERNEL_OUTPUTDIR}/.config"
		else
			print_info 1 "$(getIndent 1)>> Using config from ${KERNEL_CONFIG}"
		fi
		print_info 1 "$(getIndent 1)>> --mrproper is disabled; not running 'make mrproper'."
	fi

	# If we're not cleaning a la mrproper, then we don't want to try to overwrite the configs
	# or we might remove configurations someone is trying to test.
	if isTrue "${MRPROPER}" || [ ! -f "${KERNEL_OUTPUTDIR}/.config" ]
	then
		print_info 1 "$(getIndent 1)>> Using config from ${KERNEL_CONFIG}"

		local message='Could not copy configuration file!'
		if [[ "$(file --brief --mime-type "${KERNEL_CONFIG}")" == application/x-gzip ]]
		then
			# Support --kernel-config=/proc/config.gz, mainly
			zcat "${KERNEL_CONFIG}" > "${KERNEL_OUTPUTDIR}/.config" || gen_die "${message}"
		else
			cp "${KERNEL_CONFIG}" "${KERNEL_OUTPUTDIR}/.config" || gen_die "${message}"
		fi
	fi

	if isTrue "${OLDCONFIG}"
	then
		print_info 1 "$(getIndent 1)>> Running oldconfig..."
		yes '' 2>/dev/null | compile_generic oldconfig kernel 2>/dev/null
	else
		print_info 1 "$(getIndent 1)>> --oldconfig is disabled; not running 'make oldconfig'."
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

	if [ x"${add_config}" != x"" ]
	then
		print_info 1 "$(getIndent 1)>> Invoking ${add_config}..."
		compile_generic $add_config kernelruntask
		[ "$?" ] || gen_die "Error: ${add_config} failed!"
	fi

	local -a required_kernel_options
	[ -f "${TEMP}/.kconfig_modified" ] && rm "${TEMP}/.kconfig_modified"

	# Force this on if we are using --genzimage
	if isTrue "${CMD_GENZIMAGE}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for --genzimage are set..."
		# Make sure Ext2 support is on...
		cfg_CONFIG_EXT2_FS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT2_FS")
		if ! isTrue "${cfg_CONFIG_EXT2_FS}"
		then
			cfg_CONFIG_EXT4_USE_FOR_EXT2=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT4_USE_FOR_EXT2")
			if ! isTrue "${cfg_CONFIG_EXT4_USE_FOR_EXT2}"
			then
				cfg_CONFIG_EXT4_FS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT4_FS")
				if isTrue "${cfg_CONFIG_EXT4_FS}"
				then
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT4_USE_FOR_EXT2" "y" &&
						required_kernel_options+=(CONFIG_EXT4_USE_FOR_EXT2)
				else
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
					kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT2_FS" "y" &&
						required_kernel_options+=(CONFIG_EXT2_FS)
				fi
			fi
		fi
	fi

	# Do we support modules at all?
	cfg_CONFIG_MODULES=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MODULES")
	if isTrue "${cfg_CONFIG_MODULES}"
	then
		# yes, we support modules, set 'm' for new stuff.
		newcfg_setting='m'
		# Compare the kernel module compression vs the depmod module compression support
		# WARNING: if the buildhost has +XZ but the target machine has -XZ, you will get failures!
		cfg_CONFIG_MODULE_COMPRESS_GZIP=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MODULE_COMPRESS_GZIP")
		cfg_CONFIG_MODULE_COMPRESS_XZ=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MODULE_COMPRESS_XZ")
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
			local _no_modules_support_warning="$(getIndent 1)>> Forcing --static "
			if isTrue "${BUILD_RAMDISK}" && isTrue "${RAMDISKMODULES}"
			then
				_no_modules_support_warning+="and --no-ramdisk-modules "
				RAMDISKMODULES="no"
			fi

			_no_modules_support_warning+="to avoid genkernel failures because kernel does NOT support modules..."

			print_warning 1 "${_no_modules_support_warning}"
			BUILD_STATIC="yes"
		fi
	fi

	# If the user has configured DM as built-in, we need to respect that.
	cfg_CONFIG_BLK_DEV_DM=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM")
	case "$cfg_CONFIG_BLK_DEV_DM" in
		y|m) ;; # Do nothing
		*) cfg_CONFIG_BLK_DEV_DM=${newcfg_setting}
	esac

	# Make sure lvm modules are enabled in the kernel, if --lvm
	if isTrue "${CMD_LVM}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for LVM support are set..."
		cfg_CONFIG_DM_SNAPSHOT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_SNAPSHOT")
		case "$cfg_CONFIG_DM_SNAPSHOT" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_SNAPSHOT=${newcfg_setting}
		esac
		cfg_CONFIG_DM_MIRROR=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MIRROR")
		case "$cfg_CONFIG_DM_MIRROR" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_MIRROR=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" &&
			required_kernel_options+=(CONFIG_BLK_DEV_DM)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_SNAPSHOT" "${cfg_CONFIG_DM_SNAPSHOT}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MIRROR" "${cfg_CONFIG_DM_MIRROR}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FILE_LOCKING" "y" &&
			required_kernel_options+=(CONFIG_FILE_LOCKING)
	fi

	# Make sure multipath modules are enabled in the kernel, if --multipath
	if isTrue "${CMD_MULTIPATH}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for multipath support are set..."
		cfg_CONFIG_DM_MULTIPATH=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH")
		case "$cfg_CONFIG_DM_MULTIPATH" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_MULTIPATH=${newcfg_setting}
		esac
		cfg_CONFIG_DM_MULTIPATH_RDAC=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH_RDAC")
		case "$cfg_CONFIG_DM_MULTIPATH_RDAC" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DM_MULTIPATH_RDAC=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" &&
			required_kernel_options+=(CONFIG_BLK_DEV_DM)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH" "${cfg_CONFIG_DM_MULTIPATH}" &&
			required_kernel_options+=(CONFIG_DM_MULTIPATH)
	fi

	# Make sure dmraid modules are enabled in the kernel, if --dmraid
	if isTrue "${CMD_DMRAID}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for DMRAID support are set..."
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLOCK" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_MD" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "${cfg_CONFIG_BLK_DEV_DM}" &&
			required_kernel_options+=(CONFIG_BLK_DEV_DM)
	fi

	# Make sure iSCSI modules are enabled in the kernel, if --iscsi
	if isTrue "${CMD_ISCSI}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for iSCSI support are set..."
		cfg_CONFIG_ISCSI_BOOT_SYSFS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_BOOT_SYSFS")
		case "$cfg_CONFIG_ISCSI_BOOT_SYSFS" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_ISCSI_BOOT_SYSFS=${newcfg_setting}
		esac
		cfg_CONFIG_ISCSI_TCP=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_TCP")
		case "$cfg_CONFIG_ISCSI_TCP" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_ISCSI_TCP=${newcfg_setting}
		esac
		cfg_CONFIG_SCSI_ISCSI_ATTRS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_ISCSI_ATTRS")
		case "$cfg_CONFIG_SCSI_ISCSI_ATTRS" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI_ISCSI_ATTRS=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INET" "y"

		cfg_CONFIG_SCSI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI")
		case "${cfg_CONFIG_SCSI}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI" "${cfg_CONFIG_SCSI}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_LOWLEVEL" "y"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_BOOT_SYSFS" "${cfg_CONFIG_ISCSI_BOOT_SYSFS}" &&
			required_kernel_options+=(CONFIG_ISCSI_BOOT_SYSFS)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_TCP" "${cfg_CONFIG_ISCSI_TCP}" &&
			required_kernel_options+=(CONFIG_ISCSI_TCP)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_ISCSI_ATTRS" "${cfg_CONFIG_SCSI_ISCSI_ATTRS}" &&
			required_kernel_options+=(CONFIG_SCSI_ISCSI_ATTRS)
	fi

	# Make sure Hyper-V modules are enabled in the kernel, if --hyperv
	if isTrue "${CMD_HYPERV}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for Hyper-V support are set..."
		# Hyper-V deps
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ACPI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86_LOCAL_APIC" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERVISOR_GUEST" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NET" "y"

		cfg_CONFIG_CONNECTOR=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CONNECTOR")
		case "${cfg_CONFIG_CONNECTOR}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_CONNECTOR=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CONNECTOR" "${cfg_CONFIG_CONNECTOR}"

		cfg_CONFIG_NLS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NLS")
		case "${cfg_CONFIG_NLS}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_NLS=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NLS" "${cfg_CONFIG_NLS}"

		cfg_CONFIG_SCSI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI")
		case "${cfg_CONFIG_SCSI}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI" "${cfg_CONFIG_SCSI}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_LOWLEVEL" "y"

		cfg_CONFIG_SCSI_FC_ATTRS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_FC_ATTRS")
		case "${cfg_CONFIG_SCSI_FC_ATTRS}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI_FC_ATTRS=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_FC_ATTRS" "${cfg_CONFIG_SCSI_FC_ATTRS}"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_NETDEVICES" "y"

		cfg_CONFIG_SERIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SERIO")
		case "${cfg_CONFIG_SERIO}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SERIO=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SERIO" "${cfg_CONFIG_SERIO}"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI_MSI" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI_MSI_IRQ_DOMAIN" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_X86_64" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HAS_IOMEM" "y"

		cfg_CONFIG_FB=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB")
		case "${cfg_CONFIG_FB}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_FB=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB" "${cfg_CONFIG_FB}"

		cfg_CONFIG_INPUT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT")
		case "${cfg_CONFIG_INPUT}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_INPUT=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT" "${cfg_CONFIG_INPUT}"

		cfg_CONFIG_HID=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HID")
		case "${cfg_CONFIG_HID}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_HID=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HID" "${cfg_CONFIG_HID}"

		cfg_CONFIG_UIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UIO")
		case "${cfg_CONFIG_UIO}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_UIO=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UIO" "${cfg_CONFIG_UIO}"

		# Hyper-V modules, activate in order!
		cfg_CONFIG_HYPERV=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV")
		case "$cfg_CONFIG_HYPERV" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_HYPERV=${newcfg_setting}
		esac

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV" "${cfg_CONFIG_HYPERV}" &&
			required_kernel_options+=(CONFIG_HYPERV)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_UTILS" "${cfg_CONFIG_HYPERV}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_BALLOON" "${cfg_CONFIG_HYPERV}" &&
			required_kernel_options+=(CONFIG_HYPERV_BALLOON)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_STORAGE" "${cfg_CONFIG_HYPERV}" &&
			required_kernel_options+=(CONFIG_HYPERV_STORAGE)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_NET" "${cfg_CONFIG_HYPERV}" &&
			required_kernel_options+=(CONFIG_HYPERV_NET)

		if [ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4014 ]
		then
			cfg_CONFIG_VSOCKETS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS")
			case "${cfg_CONFIG_VSOCKETS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_VSOCKETS=${newcfg_setting}
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS" "${cfg_CONFIG_VSOCKETS}"

			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_VSOCKETS" "${cfg_CONFIG_HYPERV}"
		fi

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_KEYBOARD" "${cfg_CONFIG_HYPERV}"

		[ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4006 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_PCI_HYPERV" "${cfg_CONFIG_HYPERV}"

		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB_HYPERV" "${cfg_CONFIG_HYPERV}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HID_HYPERV_MOUSE" "${cfg_CONFIG_HYPERV}"

		[ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4010 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_UIO_HV_GENERIC" "${cfg_CONFIG_HYPERV}"

		[ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4012 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HYPERV_TSCPAGE" "y"
	fi

	# Make sure kernel supports Splash, if --splash
	if isTrue "${SPLASH}"
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for Splash support are set..."
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
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for VirtIO support are set..."
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

		cfg_CONFIG_SCSI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI")
		case "${cfg_CONFIG_SCSI}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_SCSI=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI" "${cfg_CONFIG_SCSI}"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_LOWLEVEL" "y"

		cfg_CONFIG_DRM=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DRM")
		case "${cfg_CONFIG_DRM}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_DRM=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DRM" "${cfg_CONFIG_DRM}"

		cfg_CONFIG_HW_RANDOM=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HW_RANDOM")
		case "${cfg_CONFIG_HW_RANDOM}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_HW_RANDOM=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_HW_RANDOM" "${cfg_CONFIG_HW_RANDOM}"

		cfg_CONFIG_INPUT=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT")
		case "${cfg_CONFIG_INPUT}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_INPUT=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_INPUT" "${cfg_CONFIG_INPUT}"

		cfg_CONFIG_VHOST_NET=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VHOST_NET")
		case "${cfg_CONFIG_VHOST_NET}" in
			y|m) ;; # Do nothing
			*) cfg_CONFIG_VHOST_NET=${newcfg_setting}
		esac
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VHOST_NET" "${cfg_CONFIG_VHOST_NET}"

		if [ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4006 ]
		then
			cfg_CONFIG_FW_CFG_SYSFS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FW_CFG_SYSFS")
			case "${cfg_CONFIG_FW_CFG_SYSFS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_FW_CFG_SYSFS=${newcfg_setting}
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FW_CFG_SYSFS" "${cfg_CONFIG_FW_CFG_SYSFS}"
		fi

		cfg_CONFIG_VIRTIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO")
		cfg_CONFIG_SCSI_VIRTIO=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_VIRTIO")
		cfg_CONFIG_VIRTIO_BLK=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_BLK")
		cfg_CONFIG_VIRTIO_NET=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_NET")
		cfg_CONFIG_VIRTIO_PCI=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_PCI")
		if \
			isTrue "${cfg_CONFIG_VIRTIO}" || \
			isTrue "${cfg_CONFIG_SCSI_VIRTIO}" || \
			isTrue "${cfg_CONFIG_VIRTIO_BLK}" || \
			isTrue "${cfg_CONFIG_VIRTIO_NET}" || \
			isTrue "${cfg_CONFIG_VIRTIO_PCI}"
		then
			# If the user has configured VirtIO as built-in, we need to respect that.
			newvirtio_setting="y"
		else
			newvirtio_setting=${newcfg_setting}
		fi

		# VirtIO modules, activate in order!
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO" "${newvirtio_setting}" &&
			required_kernel_options+=(CONFIG_VIRTIO)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_MENU" "y"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_VIRTIO" "${newvirtio_setting}" &&
			required_kernel_options+=(CONFIG_SCSI_VIRTIO)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_BLK" "${newvirtio_setting}" &&
			required_kernel_options+=(CONFIG_VIRTIO_BLK)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_NET" "${newvirtio_setting}" &&
			required_kernel_options+=(CONFIG_VIRTIO_NET)
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_PCI" "${newvirtio_setting}"

		if [ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4011 ]
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

		if [ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4008 ]
		then
			cfg_CONFIG_VSOCKETS=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS")
			case "${cfg_CONFIG_VSOCKETS}" in
				y|m) ;; # Do nothing
				*) cfg_CONFIG_VSOCKETS=${newcfg_setting}
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VSOCKETS" "${cfg_CONFIG_VSOCKETS}"

			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_VSOCKETS" "${newvirtio_setting}"
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_VIRTIO_VSOCKETS_COMMON" "${newvirtio_setting}"
		fi

		[ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -ge 4010 ] &&
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_CRYPTO_DEV_VIRTIO" "${newvirtio_setting}"
	fi

	# Microcode setting, intended for early microcode loading, if --microcode
	if [[ -n "${MICROCODE}" ]]
	then
		print_info 1 "$(getIndent 1)>> Ensure that required kernel options for early microcode loading support are set..."
		kconfig_microcode_intel=(CONFIG_MICROCODE_INTEL CONFIG_MICROCODE_INTEL_EARLY)

		kconfig_microcode_amd=(CONFIG_MICROCODE_AMD)
		[ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -le 4003 ] && kconfig_microcode_amd+=(CONFIG_MICROCODE_AMD_EARLY)

		kconfigs=(CONFIG_MICROCODE CONFIG_MICROCODE_OLD_INTERFACE)
		[ $(($KV_MAJOR * 1000 + ${KV_MINOR})) -le 4003 ] && kconfigs+=(CONFIG_MICROCODE_EARLY)

		[[ "$MICROCODE" == all ]] && kconfigs+=( ${kconfig_microcode_amd[@]} ${kconfig_microcode_intel[@]} )
		[[ "$MICROCODE" == amd ]] && kconfigs+=( ${kconfig_microcode_amd[@]} )
		[[ "$MICROCODE" == intel ]] && kconfigs+=( ${kconfig_microcode_intel[@]} )

		for k in "${kconfigs[@]}"
		do
			cfg=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "$k")
			case "$cfg" in
				y) ;; # Do nothing
				*) cfg='y'
			esac
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "$k" "${cfg}"
		done

		required_kernel_options+=(CONFIG_MICROCODE)
	fi

	if [ -f "${TEMP}/.kconfig_modified" ]
	then
		if isTrue "${OLDCONFIG}"
		then
			print_info 1 "$(getIndent 1)>> Re-running oldconfig due to changed kernel options..."
			yes '' 2>/dev/null | compile_generic oldconfig kernel 2>/dev/null
		else
			print_info 1 "$(getIndent 1)>> Running olddefconfig due to changed kernel options..."
			compile_generic olddefconfig kernel 2>/dev/null
		fi
	else
		print_info 2 "$(getIndent 1)>> genkernel did not need to add/modify any kernel options."
	fi

	print_info 2 "$(getIndent 1)>> checking for required kernel options..."
	for required_kernel_option in "${required_kernel_options[@]}"
	do
		optval=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "${required_kernel_option}")
		if [ -z "${optval}" ]
		then
			gen_die "something went wrong: Required kernel option '${required_kernel_option}' which genkernel tried to set is missing!"
		else
			print_info 2 "$(getIndent 2) - '${required_kernel_option}' is set to '${optval}'"
		fi
	done
}
