#!/usr/bin/env bash
#===============================================================================
#          FILE: tools.sh
#
#         USAGE: ./tools.sh
#
#   DESCRIPTION: Entrypoint for samba docker container
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: monkeydri (monkeydri@github.com),
#  ORGANIZATION:
#       CREATED: 11/11/2018 11:11
#      REVISION: 1.0
#===============================================================================

set -o nounset                              # Treat unset variables as an error

# export users : unix users info (/etc/passwd and /etc/group) + samba users database (smbpasswd)
export_users()
{
	local EXPORT_DIR="${1:-"/etc/export"}"

	 UNIX_USERS_FILE="${EXPORT_DIR}/passwd" UNIX_GROUPS_FILE="${EXPORT_DIR}/group" SAMBA_USERS_FILE="${EXPORT_DIR}/smbpasswd"

	# get list of samba usernames (pipe separated)
	USERNAMES=$(pdbedit -L | cut -d: -f1 | tr '\n' '|' | rev | cut -c 2- | rev)

	# create export dir if required
	mkdir -p -Dv /dev/null "${EXPORT_DIR}"

	# export corresponding unix users info
	grep -E "${USERNAMES}" /etc/passwd > "${UNIX_USERS_FILE}"

	# export corresponding unix group info
	grep -E "${USERNAMES}" /etc/group > "${UNIX_GROUPS_FILE}"

	# export samba users DB
	pdbedit -e smbpasswd > "${SAMBA_USERS_FILE}"
}

# usage: Help
usage()
{
	local RC="${1:-0}"

	echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
	-h					This help
	-e \"<path>\" Export users
							required arg: \"<path>\"
							<path> full file path in container to export directory
" >&2
	exit $RC
}

while getopts ":hc:e:" opt; do
	case "$opt" in
		h) usage ;;
		e) export_users "$OPTARG" ;;
		"?") echo "Unknown option: -$OPTARG"; usage 1 ;;
		":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
	esac
done
