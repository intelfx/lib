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

join1() {
	local IFS="$1"
	shift 1
	echo "$*"
}

join() {
	case "$#" in
	1) return ;;
	2) echo "$2"; return ;;
	esac

	local sep="$1" arg0="$2" IFS=''
	shift 2
	echo "$arg0${*/#/$sep}"
}

split_into() {
	declare -n out="$1"
	local IFS="$2" in="$3"
	read -ra out <<< "$in"
}

in_array() {
	local needle="$1"; shift
	local item
	for item in "$@"; do
		if [[ $item == $needle ]]; then return 0; fi
	done
	return 1
}

array_filter() {
	declare -n in="$1" out="$2"
	local arg
	out=()
	for arg in "${in[@]}"; do
		if [[ $arg == $3 ]]; then
			out+=( "$arg" )
		fi
	done
}

array_filter_out() {
	declare -n in="$1" out="$2"
	local arg
	out=()
	for arg in "${in[@]}"; do
		if [[ $arg != $3 ]]; then
			out+=( "$arg" )
		fi
	done
}

# "dirname split"
# $(dn_part $foo)$(bn $foo) == $foo
dn_slash() {
	local dn="${1%/*}"
	case "$dn" in
	"$1") echo   ;;  # $1 contains no slashes
	"")   echo / ;;  # $1 contains a single slash in the starting position
	"${1%/}") dn_part "${1%%/}" ;;  # $1 ends with slashes, strip them and retry
	*)    echo "$dn/" ;;
	esac
}

# dirname
dn() {
	local dirname="${1%/*}"
	case "$dirname" in
	"$1") echo . ;;  # $1 contains no slashes
	"")   echo / ;;  # $1 contains a single slash in the starting position
	"${1%/}") dn "${1%%/}" ;;  # $1 ends with slashes, strip them and retry
	*)    echo "$dirname" ;;
	esac
}

# basename
bn() {
	local basename="${1##*/}"
	case "$basename" in
	"$1") echo "$1" ;;  # $1 contains no slashes
	"${1%/}") echo / ;;  # $1 is a single slash (or contains no slashes)
	"")   bn "${1%%/}" ;;  # $1 ends with slashes, strip them and retry
	*)    echo "$basename" ;;
	esac
}

# extract N-th last component of pathnames
extract() {
	local n="$1"
	shift
	local i arg
	for arg; do
		for (( i=1; i<n; ++i )); do
			arg="$(dn "$arg")"
		done
		bn "$arg"
	done
}

joinpath() {
	local r arg
	for arg; do
		if [[ ! $r || $r == . ]]; then
			r="$arg"
		elif [[ $arg == /* ]]; then
			r="$arg"
		else
			r="$r/$arg"
		fi
	done
	echo "$r"
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
printa() { print_array "$@"; }

print_array0() {
	if (( $# )); then
		printf "%s\0" "$@"
	fi
}
printa0() { print_array0 "$@"; }

printfa() {
	# ad-hoc parser to compute how many format arguments we have
	local argn=1
	while (( argn <= $# )); do
		case "${@:argn:1}" in
		-v) (( argn += 2 )) ;;
		-v*) (( argn += 1 )) ;;
		--) (( argn += 1 )) ;&
		*) break ;;
		esac
	done
	# print if we have >0 format arguments, OR if FORMAT has no format specifiers
	# i.e. $(printfa "%s\n") == "", but $(printfa "foo\n") == "foo\n"
	local fmt="${@:argn:1}"
	if (( $# > argn )) || [[ "${fmt//%%}" != *%* ]]; then
		printf "$@"
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
	makeset "$name" "$value" "${array[@]}"
}

readarray_append() {
	declare -n target="${@: -1}"
	readarray -O "${#target[@]}" "$@"
}

var_copy() {
	local src="$1" dest="$2"
	local p="$(declare -p "$src")"
	p="${p/ $src/ $dest}"
	echo "$p"
}

# It is not possible to pass an array via `awk -v ...`.
# Work around this by generating a snippet for inclusion via `awk -i`.
#
# Intended usage: awk -i <(awk_make_array name elements...)
awk_make_array() {
	local name="$1"
	local -a values=( "${@:2}" )

	(( ${#values[@]} )) || return 0

	printf "BEGIN {\n"
	local i
	for (( i=0; i < ${#values[@]}; ++i )); do
		printf "\t%s[%d]=\"%s\"\n" "$name" "$i" "${values[$i]}"
	done
	printf "}\n"
}

# In the same vein, generate a snippet representing an array as a set
# (i. e. representing elements as keys of an awk (associative) array).
#
# Intended usage: awk -i <(awk_make_set name elements...)
awk_make_set() {
	local name="$1"
	local -a values=( "${@:2}" )

	(( ${#values[@]} )) || return 0

	printf "BEGIN {\n"
	local v
	for v in "${values[@]}"; do
		printf "\t%s[\"%s\"]=1\n" "$name" "$v"
	done
	printf "}\n"
}

set_difference_f() {
	grep -Fvxf "$2" "$1" ||:
}

set_intersection_f() {
	grep -Fxf "$2" "$1" ||:
}

set_union_f() {
	sort -u "$@" ||:
}

set_difference_a() {
	declare -n src1="$1" src2="$2" dest="$3"

	{ grep -Fvxf \
		<(print_array "${src2[@]}") \
		<(print_array "${src1[@]}") \
	||:; } | readarray -t dest
}

set_intersection_a() {
	declare -n src1="$1" src2="$2" dest="$3"

	{ grep -Fxf \
		<(print_array "${src1[@]}") \
		<(print_array "${src2[@]}") \
	||:; } | readarray -t dest
}

set_difference_A() {
	declare -n src1="$1" src2="$2" dest="$3"
	local k tmp=()

	{ grep -Fvxf \
		<(print_array "${!src2[@]}") \
		<(print_array "${!src1[@]}") \
	||:; } | readarray -t tmp
	for k in "${tmp[@]}"; do
		dest["$k"]=1
	done
}

set_intersection_A() {
	declare -n src1="$1" src2="$2" dest="$3"

	{ grep -Fxf \
		<(print_array "${src1[@]}") \
		<(print_array "${src2[@]}") \
	||:; } | readarray -t dest
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

repeat() {
	local in="$1" rep="$2"
	if (( rep > 0 )); then
		local out="$(printf "%*s" "$rep")"
		if [[ "$in" != " " ]]; then
			out="${out// /$in}"
		fi
		echo "$out"
	fi
}

pad() {
	local target="$1" arg="$2"
	local len="${#arg}"
	if (( len >= target )); then
		echo "$arg"
	else
		echo "$arg$(repeat ' ' $(( target-len )))"
	fi
}

stderr_is_stdout() {
	if [[ /proc/self/fd/1 -ef /proc/self/fd/2 ]]; then
		# Linux and /proc exists, and stdout == stderr
		return 0
	elif [[ -e /proc/self/fd/1 && -e /proc/self/fd/2 ]]; then
		# Linux and /proc exists, but stdout != stderr
		return 1
	elif [[ /dev/stdout -ef /dev/stderr ]]; then
		# try /dev/stdout and /dev/stderr
		# on Linux, those will be symlinks to procfs (maybe it's mounted elsewhere)
		return 0
	elif [[ -t 1 && -t 2 ]]; then
		# heuristic: if both are terminal, chances are it's the same terminal
		return 0
	else
		# otherwise assume stdout != stderr
		return 1
	fi
}

cat_config() {
	sed -r 's/[[:space:]]*(#.*)?$//g; /^$/d' "$@"
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

findctl_init() {
	declare -n find_args="$1_ARGS"; declare -g -a find_args
	declare -n find_targets="$1_TARGETS"; declare -g -a find_targets
	declare -n find_pre_args="$1_PRE_ARGS"; declare -g -a find_pre_args
	declare -n find_exclusions="$1_EXCLUSIONS"; declare -g -a find_exclusions
	declare -n find_inclusions="$1_INCLUSIONS"; declare -g -a find_inclusions
	shift

	find_args=( find "$@" )
	find_targets=()
	find_pre_args=()
	find_exclusions=()
	find_inclusions=()
}

findctl_add_targets() {
	declare -n find_targets="$1_TARGETS"; declare -g -a find_targets
	shift

	find_targets+=( "$@" )
}

findctl_add_pre_args() {
	declare -n find_pre_args="$1_PRE_ARGS"; declare -g -a find_pre_args
	shift

	find_pre_args+=( "$@" )
}

findctl_add_exclusions() {
	declare -n find_exclusions="$1_EXCLUSIONS"; declare -g -a find_exclusions
	shift

	find_exclusions+=( "$@" )
}

findctl_add_inclusions() {
	declare -n find_inclusions="$1_INCLUSIONS"; declare -g -a find_inclusions
	shift

	find_inclusions+=( "$@" )
}

findctl_run() {
	{ Trace_suspend; } &>/dev/null
	declare -n find_args="$1_ARGS"; declare -g -a find_args
	declare -n find_targets="$1_TARGETS"; declare -g -a find_targets
	declare -n find_pre_args="$1_PRE_ARGS"; declare -g -a find_pre_args
	declare -n find_exclusions="$1_EXCLUSIONS"; declare -g -a find_exclusions
	declare -n find_inclusions="$1_INCLUSIONS"; declare -g -a find_inclusions
	local name="$1"
	shift

	if ! (( ${#find_targets[@]} )); then
		return
	fi

	declare -a find_cmd
	find_cmd=( "${find_args[@]}" "${find_targets[@]}" "${find_pre_args[@]}" )

	local e i
	local i_cmd=()
	for e in "${find_exclusions[@]}"; do
		i_cmd=()
		for i in "${find_inclusions[@]}"; do
			if [[ "$e" == "$i" ]]; then
				err "findctl: bad hierarchy: $(realpath "$e") is both included and excluded"
				return 1
			fi
			if [[ "$i" == "$e"/* ]]; then
				i_cmd+=(
					-and -not -path "$i/*"
				)
			fi
		done

		if (( ${#i_cmd[@]} > 0 )); then
			find_cmd+=(
				-path "$e/*"
				"${i_cmd[@]}"
			)
		else
			find_cmd+=(
				-path "$e" -prune
			)
		fi
		find_cmd+=( -or )

	done

	find_cmd+=( "$@" )
	{ Trace_resume; } &>/dev/null

	"${find_cmd[@]}"
}
