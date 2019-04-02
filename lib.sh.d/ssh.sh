#!/bin/bash

# in: $host: [user@]host[:port]
# in: $identity: path to ssh private key
# out: ssh_args=(): internal
# out: do_ssh(): ssh to $host using $identity
# out: do_sftp(): sftp to $host using $identity
# out: do_scp(): scp to $host using $identity
# error handling: die()
function ssh_prep() {
	if ! [[ "$host" ]]; then
		die "$0: ssh: host not provided, exiting"
	fi

	local user addr port
	if ! [[ "$host" =~ ^(([^@]+)@)?(.+)(:([0-9]+))?$ ]]; then
		die "$0: ssh: host '$host' is invalid, exiting"
	fi
	user="${BASH_REMATCH[2]}"
	addr="${BASH_REMATCH[3]}"
	port="${BASH_REPATCH[5]}"

	dbg "$0: ssh: host '$host' parsed as user='$user' addr='$addr' port='$port'"

	# FIXME: drop -4
	if ! ping -4 -c 1 -w 5 -q "$addr"; then
		die "$0: ssh: address '$addr' is unresponsive, exiting"
	fi

	local ssh_args
	ssh_args=(
		# FIXME: drop -4
		-4
		-o StrictHostKeyChecking=accept-new
	)
	if [[ "$identity" ]]; then
		ssh_args+=(
			-o IdentityFile="$identity"
		)
	fi

	ssh_cmd=(
		ssh
		"${ssh_args[@]}"
		${port:+-p "$port"}
		"${user:-root}@$addr"
	)
	do_ssh() {
		"${ssh_cmd[@]}" "$@"
	}
	sftp_cmd=(
		sftp
		"${ssh_args[@]}"
		${port:+-P "$port"}
		"${user:-root}@$addr"
	)
	do_sftp() {
		"${sftp_cmd[@]}" "$@"
	}
}
