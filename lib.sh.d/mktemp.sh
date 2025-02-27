#!/hint/bash

mktemp1() {
	command mktemp --tmpdir "${0##*/}${1:+"-$1"}.XXXXXXXXXX" "${@:2}"
}

libmktemp() {
	if ! [[ $_HAVE_CLEANUP_FILES ]]; then
		die "libmktemp() called before libmktemp_setup()"
	fi

	_CLEANUP_FILES+="$(mktemp1 "$@")"
	echo "${_CLEANUP_FILES[-1]}"
}

libmktemp_cleanup() {
	if ! [[ $_HAVE_CLEANUP_FILES ]]; then
		die "libmktemp_cleanup() called before libmktemp_setup()"
	fi

	rm -f "${_CLEANUP_FILES[@]}"
	_CLEANUP_FILES=()
}

libmktemp_setup() {
	if [[ $_HAVE_CLEANUP_FILES ]]; then
		return
	fi

	declare -g _HAVE_CLEANUP_FILES=1
	declare -g -a _CLEANUP_FILES
	ltrap libmktemp_cleanup
}

libmktemp_use() {
	libmktemp_setup "$@"
	mktemp() { libmktemp "$@"; }
}
