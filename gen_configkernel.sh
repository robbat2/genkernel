#!/bin/bash
# $Id$

# Fills variable KERNEL_CONFIG
determine_config_file() {
	for f in \
		"${CMD_KERNEL_CONFIG}" \
		"/etc/kernels/kernel-config-${ARCH}-${KV}" \
		"${GK_SHARE}/arch/${ARCH}/kernel-config-${KV}" \
		"${DEFAULT_KERNEL_CONFIG}" \
		"${GK_SHARE}/arch/${ARCH}/kernel-config-${VER}.${PAT}" \
		"${GK_SHARE}/arch/${ARCH}/generated-config" \
		"${GK_SHARE}/arch/${ARCH}/kernel-config" \
		; do
		if [ -n "${f}" -a -f "${f}" ]
		then
			if ! grep -sq THIS_CONFIG_IS_BROKEN "$f"
			then
				KERNEL_CONFIG="$f" && break
			fi
		fi
	done
	if [ -z "${KERNEL_CONFIG}" ]
	then
		gen_die 'Error: No kernel .config specified, or file not found!'
	fi
    KERNEL_CONFIG="$(readlink -f "${KERNEL_CONFIG}")"
	# Validate the symlink result if any
	if [ ! -f "${KERNEL_CONFIG}" ]
	then
		gen_die "Error: No kernel .config: symlinked file not found! ($KERNEL_CONFIG)"
	fi
}

function kconfig_get_opt() {
	kconfig="$1"
	optname="$2"
	sed -n "${kconfig}" \
		-e "/^#\? \?${optname}[ =].*/{ s/.*${optname}[ =]//g; s/is not set//g; p; q }"
}

function kconfig_set_opt() {
	kconfig="$1"
	optname="$2"
	optval="$3"
	sed -i "${kconfig}" \
		-e "s/^#\? \?${optname}[ =].*/${optname}=${optval}/g" \
	|| gen_die "Failed to set ${optname}=${optval} in $kconfig"
}

config_kernel() {
	determine_config_file
	cd "${KERNEL_DIR}" || gen_die 'Could not switch to the kernel directory!'

	# Backup current kernel .config
	if isTrue "${MRPROPER}" || [ ! -f "${KERNEL_OUTPUTDIR}/.config" ]
	then
		print_info 1 "kernel: Using config from ${KERNEL_CONFIG}"
		if [ -f "${KERNEL_OUTPUTDIR}/.config" ]
		then
			NOW=`date +--%Y-%m-%d--%H-%M-%S`
			cp "${KERNEL_OUTPUTDIR}/.config" "${KERNEL_OUTPUTDIR}/.config${NOW}.bak" \
					|| gen_die "Could not backup kernel config (${KERNEL_OUTPUTDIR}/.config)"
			print_info 1 "        Previous config backed up to .config${NOW}.bak"
		fi
	fi

	if isTrue ${MRPROPER}
	then
		print_info 1 'kernel: >> Running mrproper...'
		compile_generic mrproper kernel
	else
		print_info 1 "kernel: --mrproper is disabled; not running 'make mrproper'."
	fi

	# If we're not cleaning a la mrproper, then we don't want to try to overwrite the configs
	# or we might remove configurations someone is trying to test.
	if isTrue "${MRPROPER}" || [ ! -f "${KERNEL_OUTPUTDIR}/.config" ]
	then
		local message='Could not copy configuration file!'
		if [[ "$(file --brief --mime-type "${KERNEL_CONFIG}")" == application/x-gzip ]]; then
			# Support --kernel-config=/proc/config.gz, mainly
			zcat "${KERNEL_CONFIG}" > "${KERNEL_OUTPUTDIR}/.config" || gen_die "${message}"
		else
			cp "${KERNEL_CONFIG}" "${KERNEL_OUTPUTDIR}/.config" || gen_die "${message}"
		fi
	fi

	if isTrue "${OLDCONFIG}"
	then
		print_info 1 '        >> Running oldconfig...'
		yes '' 2>/dev/null | compile_generic oldconfig kernel 2>/dev/null
	else
		print_info 1 "kernel: --oldconfig is disabled; not running 'make oldconfig'."
	fi
	if isTrue "${CLEAN}"
	then
		print_info 1 'kernel: >> Cleaning...'
		compile_generic clean kernel
	else
		print_info 1 "kernel: --clean is disabled; not running 'make clean'."
	fi

	if isTrue ${MENUCONFIG}
	then
		print_info 1 'kernel: >> Invoking menuconfig...'
		compile_generic menuconfig kernelruntask
		[ "$?" ] || gen_die 'Error: menuconfig failed!'
	elif isTrue ${CMD_GCONFIG}
	then
		print_info 1 'kernel: >> Invoking gconfig...'
		compile_generic gconfig kernel
		[ "$?" ] || gen_die 'Error: gconfig failed!'

		CMD_XCONFIG=0
	fi

	if isTrue ${CMD_XCONFIG}
	then
		print_info 1 'kernel: >> Invoking xconfig...'
		compile_generic xconfig kernel
		[ "$?" ] || gen_die 'Error: xconfig failed!'
	fi

	# Force this on if we are using --genzimage
	if isTrue ${CMD_GENZIMAGE}
	then
		# Make sure Ext2 support is on...
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_EXT2_FS" "y"
	fi

	# Make sure lvm modules are on if --lvm
	if isTrue ${CMD_LVM}
	then
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "m"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_SNAPSHOT" "m"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MIRROR" "m"
	fi

	# Multipath
	if isTrue ${CMD_MULTIPATH}
	then
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "m"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH" "m"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_DM_MULTIPATH_RDAC" "m"
	fi

	# Make sure dmraid modules are on if --dmraid
	if isTrue ${CMD_DMRAID}
	then
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_BLK_DEV_DM" "m"
	fi

	# Make sure iSCSI modules are enabled in the kernel, if --iscsi
	# CONFIG_SCSI_ISCSI_ATTRS
	# CONFIG_ISCSI_TCP
	if isTrue ${CMD_ISCSI}
	then
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_ISCSI_TCP" "m"
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_SCSI_ISCSI_ATTRS" "m"
	fi

	if isTrue ${SPLASH}
	then
		kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "CONFIG_FB_SPLASH" "y"
	fi

	# VirtIO
	if isTrue ${CMD_VIRTIO}
	then
		for k in \
			CONFIG_VIRTIO \
			CONFIG_VIRTIO_BALLOON \
			CONFIG_VIRTIO_BLK \
			CONFIG_VIRTIO_CONSOLE \
			CONFIG_VIRTIO_INPUT \
			CONFIG_VIRTIO_MMIO \
			CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES \
			CONFIG_VIRTIO_NET \
			CONFIG_VIRTIO_PCI \
			\
			CONFIG_PARAVIRT_GUEST \
			CONFIG_SCSI_VIRTIO \
			CONFIG_VHOST_NET \
			; do
			kconfig_set_opt "${KERNEL_OUTPUTDIR}/.config" "$k" "y"
		done
	fi
}
