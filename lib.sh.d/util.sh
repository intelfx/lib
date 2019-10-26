#!/bin/bash

regex_unwrap() {
	local arg="$1"
	local regex="$2"

	if [[ $arg =~ ^$regex$ ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	else
		err "regex_unwrap: string '$arg' does not fully match regex '$regex'"
		return 1
	fi
}

regex_chk() {
	local arg="$1"
	local regex="$2"
	shift 2

	if [[ $arg =~ ^$regex$ ]]; then
		local i=1
		declare -n groupvar
		for groupvar; do
			groupvar=${BASH_REMATCH[i++]}
		done
		return 0
	else
		err "regex_chk: string '$arg' does not fully match regex '$regex'"
		return 1
	fi
}

join() {
	local sep="$1" arg0="$2"
	shift 2
	echo "$arg0${@/#/$sep}"
}

split_into() {
	declare -n out="$1"
	local IFS="$2" in="$3"
	read -ra out <<< "$in"
}

inplace() {
	eval "$(ltraps)"
	_inplace_cleanup() {
		if [[ -e $out ]]; then
			rm -f "$out"
		fi
	}
	ltrap _inplace_cleanup
	local in="$1" out="$(mktemp)"
	shift 1

	"$@" <"$in" >"$out"
	cat "$out" >"$in"
}
