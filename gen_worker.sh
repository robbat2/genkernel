#!/bin/bash

export GK_WORKER_MASTER_PID=${BASHPID}
trap 'exit 1' SIGTERM

# Prevent aliases from causing portage to act inappropriately.
# Make sure it's before everything so we don't mess aliases that follow.
unalias -a

# Make sure this isn't exported to scripts we execute.
unset BASH_COMPAT

source "${GK_SHARE}"/gen_funcs.sh || exit 1

# Unset some variables that break things.
unset GZIP BZIP BZIP2 CDPATH GREP_OPTIONS GREP_COLOR GLOBIGNORE

die() {
	set +x
	if [ "$#" -gt '0' ]
	then
		print_error 1 "ERROR: ${1}"
	fi

	[[ -n "${GK_WORKER_MASTER_PID}" && ${BASHPID} == ${GK_WORKER_MASTER_PID} ]] || kill -s SIGTERM ${GK_WORKER_MASTER_PID}
	exit 1
}

# Make sure genkernel's gen_die() won't be used -- make it an alias of
# this script's die function.
gen_die() {
	die "$@"
}

# @FUNCTION: gkexec
# @USAGE: <command> [<pipestatus-to-check>]
# @DESCRIPTION:
# Executes command with support for genkernel's logging.
# Will die when command will exit with nonzero exit status.
#
# Genkernel has its own logfile and loglevel handling
# with things like color/nocolor support.
# To support this, we cannot just execute commands. Depending
# on loglevel for example, we maybe have to use pipes.
# To avoid writing complex statements each time, gkexec
# wrapper was created.
#
# <command> Command to execute.
#
# <pipestatus-to-check> By default, the first command's
# exit status will be checked. When executing multiple
# commands with pipes, this argument controls which
# command's exit status will be checked to decide if
# command has been successfully executed.
gkexec() {
	if [ ${#} -gt 2 ]
	then
		# guard against ${array[@]}, first argument must be seen as a single word (${array[*]})
		die "$(get_useful_function_stack "${FUNCNAME}")Invalid usage of ${FUNCNAME}(): Function takes at most three arguments (${#} given)!"
	fi

	local -a command=( "${1}" )
	local pipes=${2:-0}

	print_info 3 "COMMAND: ${command[@]}" 1 0 1

	command+=( "$(catch_output_and_failures "Command '${command[@]}' failed!" ${pipes})" )
	eval "${command[@]}"
}

# Prevent recursion.
unset -f cleanup gkbuild unpack

if [[ -s "${SANDBOX_LOG}" ]]
then
	print_warning 3 "Stale sandbox log '${SANDBOX_LOG}' detected, removing ..."

	# We use SANDBOX_LOG to check for sandbox violations,
	# so we ensure that there can't be a stale log to
	# interfere with our logic.
	x=
	if [[ -n ${SANDBOX_ON} ]]
	then
		x=${SANDBOX_ON}
		export SANDBOX_ON=0
	fi

	rm -f "${SANDBOX_LOG}" \
		|| die "Failed to remove stale sandbox log: '${SANDBOX_LOG}'!"

	if [[ -n ${x} ]]
	then
		export SANDBOX_ON=${x}
	fi

	unset x
fi

__sb_append_var() {
	local _v=$1 ; shift
	local var="SANDBOX_${_v}"
	[[ -z $1 || -n $2 ]] && die "Usage: add$(LC_ALL=C tr "[:upper:]" "[:lower:]" <<< "${_v}") <colon-delimited list of paths>"
	export ${var}="${!var:+${!var}:}$1"
}

# addread() { __sb_append_var ${0#add} "$@" ; }
addread()    { __sb_append_var READ    "$@" ; }
addwrite()   { __sb_append_var WRITE   "$@" ; }
adddeny()    { __sb_append_var DENY    "$@" ; }
addpredict() { __sb_append_var PREDICT "$@" ; }

catch_output_and_failures() {
	local error_msg=${1:-"Command failed!"}
	local pipes=${2:-0}
	local output_processor=

	if [[ ${LOGLEVEL} -ge 4 ]]
	then
		output_processor="2>&1 | tee -a \"${LOGFILE}\"; [[ \${PIPESTATUS[${pipes}]} -ne 0 ]] && die \"${error_msg}\" || true"
	else
		output_processor=">> \"${LOGFILE}\" 2>&1 || die \"${error_msg}\""
	fi

	echo ${output_processor}
}

# the sandbox is ENABLED by default
export SANDBOX_ON=1

#if no perms are specified, dirs/files will have decent defaults
#(not secretive, but not stupid)
umask 022

if [[ "${#}" -lt 1 ]]
then
	die 'No module specified!'
fi

case "${1}" in
	build)
		MODULE="${GK_SHARE}/worker_modules/gkbuild.sh"
		;;
	dropbear)
		MODULE="${GK_SHARE}/worker_modules/dropbear.sh"
		;;
	unpack)
		MODULE="${GK_SHARE}/worker_modules/unpack.sh"
		;;
	*)
		die "Unknown module '${1}' specified!"
		;;
esac

source "${MODULE}" || die "Failed to source '${MODULE}'!"
__module_main
exit $?
