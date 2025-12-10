#!/hint/bash

#
# Every time I get back to writing in bash, I end up writing a (new)
# library that does awful things with traps.
#
# Usage:
#  function foo() {
#  	eval "$(ltraps)"
#
#  	ltrap "echo foo"
#  	ltrap "echo bar"
#  	ltrap "rm -rf /"
#  	luntrap
#  }
#
#  eval "$(globaltraps)"
#  ltrap "echo foo"
#  ltrap "echo bar"
#  ltrap "rm -rf /"
#  luntrap
#
# NOTE: if `set -e` is used, globaltraps must be active for _any_ traps
#       to run on error. Otherwise the shell will exit without running
#       any traps because errors are not converted into returns.
#       If globaltraps is active, it will run all currently active scopes
#       before exiting.
#
# Unfortunately, EXIT traps do not have access to the local scope anymore
# (which seems to be a bug in the first place, however convenient it was),
# so we cannot "unwind" organically by accessing $__traps and unsetting
# it repeatedly until it does not exist anymore.
#
# Instead, do things the ugly way: maintain two stacks simultaneously and
# chop off the top of the global stack on RETURN.
#

# WTF moment
# ---
# If a variable at the current local scope is unset, it will remain so
# (appearing as unset) until it is reset in that scope or until the function
# returns. <...> If the unset acts on a variable at a previous scope, any
# instance of a variable with that name that had been shadowed will become
# visible <...>.
# ---
# We don't use this anymore, however, preserve this function for posterity:
# this function creates an artificial scope such that any unset that is
# performed on behalf of the caller always acts on "a previous scope".
# (See commit message for details)
__dynamic_unset() {
	unset "$@"
}

ltraps() {
	# guard against repeated setup
	if [[ ${__traps_flag+set} ]] && (( __traps_flag == ${#FUNCNAME[@]}-1 )); then
		return
	fi
	# enable global traps to handle EXIT
	globaltraps

	cat <<-"EOF"
	declare -a __traps;
	declare __traps_flag=${#FUNCNAME[@]};
	declare __gtraps_mark=${#__gtraps[@]};
	trap '{ local __t; } &>/dev/null; for __t in "${__traps[@]}"; do eval "$__t" || true; done; { __gtraps=("${__gtraps[@]:${#__gtraps[@]}-$__gtraps_mark}"); trap - RETURN; } &>/dev/null' RETURN
	EOF
}

globaltraps() {
	# guard against repeated setup
	if [[ ${__gtraps+set} ]]; then
		return
	fi
	# we add a fake local scope for other code to work consistently,
	# which we cannot do if there is already a non-fake one
	if [[ ${__traps+set} ]]; then
		die "globaltraps: localtraps activated before globaltraps"
	fi

	cat <<-"EOF"
	declare -g __traps_flag=0;
	declare -g __gtraps_mark=0;
	declare -g -a __traps;
	declare -g -a __gtraps;
	trap '{ __rc=$?; __t=""; } &>/dev/null; for __t in "${__gtraps[@]}"; do eval "$__t" || true; done; { trap - EXIT; exit "$__rc"; } &>/dev/null' EXIT
	EOF
}

ltrap() {
	# prepend
	__traps=( "$1" "${__traps[@]}" )
	# add the same trap to the "shadow" stack for EXIT (see above)
	__gtraps=( "$1" "${__gtraps[@]}" )
}

luntrap() {
	# remove first item
	__traps=( "${__traps[@]:1}" )
	__gtraps=( "${__gtraps[@]:1}" )
}

lruntrap() {
	local __t="${__traps[0]}"
	luntrap
	eval "$__t" || true
}

# returns a value (<= 0) that encodes the current depth of the trap stack
ltrap_mark() {
	printf "%s" "-${#__traps[@]}"
}

# $1: either how many traps to run (>0) or a mark (<=0)
#     NOTE: `$1 == 0` is a mark, meaning "run all traps"
ltrap_unwind() {
	local __nr="$1"
	if (( __nr <= 0 )); then
		(( __nr += ${#__traps[@]} )) ||:
	fi

	dbg "lruntraps: \$1=$1, #traps=${#__traps[@]}"
	if (( __nr == 0 )); then
		return
	elif (( __nr < 0 )); then
		# rolling back to a mark above the stack is not an error
		warn "lruntraps: mark above stack: \$1=$1, #traps=${#__traps[@]}"
		return
	elif (( __nr > ${#__traps[@]} )); then
		die "lruntraps: invalid argument: \$1=$1, #traps=${#__traps[@]}"
	fi

	local __t
	for __t in "${__traps[@]:0:$__nr}"; do
		eval "$__t" || true
	done
	__traps=( "${__traps[@]:$__nr}" )
	__gtraps=( "${__gtraps[@]:$__nr}" )
}

libsh_export_ltraps() {
	if [[ ${_LIBSH_HAS_TRAP+set} ]]; then
		return
	fi
	export _LIBSH_HAS_TRAP=1
	export -f \
		__dynamic_unset \
		globaltraps \
		ltraps \
		ltrap \
		luntrap \
		lruntrap \

	# not exporting mark/unwind because they use logging
}
libsh_export_trap() { libsh_export_ltraps; }
libsh_export_ltrap() { libsh_export_ltraps; }
