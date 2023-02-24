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

ltraps() {
	cat <<-"EOF"
	declare -a __traps;
	trap 'local __t; for __t in "${__traps[@]}"; do eval "$__t" || true; done; trap - RETURN' RETURN
	EOF
}

globaltraps() {
	cat <<-"EOF"
	declare -a __traps;
	trap '__rc=$?; __t=""; while [[ ${__traps+set} ]]; do for __t in "${__traps[@]}"; do eval "$__t" || true; done; unset __traps; done; trap - EXIT; exit "$__rc";' EXIT
	EOF
}

ltrap() {
	# prepend
	__traps=( "$1" "${__traps[@]}" )
}

luntrap() {
	# remove first item
	__traps=( "${traps[@]:1}" )
}

lruntrap() {
	local __t="${__traps[0]}"
	__traps=( "${__traps[@]:1}" )
	eval "$__t" || true
}

# returns a value (<= 0) that encodes the current depth of the trap stack
ltrap_mark() {
	printf "%s" "-${#__traps[@]}"
}

# $1: either how many traps to run (>0) or a mark (<=0)
#     NOTE: `$1 == 0`` is a mark, meaning "run all traps"
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
}