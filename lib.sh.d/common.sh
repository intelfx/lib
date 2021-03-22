#!/bin/bash

BASH_BUILTINS_LOADABLE=(
	sleep
)

function bash_enable_builtin() {
	local loadablesdir
	if ! loadablesdir="$(pkg-config --variable=loadablesdir bash)"; then
		# TODO: fallback
		return 1
	fi

	if ! [[ -f "$loadablesdir/$1" ]]; then
		# TODO: fallback
		return 1
	fi

	enable -f "$loadablesdir/$1" "$1"
}

for b in "${BASH_BUILTINS_LOADABLE[@]}"; do
	bash_enable_builtin "$b" ||:
done
unset b
