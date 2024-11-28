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
	declare -A args_spec
	local i c=0 cnt

	# iterate over conversion specifiers
	# remember which are %v/%V and count them
	for (( i=0; i < ${#fmt} - 1; ++i )); do
		case "${fmt:i:2}" in
		%%) (( ++i )) ;;
		%v) args_spec[$c]='%v'; (( ++c, ++i )) ;;
		%V) args_spec[$c]='%V'; (( ++c, ++i )) ;;
		%?) (( ++c, ++i )) ;;
		esac
	done
	cnt="$c"

	# iterate over arguments (there might be more arguments than specifiers)
	# mangle those corresponding to %v/%V
	for (( c=0; c < ${#args[@]}; ++c )); do
		case "${args_spec[$((c % cnt))]}" in
		%v) args[c]="${!args[c]}"; ;;
		%V) args[c]="$(declare -p "${args[c]}")"; args[c]="${args[c]#declare +(-+([^ ]) )}"; ;;
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

# XXX: this is exported to facilitate trace-like functions in external scripts
function _libsh_trace() {
	if [[ $LIBSH_TRACE_NO_PREFIX ]]; then
		local LIBSH_LOG_PREFIX=""
	fi
	_libsh_log "${_LIBSH_PRIO[trace]}" "->" "$LIBSH_LOG_PREFIX" "$@"
}
function trace() {
	if [[ $LIBSH_TRACE_NO_PREFIX ]]; then
		local LIBSH_LOG_PREFIX=""
	fi
	_libsh_log "${_LIBSH_PRIO[trace]}" "->" "$LIBSH_LOG_PREFIX" "${*@Q}"
	"$@"
}

function Trace() {
	local priority="${_LIBSH_PRIO[trace]}"
	local prefix="${_LIBSH_PREFIX[$priority]}"
	local rc=0
	local PS4=""
	if [[ $prefix ]]; then
		PS4+="\\[$prefix\\]"
	fi
	PS4+="-> "
	if [[ ! $LIBSH_TRACE_NO_PREFIX ]] && [[ $LIBSH_LOG_PREFIX ]]; then
		PS4+="$LIBSH_LOG_PREFIX: "
	fi

	local _in_trace=1
	local _in_trace_suspend=0
	local _trace_old_set _trace_new_set
	# `var=$(set +o)` creates a subshell and clears `set -e`, use read instead
	# `read` returns nonzero on EOF, which will always happen due to `-d ''`
	set +o | IFS= read -r -d '' _trace_old_set || true
	trap '{ rc=$?; eval "$_trace_old_set"; } &>/dev/null; trap - ERR; return $rc' ERR
	set -x
	{ set +o | IFS= read -r -d '' _trace_new_set || true; } &>/dev/null
	"$@"
	{ rc=$?; eval "$_trace_old_set"; } &>/dev/null; trap - ERR; return $rc
}
function Trace_suspend() {
	if ! [[ ${_in_trace+set} ]]; then
		return
	fi
	if ! (( _in_trace_suspend++ )); then
		eval "$_trace_old_set"
	fi
}
function Trace_resume() {
	if ! [[ ${_in_trace+set} ]]; then
		return
	fi
	if ! (( _in_trace_suspend > 0 )); then
		return
	fi
	if ! (( --_in_trace_suspend )); then
		eval "$_trace_new_set"
	fi
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
	declare -g _LIBSH_LAST_LOUD

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

	_LIBSH_LAST_LOUD="$(( 5 + len + 5 ))"
}

function loudsep() {
	declare -g _LIBSH_LAST_LOUD

	local prio="${_LIBSH_PRIO[loud]}"
	local header="$(repeat '=' "$_LIBSH_LAST_LOUD")"
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
		_libsh_trace \
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
		Trace \
		dry_run \

		#check check_e \
		#assert assert_e \
}
