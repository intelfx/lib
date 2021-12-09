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

# dirname
dn() {
	local dirname="${1%/*}"
	case "$dirname" in
	"$1") echo . ;;  # $1 contains no slashes
	"")   echo / ;;  # $1 contains a single slash in the starting position
	*)    echo "$dirname" ;;
	esac
}

scriptdir() {
	echo "$(dn "$(realpath -qe "${BASH_SOURCE[1]}")")"
}

inplace() {
	eval "$(ltraps)"
	_inplace_cleanup() {
		if [[ -e $out ]]; then
			rm -f "$out"
		fi
	}
	ltrap _inplace_cleanup
	local in="${@: -1}"
	local out="$(mktemp)"
	set -- "${@:1:$#}"

	"$@" <"$in" >"$out"
	cat "$out" >"$in"
}

inplace_rename() {
	eval "$(ltraps)"
	_inplace_cleanup() {
		if [[ -e $out ]]; then
			rm -f "$out"
		fi
	}
	ltrap _inplace_cleanup
	local in="${@: -1}"
	local out="$(mktemp -p "$(dn "$in")" "${in##*/}.XXXXXXXXXX")"
	set -- "${@:0:$#}"

	"$@" <"$in" >"$out"
	mv "$out" "$in"
}

print_array() {
	if (( $# )); then
		printf "%s\n" "$@"
	fi
}

sort_array() {
	local name="$1"
	declare -n array="$name"
	shift 1

	if ! (( "${#array[@]}" )); then
		return
	fi

	readarray -t -d '' "$name" < <(printf '%s\0' "${array[@]}" | sort -z "$@")
}

makeset() {
	local name="$1"
	local value="$2"
	declare -n map="$name"
	shift 2

	local key
	for key in "$@"; do
		map["$key"]="$value"
	done
}

readset() {
	local args=( "${@:1:$#-2}" )
	local name="${@:($#-1):1}"
	local value="${@:($#):1}"

	declare -a array
	readarray "${args[@]}" array
	make_map "$name" "$value" "${array[@]}"
}

var_copy() {
	local src="$1" dest="$2"
	local p="$(declare -p "$src")"
	p="${p/ $src/ $dest}"
	echo "$p"
}

all_parents() {
	local d
	for d; do
		while [[ $d && $d != '.' && $d != '/' ]]; do
			echo "$d"
			d="${d%/*}"
		done
	done
}

max() {
	if ! (( $# )); then return; fi
	local max="$1" arg
	shift
	for arg; do
		(( max = arg>max ? arg : max )) || true
	done

	echo "$max"
}

maybe_find() {
	local has_paths=0

	#
	# very simple partial argument parser for find(1), utilizing the fact
	# that only a few options to `find` may appear before paths
	#

	local skip=0
	for arg; do
		if (( skip )); then (( skip-- )); continue; fi
		case "$arg" in
		-H|-L|-P|-O?*|-D?*)  # -O, -D with arg (-O1, -Dfoobar)
			continue ;;
		-O|-D)  # -O, -D with next arg (-O 1, -D foobar)
			skip=1; continue ;;
		-*)
			break ;;
		*)
			has_paths=1 ;;
		esac
	done
	if ! (( has_paths )); then return; fi
	find "$@"
}
