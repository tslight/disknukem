#!/bin/bash
cat << "EOF"
				  ____
		     ____  , -- -        ---   -.
		  (((   ((  ///   //   '  \\-\ \  )) ))
	      ///    ///  (( _        _   -- \\--     \\\ \)
	   ((( ==  ((  -- ((             ))  )- ) __   ))  )))
	    ((  (( -=   ((  ---  (          _ ) ---  ))   ))
	       (( __ ((    ()(((  \\  / ///     )) __ )))
		      \\_ (( __  |     | __  ) _ ))
				,|  |  |
			       `-._____,-'
			       `--.___,--'   [INSERT DUKE NUKEM
				 |     |      FOREVER JOKE HERE]
				 |    ||
				 | ||  |
		       ,    _,   |   | |
	      (  ((  ((((  /,| __|     |  ))))  )))  )  ))
	    (()))       __/ ||(    ,,     ((//\     )     ))))
---------((( ///_.___ _/    ||,,_____,_,,, (|\ \___.....__..  ))------ool
		 ____/      |/______________| \/_/\__
		/                                \/_/|
	       /  |___|___|__                        ||     ___
	       \    |___|___|_                       |/\   /__/|
	       /      |   |                           \/   |__|/
EOF

nukem () {
    printf "\nI'll be done with you and still have time to watch Oprah!\n";
    printf "\nNuke 'em 'till they glow, then shoot 'em in the dark!\n";

    apfs=$(diskutil list internal | grep synthesized | cut -f 1 -d " ");

    if [ -z "apfs" ]; then
	printf "\nUnmounting disk....\n";
	diskutil unmountDisk force $1;

	printf "\nZeroing first megabyte of drive....\n"
	dd if=/dev/zero of=$1 bs=1k count=1024;

	printf "\nFormatting drive....\n";
	diskutil eraseDisk HFS+ "Macintosh HD" $1;

	printf "\nDisk Nukem has sucessfully nuked your disk!\n";
	printf "\nHere is your shiny new partition table :-)\n";
	diskutil list $1
    else
	printf "\nUnmounting disk....\n";
	diskutil unmountDisk force $apfs;

	printf "\nDeleting APFS Container\n";
	diskutil apfs deleteContainer $apfs;

	printf "\nFormatting drive....\n";
	diskutil eraseDisk HFS+ "Macintosh HD" $1;

	printf "\nDisk Nukem has sucessfully nuked your disk!\n";
	printf "\nHere is your shiny new partition table :-)\n";
	diskutil list $1
    fi;
}

ask () {
    printf '\nBelow is the output of diskutil list on '$1':\n\n';
    diskutil list $1;
    printf '\nDo you really want to nuke '$1'?\n\n';
    read -p 'Y or N? ' wipeq;
    case "$wipeq" in
	[yY])
	    nukem $1
	    ;;
	[nN])
	    echo "\nNot Nuking Disk. Disk Nukem is sad :-(\n";
	    ;;
	*)
	    echo "\nYou're wrong, Proton breath. Invalid Input. Aborting.\n";
	    break;
	    ;;
    esac;
}

#disks=(`ls -r /dev/disk* | grep -v "s[0-9]"`);
disks=(`diskutil list internal physical | cut -f 1 -d " " | sed '/^$/d'`);

for i in "${disks[@]}"; do
    found=$(diskutil list $i | egrep -i "Apple_APFS|CoreStorage|Logical\ Volume");
    case $found in
	*"Apple_APFS"*)
	    printf '\nAPFS Container detected on '$i'\n';
	    ask $i;
	    ;;
	*"CoreStorage"*)
	    printf '\nCoreStorage Container detected on '$i'\n';
	    ask $i;
	    ;;
	*"Logical Volume"*)
	    printf '\nLogical Volume detected on '$i'\n';
	    ask $i;
	    ;;
	*)
	    printf '\nNo Logical Volumes, CoreStorage Containers or APFS Slices on '$i'\n';
	    ;;
    esac;
done
