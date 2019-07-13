#!/bin/bash
# $Id$

determine_KV() {
	local old_KV=
	[ -n "${KV}" ] && old_KV="${KV}"

	if ! isTrue "${KERNEL_SOURCES}" && [ -e "${KERNCACHE}" ]
	then
		tar -x -C "${TEMP}" -f "${KERNCACHE}" kerncache.config \
			|| gen_die "Failed to extract 'kerncache.config' from '${KERNCACHE}' to '${TEMP}'!"

		if [ -e "${TEMP}/kerncache.config" ]
		then
			VER=$(grep ^VERSION\ \= "${TEMP}"/kerncache.config | awk '{ print $3 };')
			PAT=$(grep ^PATCHLEVEL\ \= "${TEMP}"/kerncache.config | awk '{ print $3 };')
			SUB=$(grep ^SUBLEVEL\ \= "${TEMP}"/kerncache.config | awk '{ print $3 };')
			EXV=$(grep ^EXTRAVERSION\ \= "${TEMP}"/kerncache.config | sed -e "s/EXTRAVERSION =//" -e "s/ //g")
			LOV=$(grep ^CONFIG_LOCALVERSION\ \= "${TEMP}"/kerncache.config | sed -e "s/CONFIG_LOCALVERSION=\"\(.*\)\"/\1/")
			KV=${VER}.${PAT}.${SUB}${EXV}${LOV}
		else
			gen_die "Could not find kerncache.config in the kernel cache! Exiting."
		fi
	else
		# Configure the kernel
		# If BUILD_KERNEL=0 then assume --no-clean, menuconfig is cleared

		if [ ! -f "${KERNEL_DIR}"/Makefile ]
		then
			gen_die "Kernel Makefile (${KERNEL_DIR}/Makefile) missing.  Maybe re-install the kernel sources."
		fi

		VER=$(grep ^VERSION\ \= ${KERNEL_DIR}/Makefile | awk '{ print $3 };')
		PAT=$(grep ^PATCHLEVEL\ \= ${KERNEL_DIR}/Makefile | awk '{ print $3 };')
		SUB=$(grep ^SUBLEVEL\ \= ${KERNEL_DIR}/Makefile | awk '{ print $3 };')
		EXV=$(grep ^EXTRAVERSION\ \= ${KERNEL_DIR}/Makefile | sed -e "s/EXTRAVERSION =//" -e "s/ //g" -e 's/\$([a-z]*)//gi')

		# The files we are looking for are always in KERNEL_OUTPUTDIR
		# because in most cases, KERNEL_OUTPUTDIR == KERNEL_DIR.
		# If KERNEL_OUTPUTDIR != KERNEL_DIR, --kernel-outputdir is used,
		# in which case files will only be in KERNEL_OUTPUTDIR.
		[ -f "${KERNEL_OUTPUTDIR}/include/linux/version.h" ] && \
			VERSION_SOURCE="${KERNEL_OUTPUTDIR}/include/linux/version.h"
		[ -f "${KERNEL_OUTPUTDIR}/include/linux/utsrelease.h" ] && \
			VERSION_SOURCE="${KERNEL_OUTPUTDIR}/include/linux/utsrelease.h"
		# Handle new-style releases where version.h doesn't have UTS_RELEASE
		if [ -f ${KERNEL_OUTPUTDIR}/include/config/kernel.release ]
		then
			print_info 3 "Using '${KERNEL_OUTPUTDIR}/include/config/kernel.release' to extract LOCALVERSION ..."
			UTS_RELEASE=$(cat ${KERNEL_OUTPUTDIR}/include/config/kernel.release)
			LOV=$(echo ${UTS_RELEASE}|sed -e "s/${VER}.${PAT}.${SUB}${EXV}//")
			KV=${VER}.${PAT}.${SUB}${EXV}${LOV}
		elif [ -n "${VERSION_SOURCE}" ]
		then
			print_info 3 "Using '${VERSION_SOURCE}' to extract LOCALVERSION ..."
			UTS_RELEASE=$(grep UTS_RELEASE ${VERSION_SOURCE} | sed -e 's/#define UTS_RELEASE "\(.*\)"/\1/')
			LOV=$(echo ${UTS_RELEASE}|sed -e "s/${VER}.${PAT}.${SUB}${EXV}//")
			KV=${VER}.${PAT}.${SUB}${EXV}${LOV}
		else
			# We will be here only when currently selected kernel source
			# is untouched (i.e. after a new kernel sources version was
			# installed and will now be used for the first time) or
			# was cleaned.
			# Anyway, we have no chance to get a LOCALVERSION,
			# so don't even try -- it would be also useless at this stage.
			# Note: If we are building a kernel in this genkernel run and
			#       LOCALVERSION will become available later due to
			#       changed configuration we will notice after we have
			#       prepared the sources.
			print_info 3 "Unable to determine LOCALVERSION -- maybe cleaned/fresh sources?"
			KV=${VER}.${PAT}.${SUB}${EXV}
		fi
	fi

	KV_MAJOR=$(echo $KV | cut -f1 -d.)
	KV_MINOR=$(echo $KV | cut -f2 -d.)

	if [ -n "${old_KV}" -a "${KV}" != "${old_KV}" ]
	then
		print_info 3 "KV changed from '${old_KV}' to '${KV}'!"
		echo "${old_KV}" > "${TEMP}/.old_kv" ||
			gen_die "failed to to store '${old_KV}' in '${TEMP}/.old_kv' marker"
	fi
}

determine_real_args() {
	print_info 4 "Resolving config file, command line, and arch default settings."

	#                               Dest / Config File   Command Line                     Arch Default
	#                               ------------------   ------------                     ------------
	set_config_with_override STRING LOGFILE                  CMD_LOGFILE                  "/var/log/genkernel.conf"
	set_config_with_override STRING KERNEL_DIR               CMD_KERNEL_DIR               "${DEFAULT_KERNEL_SOURCE}"
	set_config_with_override BOOL   KERNEL_SOURCES           CMD_KERNEL_SOURCES           "yes"
	set_config_with_override STRING KNAME                    CMD_KERNNAME                 "genkernel"

	set_config_with_override STRING COMPRESS_INITRD          CMD_COMPRESS_INITRD          "$DEFAULT_COMPRESS_INITRD"
	set_config_with_override STRING COMPRESS_INITRD_TYPE     CMD_COMPRESS_INITRD_TYPE     "$DEFAULT_COMPRESS_INITRD_TYPE"
	set_config_with_override STRING MAKEOPTS                 CMD_MAKEOPTS                 "$DEFAULT_MAKEOPTS"
	set_config_with_override STRING NICE                     CMD_NICE                     "10"
	set_config_with_override STRING KERNEL_MAKE              CMD_KERNEL_MAKE              "$DEFAULT_KERNEL_MAKE"
	set_config_with_override STRING UTILS_MAKE               CMD_UTILS_MAKE               "$DEFAULT_UTILS_MAKE"
	set_config_with_override STRING KERNEL_CC                CMD_KERNEL_CC                "$DEFAULT_KERNEL_CC"
	set_config_with_override STRING KERNEL_LD                CMD_KERNEL_LD                "$DEFAULT_KERNEL_LD"
	set_config_with_override STRING KERNEL_AS                CMD_KERNEL_AS                "$DEFAULT_KERNEL_AS"
	set_config_with_override STRING UTILS_CC                 CMD_UTILS_CC                 "$DEFAULT_UTILS_CC"
	set_config_with_override STRING UTILS_LD                 CMD_UTILS_LD                 "$DEFAULT_UTILS_LD"
	set_config_with_override STRING UTILS_AS                 CMD_UTILS_AS                 "$DEFAULT_UTILS_AS"

	set_config_with_override STRING KERNEL_CROSS_COMPILE     CMD_KERNEL_CROSS_COMPILE
	set_config_with_override STRING UTILS_CROSS_COMPILE      CMD_UTILS_CROSS_COMPILE
	set_config_with_override STRING BOOTDIR                  CMD_BOOTDIR                  "/boot"
	set_config_with_override STRING KERNEL_OUTPUTDIR         CMD_KERNEL_OUTPUTDIR         "${KERNEL_DIR}"
	set_config_with_override STRING MODPROBEDIR              CMD_MODPROBEDIR              "/etc/modprobe.d"

	set_config_with_override BOOL   SPLASH                   CMD_SPLASH                   "no"
	set_config_with_override BOOL   CLEAR_CACHEDIR           CMD_CLEAR_CACHEDIR           "no"
	set_config_with_override BOOL   POSTCLEAR                CMD_POSTCLEAR                "no"
	set_config_with_override BOOL   MRPROPER                 CMD_MRPROPER                 "yes"
	set_config_with_override BOOL   MENUCONFIG               CMD_MENUCONFIG               "no"
	set_config_with_override BOOL   GCONFIG                  CMD_GCONFIG                  "no"
	set_config_with_override BOOL   NCONFIG                  CMD_NCONFIG                  "no"
	set_config_with_override BOOL   XCONFIG                  CMD_XCONFIG                  "no"
	set_config_with_override BOOL   CLEAN                    CMD_CLEAN                    "yes"

	set_config_with_override STRING MINKERNPACKAGE           CMD_MINKERNPACKAGE
	set_config_with_override STRING MODULESPACKAGE           CMD_MODULESPACKAGE
	set_config_with_override STRING KERNCACHE                CMD_KERNCACHE
	set_config_with_override BOOL   RAMDISKMODULES           CMD_RAMDISKMODULES           "yes"
	set_config_with_override BOOL   ALLRAMDISKMODULES        CMD_ALLRAMDISKMODULES        "no"
	set_config_with_override STRING INITRAMFS_OVERLAY        CMD_INITRAMFS_OVERLAY
	set_config_with_override BOOL   MOUNTBOOT                CMD_MOUNTBOOT                "yes"
	set_config_with_override BOOL   BUILD_STATIC             CMD_STATIC                   "no"
	set_config_with_override BOOL   SAVE_CONFIG              CMD_SAVE_CONFIG              "yes"
	set_config_with_override BOOL   SYMLINK                  CMD_SYMLINK                  "no"
	set_config_with_override STRING INSTALL_MOD_PATH         CMD_INSTALL_MOD_PATH
	set_config_with_override BOOL   OLDCONFIG                CMD_OLDCONFIG                "yes"
	set_config_with_override BOOL   SSH                      CMD_SSH                      "no"
	set_config_with_override BOOL   LVM                      CMD_LVM                      "no"
	set_config_with_override BOOL   DMRAID                   CMD_DMRAID                   "no"
	set_config_with_override BOOL   ISCSI                    CMD_ISCSI                    "no"
	set_config_with_override BOOL   HYPERV                   CMD_HYPERV                   "no"
	set_config_with_override STRING BOOTLOADER               CMD_BOOTLOADER               "no"
	set_config_with_override BOOL   BUSYBOX                  CMD_BUSYBOX                  "yes"
	set_config_with_override BOOL   NFS                      CMD_NFS                      "yes"
	set_config_with_override STRING MICROCODE                CMD_MICROCODE                "all"
	set_config_with_override BOOL   MICROCODE_INITRAMFS      CMD_MICROCODE_INITRAMFS      "yes"
	set_config_with_override BOOL   UNIONFS                  CMD_UNIONFS                  "no"
	set_config_with_override BOOL   NETBOOT                  CMD_NETBOOT                  "no"
	set_config_with_override STRING REAL_ROOT                CMD_REAL_ROOT
	set_config_with_override BOOL   DISKLABEL                CMD_DISKLABEL                "yes"
	set_config_with_override BOOL   LUKS                     CMD_LUKS                     "no"
	set_config_with_override BOOL   GPG                      CMD_GPG                      "no"
	set_config_with_override BOOL   MDADM                    CMD_MDADM                    "no"
	set_config_with_override STRING MDADM_CONFIG             CMD_MDADM_CONFIG
	set_config_with_override BOOL   E2FSPROGS                CMD_E2FSPROGS                "no"
	set_config_with_override BOOL   ZFS                      CMD_ZFS                      "$(rootfs_type_is zfs)"
	set_config_with_override BOOL   BTRFS                    CMD_BTRFS                    "$(rootfs_type_is btrfs)"
	set_config_with_override BOOL   VIRTIO                   CMD_VIRTIO                   "no"
	set_config_with_override BOOL   MULTIPATH                CMD_MULTIPATH                "no"
	set_config_with_override BOOL   FIRMWARE                 CMD_FIRMWARE                 "no"
	set_config_with_override STRING FIRMWARE_DIR             CMD_FIRMWARE_DIR             "/lib/firmware"
	set_config_with_override STRING FIRMWARE_FILES           CMD_FIRMWARE_FILES
	set_config_with_override BOOL   FIRMWARE_INSTALL         CMD_FIRMWARE_INSTALL         "no"
	set_config_with_override BOOL   INTEGRATED_INITRAMFS     CMD_INTEGRATED_INITRAMFS     "no"
	set_config_with_override BOOL   WRAP_INITRD              CMD_WRAP_INITRD              "no"
	set_config_with_override BOOL   GENZIMAGE                CMD_GENZIMAGE                "no"
	set_config_with_override BOOL   KEYMAP                   CMD_KEYMAP                   "yes"
	set_config_with_override BOOL   DOKEYMAPAUTO             CMD_DOKEYMAPAUTO             "no"
	set_config_with_override STRING BUSYBOX_CONFIG           CMD_BUSYBOX_CONFIG
	set_config_with_override STRING STRIP_TYPE               CMD_STRIP_TYPE               "modules"
	set_config_with_override BOOL   INSTALL                  CMD_INSTALL                  "yes"
	set_config_with_override BOOL   CLEANUP                  CMD_CLEANUP                  "yes"

	# Initialize variables
	BOOTDIR=$(arch_replace "${BOOTDIR}")
	BOOTDIR=${BOOTDIR%/}    # Remove any trailing slash
	MODPROBEDIR=${MODPROBEDIR%/}    # Remove any trailing slash

	__VARS_BINCACHE=(
		BLKID_BINCACHE
		BUSYBOX_BINCACHE
		DMRAID_BINCACHE
		FUSE_BINCACHE
		GPG_BINCACHE
		ISCSI_BINCACHE
		ISCSI_ISNS_BINCACHE
		LIBAIO_BINCACHE
		LVM_BINCACHE
		MDADM_BINCACHE
		UNIONFS_FUSE_BINCACHE
	)
	for v in CACHE_DIR BUSYBOX_CONFIG DEFAULT_KERNEL_CONFIG "${__VARS_BINCACHE[@]}"; do
		eval "$v='$(arch_replace "${!v}")'"
		eval "$v='$(cache_replace "${!v}")'"
	done

	if [ -n "${CMD_BOOTLOADER}" ]
	then
		BOOTLOADER="${CMD_BOOTLOADER}"
		if [ "${CMD_BOOTLOADER}" != "${CMD_BOOTLOADER/:/}" ]
		then
			BOOTFS=$(echo "${CMD_BOOTLOADER}" | cut -f2- -d:)
			BOOTLOADER=$(echo "${CMD_BOOTLOADER}" | cut -f1 -d:)
		fi
	fi

	if isTrue "${KERNEL_SOURCES}"
	then
		if [ ! -d ${KERNEL_DIR} ]
		then
			gen_die "kernel source directory \"${KERNEL_DIR}\" was not found!"
		fi
	fi

	if [ -z "${KERNCACHE}" ]
	then
		if [ "${KERNEL_DIR}" = '' ] && isTrue "${KERNEL_SOURCES}"
		then
			gen_die 'No kernel source directory!'
		fi
		if [ ! -e "${KERNEL_DIR}" ] && isTrue "${KERNEL_SOURCES}"
		then
			gen_die 'No kernel source directory!'
		fi
	else
		if [ "${KERNEL_DIR}" = '' ]
		then
			gen_die 'Kernel Cache specified but no kernel tree to verify against!'
		fi
	fi

	# Special case:  If --no-clean is specified on the command line,
	# imply --no-mrproper.
	if [ "${CMD_CLEAN}" != '' ]
	then
		if ! isTrue "${CLEAN}"
		then
			MRPROPER="no"
		fi
	fi

	if [ -n "${MINKERNPACKAGE}" ]
	then
		MINKERNPACKAGE=$(expand_file "${CMD_MINKERNPACKAGE}")
		if [[ -z "${MINKERNPACKAGE}" || "${MINKERNPACKAGE}" != *.tar* ]]
		then
			gen_die "--minkernpackage value '${CMD_MINKERNPACKAGE}' is invalid!"
		fi

		local minkernpackage_dir=$(dirname "${MINKERNPACKAGE}")
		if [ ! -d "${minkernpackage_dir}" ]
		then
			mkdir -p "${minkernpackage_dir}" \
				|| gen_die "Failed to create '${minkernpackage_dir}'!"
		fi
	fi

	if [ -n "${MODULESPACKAGE}" ]
	then
		MODULESPACKAGE=$(expand_file "${CMD_MODULESPACKAGE}")
		if [[ -z "${MODULESPACKAGE}" || "${MODULESPACKAGE}" != *.tar* ]]
		then
			gen_die "--modulespackage value '${CMD_MODULESPACKAGE}' is invalid!"
		fi

		local modulespackage_dir=$(dirname "${MODULESPACKAGE}")
		if [ ! -d "${modulespackage_dir}" ]
		then
			mkdir -p "${modulespackage_dir}" \
				|| gen_die "Failed to create '${modulespackage_dir}'!"
		fi
	fi

	if [ -n "${KERNCACHE}" ]
	then
		KERNCACHE=$(expand_file "${CMD_KERNCACHE}")
		if [[ -z "${KERNCACHE}" || "${KERNCACHE}" != *.tar* ]]
		then
			gen_die "--kerncache value '${CMD_KERNCACHE}' is invalid!"
		fi

		local kerncache_dir=$(dirname "${KERNCACHE}")
		if [ ! -d "${kerncache_dir}" ]
		then
			mkdir -p "${kerncache_dir}" \
				|| gen_die "Failed to create '${kerncache_dir}'!"
		fi
	fi

	if ! isTrue "${BUILD_RAMDISK}"
	then
		INTEGRATED_INITRAMFS=0
	fi

	MICROCODE=${MICROCODE,,}
	case ${MICROCODE} in
		all|amd|intel) ;;
		y|yes|1|true|t) MICROCODE='all' ;;
		n|no|none|0|false|f) MICROCODE='' ;;
		*) gen_die "Invalid microcode '${MICROCODE}', --microcode=<type> requires one of: no, all, intel, amd" ;;
	esac

	if isTrue "${FIRMWARE}"
	then
		for ff in ${FIRMWARE_FILES}; do
			[[ ${ff} = /* ]] && gen_die "FIRMWARE_FILES should list paths relative to FIRMWARE_DIR, not absolute."
		done

		[[ "${FIRMWARE_FILES}" = *,* ]] && gen_die "FIRMWARE_FILES should be a space-separated list."
	fi
}
