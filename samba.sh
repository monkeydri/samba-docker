#!/usr/bin/env bash
#===============================================================================
#          FILE: samba.sh
#
#         USAGE: ./samba.sh
#
#   DESCRIPTION: Entrypoint for samba docker container
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: David Personette (dperson@gmail.com),
#  ORGANIZATION:
#       CREATED: 09/28/2014 12:11
#      REVISION: 1.0
#===============================================================================

set -o nounset                              # Treat unset variables as an error

### charmap: setup character mapping for file/directory names
# Arguments:
#   chars) from:to character mappings separated by ','
# Return: configured character mapings
charmap() { local chars="$1" file=/etc/samba/smb.conf
		grep -q catia $file || sed -i '/TCP_NODELAY/a \
\
		vfs objects = catia\
		catia:mappings =\

								' $file

		sed -i '/catia:mappings/s/ =.*/ = '"$chars" $file
}

### global: set a global config option
# Arguments:
#   option) raw option
# Return: line added to smb.conf (replaces existing line with same key)
global() { local key="${1%%=*}" value="${1#*=}" file=/etc/samba/smb.conf
		if grep -qE '^;*\s*'"$key" "$file"; then
				sed -i 's|^;*\s*'"$key"'.*|   '"${key% } = ${value# }"'|' "$file"
		else
				sed -i '/\[global\]/a \   '"${key% } = ${value# }" "$file"
		fi
}

### include: add a samba config file include
# Arguments:
#   file) file to import
include() { local includefile="$1" file=/etc/samba/smb.conf
		sed -i "\\|include = $includefile|d" "$file"
		echo "include = $includefile" >> "$file"
}

# create unix and samba users from smbpasswd file
import()
{
	local UNIX_USERS_FILE="$1/passwd" UNIX_GROUPS_FILE="$1/group" SAMBA_USERS_FILE="$1/smbpasswd" username uid

	# read UNIX_USERS_FILE
	while read username uid gid; do

		# find groupname corresponding to gid
		groupname=$(grep ":${gid}:" "${UNIX_GROUPS_FILE}" | sed -E "s/^([a-zA-Z0-9]*):x:[0-9]+:.*$/\1/");

		# TODO : handle unfound groupname

		# create unix group (with correct gid) if it does not exists
		grep -q "^${groupname}:" /etc/group || addgroup -g "${gid}" "${groupname}";

		# check if unix user exists
		if grep -q "^${username}:" /etc/passwd; then
			echo "unix user ${username} already exists"
		else
			# create unix user with correct UID and group, without password and home directory
			adduser -D -H -u "${uid}" -G "${groupname}" "${username}"
		fi

	done < <(cut -d: -f1,3,4 $UNIX_USERS_FILE | sed 's/:/ /g')

	# import samba users database
	pdbedit -i smbpasswd:$SAMBA_USERS_FILE
}

### perms: fix ownership and permissions of share paths
# Arguments:
#   none)
# Return: result
perms() { local i file=/etc/samba/smb.conf
		for i in $(awk -F ' = ' '/   path = / {print $2}' $file); do
				chown -Rh smbuser. $i
				find $i -type d ! -perm 775 -exec chmod 775 {} \;
				find $i -type f ! -perm 0664 -exec chmod 0664 {} \;
		done
}

### recycle: disable recycle bin
# Arguments:
#   none)
# Return: result
recycle() { local file=/etc/samba/smb.conf
		sed -i '/recycle/d; /vfs/d' $file
}

### share: Add share
# Arguments:
#   share) share name
#   path) path to share
#   browsable) 'yes' or 'no'
#   readonly) 'yes' or 'no'
#   guest) 'yes' or 'no'
#   users) list of allowed users
#   admins) list of admin users
#   writelist) list of users that can write to a RO share
#   comment) description of share
# Return: result
share() { local share="$1" path="$2" browsable="${3:-yes}" ro="${4:-yes}" \
								guest="${5:-yes}" users="${6:-""}" admins="${7:-""}" \
								writelist="${8:-""}" comment="${9:-""}" file=/etc/samba/smb.conf
		sed -i "/\\[$share\\]/,/^\$/d" $file
		echo "[$share]" >>$file
		echo "   path = $path" >>$file
		echo "   browsable = $browsable" >>$file
		echo "   read only = $ro" >>$file
		echo "   guest ok = $guest" >>$file
		echo -n "   veto files = /._*/.apdisk/.AppleDouble/.DS_Store/" >>$file
		echo -n ".TemporaryItems/.Trashes/desktop.ini/ehthumbs.db/" >>$file
		echo "Network Trash Folder/Temporary Items/Thumbs.db/" >>$file
		echo "   delete veto files = yes" >>$file
		[[ ${users:-""} && ! ${users:-""} =~ all ]] &&
				echo "   valid users = $(tr ',' ' ' <<< $users)" >>$file
		[[ ${admins:-""} && ! ${admins:-""} =~ none ]] &&
				echo "   admin users = $(tr ',' ' ' <<< $admins)" >>$file
		[[ ${writelist:-""} && ! ${writelist:-""} =~ none ]] &&
				echo "   write list = $(tr ',' ' ' <<< $writelist)" >>$file
		[[ ${comment:-""} && ! ${comment:-""} =~ none ]] &&
				echo "   comment = $(tr ',' ' ' <<< $comment)" >>$file
		echo "" >>$file
		[[ -d $path ]] || mkdir -p $path
}

# disable SMB minimum protocol version conf setting (SMB2 by default)
smb()
{
	local file=/etc/samba/smb.conf
	sed -i '/min protocol/d' $file
}

# create user (unix user + samba user) - default group is users
user()
{
	local username="$1" password="$2" groupname="${3:-"users"}" uid="${4:-""}" sid="${5:-""}" 

	# create unix group if it does not exists
	grep -q "^${groupname}:" /etc/group || addgroup "${groupname}";

	# check if unix user exists
	if grep -q "^${username}:" /etc/passwd; then
		echo "unix user ${username} already exists"
	else
		# create unix user without password and home directory (optional UID)
		adduser -D -H "${uid:+-u $uid}" -G "${groupname}" "${username}"

		# add user to samba internal user DB (optional SID)
		echo -e "$password\n$password" | smbpasswd -s -a "${username}" "${sid:+-U $sid}"

		# enable samba user
		smbpasswd -e "${username}"
	fi
}

### workgroup: set the workgroup
# Arguments:
#   workgroup) the name to set
# Return: configure the correct workgroup
workgroup() { local workgroup="$1" file=/etc/samba/smb.conf
		sed -i 's|^\( *workgroup = \).*|\1'"$workgroup"'|' $file
}

### widelinks: allow access wide symbolic links
# Arguments:
#   none)
# Return: result
widelinks() { local file=/etc/samba/smb.conf \
						replace='\1\n   wide links = yes\n   unix extensions = no'
		sed -i 's/\(follow symlinks = yes\)/'"$replace"'/' $file
}

### usage: Help
# Arguments:
#   none)
# Return: Help text
usage() { local RC="${1:-0}"
		echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
		-h					This help
		-c \"<from:to>\" setup character mapping for file/directory names
								required arg: \"<from:to>\" character mappings separated by ','
		-g \"<parameter>\" Provide global option for smb.conf
										required arg: \"<parameter>\" - IE: -g \"log level = 2\"
		-i \"<path>\" Import users
								required arg: \"<path>\"
								<path> full file path in container to users files directory
		-n					Start the 'nmbd' daemon to advertise the shares
		-p					Set ownership and permissions on the shares
		-r					Disable recycle bin for shares
		-S					Disable SMB minimum protocol version conf setting (SMB2 by default)
		-s \"<name;/path>[;browse;readonly;guest;users;admins;writelist;comment]\"
								Configure a share
								required arg: \"<name>;</path>\"
								<name> is how it's called for clients
								<path> path to share
								NOTE: for the default value, just leave blank
								[browsable] default:'yes' or 'no'
								[readonly] default:'yes' or 'no'
								[guest] allowed default:'yes' or 'no'
								[users] allowed default:'all' or list of allowed users
								[admins] allowed default:'none' or list of admin users
								[writelist] list of users that can write to a RO share
								[comment] description of share
		-u \"<username;password>[;ID;group]\"       Add a user
								required arg: \"<username>;<passwd>\"
								<username> for unix and samba user
								<password> for samba user
								[UID] for unix user
								[group] for unix user (default group is `users`)
								[SID] for samba user
		-w \"<workgroup>\"       Configure the workgroup (domain) samba should use
								required arg: \"<workgroup>\"
								<workgroup> for samba
		-W					Allow access wide symbolic links
		-I					Add an include option at the end of the smb.conf
								required arg: \"<include file path>\"
								<include file path> in the container, e.g. a bind mount

The 'command' (if provided and valid) will be run instead of samba
" >&2
		exit $RC
}

[[ "${USERID:-""}" =~ ^[0-9]+$ ]] && usermod -u $USERID -o smbuser
[[ "${GROUPID:-""}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o users

while getopts ":hc:g:i:nprs:Su:Ww:I:" opt; do
		case "$opt" in
				h) usage ;;
				c) charmap "$OPTARG" ;;
				g) global "$OPTARG" ;;
				i) import "$OPTARG" ;;
				n) NMBD="true" ;;
				p) PERMISSIONS="true" ;;
				r) recycle ;;
				s) eval share $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< $OPTARG) ;;
				S) smb ;;
				u) eval user $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< $OPTARG) ;;
				w) workgroup "$OPTARG" ;;
				W) widelinks ;;
				I) include "$OPTARG" ;;
				"?") echo "Unknown option: -$OPTARG"; usage 1 ;;
				":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
		esac
done
shift $(( OPTIND - 1 ))

[[ "${CHARMAP:-""}" ]] && charmap "$CHARMAP"
[[ "${GLOBAL:-""}" ]] && global "$GLOBAL"
[[ "${IMPORT:-""}" ]] && import "$IMPORT"
[[ "${PERMISSIONS:-""}" ]] && perms
[[ "${RECYCLE:-""}" ]] && recycle
[[ "${SHARE:-""}" ]] && eval share $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< $SHARE)
[[ "${SMB:-""}" ]] && smb
[[ "${USER:-""}" ]] && eval user $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< $USER)
[[ "${WORKGROUP:-""}" ]] && workgroup "$WORKGROUP"
[[ "${WIDELINKS:-""}" ]] && widelinks
[[ "${INCLUDE:-""}" ]] && include "$INCLUDE"

if [[ $# -ge 1 && -x $(which $1 2>&-) ]]; then
		exec "$@"
elif [[ $# -ge 1 ]]; then
		echo "ERROR: command not found: $1"
		exit 13
elif ps -ef | egrep -v grep | grep -q smbd; then
		echo "Service already running, please restart container to apply changes"
else
		[[ ${NMBD:-""} ]] && ionice -c 3 nmbd -D
		exec ionice -c 3 smbd -FS --no-process-group </dev/null
fi