#!/bin/bash

# log message prefixes by priority
declare -A _LIBSH_PREFIX
if [[ $JOURNAL_STREAM ]]; then
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

function _libsh_log() {
	local priority="$1" marker="$2" prefix="$3" text="$4"
	echo "${_LIBSH_PREFIX[$priority]}${marker:+$marker }${prefix:+$prefix: }$text" >&2
}

function dbg() {
	if (( LIBSH_DEBUG )); then
		_libsh_log "${_LIBSH_PRIO[dbg]}" "DBG:" "$LIBSH_LOG_PREFIX" "$*"
	fi
}

function log() {
	_libsh_log "${_LIBSH_PRIO[log]}" "::" "$LIBSH_LOG_PREFIX" "$*"
}

function say() {
	_libsh_log "${_LIBSH_PRIO[say]}" "" "" "$*"
}

function warn() {
	_libsh_log "${_LIBSH_PRIO[warn]}" "W:" "$LIBSH_LOG_PREFIX" "$*"
}

function warning() {
	warn "$@"
}

function err() {
	_libsh_log "${_LIBSH_PRIO[err]}" "E:" "$LIBSH_LOG_PREFIX" "$*"
}

function die() {
	err "$@"
	exit 1
}

function xxx() {
	_libsh_log "${_LIBSH_PRIO[xxx]}" "XXX:" "$LIBSH_LOG_PREFIX" "$*"
}

function XXX() {
	xxx "$@"
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
