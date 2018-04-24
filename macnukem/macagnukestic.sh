#!/bin/bash
DISKTYPE=internal;
DISKARRAY=(`diskutil list $DISKTYPE | awk '{print $1}' | grep "/dev/"`);

for i in "${DISKARRAY[@]}"; do
    found=$(diskutil list $i | egrep "APFS\ Container\ Scheme|CoreStorage");
    case $found in
	*"APFS Container Scheme"*)
	    printf 'APFS Container found on '$i' - NUKEING!\n';
	    diskutil apfs deleteContainer $i "Macintosh HD";
	    ;;
	*"CoreStorage"*)
	    if diskutil cs list | grep -iq "encryption"; then
		printf 'Encrypted volume found on '$i' - NUKEING!\n';
		diskutil unmountDisk force $i;
		diskutil eraseDisk JHFS+ "Macintosh HD" $i;
	    else
		found="";
	    fi
	    ;;
	*)
	    printf 'No APFS Container or encrypted volume found on '$i'\n';
	    ;;
    esac;
done
