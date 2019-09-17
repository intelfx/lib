#!/hint/bash

# $1: name of an associative array with argument definitions (see below)
# $2...: arguments to parse
#
# EXAMPLE=(
#	[-f]="ARG_FOO"
#	[--foo]="ARG_FOO"
#	[--]="ARG_REMAINDER"
# )
#
# All target variables will be unset upon entry.
# Boolean flags will cause the target variable to be set to 1.
#
parse_args() {
	local opts=() optstring
	local longopts=() longoptstring
	local args=( "${@:2}" ) parsed_args
	declare -n spec="$1"
	declare -A arg_to_target
	declare -A arg_to_valspec

	local key value
	local key_dashes key_name key_valspec
	for key in "${!spec[@]}"; do
		value="${spec[$key]}"

		if [[ $key =~ ^(--|-)([a-zA-Z0-9_-]+)(|:|::)$ ]]; then
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
		elif [[ $key == -- ]]; then
			arg_to_target[$key]="$value"
		else
			err "parse_args: bad key: [$key]=$value"
			return 1
		fi

		declare -n target="$value"; unset target; unset -n target
	done

	optstring="$(IFS=""; echo "${opts[*]}")"
	longoptstring="$(IFS=","; echo "${longopts[*]}")"

	parsed_args="$(getopt -o "$optstring" ${longoptstring:+--long "$longoptstring"} -- "${args[@]}")"
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
