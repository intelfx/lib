#!/bin/bash

set -eo pipefail
shopt -s lastpipe

__libsh="$(realpath -qe "${BASH_SOURCE}").d"
if ! [[ -d "$__libsh" ]]; then
	echo "lib.sh: lib.sh.d does not exist!" >&2
	return 1
fi

for __libsh_file in "$__libsh"/*.sh; do
	if [[ -x "$__libsh_file" ]]; then
		source "$__libsh_file" || exit
	fi
done

unset __libsh __libsh_file
