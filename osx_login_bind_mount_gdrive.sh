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
	local GDRIVEABS="$GDRIVEDIR/$GDRIVEREL"
	bindmount "$MOUNTPOINT" "$GDRIVEABS"
}

# bindmount $dirname1 $dirname2 -- Utility function that does the actual checking and bind mounting.
function bindmount {
	
	local MOUNTPOINT=$1
	local TARGET=$2
	
	# check if mount point actually exists
	if [ ! -e "$MOUNTPOINT" ] || [ ! -d "$MOUNTPOINT" ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Mount point does not exist: ${MOUNTPOINT}\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	
	# ensure mount point is not currently used
	test_mount "$MOUNTPOINT"
	if [ $? -eq 1 ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Mount point in use: ${MOUNTPOINT}\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	
	# checks if the directory we are going to bind also exists
	if [ ! -e "$TARGET" ]; then
		if [ $LOGINHOOK ]; then
			su woei -c "mkdir -p \"$TARGET\""
		else
			mkdir -p "$TARGET"
		fi
	fi
	
	# move existing files in without overwriting
	if [ $LOGINHOOK ]; then
		su woei -c "mv -nv \"$MOUNTPOINT\"/* \"$TARGET\""
	else
		mv -nv "$MOUNTPOINT"/* "$TARGET"
	fi
	
	local BASENAMETGT=$(basename "$TARGET")
	local BASENAMEMPT=$(basename "$MOUNTPOINT")
	local VOLNAME="$BASENAMEMPT"
	
	# performs the actual bind mount
	if [ $LOGINHOOK ]; then
		# $BINDFS --create-for-user=$LOGINUSER --chown-deny --chmod-normal --xattr-none -o noappledouble -o noapplexattr -o volname="$VOLNAME" "$TARGET" "$MOUNTPOINT"
		$BINDFS --create-for-user=$LOGINUSER --chown-deny --chmod-normal --xattr-none -o noappledouble -o noapplexattr -o volname="$VOLNAME" "$TARGET" "$MOUNTPOINT"
	else
		$BINDFS --chown-deny --chmod-normal --xattr-none -o noappledouble -o noapplexattr -o volname="$VOLNAME" "$TARGET" "$MOUNTPOINT"
	fi
	local BINDFSRV=$?
	if [ $BINDFSRV != 0 ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Failed to bind ${MOUNTPOINT}: abnormal return value $BINDFSRV\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	
	# now verifies that the bind mount operation is successful :)
	test_mount "$MOUNTPOINT"
	if [ $? -ne 1 ]; then
		osascript -e "tell application \"System Events\" to display dialog \"Bind mount not successful: ${MOUNTPOINT} not bound\" buttons \"OK\" default button 1 with title \"Error\""
		return 0
	fi
	return 1
}

function symlink {
	local SOURCE=$1
	local TARGET=$2
	
	# if the source is already a symlink, then we can skip it
	if [ -L "$SOURCE" ]; then
		return 0;
	fi
	
	# checks to see if source exists first, backs it up if so
	if [ -e "$SOURCE" ]; then
		local SOURCEBACKUP="$SOURCE.bak"
		mv "$SOURCE" "$SOURCEBACKUP"
		if [ -d "$SOURCEBACKUP" ]; then
			mv -nv "$SOURCEBACKUP"/* "$TARGET"
		elif [ -f "$SOURCEBACKUP" ]; then
			mv -nv "$SOURCEBACKUP" "$TARGET"
		fi
	fi
	
	ln -s "$TARGET" "$SOURCE"
	if [ $? -ne 0 ]; then
		return 0;
	else
		return 1
	fi
}


BINDFS=`which bindfs`
if [ $? -ne 0 ]; then
	osascript -e "tell application \"System Events\" to display dialog \"bindfs not found in path\" buttons \"OK\" default button 1 with title \"Error\""
	exit 1
fi

USERHOME=${HOME}
LOGINUSER=$(whoami)
LOGINHOOK=0
if [ "$1" != "" ] && [ "$(whoami)" == 'root' ] ; then
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
gdrive_mount "Pictures" "Pictures"
gdrive_mount "Library/Application Support/Adium 2.0/Users/Default/Logs" "Misc/Mac/Adium 2.0/Logs"
gdrive_mount "Library/Application Support/Typinator" "Misc/Mac/Typinator"
gdrive_mount "Library/Application Support/Hazel"  "Misc/Mac/Hazel"
gdrive_mount ".ssh"  "Misc/Mac/.ssh"
bindmount "$USERHOME/Library/Saved Application State" "/tmp"
symlink "$USERHOME/.sleep" "$USERHOME/Google Drive/Misc/Mac/sleepwatcher/.sleep"