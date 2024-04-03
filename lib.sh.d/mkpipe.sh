#!/hint/bash

# Usage: mkpipe <READ_FD> <WRITE_FD>
# Returns: two newly opened fds in $<READ_FD> and $<WRITE_FD>
mkpipe() {
	eval "$(ltraps)"
	declare -n rd_fd="$1" wr_fd="$2"
	local rdwr_fd fifo
	fifo="$(command mktemp --dry-run)"
	ltrap "rm -f '$fifo'"
	mkfifo -m0600 "$fifo"
	# open RDWR in a throwaway fd before doing anything else because
	# opening a pipe either RD or WR when other end isn't opened blocks
	exec {rdwr_fd}<>"$fifo" {rd_fd}<"$fifo" {wr_fd}>"$fifo" {rdwr_fd}>&-
}
