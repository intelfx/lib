#!/hint/bash

# More ergonomic mktemp(1).
# - implies `--tmpdir`
# - any flags are passed to mktemp(1)
# - the default tmpfile pattern is based on the current script name
# - any argument that contains three or more Xs is used as a replacement pattern
# - any argument that starts with a dot is appended to the default pattern (as an extension)
# - any other argument is inserted into the default pattern after the script name (as a disambiguator)
mktemp1() {
	local -a opts
	local prefix suffix pattern
	local arg
	for arg; do
		case "$arg" in
		-*)
			opts+=( "$arg" )
			;;
		.*)
			[[ ! "$suffix" ]] || die "mktemp1(${*@Q}): invalid arguments: duplicate suffix"
			suffix="${arg#*.}"
			;;
		*XXX*)
			[[ ! "$pattern" ]] || die "mktemp1(${*@Q}): invalid arguments: duplicate pattern"
			[[ ! "$prefix" && ! "$suffix" ]] || die "mktemp1(${*@Q}): invalid arguments: pattern must not be combined with prefix/suffix"
			pattern="$arg"
			;;
		*)
			[[ ! "$prefix" ]] || die "mktemp1(${*@Q}): invalid arguments: duplicate prefix"
			prefix="$arg"
			;;
		esac
	done
	if ! [[ $pattern ]]; then
		pattern="${LIB_NAME}${prefix:+"-$prefix"}.XXXXXXXXXX${suffix:+".$suffix"}"
	fi
	command mktemp --tmpdir "${opts[@]}" "$pattern"
}

# XXX: do not use: this is normally used in a substitution, but traps do not survive subshells
# mktemp_trap() {
# 	local tmpfile
# 	tmpfile="$(mktemp1 "$@")" || return
# 	ltrap "rm -f ${tmpfile@Q}"
# 	printf "%s\n" "$tmpfile"
# }

# More ergonomic mktemp(1) with automatic cleanup.
# Must be invoked after libmktemp_setup() which configures the cleanup handler.
# See mktemp1() for behavior details.
libmktemp() {
	if ! [[ $_CLEANUP_LIST ]]; then
		die "libmktemp() called before libmktemp_setup()"
	fi

	local tmpfile
	tmpfile="$(mktemp1 "$@")" || return
	printf "%s\n" "$tmpfile" >>"$_CLEANUP_LIST"
	printf "%s\n" "$tmpfile"
}

libmktemp_cleanup() {
	if ! [[ $_CLEANUP_LIST ]]; then
		die "libmktemp_cleanup() called before libmktemp_setup()"
	fi

	local -a files
	readarray -t files <"$_CLEANUP_LIST"
	if (( ${#files[@]} )); then
		rm -f "${files[@]}"
	fi
	: >"$_CLEANUP_LIST"
}

libmktemp_setup() {
	if [[ $_CLEANUP_LIST ]]; then
		return
	fi

	# NOTE: the list of files to clean up is kept in a file rather than in
	#       an array because libmktemp() is normally invoked in a command
	#       substitution, and a subshell cannot register anything with us.
	declare -g _CLEANUP_LIST
	_CLEANUP_LIST="$(command mktemp --tmpdir "${LIB_NAME}.cleanup.XXXXXXXXXX")"
	ltrap "libmktemp_cleanup; rm -f ${_CLEANUP_LIST@Q}"
}

libmktemp_use() {
	libmktemp_setup "$@"
	mktemp() { libmktemp "$@"; }
}
