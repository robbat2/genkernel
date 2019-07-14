#!/bin/bash
# $Id$

isTrue() {
	case "$1" in
		[Tt][Rr][Uu][Ee])
			return 0
		;;
		[Tt])
			return 0
		;;
		[Yy][Ee][Ss])
			return 0
		;;
		[Yy])
			return 0
		;;
		1)
			return 0
		;;
	esac
	return 1
}

set_color_vars() {
	if ! isTrue "${NOCOLOR}"
	then
		GOOD=$'\e[32;01m'
		WARN=$'\e[33;01m'
		BAD=$'\e[31;01m'
		NORMAL=$'\e[0m'
		BOLD=$'\e[0;01m'
		UNDER=$'\e[4m'
	else
		GOOD=''
		WARN=''
		BAD=''
		NORMAL=''
		BOLD=''
		UNDER=''
	fi
}
set_color_vars

dump_debugcache() {
	TODEBUGCACHE=no
	echo "${DEBUGCACHE}" >> "${LOGFILE}"
	DEBUGCACHE=
}

# print_info(loglevel, print [, newline [, prefixline [, forcefile ] ] ])
print_info() {
	local reset_x=0
	if [ -o xtrace ]
	then
		set +x
		reset_x=1
	fi

	local NEWLINE=1
	local FORCEFILE=1
	local PREFIXLINE=1
	local SCRPRINT=0
	local STR=''

	[[ ${#} -lt 2 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at least two arguments (${#} given)!"

	[[ ${#} -gt 5 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at most five arguments (${#} given)!"

	# IF 3 OR MORE ARGS, CHECK IF WE WANT A NEWLINE AFTER PRINT
	if [ ${#} -gt 2 ]
	then
		if isTrue "$3"
		then
			NEWLINE=1
		else
			NEWLINE=0
		fi
	fi

	# IF 4 OR MORE ARGS, CHECK IF WE WANT TO PREFIX WITH A *
	if [ ${#} -gt 3 ]
	then
		if isTrue "$4"
		then
			PREFIXLINE=1
		else
			PREFIXLINE=0
		fi
	fi

	# IF 5 OR MORE ARGS, CHECK IF WE WANT TO FORCE OUTPUT TO DEBUG
	# FILE EVEN IF IT DOESN'T MEET THE MINIMUM DEBUG REQS
	if [ ${#} -gt 4 ]
	then
		if isTrue "$5"
		then
			FORCEFILE=1
		else
			FORCEFILE=0
		fi
	fi

	# PRINT TO SCREEN ONLY IF PASSED LOGLEVEL IS HIGHER THAN
	# OR EQUAL TO SET LOG LEVEL
	if [[ ${1} -lt ${LOGLEVEL} || ${1} -eq ${LOGLEVEL} ]]
	then
		SCRPRINT=1
	fi

	# RETURN IF NOT OUTPUTTING ANYWHERE
	if [ ${SCRPRINT} -ne 1 -a ${FORCEFILE} -ne 1 ]
	then
		[ ${reset_x} -eq 1 ] && set -x

		return 0
	fi

	# STRUCTURE DATA TO BE OUTPUT TO SCREEN, AND OUTPUT IT
	if [ ${SCRPRINT} -eq 1 ]
	then
		if [ ${PREFIXLINE} -eq 1 ]
		then
			STR="${GOOD}*${NORMAL} ${2}"
		else
			STR="${2}"
		fi

		printf "%b" "${STR}"

		if [ ${NEWLINE} -ne 0 ]
		then
			echo
		fi
	fi

	# STRUCTURE DATA TO BE OUTPUT TO FILE, AND OUTPUT IT
	if [ ${SCRPRINT} -eq 1 -o ${FORCEFILE} -eq 1 ]
	then
		local STRR=${2//${WARN}/}
		STRR=${STRR//${BAD}/}
		STRR=${STRR//${BOLD}/}
		STRR=${STRR//${NORMAL}/}

		if [ ${PREFIXLINE} -eq 1 ]
		then
			STR="* ${STRR}"
		else
			STR="${STRR}"
		fi

		if isTrue "${TODEBUGCACHE}"
		then
			DEBUGCACHE="${DEBUGCACHE}${STR}"
		else
			printf "%b" "${STR}" >> "${LOGFILE}"
		fi

		if [ ${NEWLINE} -ne 0 ]
		then
			if isTrue "${TODEBUGCACHE}"
			then
				DEBUGCACHE="${DEBUGCACHE}"$'\n'
			else
				echo >> "${LOGFILE}"
			fi
		fi
	fi

	[ ${reset_x} -eq 1 ] && set -x

	return 0
}

print_error() {
	GOOD=${BAD} print_info "$@"
}

print_warning() {
	GOOD=${WARN} print_info "$@"
}

can_run_programs_compiled_by_genkernel() {
	local can_run_programs=no

	if ! isTrue "$(tc-is-cross-compiler)"
	then
		can_run_programs=yes
	else
		if [[ ${CBUILD} = x86_64* && ${ARCH} == "x86" ]]
		then
			can_run_programs=yes
		elif [[ ${CBUILD} = powerpc64* && ${ARCH} == "powerpc" ]]
		then
			can_run_programs=yes
		fi
	fi

	echo "${can_run_programs}"
}

is_valid_triplet() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local triplet=${1}
	local is_triplet=no

	if [[ "${triplet}" =~ ^[a-zA-Z0-9]{2,}-[a-zA-Z0-9]{2,}-[a-zA-Z0-9]{2,} ]]
	then
		is_triplet=yes
	fi

	echo "${is_triplet}"
}

# var_replace(var_name, var_value, string)
# $1 = variable name
# $2 = variable value
# $3 = string

var_replace() {
	[[ ${#} -ne 3 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly three arguments (${#} given)!"

	# Escape '\' and '.' in $2 to make it safe to use
	# in the later sed expression
	local SAFE_VAR
	SAFE_VAR=$(echo "${2}" | sed -e 's#\([/.]\)#\\\1#g')

	echo "${3}" | sed -e "s/%%${1}%%/${SAFE_VAR}/g" -
	if [ $? -ne 0 ]
	then
		gen_die "var_replace() failed: 1: '${1}'  2: '${2}'  3: '${3}'"
	fi
}

arch_replace() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	var_replace "ARCH" "${ARCH}" "${1}"
}

cache_replace() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	var_replace "CACHE" "${GK_V_CACHEDIR}" "${1}"
}

start_log() {
	if [ -f "${LOGFILE}" ]
	then
		(echo > "${LOGFILE}") 2>/dev/null || small_die "Genkernel: Could not write to '${LOGFILE}'."
	fi

	dump_debugcache
}

gen_die() {
	set +x

	dump_debugcache

	if [ "$#" -gt '0' ]
	then
		print_error 1 "ERROR: ${1}"
	fi

	print_error 1 "Please consult '${LOGFILE}' for more information and any"
	print_error 1 "errors that were reported above."
	print_error 1 ''
	print_error 1 "Report any genkernel bugs to bugs.gentoo.org and"
	print_error 1 "assign your bug to genkernel@gentoo.org. Please include"
	print_error 1 "as much information as you can in your bug report; attaching"
	print_error 1 "'${LOGFILE}' so that your issue can be dealt with effectively."
	print_error 1 ''
	print_error 1 "Please do ${BOLD}*not*${NORMAL} report ${BOLD}kernel${NORMAL} compilation failures as genkernel bugs!"
	print_error 1 ''

	# Cleanup temp dirs and caches if requested
	cleanup

	[[ -n "${GK_MASTER_PID}" && ${BASHPID} != ${GK_MASTER_PID} ]] && kill -s SIGTERM ${GK_MASTER_PID}
	exit 1
}

# @FUNCTION: get_indent
# @USAGE: <level>
# @DESCRIPTION:
# Returns the indent level in spaces.
#
# <level> Indentation level.
get_indent() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local _level=${1}
	local _indent=
	local _indentTemplate="        "
	local i=0

	while [[ ${i} -lt ${_level} ]]
	do
		_indent+=${_indentTemplate}
		i=$[$i+1]
	done

	echo "${_indent}"
}

is_boot_ro() {
	return $(awk '( $2 == "'${BOOTDIR}'" && $4 ~ /(^|,)ro(,|$)/){ I=1; exit }END{print !I }' /proc/mounts);
}

setup_cache_dir() {
	if [ ! -d "${GK_V_CACHEDIR}" ]
	then
		mkdir -p "${GK_V_CACHEDIR}" || gen_die "Failed to create '${GK_V_CACHEDIR}'!"
	fi

	if isTrue "${CLEAR_CACHEDIR}"
	then
		print_info 2 "Clearing cache dir contents from ${CACHE_DIR} ..."
		while read i
		do
			print_info 3 "$(get_indent 1)>> removing ${i}"
			rm "${i}"
		done < <(find "${CACHE_DIR}" -maxdepth 2 -type f -name '*.tar.*' -o -name '*.bz2' -o -name '*.xz')
	fi
}

cleanup() {
	if isTrue "${CLEANUP}"
	then
		if [ -n "${TEMP}" -a -d "${TEMP}" ]
		then
			rm -rf "${TEMP}"
		fi

		if isTrue "${POSTCLEAR}"
		then
			echo
			print_info 2 'Running final cache/tmp cleanup ...'
			print_info 3 "CACHE_DIR: ${CACHE_DIR}"
			CLEAR_CACHEDIR=yes setup_cache_dir
			echo
			print_info 3 "TMPDIR: ${TMPDIR}"
			clear_tmpdir
		fi
	else
		print_info 2 "--no-cleanup is set; Skipping cleanup ..."
		print_info 3 "TEMP: ${TEMP}"
		print_info 3 "CACHE_DIR: ${CACHE_DIR}"
		print_info 3 "TMPDIR: ${TMPDIR}"
	fi
}

clear_tmpdir() {
	if isTrue "${CMD_INSTALL}"
	then
		TMPDIR_CONTENTS=$(ls "${TMPDIR}")
		print_info 2 "Removing tmp dir contents"
		for i in ${TMPDIR_CONTENTS}
		do
			print_info 3 "$(get_indent 1)>> removing ${i}"
			rm -r "${TMPDIR}/${i}"
		done
	fi
}

# @FUNCTION: copy_image_with_preserve
# @USAGE: <symlink name> <source image> <dest image>
# @DESCRIPTION:
# Function to copy various kernel boot image products to the boot directory,
# preserve a generation of old images (just like the manual kernel build's
# "make install" does), and maintain the symlinks (if enabled).
#
# <symlink name> Symlink in the boot directory. Path not included.
#
# <source image> Fully qualified path name of the source image.
#
# <dest image>   Name of the destination image in the boot directory,
#                no path included.
copy_image_with_preserve() {
	[[ ${#} -ne 3 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly three arguments (${#} given)!"

	local symlinkName=${1}
	local newSrceImage=${2}
	local fullDestName=${3}

	local currDestImage
	local prevDestImage

	print_info 3 "Shall copy new ${symlinkName} image, " 0

	# Old product might be a different version.  If so, we need to read
	# the symlink to see what it's name is, if there are symlinks.
	cd "${KERNEL_OUTPUTDIR}" || gen_die "Failed to chdir to '${KERNEL_OUTPUTDIR}'!"
	if isTrue "${SYMLINK}"
	then
		print_info 3 "automatically managing symlinks and old images." 1 0
		if [ -e "${BOOTDIR}/${symlinkName}" ]
		then
			# JRG: Do I need a special case here for when the standard symlink
			# name is, in fact, not a symlink?
			currDestImage=$(readlink --no-newline "${BOOTDIR}/${symlinkName}")
			print_info 4 "Current ${symlinkName} symlink exists:"
			print_info 4 "  ${currDestImage}"
		else
			currDestImage="${fullDestName}"
			print_info 4 "Current ${symlinkName} symlink does NOT exist."
			print_info 4 "  Defaulted to: ${currDestImage}"
		fi

		if [ -e "${BOOTDIR}/${symlinkName}.old" ]
		then
			# JRG: Do I need a special case here for when the standard symlink
			# name is, in fact, not a symlink?
			prevDestImage=$(readlink --no-newline "${BOOTDIR}/${symlinkName}.old")
			print_info 4 "Old ${symlinkName} symlink exists:"
			print_info 4 "  ${prevDestImage}"
		else
			prevDestImage="${fullDestName}.old"
			print_info 4 "Old ${symlinkName} symlink does NOT exist."
			print_info 4 "  Defaulted to: ${prevDestImage}"
		fi
	else
		print_info 3 "symlinks not being handled by genkernel." 1 0
		currDestImage="${fullDestName}"
		prevDestImage="${fullDestName}.old"
	fi

	if [ -e "${BOOTDIR}/${currDestImage}" ]
	then
		local currDestImageExists=yes
		print_info 4 "Actual image file '${BOOTDIR}/${currDestImage}' does exist."
	else
		local currDestImageExists=no
		print_info 4 "Actual image file '${BOOTDIR}/${currDestImage}' does NOT exist."
	fi

	if [ -e "${BOOTDIR}/${prevDestImage}" ]
	then
		local prevDestImageExists=yes
		print_info 4 "Actual old image file '${BOOTDIR}/${prevDestImage}' does exist."
	else
		local prevDestImageExists=no
		print_info 4 "Actual old image file '${BOOTDIR}/${prevDestImage}' does NOT exist."
	fi

	# When symlinks are not being managed by genkernel, old symlinks might
	# still be useful.  Leave 'em alone unless managed.
	if isTrue "${SYMLINK}"
	then
		local -a old_symlinks=()
		old_symlinks+=( "${BOOTDIR}/${symlinkName}" )
		old_symlinks+=( "${BOOTDIR}/${symlinkName}.old" )

		local old_symlink=
		for old_symlink in "${old_symlinks[@]}"
		do
			if [ -L "${old_symlink}" ]
			then
				print_info 4 "Deleting old symlink '${old_symlink}' ..."
				rm "${old_symlink}" || gen_die "Failed to delete '${old_symlink}'!"
			else
				print_info 4 "Old symlink '${old_symlink}' does NOT exist; Skipping ..."
			fi
		done
		unset old_symlinks old_symlink
	fi

	# We only erase the .old image when it is the exact same version as the
	# current and new images.  Different version .old (and current) images are
	# left behind.  This is consistent with how "make install" of the manual
	# kernel build works.
	if [ "${currDestImage}" == "${fullDestName}" ]
	then
		# Case for new and currrent of the same base version.
		print_info 4 "Same base version (${currDestImage})."

		if isTrue "${currDestImageExists}"
		then
			if [ -e "${BOOTDIR}/${currDestImage}.old" ]
			then
				print_info 3 "Deleting old identical ${symlinkName} version '${BOOTDIR}/${currDestImage}.old' ..."
				rm "${BOOTDIR}/${currDestImage}.old" \
					|| gen_die "Failed to delete '${BOOTDIR}/${currDestImage}.old'!"
			fi

			print_info 3 "Moving '${BOOTDIR}/${currDestImage}' to '${BOOTDIR}/${currDestImage}.old' ..."
			mv "${BOOTDIR}/${currDestImage}" "${BOOTDIR}/${currDestImage}.old" \
				|| gen_die "Could not rename the old ${symlinkName} image!"

			prevDestImage="${currDestImage}.old"
			prevDestImageExists=yes
		fi
	else
		# Case for new / current not of the same base version.
		print_info 4 "Different base version."
		prevDestImage="${currDestImage}"
		currDestImage="${fullDestName}"
	fi

	print_info 3 "Copying '${newSrceImage}' to '${BOOTDIR}/${currDestImage}' ..."
	cp -aL "${newSrceImage}" "${BOOTDIR}/${currDestImage}" \
		|| gen_die "Failed to copy '${newSrceImage}' to '${BOOTDIR}/${currDestImage}'!"

	if isTrue "${SYMLINK}"
	then
		print_info 3 "Creating '${symlinkName}' -> '${currDestImage}' symlink ..."
		ln -s "${currDestImage}" "${BOOTDIR}/${symlinkName}" \
			|| gen_die "Failed to create '${symlinkName}' -> '${currDestImage}' symlink!"

		if isTrue "${prevDestImageExists}"
		then
			print_info 3 "Creating '${symlinkName}.old' -> '${prevDestImage}' symlink ..."
			ln -s "${prevDestImage}" "${BOOTDIR}/${symlinkName}.old" \
				|| "Failed to create '${symlinkName}.old' -> '${prevDestImage}' symlink!"
		fi
	fi
}

# @FUNCTION: debug_breakpoint
# @USAGE: [<NAME>]
# @DESCRIPTION:
# Internal helper function which can be used during development to act like
# a breakpoint. I.e. will stop execution and show some variables.
#
# <NAME> Give breakpoint a name
debug_breakpoint() {
	set +x
	local name=${1}
	[ -n "${name}" ] && name=" '${name}'"

	echo "Debug breakpoint${name} reached"
	echo "TEMP: ${TEMP}"
	[[ -n "${WORKDIR}" ]] && echo "WORKDIR: ${WORKDIR}"
	[[ -n "${S}" ]] && echo "S: ${S}"
	[[ -n "${D}" ]] && echo "D: ${D}"

	if [ -n "${GK_WORKER_MASTER_PID}" ]
	then
		[[ ${BASHPID:-$(__bashpid)} == ${GK_WORKER_MASTER_PID} ]] || kill -s SIGTERM ${GK_WORKER_MASTER_PID}
	else
		[[ ${BASHPID:-$(__bashpid)} == ${GK_MASTER_PID} ]] || kill -s SIGTERM ${GK_MASTER_PID}
	fi

	exit 99
}

get_chost_libdir() {
	local cc=$(tc-getCC)
	local libdir=$(dirname "$(realpath "$(${cc} -print-file-name=libnss_files.so)")")

	if [[ -z "${libdir}" ]]
	then
		gen_die "$(get_useful_function_stack "${FUNCNAME}")Unable to determine CHOST's libdir!"
	fi

	echo "${libdir}"
}

_get_gkpkg_var_value() {
	[[ ${#} -ne 2 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly two arguments (${#} given)!"

	local VARNAME=${1}
	case "${VARNAME}" in
		BINPKG|DEPS|PN|PV|SRCDIR|SRCTAR)
			;;
		*)
			# Let's make variable support explicit
			gen_die "$(get_useful_function_stack)Variable '${VARNAME}' is not supported by ${FUNCNAME}()!"
			;;
	esac

	local PN=${2}
	[[ -z "${PN}" ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): No package specified!"

	[[ -z "${GKPKG_LOOKUP_TABLE[${PN}]}" ]] \
		&& gen_die "$(get_useful_function_stack)Internal error: Package '${PN}' is unknown! Was package added to software.sh?"

	local REQUESTED_VARNAME="${GKPKG_LOOKUP_TABLE[${PN}]}_${VARNAME}"
	local REQUESTED_VALUE="${!REQUESTED_VARNAME}"
	[[ ${VARNAME} != 'DEPS' && -z "${REQUESTED_VALUE}" ]] \
		&& gen_die "$(get_useful_function_stack)Internal error: Variable '${REQUESTED_VARNAME}' is not set!"

	echo "${REQUESTED_VALUE}"
}

get_gkpkg_binpkg() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local PN=${1}

	_get_gkpkg_var_value BINPKG ${PN}
}

get_gkpkg_deps() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local PN=${1}
	[[ -z "${PN}" ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): No package specified!"

	_get_gkpkg_var_value DEPS ${PN}
}

get_gkpkg_srcdir() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local PN=${1}
	[[ -z "${PN}" ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): No package specified!"

	_get_gkpkg_var_value SRCDIR ${PN}
}

get_gkpkg_srctar() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local PN=${1}
	[[ -z "${PN}" ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): No package specified!"

	_get_gkpkg_var_value SRCTAR ${PN}
}

get_gkpkg_version() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one argument (${#} given)!"

	local PN=${1}
	[[ -z "${PN}" ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): No package specified!"

	_get_gkpkg_var_value PV ${PN}
}

# @FUNCTION: get_tar_cmd
# @USAGE: <ARCHIVE>
# @DESCRIPTION:
# Returns tar command which can make use of pbzip2, pxz or pigz when
# possible.
#
# <ARCHIVE> Archive file
get_tar_cmd() {
	[[ ${#} -ne 1 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly one arguments (${#} given)!"

	local archive_file=${1}

	local -a tar_cmd
	tar_cmd+=( 'tar -c' )

	local pcmd
	if [[ "${archive_file}" == *.tar.bz2 ]]
	then
		pcmd=$(which pbzip2 2>/dev/null)
	elif [[ "${archive_file}" == *.tar.xz ]]
	then
		pcmd=$(which pxz 2>/dev/null)
	elif [[ "${archive_file}" == *.tar.gz ]]
	then
		pcmd=$(which pigz 2>/dev/null)
	fi

	if [ -n "${pcmd}" ]
	then
		tar_cmd+=( "-I ${pcmd}" )
	else
		tar_cmd+=( '-a' )
	fi

	tar_cmd+=( '-pf' )
	tar_cmd+=( "${archive_file}" )

	echo "${tar_cmd[@]}"
}

get_tc_vars() {
	local -a tc_vars=()
	tc_vars+=( AR )
	tc_vars+=( AS )
	tc_vars+=( CC )
	tc_vars+=( CPP )
	tc_vars+=( CXX )
	tc_vars+=( LD )
	tc_vars+=( STRIP )
	tc_vars+=( NM )
	tc_vars+=( RANLIB )
	tc_vars+=( OBJCOPY )
	tc_vars+=( PKG_CONFIG )

	echo "${tc_vars[@]}"
}

get_useful_function_stack() {
	local end_function=${1:-${FUNCNAME}}
	local n_functions=${#FUNCNAME[@]}
	local last_function=$(( n_functions - 1 )) # -1 because arrays are starting with 0
	local first_function=0

	local stack_str=
	local last_function_name=
	while [ ${last_function} -gt ${first_function} ]
	do
		last_function_name=${FUNCNAME[last_function]}
		last_function=$(( last_function - 1 ))

		case "${last_function_name}" in
			__module_main|main)
				# filter main function
				continue
				;;
			${end_function})
				# this the end
				break
				;;
			*)
				;;
		esac

		stack_str+="${last_function_name}(): "
	done

	echo "${stack_str}"
}

_tc-getPROG() {
	local tuple=${!1:-""}
	local v var vars=$2
	local prog=( $3 )

	var=${vars%% *}
	for v in ${vars} ; do
		if [[ -n ${!v} ]] ; then
			export ${var}="${!v}"
			echo "${!v}"
			return 0
		fi
	done

	# We allow user to specify different CC/AS/MAKE/LD... values for
	# building kernel and utilities. To avoid having multiple tc-get*
	# functions, we default to utilities and allow switching via
	# TC_PROG_TYPE variable.
	local type=UTILS
	if [ -n "${TC_PROG_TYPE}" -a "${TC_PROG_TYPE}" = "KERNEL" ]
	then
		type=KERNEL
	fi

	local prog_default_varname="DEFAULT_${type}_${var}"
	local prog_override_varname="${type}_${var}"

	if [[ -n "${!prog_default_varname}" ]] \
		&& [[ "${!prog_override_varname}" != "${!prog_default_varname}" ]]
	then
		# User wants to run specific program
		prog[0]=${!prog_override_varname}
	elif isTrue "$(tc-is-cross-compiler)"
	then
		# Let's try to handle multilib:
		# We will mimic profile's make.defaults.

		local multilib_cflags multilib_ldflags
		local cpu_cbuild=${CBUILD%%-*}
		local cpu_chost=${CHOST%%-*}

		case "${cpu_cbuild}" in
			powerpc64*)
				if [[ "${cpu_chost}" == "powerpc" ]]
				then
					tuple=${tuple/${cpu_chost}/${cpu_cbuild}}
					multilib_cflags="-m32"
					multilib_ldflags="-m elf32ppc"
				fi
				;;
			x86_64*)
				if [[ "${cpu_chost}" == "i686" ]]
				then
					# changing tuple so that we don't call pure gcc
					tuple=${tuple/${cpu_chost}/${cpu_cbuild}}
					multilib_cflags="-m32"
					multilib_ldflags="-m elf_i386"
				fi
				;;
		esac

		case "${var}" in
			CC)
				[[ -n "${multilib_cflags}" ]] && prog+=( "${multilib_cflags}" )
				;;
			LD)
				[[ -n "${multilib_ldflags}" ]] &&  prog+=( "${multilib_ldflags}" )
				;;
		esac
	fi

	local search=
	[[ -n ${tuple} ]] && search=$(type -p ${tuple}-${prog[0]})
	[[ -n ${search} ]] && prog[0]=${search##*/}

	export ${var}="${prog[*]}"
	echo "${!var}"
}

tc-export() {
	local var
	for var in "$@"
	do
		[[ $(type -t "tc-get${var}") != "function" ]] && gen_die "tc-export: invalid export variable '${var}'"
		"tc-get${var}" > /dev/null
	done
}

tc-getAR() {
	tc-getPROG AR ar "$@"
}

tc-getAS() {
	tc-getPROG AR ar "$@"
}

tc-getBUILD_CC() {
	tc-getBUILD_PROG CC gcc "$@"
}

tc-getCC() {
	tc-getPROG CC gcc "$@"
}

tc-getCPP() {
	local cc=$(tc-getCC)
	tc-getPROG CPP "${cc} -E" "$@"
}

tc-getCXX() {
	tc-getPROG CXX g++ "$@"
}

tc-getLD() {
	tc-getPROG LD ld "$@"
}

tc-getNM() {
	tc-getPROG NM nm "$@"
}

tc-getOBJCOPY() {
	tc-getPROG OBJCOPY objcopy "$@"
}

tc-getOBJDUMP() {
	tc-getPROG OBJDUMP objdump "$@"
}

tc-getBUILD_PROG() {
	local vars="BUILD_$1 $1_FOR_BUILD HOST$1"
	# respect host vars if not cross-compiling
	# https://bugs.gentoo.org/630282
	isTrue "$(tc-is-cross-compiler)" || vars+=" $1"
	_tc-getPROG CBUILD "${vars}" "${@:2}"
}

tc-getPROG() {
	_tc-getPROG CHOST "$@"
}

tc-getRANLIB() {
	tc-getPROG RANLIB ranlib
}

tc-getSTRIP() {
	tc-getPROG STRIP strip
}

tc-getSTRIP() {
	tc-getPROG STRIP strip "$@";
}

tc-is-cross-compiler() {
	local wants_cross_compile=no
	if [[ "${CBUILD:-${CHOST}}" != "${CHOST}" ]]
	then
		wants_cross_compile=yes
	fi

	echo ${wants_cross_compile}
}

trap_cleanup() {
	# Call exit code of 1 for failure
	cleanup
	exit 1
}

# @FUNCTION: gkbuild
# @USAGE: <PKG> <PKG_VERSION> <PKG_SRCDIR> <PKG_SRCTAR> <PKG_BINCACHE> [<PKG_DEPS>]
# @DESCRIPTION:
# Builds a package for genkernel's initramfs, with cross-compile support.
#
# Genkernel's initramfs uses various utilities like Busybox, LVM,
# MDADM, cryptsetup or others. gkbuild() will run an ebuild-like script
# to build such utilities in sandbox environment with cross-compile
# support (requires existing cross-compile toolchain!).
#
# For developers:
# Any package you want to build using gkbuild() must be correctly added to
# ${GK_SHARE}/software.sh file, check_distfiles() and determine_real_args()
# function.
#
# For users:
# Any package you want to add must have set same (initialized!) variables
# like you can see in ${GK_SHARE}/software.sh.
#
# <PKG> Name of the package (as used in ${GK_SHARE}/patches).
#
# <PKG_VERSION> Version of the package.
#
# <PKG_SRCDIR> Source directory when unpacked.
#
# <PKG_SRCTAR> Source file. Only archives supported by `tar -xaf` are
# supported.
#
# <PKG_BINCACHE> File where genkernel will store the package's image.
#
# <PKG_DEPS> Single word string of required package's PKG_BINCACHE.
gkbuild() {
	[[ ${#} -lt 5 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at least five arguments (${#} given)!"
	[[ ${#} -gt 7 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at most six arguments (${#} given)!"

	if ! hash sandbox &>/dev/null
	then
		gen_die "Sandbox not found. Please install sys-apps/sandbox!"
	fi

	local PKG=${1}
	local VERSION=${2}
	local SRCDIR=${3}
	local SRCTAR=${4}
	local BINPKG=${5}

	if [[ "$#" -eq '6' ]]
	then
		local DEPS=${6}
	else
		local DEPS=""
	fi

	if [ -z "${PKG}" ]
	then
		gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): PKG is not set!"
	elif [ -z "${VERSION}" ]
	then
		gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): VERSION is not set!"
	elif [ -z "${SRCDIR}" ]
	then
		gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): SRCDIR is not set!"
	elif [ -z "${SRCTAR}" ]
	then
		gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): SRCTAR is not set!"
	elif [ -z "${BINPKG}" ]
	then
		gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): BINPKG is not set!"
	fi

	local -a envvars=(
		GK_SHARE="${GK_SHARE}"
		LOGLEVEL="${LOGLEVEL}"
		LOGFILE="${LOGFILE}"
		NOCOLOR="${NOCOLOR}"
		TEMP="${TEMP}"
		SANDBOX_WRITE="${LOGFILE}:${TEMP}"
	)

	envvars+=(
		GKPKG_PN="${PKG}"
		GKPKG_PV="${VERSION}"
		GKPKG_SRCDIR="${SRCDIR}"
		GKPKG_SRCTAR="${SRCTAR}"
		GKPKG_BINPKG="${BINPKG}"
		GKPKG_DEPS="${DEPS}"
	)

	envvars+=(
		CFLAGS="${CMD_UTILS_CFLAGS}"
		CXXFLAGS="${CMD_UTILS_CFLAGS}"
		CBUILD="${CBUILD}"
		CHOST="${CHOST}"
		AR="$(tc-getAR)"
		AS="$(tc-getAS)"
		CC="$(tc-getCC)"
		CPP="$(tc-getCPP)"
		CXX="$(tc-getCXX)"
		LD="$(tc-getLD)"
		NM="$(tc-getNM)"
		MAKE="${CMD_UTILS_MAKE}"
		OBJCOPY="$(tc-getOBJCOPY)"
		OBJDUMP="$(tc-getOBJDUMP)"
		RANLIB="$(tc-getRANLIB)"
		STRIP="$(tc-getSTRIP)"
	)

	if [ ${NICE} -ne 0 ]
	then
		NICEOPTS="nice -n${NICE} "
	else
		NICEOPTS=""
	fi
	envvars+=( NICEOPTS="${NICEOPTS}" )

	envvars+=( MAKEOPTS="${MAKEOPTS}" )

	# set up gkbuild signal handler
	local error_msg="gen_worker.sh aborted: Failed to compile ${PKG}-${VERSION}!"
	trap "gen_die \"${error_msg}\"" SIGABRT SIGHUP SIGQUIT SIGINT SIGTERM

	env -i \
		"${envvars[@]}" \
		sandbox "${GK_SHARE}"/gen_worker.sh build 2>&1

	local RET=$?

	# remove gkbuild signal handler
	set_default_gk_trap

	[ ${RET} -ne 0 ] && gen_die "$(get_useful_function_stack)Failed to create binpkg of ${PKG}-${VERSION}!"
}

# @FUNCTION: unpack
# @USAGE: <ARCHIVE> <DEST>
# @DESCRIPTION:
# Unpack archive file to dest dir using sandbox.
#
# <ARCHIVE> Archive to unpack.
#
# <DEST> Folder to unpack to.
unpack() {
	[[ ${#} -ne 2 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly two arguments (${#} given)!"

	if ! hash sandbox &>/dev/null
	then
		gen_die "Sandbox not found. Please install sys-apps/sandbox!"
	fi

	local unpack_file=${1}
	local unpack_dir=${2}

	local -a envvars=(
		GK_SHARE="${GK_SHARE}"
		LOGLEVEL="${LOGLEVEL}"
		LOGFILE="${LOGFILE}"
		NOCOLOR="${NOCOLOR}"
		TEMP="${TEMP}"
		SANDBOX_WRITE="${LOGFILE}:${TEMP}"
	)

	envvars+=(
		UNPACK_FILE="${unpack_file}"
		UNPACK_DIR="${unpack_dir}"
	)

	# set up unpack signal handler
	local error_msg_detail="Failed to unpack '${unpack_file}' to '${unpack_dir}'!"
	local error_msg="gen_worker.sh aborted: ${error_msg_detail}"
	trap "gen_die \"${error_msg}\"" SIGABRT SIGHUP SIGQUIT SIGINT SIGTERM

	env -i \
		"${envvars[@]}" \
		sandbox "${GK_SHARE}"/gen_worker.sh unpack 2>&1

	local RET=$?

	# restore default trap
	set_default_gk_trap

	[ ${RET} -ne 0 ] && gen_die "$(get_useful_function_stack)${error_msg_detail}"
}

set_default_gk_trap() {
	trap trap_cleanup SIGABRT SIGHUP SIGQUIT SIGINT SIGTERM
}

#
# Helper function to allow command line arguments to override configuration
# file specified values and to apply defaults.
#
# Arguments:
#     $1  Argument type:
#           1  Switch type arguments (e.g., --color / --no-color).
#           2  Value type arguments (e.g., --debuglevel=5).
#     $2  Config file variable name.
#     $3  Command line variable name.
#     $4  Default.  If both the config file variable and the command line
#         option are not present, then the config file variable is set to
#         this default value.  Optional.
#
# The order of priority of these three sources (highest first) is:
#     Command line, which overrides
#     Config file (/etc/genkernel.conf), which overrides
#     Default.
#
# Arguments $2 and $3 are variable *names*, not *values*.  This function uses
# various forms of indirection to access the values.
#
# For switch type arguments, all forms of "True" are converted to a numeric 1
# and all forms of "False" (everything else, really) to a numeric 0.
#
# - JRG
#
set_config_with_override() {
	local VarType=$1
	local CfgVar=$2
	local OverrideVar=$3
	local Default=$4
	local Result

	#
	# Syntax check the function arguments.
	#
	case "$VarType" in
		BOOL|STRING)
			;;
		*)
			gen_die "Illegal variable type \"$VarType\" passed to set_config_with_override()."
			;;
	esac

	if [ -n "${!OverrideVar}" ]
	then
		Result=${!OverrideVar}
		if [ -n "${!CfgVar}" ]
		then
			print_info 5 "  $CfgVar overridden on command line to \"$Result\"."
		else
			print_info 5 "  $CfgVar set on command line to \"$Result\"."
		fi
	else
		if [ -n "${!CfgVar}" ]
		then
			Result=${!CfgVar}
			# we need to set the CMD_* according to configfile...
			eval ${OverrideVar}=\"${Result}\"
			print_info 5 "  $CfgVar set in config file to \"${Result}\"."
		else
			if [ -n "$Default" ]
			then
				Result=${Default}
				# set OverrideVar to Result, otherwise CMD_* may not be initialized...
				eval ${OverrideVar}=\"${Result}\"
				print_info 5 "  $CfgVar defaulted to \"${Result}\"."
			else
				print_info 5 "  $CfgVar not set."
			fi
		fi
	fi

	if [ "${VarType}" = BOOL ]
	then
		if isTrue "${Result}"
		then
			Result=1
		else
			Result=0
		fi
	fi

	eval ${CfgVar}=\"${Result}\"
}

rootfs_type_is() {
	local fstype=$1

	# It is possible that the awk will return MULTIPLE lines, depending on your
	# initramfs setup (one of the entries will be 'rootfs').
	if awk '($2=="/"){print $3}' /proc/mounts | grep -sq --line-regexp "$fstype" ;
	then
		echo yes
	else
		echo no
	fi
}

check_distfiles() {
	for i in \
		$BUSYBOX_SRCTAR \
		$DMRAID_SRCTAR \
		$FUSE_SRCTAR \
		$GPG_SRCTAR \
		$ISCSI_SRCTAR \
		$ISCSI_ISNS_SRCTAR \
		$LIBAIO_SRCTAR \
		$LVM_SRCTAR \
		$MDADM_SRCTAR \
		$MULTIPATH_SRCTAR \
		$UNIONFS_FUSE_SRCTAR
	do
		if [ ! -f "${i}" ]
		then
			small_die "Could not find source tarball ${i}. Please refetch."
		fi
	done
}

expand_file() {
	if [[ "${#}" -lt 1 ]]
	then
		# Nothing to do for us
		echo ''
		return
	fi

	local file="${1}"
	local expanded_file=

	expanded_file=$(python -c "import os; print(os.path.expanduser('${file}'))" 2>/dev/null)
	if [ -z "${expanded_file}" ]
	then
		# if Python failed for some reason, just reset
		expanded_file=${file}
	fi

	expanded_file=$(realpath -q "${expanded_file}" 2>/dev/null)

	echo "${expanded_file}"
}

find_kernel_binary() {
	local kernel_binary=$*
	local curdir=$(pwd)

	cd "${KERNEL_OUTPUTDIR}" || gen_die "Failed to chdir to '${TDIR}'!"
	for i in ${kernel_binary}
	do
		if [ -e "${i}" ]
		then
			tmp_kernel_binary=$i
			break
		fi
	done

	cd "${curdir}" || gen_die "Failed to chdir to '${TDIR}'!"
	echo "${tmp_kernel_binary}"
}

kconfig_get_opt() {
	[[ ${#} -ne 2 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes exactly two arguments (${#} given)!"

	local kconfig="${1}"
	local optname="${2}"
	sed -n "${kconfig}" \
		-e "/^#\? \?${optname}[ =].*/{ s/.*${optname}[ =]//g; s/is not set\| +//g; p; q }"
}

KCONFIG_MODIFIED_MARKER="${TEMP}/.kconfig_modified"

kconfig_set_opt() {
	[[ ${#} -lt 3 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at least three arguments (${#} given)!"
	[[ ${#} -gt 4 ]] \
		&& gen_die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at most four arguments (${#} given)!"

	local kconfig="${1}"
	local optname="${2}"
	local optval="${3}"
	local indentlevel=${4:-2}

	local curropt=$(grep -E "^#? ?${optname}[ =].*$" "${kconfig}")
	if [[ -z "${curropt}" ]]
	then
		print_info 2 "$(get_indent ${indentlevel}) - Adding option '${optname}' with value '${optval}' to '${kconfig}'..."
		echo "${optname}=${optval}" >> "${kconfig}" \
			|| gen_die "Failed to add '${optname}=${optval}' to '$kconfig'"

		[ ! -f "${TEMP}/.kconfig_modified" ] && touch "${TEMP}/.kconfig_modified"
	elif [[ "${curropt}" != "*#*" && "${curropt#*=}" == "${optval}" ]]
	then
		print_info 2 "$(get_indent ${indentlevel}) - Option '${optname}=${optval}' already set in '${kconfig}'; Skipping ..."
	else
		print_info 2 "$(get_indent ${indentlevel}) - Setting option '${optname}' to '${optval}' in '${kconfig}'..."
		sed -i "${kconfig}" \
			-e "s/^#\? \?${optname}[ =].*/${optname}=${optval}/g" \
			|| gen_die "Failed to set '${optname}=${optval}' in '$kconfig'"

		[ ! -f "${KCONFIG_MODIFIED_MARKER}" ] && touch "${KCONFIG_MODIFIED_MARKER}"
	fi
}

unset GK_DEFAULT_IFS
declare -r GK_DEFAULT_IFS="${IFS}"
