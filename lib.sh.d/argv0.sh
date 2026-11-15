#!/hint/bash

# Remember original $0 for error messages
if ! [[ ${LIB_ARGV0+set} ]]; then
	# Apparently, interpreted execution on Linux provides no way
	# to acquire the original $0 with which the script was invoked.
	# (https://stackoverflow.com/a/37369285/857932)
	# Try to re-derive it.
	for LIB_ARGV0 in "${0##*/}" "$0" "${BASH_SOURCE[2]}"; do
		if [[ "$(command -v "$LIB_ARGV0")" -ef "${BASH_SOURCE[2]}" ]]; then
			break
		fi
	done

	# Also provide the script _name_ for convenience.
	LIB_NAME="${0##*/}"

	# Precompute a string with all arguments for logging/debugging purposes
	LIB_ARGV="$LIB_ARGV0${*:+" ${*@Q}"}"

	# NOTE: if $LIB_ARGV0 needs to be inherited across subprocesses,
	# the caller must export it manually.
fi
