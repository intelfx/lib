#!/bin/bash

# in: $host: [user@]host[:port]
# out: $addr, $user, $port
# error handling: die()
function ssh_prep_parse_host() {
	if ! [[ "$host" ]]; then
		die "ssh: host not provided, exiting"
	fi

	if ! [[ "$host" =~ ^(([^@]+)@)?(.+)(:([0-9]+))?$ ]]; then
		die "ssh: host '$host' is invalid, exiting"
	fi
	user="${BASH_REMATCH[2]}"
	addr="${BASH_REMATCH[3]}"
	port="${BASH_REPATCH[5]}"

	dbg "ssh: host '$host' parsed as user='$user' addr='$addr' port='$port'"
}

# in: $host: [user@]host[:port] OR $addr + $user (optional) + $port (optional)
# in: $identity: path to ssh private key
# in: $known_hosts: path to a custom known_hosts file
#                   (optional; set to "" to use default known_hosts, otherwise /dev/null if unset)
# in: $@: additional ssh arguments
# out: ssh_args=(): internal
# out: do_ssh(): ssh to $host using $identity
# out: do_sftp(): sftp to $host using $identity
# out: do_scp(): scp to $host using $identity
# out: $user, $addr, $port: parsed $host
# error handling: die()
function ssh_prep() {
	if ! [[ $addr ]]; then
		ssh_prep_parse_host
	fi

	if ! ping -c 1 -w 5 -q "$addr"; then
		die "ssh: address '$addr' is unresponsive, exiting"
	fi

	local ssh_args
	ssh_args=(
		-o BatchMode=yes
		-o StrictHostKeyChecking=no
	)

	if [[ "$known_hosts" ]]; then
		# pass known_hosts file if $known_hosts is set
		ssh_args+=( -o UserKnownHostsFile="$known_hosts" )
	elif ! [[ ${known_hosts+set} ]]; then
		# pass /dev/null UNLESS $known_hosts is set to an empty string
		ssh_args+=( -o UserKnownHostsFile=/dev/null )
	fi
	if [[ "$identity" ]]; then
		# pass identity (private key) if $identity is set
		ssh_args+=(
			-o IdentitiesOnly=yes
			-i "$identity"
		)
	fi
	# append the remaining ssh options
	ssh_args+=( "$@" )

	ssh_cmd=(
		ssh
		"${ssh_args[@]}"
		${port:+-p "$port"}
		"${user:-root}@$addr"
	)
	do_ssh() {
		dbg "ssh: will run ${ssh_cmd[*]} $*"
		"${ssh_cmd[@]}" "$@" || die "ssh: ssh failed ($?), exiting"
	}
	sftp_cmd=(
		sftp
		"${ssh_args[@]}"
		${port:+-P "$port"}
		"${user:-root}@$addr"
	)
	do_sftp() {
		dbg "ssh: will run ${sftp_cmd[*]} $*"
		"${sftp_cmd[@]}" "$@" || die "ssh: sftp failed ($?), exiting"
	}
}
