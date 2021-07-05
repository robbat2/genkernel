#!/bin/bash
# $Id$

gen_dep_list() {
	if isTrue "${ALLRAMDISKMODULES}"
	then
		strip_mod_paths $(find "${KERNEL_MODULES_PREFIX%/}/lib/modules/${KV}" -name "*${KEXT}") | sort
	else
		rm -f "${TEMP}/moddeps" >/dev/null

		local group_modules
		for group_modules in ${!MODULES_*} GK_INITRAMFS_ADDITIONAL_KMODULES
		do
			gen_deps ${!group_modules}
		done

		# Only list each module once
		if [ -f "${TEMP}/moddeps" ]
		then
			cat "${TEMP}/moddeps" | sort | uniq
		fi
	fi
}

gen_deps() {
	local modlist
	local deps

	local x
	for x in ${*}
	do
		echo ${x} >> "${TEMP}/moddeps"
		modlist=$(modules_dep_list ${x})
		if [ "${modlist}" != "" -a "${modlist}" != " " ]
		then
			deps=$(strip_mod_paths ${modlist})
		else
			deps=""
		fi

		local y
		for y in ${deps}
		do
			echo ${y} >> "${TEMP}/moddeps"
		done
	done
}

modules_dep_list() {
	KEXT=$(modules_kext)
	if [ -f "${KERNEL_MODULES_PREFIX%/}/lib/modules/${KV}/modules.dep" ]
	then
		grep -F -- "/${1}${KEXT}:" "${KERNEL_MODULES_PREFIX%/}/lib/modules/${KV}/modules.dep" | cut -d\:  -f2
	fi
}

modules_kext() {
	local KEXT='.ko'

	declare -A module_compression_algorithms=()
	module_compression_algorithms[NONE]='.ko'
	module_compression_algorithms[GZIP]='.ko.gz'
	module_compression_algorithms[XZ]='.ko.xz'
	module_compression_algorithms[ZSTD]='.ko.zst'

	local module_compression_algorithm
	for module_compression_algorithm in "${!module_compression_algorithms[@]}"
	do
		print_info 5 "Checking if module compression algorithm '${module_compression_algorithm}' is being used ..."

		local koption="CONFIG_MODULE_COMPRESS_${module_compression_algorithm}"
		local value_koption=$(kconfig_get_opt "${KERNEL_OUTPUTDIR}/.config" "${koption}")
		if [[ "${value_koption}" != "y" ]]
		then
			print_info 5 "Cannot use '${module_compression_algorithm}' algorithm for module compression, kernel option '${koption}' is not set!"
			continue
		fi

		print_info 5 "Will use '${module_compression_algorithm}' algorithm for kernel module compression!"
		KEXT="${module_compression_algorithms[${module_compression_algorithm}]}"
		break
	done
	unset module_compression_algorithms module_compression_algorithm koption value_koption

	echo ${KEXT}
}

# Pass module deps list
strip_mod_paths() {
	local x
	local ret
	local myret

	for x in ${*}
	do
		ret=$(basename ${x} | cut -d. -f1)
		myret="${myret} ${ret}"
	done

	echo "${myret}"
}
