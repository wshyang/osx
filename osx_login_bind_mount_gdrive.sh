#!/bin/bash
set -o xtrace


# abspath $dirname -- Hacky workaround function due to absence of abspath 
# 					  on OS X. Macs come with perl preinstalled though!
function abspath {
	local ABSPATH=$(perl -MCwd=realpath -e "print realpath '$1'")
	echo "$ABSPATH"
}

# test_mount $dirname -- Tests if specified directory is currently a mount point
#                        for another file system. Returns 1 if true.
function test_mount {
	local ABSPATH=$(abspath "$1")
	local MOUNT=""
	mount | sed 's/^.*on \//\//' | sed 's/(.*)$//' | while read -r MOUNT; do
		if [ "$ABSPATH" == "$MOUNT" ]; then
			return 1
			break;
		fi
	done
}

# gdrive_mount $dirname1 $dirname2 -- Bind mounts directory in current user's home (dirname1) to subdirectory
#                                     located within current user's gdrive directory.
function gdrive_mount {
	local RELMOUNTPOINT=$1
	local MOUNTPOINT=$(abspath "$RELMOUNTPOINT")
	local GDRIVEREL=$2
	local GDRIVEDIR="$GDRIVEDIR/$GDRIVEREL"
	
	# ensure mount point is not currently used
	test_mount "$MOUNTPOINT"
	if [ $? == 1 ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Mount point in use: ${MOUNTPOINT}\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	
	# move existing files in without overwriting
	mv -nv "$MOUNTPOINT"/* "$GDRIVEDIR"
	
	# performs the actual bind mount
	if [ $LOGINHOOK ]; then
		$BINDFS --create-for-user=$LOGINUSER --chown-deny --chmod-normal --xattr-none "$GDRIVEDIR" "$MOUNTPOINT"
	else
		$BINDFS "$GDRIVEDIR" "$MOUNTPOINT"
	fi
	BINDFSRV=$?
	if [ $BINDFSRV != 0 ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Failed to bind ${MOUNTPOINT}: abnormal return value $BINDFSRV\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	
	# now verifies that the bind mount operation is successful :)
	test_mount "$MOUNTPOINT"
	if [ $? != 1 ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Bind mount not successful: ${MOUNTPOINT} not bound\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	return 1
}

BINDFS=`which bindfs`
if [ $? != 0 ]; then
	osascript -e "tell application \"System Events\" to display dialog \"bindfs not found in path\" buttons \"OK\" default button 1 with title \"Error\""
	exit 1
fi

USERHOME=${HOME}
LOGINUSER=$(whoami)
LOGINHOOK=0
if [ $1 -ne "" ] && [ $(whoami) -eq 'root' ] ; then
	# script is being run as a login hook
	LOGINHOOK=1
	LOGINUSER=$1
	USERHOME="/Users/${LOGINUSER}"
fi
	
	
GDRIVEDIR="${USERHOME}/Google Drive"
if [ ! -e "$GDRIVEDIR" ] || [ ! -d "$GDRIVEDIR" ]; then
	osascript -e "tell application \"System Events\" to display dialog \"Google Drive folder not set up at default location\" buttons \"OK\" default button 1 with title \"Error\""
	exit 1
fi

cd $USERHOME
gdrive_mount "Documents" "Documents"