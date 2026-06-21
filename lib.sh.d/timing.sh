#!/hint/bash

timer_start() {
	# $EPOCHREALTIME is locale-dependent
	# but, apparently, setting $LC_ALL as a local is enough to influence it
	local LC_ALL=C
	declare -g _TIMER_END=
	declare -g _TIMER_START=$EPOCHREALTIME
}

timer_end() {
	# see timer_start()
	local LC_ALL=C
	declare -g _TIMER_END=$EPOCHREALTIME
}

_timer_scale() {
	local unit="$1" scale
	case "$unit" in
	s|sec) scale=1 ;;
	ms|msec) scale=1000 ;;
	us|usec) scale=1000000 ;;
	*) die "timer: invalid unit: ${unit@Q}" ;;
	esac
	printf "%s\n" "$scale"
}

timer_delta() {
	local unit="${1-s}"

	local scale
	scale="$(_timer_scale "$unit")"
	bc -l <<<"(${_TIMER_END:?} - ${_TIMER_START:?}) / $scale"
}

timer_delta_int() {
	local unit="${1-s}"

	local scale
	scale="$(_timer_scale "$unit")"
	bc -l <<<"scale=0; (${_TIMER_END:?} - ${_TIMER_START:?}) / $scale"
}

timer_delta_fmt() {
	awk -v t1="${_TIMER_START:?}" -v t2="${_TIMER_END:?}" </dev/null \
	'BEGIN {
		d = t2 - t1
		h = int(d / 3600); d -= h * 3600
		m = int(d / 60);   d -= m * 60
		if (h)      printf "%dh %dm %.3fs\n", h, m, d
		else if (m) printf "%dm %.3fs\n", m, d
		else        printf "%.3fs\n", d
	}'
}
