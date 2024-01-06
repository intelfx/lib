#!/bin/bash

# log message prefixes by priority
declare -A _LIBSH_PREFIX
if [[ $JOURNAL_STREAM && ! -t 2 ]]; then
	_LIBSH_PREFIX=(
		[debug]='<7>'
		[info]='<6>'
		[notice]='<5>'
		[warning]='<4>'
		[error]='<3>'
		[xxx]='<0>'  # emerg
	)
fi

# log message priorities by type
declare -A _LIBSH_PRIO
_LIBSH_PRIO=(
	[dbg]=debug
	[log]=info
	[say]=info
	[trace]=notice
	[loud]=notice
	[warn]=warning
	[err]=error
	[xxx]=xxx
)

# manual implementation of %v and %V printf specifiers
# %v: outputs the value of the shell variable whose name is the ARGUMENT
# %V: outputs the definition (as in `declare -p`) of the shell variable
#     whose name is the ARGUMENT, without the `declare --` prefix
function _libsh_printf_var() {
	local var="$1" fmt="$2"
	shift 2
	if ! [[ $fmt == *%[Vv]* ]]; then
		printf -v "$var" -- "$fmt" "$@"
		return
	fi
	local args=( "$@" )
	local i c=0
	for (( i=0; i < ${#fmt} - 1; ++i )); do
		case "${fmt:i:2}" in
		%%) (( ++i )) ;;
		%v) args[c]="${!args[c]}"; (( ++c, ++i )) ;;
		%V) args[c]="$(declare -p "${args[c]}")"; args[c]="${args[c]#declare +(-+([^ ]) )}"; (( ++c, ++i )) ;;
		%?) (( ++c, ++i )) ;;
		esac
	done
	printf -v "$var" -- "${fmt//%[Vv]/%s}" "${args[@]}"

}

function _libsh_log() {
	local priority="$1" marker="$2" prefix="$3" text="$4"
	echo "${_LIBSH_PREFIX[$priority]}${marker:+$marker }${prefix:+$prefix: }$text" >&2
}
function _libsh_logf() {
	local priority="$1" marker="$2" prefix="$3" text
	shift 3
	_libsh_printf_var text "$@"
	echo "${_LIBSH_PREFIX[$priority]}${marker:+$marker }${prefix:+$prefix: }$text" >&2
}

function dbg() {
	if (( LIBSH_DEBUG )); then
		_libsh_log "${_LIBSH_PRIO[dbg]}" "DBG:" "$LIBSH_LOG_PREFIX" "$*"
	fi
}
function dbgf() {
	if (( LIBSH_DEBUG )); then
		_libsh_logf "${_LIBSH_PRIO[dbg]}" "DBG:" "$LIBSH_LOG_PREFIX" "$@"
	fi
}

function log() {
	_libsh_log "${_LIBSH_PRIO[log]}" "::" "$LIBSH_LOG_PREFIX" "$*"
}
function logf() {
	_libsh_logf "${_LIBSH_PRIO[log]}" "::" "$LIBSH_LOG_PREFIX" "$@"
}

function say() {
	_libsh_log "${_LIBSH_PRIO[say]}" "" "" "$*"
}
function sayf() {
	_libsh_logf "${_LIBSH_PRIO[say]}" "" "" "$@"
}

function warn() {
	_libsh_log "${_LIBSH_PRIO[warn]}" "W:" "$LIBSH_LOG_PREFIX" "$*"
}
function warnf() {
	_libsh_logf "${_LIBSH_PRIO[warn]}" "W:" "$LIBSH_LOG_PREFIX" "$@"
}

function warning() {
	warn "$@"
}
function warningf() {
	warnf "$@"
}

function err() {
	_libsh_log "${_LIBSH_PRIO[err]}" "E:" "$LIBSH_LOG_PREFIX" "$*"
}
function errf() {
	_libsh_logf "${_LIBSH_PRIO[err]}" "E:" "$LIBSH_LOG_PREFIX" "$@"
}

function die() {
	err "$@"
	exit 1
}
function dief() {
	errf "$@"
	exit 1
}

function xxx() {
	_libsh_log "${_LIBSH_PRIO[xxx]}" "XXX:" "$LIBSH_LOG_PREFIX" "$*"
}
function xxxf() {
	_libsh_logf "${_LIBSH_PRIO[xxx]}" "XXX:" "$LIBSH_LOG_PREFIX" "$@"
}

function XXX() {
	xxx "$@"
}
function XXXf() {
	xxxf "$@"
}

function trace() {
	_libsh_log "${_LIBSH_PRIO[trace]}" "->" "$LIBSH_LOG_PREFIX" "${*@Q}"
	"$@"
}

function dry_run() {
	_libsh_log "${_LIBSH_PRIO[trace]}" "->" "$LIBSH_LOG_PREFIX" "${*@Q}"
	if ! (( DRY_RUN )); then
		"$@"
	fi
}

function check() {
	local stmt="$1"
	shift
	if ! eval "$stmt"; then
		die "$*"
	fi
}

function check_e() {
	local expr="$1"
	shift
	if ! eval "[[ $expr ]]"; then
		die "$*"
	fi
}

function assert() {
	local stmt="$1"
	shift
	if ! eval "$stmt"; then
		die "assertion failed: $stmt ($(eval "echo $stmt"))${*+": $*"}"
	fi
}

function assert_e() {
	local expr="$1"
	shift
	if ! eval "[[ $expr ]]"; then
		die "assertion failed: $expr ($(eval "echo $expr"))${*+": $*"}"
	fi
}

function usage() {
	if (( $# )); then
		if [[ "$*" ]]; then
			_libsh_log "${_LIBSH_PRIO[err]}" "" "$LIBSH_LOG_PREFIX" "$*"
		fi
		echo >&2
	fi
	_usage >&2
	exit 1
}
function usagef() {
	_libsh_log "${_LIBSH_PRIO[err]}" "" "$LIBSH_LOG_PREFIX" "$(printf -- "$@")"
	echo >&2
	_usage >&2
	exit 1
}

function loud() {
	local prio="${_LIBSH_PRIO[loud]}"
	local args=( "$@" )
	local len=0
	local a
	for a in "${args[@]}"; do
		if (( "${#a}" > len )); then
			len="${#a}"
		fi
	done

	local header="$(repeat '=' "$(( 5 + len + 5 ))")"
	_libsh_log "$prio" "" "" "$header"
	for a in "${args[@]}"; do
		local pad_l="$(repeat ' ' "$(( (len - ${#a}    ) / 2 ))")"  # rounded down
		local pad_r="$(repeat ' ' "$(( (len - ${#a} + 1) / 2 ))")"  # rounded up
		_libsh_log "$prio" "" "" "==== ${pad_l}${a}${pad_r} ===="
	done
	_libsh_log "$prio" "" "" "$header"
}

libsh_export_log() {
	if [[ ${_LIBSH_HAS_LOG+set} ]]; then
		return
	fi
	export _LIBSH_HAS_LOG=1
	export -f \
		_libsh_printf_var \
		_libsh_log \
		_libsh_logf \
		dbg dbgf \
		log logf \
		say sayf \
		warn warnf \
		warning warningf \
		err errf \
		die dief \
		xxx xxxf \
		XXX XXXf \
		trace \
		dry_run \

		#check check_e \
		#assert assert_e \
}
