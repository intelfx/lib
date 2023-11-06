#!/hint/bash

# $1: name of an associative array with argument definitions (see below)
# $2...: arguments to parse
#
# EXAMPLE=(
#	[-f]="ARG_FOO"
#	[--foo]="ARG_FOO"
#	[--bar:]="ARG_BAR"
#	[--baz::]="ARG_BAZ"
#	[-q|--quux:]="ARG_QUUX"
#	[--]="ARG_REMAINDER"
#	[getopt]="+-"
# )
#
# All target variables will be unset upon entry.
# Boolean flags will cause the target variable to be set to 1.
# ":" and "::" suffixes to option names will be treated similar to getopt(1).
# Multiple options may be joined with a "|" in a single key; in this case only a single suffix shall be provided.
#
parse_args() {
	eval "$(ltraps)"
	ltrap "eval '$(shopt -p extglob)'"
	shopt -s extglob

	local modes
	local opts=() optstring
	local longopts=() longoptstring
	local args=( "${@:2}" ) parsed_args
	declare -n spec="$1"
	declare -A arg_to_target
	declare -A arg_to_valspec

	# pass parsing modes ("+" or "-")
	if [[ "${spec[getopt]+set}" ]]; then
		modes="${spec[getopt]}"
		unset spec[getopt]
	fi

	local key value flag
	declare -a keys
	for key in "${!spec[@]}"; do
		if [[ $key == *"|"* ]]; then
			value="${spec["$key"]}"
			unset spec["$key"]

			flag="${key##*([^:])}"
			key="${key%%*(:)}"
			echo -n "$key" | readarray -d'|' -t keys
			for key in "${keys[@]}"; do
				spec["$key$flag"]="$value"
			done
		fi
	done

	local key_dashes key_name key_valspec
	for key in "${!spec[@]}"; do
		value="${spec[$key]}"

		if [[ $key == -- ]]; then
			arg_to_target[$key]="$value"
		elif [[ $key =~ ^(--|-)([a-zA-Z0-9_-]+)(|:|::)$ ]]; then
			key_dashes="${BASH_REMATCH[1]}"
			key_name="${BASH_REMATCH[2]}"
			key_valspec="${BASH_REMATCH[3]}"

			if [[ $key_dashes == - ]]; then
				opts+=( "$key_name$key_valspec" )
			elif [[ $key_dashes == -- ]]; then
				longopts+=( "$key_name$key_valspec" )
			else
				die "parse_args: Internal error"
			fi

			arg_to_target[$key_dashes$key_name]="$value"
			arg_to_valspec[$key_dashes$key_name]="$key_valspec"
		else
			err "parse_args: bad key: [$key]=$value"
			return 1
		fi

		declare -n target="$value"; unset target; unset -n target
	done

	optstring="${modes}$(IFS=""; echo "${opts[*]}")"
	longoptstring="$(IFS=","; echo "${longopts[*]}")"

	parsed_args="$(getopt -n "$0" -o "$optstring" ${longoptstring:+--long "$longoptstring"} -- "${args[@]}")" || return
	eval set -- "$parsed_args"

	local arg valspec
	while (( $# )); do
		if [[ $1 == -- ]] && ! [[ ${arg_to_target[$1]} ]]; then
			if (( $# > 1 )); then
				err "parse_args: unexpected positional arguments"
				return 1
			else
				shift
				break
			fi
		fi

		declare -n target="${arg_to_target[$1]}"

		if [[ $1 == -- ]]; then
			target=( "${@:2}" )
			shift $#
		else
			valspec="${arg_to_valspec[$1]}"
			case "$valspec" in
			'') target="1"; shift ;;
			':') target="$2"; shift 2 ;;
			'::') target="$2"; shift 2 ;;
			*) die "parse_args: Internal error" ;;
			esac
		fi

		unset -n target
	done
}

# get_arg <KEY VAR> <VALUE VAR> <SHIFT COUNT VAR> <FORMS...> -- [INPUT ARGS]
# $1: variable name for the found form
# $2: variable name for the found argument value
# $3: variable name for the shift count (how many args were consumed)
# $4...: argument forms (short or long)
# $n: "--"
# $n+1...: input
function get_arg() {
	# read namerefs
	declare -n key="$1" value="$2" shift_nr="$3"
	shift 3
	# read forms until "--"
	declare -a short long
	while (( $# )); do
		case "$1" in
		--) shift; break;;
		-[a-zA-Z0-9]) short+=( "$1" ); shift;;
		--*) long+=( "$1" ); shift;;
		*) die "get_arg: unexpected form \"$1\""
		esac
	done

	local f
	# TODO: combined short options
	for f in "${short[@]}"; do
		if (( $# >= 2 )) && [[ $1 == $f ]]; then
			key="$f"
			value="$2"
			shift_nr=2
			return 0
		elif (( $# >= 1 )) && [[ $1 == $f* ]]; then
			key="$f"
			value="${1#$f}"
			shift_nr=1
			return 0
		fi
	done
	for f in "${long[@]}"; do
		if (( $# >= 2 )) && [[ $1 == $f ]]; then
			key="$f"
			value="$2"
			shift_nr=2
			return 0
		elif (( $# >= 1 )) && [[ $1 == $f=* ]]; then
			key="$f"
			value="${1#$f=}"
			shift_nr=1
			return 0
		fi
	done
	shift_nr=0
	return 1
}

# get_flag <KEY VAR> <SHIFT COUNT VAR> <FORMS...> -- [INPUT ARGS]
# $1: variable name for the found form
# $2: variable name for the shift count (how many args were consumed)
# $3...: argument forms (short or long)
# $n: "--"
# $n+1...: input
function get_flag() {
	# read namerefs
	declare -n key="$1" shift_nr="$2"
	shift 2
	# read forms until "--"
	declare -a short long
	while (( $# )); do
		case "$1" in
		--) shift; break;;
		-[a-zA-Z0-9]) short+=( "$1" ); shift;;
		--*) long+=( "$1" ); shift;;
		*) die "get_arg: unexpected form \"$1\""
		esac
	done

	local f
	# TODO: combined short options
	for f in "${short[@]}"; do
		if (( $# >= 1 )) && [[ $1 == $f ]]; then
			key="$f"
			shift_nr=1
			return 0
		fi
	done
	for f in "${long[@]}"; do
		if (( $# >= 1 )) && [[ $1 == $f ]]; then
			key="$f"
			value="$2"
			shift_nr=1
			return 0
		fi
	done
	shift_nr=0
	return 1
}
