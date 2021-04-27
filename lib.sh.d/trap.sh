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

ltraps() {
	cat <<-"EOF"
	declare -a __traps;
	trap 'local __rc=$?; local __t; for __t in "${__traps[@]}"; do eval "$__t"; done; trap - RETURN; return "$__rc";' RETURN
	EOF
}

globaltraps() {
	cat <<-"EOF"
	declare -a __traps;
	trap '__rc=$?; __t=""; for __t in "${__traps[@]}"; do eval "$__t"; done; trap - EXIT; exit "$__rc";' EXIT
	EOF
}

ltrap() {
	__traps+=("$1")
}

luntrap() {
	unset __traps[-1]
}

lruntrap() {
	local __t="${__traps[-1]}"
	unset __traps=[-1]
	eval "$__t"
}
