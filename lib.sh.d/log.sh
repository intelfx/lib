#!/hint/bash

# set explicitly for shellcheck sake
shopt -s lastpipe
shopt -s extglob

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
	if [[ $text == *$'\n'* ]]; then
		# If message text contains embedded newlines, indent each subsequent line
		# to the length of the prefix string.
		local _prefix="${_LIBSH_PREFIX[$priority]}${marker:+$marker }${prefix:+$prefix: }"
		local _prefix_len="${#_prefix}"
		printf -v _indent '%*s' "$_prefix_len" ''
		text="${text//$'\n'/$'\n'"$_indent"}"
		echo "${_prefix}${text}" >&2
		return
	fi
	echo "${_LIBSH_PREFIX[$priority]}${marker:+$marker }${prefix:+$prefix: }$text" >&2
}
function _libsh_logf() {
	local priority="$1" marker="$2" prefix="$3" text line
	shift 3
	_libsh_printf_var text "$@"

	# if a `logf` family function is used to print several sets of args,
	# e.g. `logf "%s\n" foo bar baz`, log each line separately.
	if [[ $text == *$'\n'* ]]; then
		# `<<<$text` appends a newline of its own, so chop the existing one.
		readarray -t text <<<"${text%$'\n'}"
	fi

	for line in "${text[@]}"; do
		echo "${_LIBSH_PREFIX[$priority]}${marker:+$marker }${prefix:+$prefix: }$line" >&2
	done
}

function dbg() {
	{ local -; set +x; } &>/dev/null
	if (( LIBSH_DEBUG )); then
		_libsh_log "${_LIBSH_PRIO[dbg]}" "DBG:" "$LIBSH_LOG_PREFIX" "$*"
	fi
}
function dbgf() {
	{ local -; set +x; } &>/dev/null
	if (( LIBSH_DEBUG )); then
		_libsh_logf "${_LIBSH_PRIO[dbg]}" "DBG:" "$LIBSH_LOG_PREFIX" "$@"
	fi
}

function log() {
	{ local -; set +x; } &>/dev/null
	_libsh_log "${_LIBSH_PRIO[log]}" "::" "$LIBSH_LOG_PREFIX" "$*"
}
function logf() {
	{ local -; set +x; } &>/dev/null
	_libsh_logf "${_LIBSH_PRIO[log]}" "::" "$LIBSH_LOG_PREFIX" "$@"
}

function say() {
	{ local -; set +x; } &>/dev/null
	_libsh_log "${_LIBSH_PRIO[say]}" "" "" "$*"
}
function sayf() {
	{ local -; set +x; } &>/dev/null
	_libsh_logf "${_LIBSH_PRIO[say]}" "" "" "$@"
}

function warn() {
	{ local -; set +x; } &>/dev/null
	_libsh_log "${_LIBSH_PRIO[warn]}" "W:" "$LIBSH_LOG_PREFIX" "$*"
}
function warnf() {
	{ local -; set +x; } &>/dev/null
	_libsh_logf "${_LIBSH_PRIO[warn]}" "W:" "$LIBSH_LOG_PREFIX" "$@"
}

function warning() {
	{ local -; set +x; } &>/dev/null
	warn "$@"
}
function warningf() {
	{ local -; set +x; } &>/dev/null
	warnf "$@"
}

function err() {
	{ local -; set +x; } &>/dev/null
	_libsh_log "${_LIBSH_PRIO[err]}" "E:" "$LIBSH_LOG_PREFIX" "$*"
}
function errf() {
	{ local -; set +x; } &>/dev/null
	_libsh_logf "${_LIBSH_PRIO[err]}" "E:" "$LIBSH_LOG_PREFIX" "$@"
}

function die() {
	{ local -; set +x; } &>/dev/null
	err "$@"
	exit 1
}
function dief() {
	{ local -; set +x; } &>/dev/null
	errf "$@"
	exit 1
}

function xxx() {
	{ local -; set +x; } &>/dev/null
	_libsh_log "${_LIBSH_PRIO[xxx]}" "XXX:" "$LIBSH_LOG_PREFIX" "$*"
}
function xxxf() {
	{ local -; set +x; } &>/dev/null
	_libsh_logf "${_LIBSH_PRIO[xxx]}" "XXX:" "$LIBSH_LOG_PREFIX" "$@"
}

function XXX() {
	{ local -; set +x; } &>/dev/null
	xxx "$@"
}
function XXXf() {
	{ local -; set +x; } &>/dev/null
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
	{ local -; set +x; } &>/dev/null
	if [[ $LIBSH_TRACE_NO_PREFIX ]]; then
		local LIBSH_LOG_PREFIX=""
	fi
	_libsh_log "${_LIBSH_PRIO[trace]}" "->" "$LIBSH_LOG_PREFIX" "${*@Q}"
	"$@"
}

# Trace(): log the commands being executed, recursively, using Bash's xtrace (set -x).
# Reentrancy is supported. Trace_{suspend,resume}() temporarily disable and reenable xtrace.
function Trace() {
	{ local -; set +x; } &>/dev/null

	# Create a new scope for the suspend counter even if recursively invoked
	# (to match the new scope we create for xtrace)
	local _in_trace_suspend=0

	# All of this is skipped when recursively invoked
	if ! [[ ${_in_trace+set} ]]; then
		local _in_trace=1

		local priority="${_LIBSH_PRIO[trace]}"
		local prefix="${_LIBSH_PREFIX[$priority]}"
		local ps4=""
		if [[ $prefix ]]; then
			ps4+="\\[$prefix\\]"
		fi
		ps4+="+  "
		if ! [[ $LIBSH_TRACE_NO_PREFIX ]]; then
			# expanded under `shopt -s promptvars` (default)
			ps4+='${LIBSH_LOG_PREFIX:+"$LIBSH_LOG_PREFIX: "}'
		fi
		local PS4="$ps4"
	fi

	set -x
	"$@"
}
function Trace_suspend() {
	# we cannot use `local -; set +x` here because we need to modify
	# shell options in the parent scope.
	#
	# if _you_ can, though, just use `{ local -; set +x; } &>/dev/null`
	# instead of using Trace_{suspend,resume}().
	{

	if ! [[ ${_in_trace+set} ]]; then
		return
	fi
	if ! (( _in_trace_suspend++ )); then
		set +x
	fi

	} &>/dev/null
}
function Trace_resume() {
	# we cannot use `local -; set +x` here because we need to modify
	# shell options in the parent scope
	{

	if ! [[ ${_in_trace+set} ]]; then
		return
	fi
	if ! (( _in_trace_suspend > 0 )); then
		return
	fi
	if ! (( --_in_trace_suspend )); then
		set -x
	fi

	} &>/dev/null
}

# dry_run(): log the command being executed (as in trace()), unless --quiet is set,
# and execute the command, unless $DRY_RUN is non-zero.
function dry_run() {
	# dry_run() is awkward. We need to suspend xtracing temporarily like
	# any other logging function, but we also need to _resume_ xtracing
	# before actually executing the command (_if_ we end up executing it).
	{ local -; local _status="$-"; set +x; } &>/dev/null
	if [[ $1 == "-q" || $1 == "--quiet" ]]; then
		shift
	else
		_libsh_log "${_LIBSH_PRIO[trace]}" "->" "$LIBSH_LOG_PREFIX" "${*@Q}"
	fi
	if ! (( DRY_RUN )); then
		{ if [[ $_status == *x* ]]; then set -x; fi; } &>/dev/null
		"$@"
	fi
}

function check() {
	{ local -; set +x; } &>/dev/null
	local stmt="$1"
	shift
	if ! eval "$stmt"; then
		die "$*"
	fi
}

function check_e() {
	{ local -; set +x; } &>/dev/null
	local expr="$1"
	shift
	if ! eval "[[ $expr ]]"; then
		die "$*"
	fi
}

function assert() {
	{ local -; set +x; } &>/dev/null
	local stmt="$1"
	shift
	if ! eval "$stmt"; then
		die "assertion failed: $stmt ($(eval "echo $stmt"))${*+": $*"}"
	fi
}

function assert_e() {
	{ local -; set +x; } &>/dev/null
	local expr="$1"
	shift
	if ! eval "[[ $expr ]]"; then
		die "assertion failed: $expr ($(eval "echo $expr"))${*+": $*"}"
	fi
}

function usage() {
	{ local -; set +x; } &>/dev/null
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
	{ local -; set +x; } &>/dev/null
	_libsh_log "${_LIBSH_PRIO[err]}" "" "$LIBSH_LOG_PREFIX" "$(printf -- "$@")"
	echo >&2
	_usage >&2
	exit 1
}

function loud() {
	{ local -; set +x; } &>/dev/null
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
	{ local -; set +x; } &>/dev/null
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
