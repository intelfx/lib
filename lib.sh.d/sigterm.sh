#!/hint/bash

#
# A companion to trap.sh (same disclaimer applies), this module can be used to
# run long-living processes while remaining receptive to SIGTERM.
#
# Adapted from https://unix.stackexchange.com/q/146756/21885
#

TH_SIGNALS=( TERM )

# th_handler(): internal SIGTERM handler
th_handler() {
	declare -g TH_PID TH_RACE TH_WE_GET_SIGNAL=1
	local rc
	trap - "${TH_SIGNALS[@]}"

	if ! [[ $TH_PID ]]; then
		dbg "th_handler: no job in progress, flagging"
		TH_RACE=1
		return
	fi

	dbg "th_handler: job in progress (pid=$TH_PID), killing"
	kill -TERM "$TH_PID"

	# assume that SIGTERM is fatal -- don't even return from the handler,
	# just wait for the child process ourselves and exit.
	# this way we skip the whole mess in th_wait().
	# TODO: make configurable?

	dbg "th_handler: waiting"
	# capture $rc without dying due to `set -e`
	th_wait "$TH_PID" && rc=0 || rc=$?
	dbg "th_handler: exiting (rc=$rc)"
	exit $rc
}

# th_wait(): wait for the child process, skipping trapped signals for the shell itself
th_wait() {
	declare -g TH_WE_GET_SIGNAL
	local rc
	while :; do
		TH_WE_GET_SIGNAL=0
		# capture $rc without dying due to `set -e`
		wait "$@" && rc=0 || rc=$?
		if (( rc >= 128 )) && (( TH_WE_GET_SIGNAL )); then
			# This is awkward.
			# Receipt of exit status >= 128 means we got a signal.
			# However, this can happen for two completely unrelated reasons:
			# - either the child process exited on receipt of a signal,
			# - OR _we_ as a shell have been signaled and the signal is trapped.
			# Handler will set $TH_WE_GET_SIGNAL when it runs for us to know what case is what.
			#
			# In fact, currently this is unused at all because the handler will untrap itself,
			# wait for the child process for the second time and exit without ever returning.
			# However, this code is included here for posterity.
			dbg "th_wait: wait $*: rc=$rc (sig=$((rc-128))) -- _shell_ signaled, waiting again"
			continue
		else
			if (( rc >= 128 )); then
				dbg "th_wait: wait $*: rc=$rc (sig=$((rc-128))) -- child signaled"
			elif (( rc == 127 )); then
				dbg "th_wait: wait $*: rc=127 -- no such PID"
			else
				dbg "th_wait: wait $*: rc=$rc"
			fi
			break
		fi
	done
	return $rc
}

# th_run(): run a long-living subprocess, while remaining receptive to SIGTERM.
#           Kill the subprocess, wait for it and exit on receipt of SIGTERM.
th_run() {
	declare -g TH_PID= TH_RACE= TH_WE_GET_SIGNAL=
	local rc

	dbg "th_run: $*"
	trap th_handler "${TH_SIGNALS[@]}"
	"$@" &
	TH_PID="$!"
	if (( TH_RACE )); then
		th_handler
	fi
	th_wait "$TH_PID" && rc=0 || rc=$?
	dbg "th_run: $*: completed"
	return $rc
}
