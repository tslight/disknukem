#!/bin/bash

# set some booleans, to produce terse error messages.

ERROR=false;
NUKED=false;

# logfile variable, may be better to send to tmp dir instead...

LOG="/tmp/$(basename $0)-$(date '+%Y-%m-%d').log"

# choose which kind of disk we should look for, can be set to external.

DISKTYPE=internal;

# create an array of disks of the type specified above.

DISKARRAY=$(diskutil list $DISKTYPE | cut -f 1 -d " " | sed '/^$/d');

# function that creates a break in the logfile, so we can discern,
# which log was for which execution.

log_entry () {
    echo "" >> $LOG;
    echo "DATE: "$(date "+%A %d %B %Y") >> $LOG;
    echo "TIME: "$(date "+%H:%M:%S") >> $LOG;
    echo "Output from $(basename $0) execution:" >> $LOG
    echo "" >> $LOG;
}

# function to ask whether or not we really want to nuke the
# disk. takes the disk path as an argument and returns true if y is
# entered, false if n is entered and continues to reprompt if any
# other letter is entered.

ask () {
    printf '\nBelow is the output of diskutil list on '$1':\n\n';
    diskutil list $1;
    printf '\nDo you really want to nuke '$1'?\n\n';
    read -p 'Y or N? ' wipeq;
    until [ $wipeq == [yY] ] || [ $wipeq == [nN] ]; do
	case "$wipeq" in
	    [yY])
		return 0
		;;
	    [nN])
		return 1
		;;
	    *)
		printf "\nYou're wrong, Proton breath.\n\n";
		read -p 'Y or N? ' wipeq;
		;;
	esac;
    done
}

# Main loop of the program. Iterates over array of disks and sets a
# found flag containing a grepped string which identifys whether or
# not the output of diskutil contains certain identifying strings.

# Based on the content of $found, we call the ask function, and if
# that function returns true, we set the nuked bool to true & carry
# out the appropriate diskutil erase commands.

# We send the output of these commands to the logfile, and check if
# they completed sucessfully, if they did not, we set the error bool
# to true.

for i in "${DISKARRAY[@]}"; do
    found=$(diskutil list $i | egrep -i "APFS\ Container\ Scheme|Encrypted");
    case $found in
	*"APFS Container Scheme"*)
	    log_entry;
	    container=$(diskutil list $i | grep "Physical Store" | cut -c49-53);
	    printf '\nAPFS Container detected on '$i'\n';
	    if ask $i; then
		NUKED=true;
		printf '\nNUKEING...(this may take a minute...)\n\n';
		! $(diskutil apfs deleteContainer $i >> $LOG) && ERROR=true;
		! $(diskutil eraseDisk HFS+ "Macintosh HD" $container >> $LOG) && ERROR=true;
	    else
		NUKED=false;
		printf '\nNOT NUKEING... Disk Nukem is :-(\n\n';
	    fi
	    ;;
	*"Encrypted"*)
	    log_entry;
	    csdisk=$(diskutil list $i | grep "Logical Volume on disk" | cut -c52-56);
	    printf '\nOnline Encrypted Logical Volume detected on '$i'\n';
	    if ask $i; then
		NUKED=true;
		printf '\nNUKEING...(this may take a minute...)\n\n';
		! $(diskutil cs deleteVolume $i >> $LOG) && ERROR=true;
		! $(diskutil eraseDisk HFS+ "Macintosh HD" $csdisk >> $LOG) && ERROR=true;
	    else
		NUKED=false;
		printf '\nNOT NUKEING... Disk Nukem is :-(\n\n';
	    fi
	    ;;
	*)
	    ;;
    esac;
done

# We now need to find out if anything went wrong based on the state of
# the error and nuked booleans, and provide user feedback.

if [ "$ERROR" = true ] && [ "$NUKED" = true ]; then
    printf 'UH OH! Something went awry. Please see the log file.\n\n';
elif [ "$ERROR" = false ] && [ "$NUKED" = true ]; then
    printf "Disk Nukem has sucessfully nuked your irksome disks!\n\n";
    printf 'Here is the diskutil listing of all '$DISKTYPE' disks:\n\n';
    diskutil list $DISKTYPE;
fi

# Finally if no string was found in our loop we can inform the user.

if [ -z "${found// }" ]; then
    printf '\nNo APFS or Online Encrypted devices detected on '$DISKTYPE' devices.\n\n';
fi
