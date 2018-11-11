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

# create user (unix user + samba user) - default group is users
create_user()
{
	local username="$1" password="$2" groupname="${3:-"users"}" uid="${4:-""}" sid="${5:-""}" 

	# create unix group if it does not exists
	grep -q "^${groupname}:" /etc/group || addgroup "${groupname}";

	# check if unix user exists
	if grep -q "^${username}:" /etc/passwd; then
		echo "user ${username} already exists"
	else
		# create unix user with correct group without password and home directory (optional uid)
		adduser -D -H -G "${groupname}" ${uid:+-u $uid} "${username}";

		# add user to samba internal user DB (optional sid)
		echo -e "$password\n$password" | smbpasswd -s -a ${sid:+-U $sid} "${username}";

		# enable samba user
		smbpasswd -e "${username}"
	fi
}

# export users : unix users info (/etc/passwd and /etc/group) + samba users database (smbpasswd)
export_users()
{
	local EXPORT_DIR="${1:-"/etc/export"}"

	UNIX_USERS_FILE="${EXPORT_DIR}/passwd" UNIX_GROUPS_FILE="${EXPORT_DIR}/group" SAMBA_USERS_FILE="${EXPORT_DIR}/smbpasswd"

	# get list of samba usernames (pipe separated)
	usernames=$(pdbedit -L | cut -d: -f1 | tr '\n' '|' | rev | cut -c 2- | rev)

	# create export dir if required
	mkdir -p "${EXPORT_DIR}"

	# export corresponding unix users info
	grep -E "${usernames}" /etc/passwd > "${UNIX_USERS_FILE}"

	# export corresponding unix group info
	grep -E "${usernames}" /etc/group > "${UNIX_GROUPS_FILE}"

	# export samba users DB
	rm ${SAMBA_USERS_FILE}
	pdbedit -e smbpasswd:"${SAMBA_USERS_FILE}"
}

# usage: Help
usage()
{
	local RC="${1:-0}"

	echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
	-h					This help
	-u \"<username;password>[;ID;group]\"       Add a user
							required arg: \"<username>;<passwd>\"
							<username> for unix and samba user
							<password> for samba user
							[UID] for unix user
							[group] for unix user (default group is `users`)
							[SID] for samba user
	-e \"<path>\" Export users
							required arg: \"<path>\"
							<path> full file path in container to export directory
" >&2
	exit $RC
}

while getopts ":hu:e:" opt; do
	case "$opt" in
		h) usage ;;
		u) eval create_user $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< $OPTARG) ;;
		e) export_users "$OPTARG" ;;
		"?") echo "Unknown option: -$OPTARG"; usage 1 ;;
		":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
	esac
done
