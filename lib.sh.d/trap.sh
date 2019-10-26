#!/hint/bash

#
# Every time I get back to writing in bash, I end up writing a (new)
# library that does awful things with traps.
#

ltraps() {
	cat <<-"EOF"
	declare -a __traps;
	trap 'local __rc=$?; local __t; for __t in "${__traps[@]}"; do eval "$__t"; done; trap - RETURN; return "$__rc";' RETURN
	EOF
}

ltrap() {
	__traps+=("$1")
}

luntrap() {
	unset __traps[-1]
}
