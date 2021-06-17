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

_list_collapse_A() {
	declare -n in_hash="$1"
	declare -a in_array out_array

	# printf '%s\n' breaks for empty arrays
	if ! (( ${#in_hash[@]} )); then
		return
	fi

	printf '%s\n' "${!in_hash[@]}" | sort -n | readarray -t in_array

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

list_or() {
	declare -a lhs rhs
	declare -A result

	_list_explode_a lhs "$1"
	_list_explode_a rhs "$2"

	declare -p lhs
	declare -p rhs

	local k
	for k in "${lhs[@]}" "${rhs[@]}"; do
		result[$k]=1
	done

	declare -p result

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
