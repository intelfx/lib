#!/bin/bash

function _libsh_log() {
	local marker="$1" prefix="$2" text="$3"
	echo "${marker:+$marker }${prefix:+$prefix: }$text" >&2
}

function dbg() {
	if (( LIBSH_DEBUG )); then
		_libsh_log "DBG:" "$LIBSH_LOG_PREFIX" "$*"
	fi
}

function log() {
	_libsh_log "::" "$LIBSH_LOG_PREFIX" "$*"
}

function say() {
	_libsh_log "" "" "$*"
}

function warn() {
	_libsh_log "W:" "$LIBSH_LOG_PREFIX" "$*"
}

function err() {
	_libsh_log "E:" "$LIBSH_LOG_PREFIX" "$*"
}

function die() {
	err "$@"
	exit 1
}
