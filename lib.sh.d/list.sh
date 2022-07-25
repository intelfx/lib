#!/hint/bash

#
# A particularly ugly and inefficient implementation of basic logic operations
# on lists of integer ranges (e. g. "1,2,4-5,7") as commonly found in various
# configuration files and filesystems around Linux.
#

_list_explode_a() {
	declare -n out_array="$1"
	declare -a in_array

	IFS=,
	in_array=( $2 )
	unset IFS

	local i
	for i in "${in_array[@]}"; do
		if [[ "$i" =~ ^[0-9]+$ ]]; then
			out_array+=( $(( i )) )
		elif [[ "$i" =~ ^([0-9]+)-([0-9]+)$ ]]; then
			local a b j
			a="${BASH_REMATCH[1]}"
			b="${BASH_REMATCH[2]}"
			for (( j=a; j<=b; ++j )); do
				out_array+=( "$j" )
			done
		elif [[ "$i" == "" ]]; then
			:
		else
			err "_list_explode_a: bad list: '$2' (bad element: '$i')"
			return 1
		fi
	done
}

__list_collapse_one() {
	if [[ $first == $last ]]; then
		out_array+=( "$first" )
	else
		out_array+=( "$first-$last" )
	fi
}

_list_collapse_a() {
	declare -n in_array="$1"
	declare -a out_array

	local i first last

	i="${in_array[0]}"; unset in_array[0]
	first=$i
	last=$i
	for i in "${in_array[@]}"; do
		if (( i == last + 1 )); then
			last=$i
		else
			__list_collapse_one
			first=$i
			last=$i
		fi
	done
	__list_collapse_one

	IFS=,
	echo "${out_array[*]}"
	unset IFS
}

_list_A_to_a() {
	declare -n in_hash="$1"
	declare -n out_array="$2"

	# printf '%s\n' breaks for empty arrays
	if ! (( ${#in_hash[@]} )); then
		return
	fi

	printf '%s\n' "${!in_hash[@]}" | sort -n | readarray -t out_array
}

_list_collapse_A() {
	declare -a array

	_list_A_to_a "$1" array
	_list_collapse_a array
}

list_or() {
	declare -A result
	declare -a op

	local arg k
	for arg; do
		_list_explode_a op "$arg"
		for k in "${op[@]}"; do
			result[$k]=1
		done

	done

	_list_collapse_A result
}

list_and() {
	declare -a lhs rhs
	declare -A result

	_list_explode_a lhs "$1"
	_list_explode_a rhs "$2"

	local k v
	for k in "${lhs[@]}" "${rhs[@]}"; do
		(( ++result[$k] ))
	done

	for k in "${!result[@]}"; do
		v="${result[$k]}"
		if (( v != 2 )); then
			unset result[$k]
		fi
	done

	_list_collapse_A result
}

list_sub() {
	declare -a lhs rhs
	declare -A result

	_list_explode_a lhs "$1"
	_list_explode_a rhs "$2"

	local k
	for k in "${lhs[@]}"; do
		result[$k]=1
	done

	for k in "${rhs[@]}"; do
		unset result[$k]
	done

	_list_collapse_A result
}

list_into_mask() {
	declare -a in
	_list_explode_a in "$1"
	local out="0"

	local k
	for k in "${in[@]}"; do
		out="$(( out | 1<<k ))"
	done

	if (( "${2:-0}" )); then
		local width_bit="$2"
		local width_hex="$(( (width_bit + 3) / 4 ))"
		printf "%0*x\n" "$width_hex" "$out"
	else
		printf '%x\n' "$out"
	fi
}

list_from_mask() {
	local in="$(( 0x"${1:-0}" ))"
	declare -a out

	local k=0
	while (( in )); do
		if (( in & 1 )); then
			out+=( "$k" )
		fi
		in="$(( in >> 1 ))"
		(( ++k ))
	done

	_list_collapse_a out
}

list_into_array() {
	_list_explode_a "$1" "$2"
}

list_max() {
	declare -a in
	_list_explode_a in "$1"
	local out="${in[0]}"

	local k
	for k in "${in[@]:1}"; do
		if (( k > out )); then out="$k"; fi
	done

	echo "$out"
}

list_count() {
	declare -a in
	_list_explode_a in "$1"
	echo "${#in[@]}"
}
