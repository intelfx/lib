#!/hint/bash

# $1: name of an associative array with argument definitions (see below)
# $2...: arguments to parse
#
# EXAMPLE=(
#	[-f]="ARG_FOO default=TRUE"
#	[--foo]="ARG_FOO"
#	[--bar:]="ARG_BAR split=, append"
#	[--baz::]="ARG_BAZ"
#	[-q|--quux:]="ARG_QUUX"
#	[--]="ARG_REMAINDER"
#	[getopt]="+-"
# )
#
# All target variables will be unset upon entry.
# Boolean flags will cause the target variable to be set to 1, or the default (see below).
# ":" and "::" suffixes to option names will be treated similar to getopt(1).
# Multiple options may be joined with a "|" in a single key; in this case only a single suffix shall be provided.
# Target variable name may be followed by 0 or more items, separated by spaces,
# which affect parse_args' behavior when the option is encountered.
# Possible items include:
# - default=X
#     store "X" if the option has no value
#     (only possible for flags and optional-argument options)
#     (_no_ value is not the same as _empty_ value)
#     (HOWEVER, optional-argument options currently treat empty value as no value)
#      ex. --foo    has no value
#          --bar='' has empty value
#          --baz    has no value
#          --baz='' has empty value BUT is treated like there's no value
# - split=X:
#     split the argument on "X" and store the results in an array variable
# - append:
#     append the argument (after possible splitting) to an array variable
# - pass=X:
#     save the original option (and argument, if required) into array "X"
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

	declare -A arg_is_array
	declare -A arg_append
	declare -A arg_delim
	declare -A arg_default
	declare -A arg_passthrough
	local DEFAULT=1

	# pass parsing modes ("+" or "-")
	if [[ "${spec[getopt]+set}" ]]; then
		modes="${spec[getopt]}"
		unset spec[getopt]
	fi

	# preprocess compound keys ("-a|--arg")
	# currently, we split them into identical entries for each key
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

	# parse keys (--, -a, --arg, : and ::)
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
	done

	# postprocess values (extract items such as default=X, split=Y)
	declare -a value_items
	local item
	for key in "${!arg_to_target[@]}"; do
		value="${arg_to_target["$key"]}"

		# split on whitespace
		IFS=' '; value_items=( $value ); unset IFS

		# first item is the actual target variable name,
		# unless it has a "=" (to support bare "pass=")
		if [[ ${value_items[0]} != *=* ]]; then
			# update the target
			value="${value_items[0]}"
			arg_to_target["$key"]="$value"
			# while we have the name, clear (unset) target variable
			declare -n target="$value"; unset target; unset -n target
		else
			# patch something in to let the next loop start from 1
			value_items=( - "${value_items[@]}" )
			# delete the bogus target
			unset arg_to_target["$key"]
		fi

		# next items are behavior modifiers
		for item in "${value_items[@]:1}"; do
			case "$item" in
			append)
				arg_is_array[$key]=1
				arg_append[$key]=1
				;;
			split=*)
				arg_is_array[$key]=1
				arg_delim[$key]="${item#split=}"
				;;
			default=*)
				arg_default[$key]="${item#default=}"
				;;
			pass=*)
				# sic: this is split at whitespace (bash has no nested arrays)
				arg_passthrough[$key]+=" ${item#pass=}"
				;;
			*)
				err "parse_args: bad item: [$key]=$value (item: $item)"
				return 1
				;;
			esac
		done
	done

	optstring="${modes}$(IFS=""; echo "${opts[*]}")"
	longoptstring="$(IFS=","; echo "${longopts[*]}")"

	parsed_args="$(getopt -n "$0" -o "$optstring" ${longoptstring:+--long "$longoptstring"} -- "${args[@]}")" || return
	eval set -- "$parsed_args"

	local arg valspec dfl count
	declare -a items
	while (( $# )); do
		# special case
		if [[ $1 == -- ]]; then
			if [[ ${arg_to_target[$1]+set} ]]; then
				declare -n target="${arg_to_target[$1]}"
				target=( "${@:2}" )
				unset -n target
			elif (( $# > 1 )); then
				err "parse_args: unexpected positional arguments"
				return 1
			fi
			return 0
		fi

		# get value
		valspec="${arg_to_valspec[$1]}"
		case "$valspec" in
		'') dfl=1; value=""; count=1 ;;
		':') dfl=0; value="$2"; count=2 ;;
		'::') dfl=1; value="$2"; count=2 ;;
		*) die "parse_args: Internal error" ;;
		esac
		# apply default (if needed)
		if [[ ! $value ]] && (( dfl )); then
			value="${arg_default[$1]-$DEFAULT}"
		fi

		# save (passthrough) the original option
		if [[ ${arg_passthrough[$1]+set} ]]; then
			# sic: split passthrough at whitespace (bash has no nested arrays)
			IFS=' '; items=( ${arg_passthrough[$1]} ); unset IFS
			for item in "${items[@]}"; do
				declare -n target="$item"
				target+=( "${@:1:$count}" )
				unset -n target
			done
		fi

		# shortcut: support options without a target
		# (must come after passthrough to support bare "pass=")
		if ! [[ ${arg_to_target[$1]+set} ]]; then
			shift "$count"
			continue
		fi

		declare -n target="${arg_to_target[$1]}"

		# apply value to target according to flags
		# XXX: this is a war crime
		if [[ ${arg_is_array[$1]+set} ]]; then
			if [[ ${arg_delim[$1]+set} ]]; then
				if [[ ${arg_append[$1]+set} ]]; then
					echo -n "$value" \
					| readarray \
						-t \
						-d "${arg_delim[$1]}" \
						-O "${#target[@]}" \
						target
				else
					echo -n "$value" \
					| readarray \
						-t \
						-d "${arg_delim[$1]}" \
						target
				fi
			else
				if [[ ${arg_append[$1]+set} ]]; then
					target+=( "$value" )
				else
					target=( "$value" )
				fi
			fi
		else
			target="$value"
		fi

		unset -n target
		shift "$count"
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
