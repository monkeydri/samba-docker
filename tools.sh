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

# export users : unix users info (/etc/passwd) + samba users database (smbpasswd)
export_users()
{
	local UNIX_USERS_FILE="${1:-"/etc/export/passwd"}" UNIX_GROUPS_FILE="${2:-"/etc/export/group"}" SAMBA_USERS_FILE="${3:-"/etc/export/smbpasswd"}"

	# get list of samba usernames (pipe separated)
	USERNAMES=$(pdbedit -L | cut -d: -f1 | tr '\n' '|' | rev | cut -c 2- | rev)

	# create required parent dirs if necessary (Note : also empties the file)
	install -Dv /dev/null "${UNIX_USERS_FILE}"
	install -Dv /dev/null "${UNIX_GROUPS_FILE}"

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
	-e \"<passwd>;<group>;<smbpasswd>\" Export users
							required arg: \"<passwd>;<group>;<smbpasswd>\"
							<passwd> full file path in container for unix users file
							<group> full file path in container for unix groups file
							<smbpasswd> full file path in container for samba users file
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
