#!/usr/bin/env bash

clear

# Define colors to be used when echoing output
NC=`tput sgr0`
BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`
BOLD=`tput bold`

DISKS=$(lsblk -io KNAME,TRAN | grep sata | awk '{print $1}') # kernel name & transfer type
LOG="/tmp/$(basename $0)-$(date '+%Y-%m-%d').log"

usage () {
    echo -n "
$SCRIPTNAME [OPTION]

This script must be run with one of the following options.

Options:
  -a, --automate	Automate all disk wiping commands with no need for user input
  -i, --interactive	Query user for each command before running it.

"
}

# make log more readable
logentry () {
    echo "" >> "$LOG";
    echo "DATE: "$(date "+%A %d %B %Y") >> "$LOG";
    echo "TIME: "$(date "+%H:%M:%S") >> "$LOG";
    echo "OUTPUT FROM DISK_NUKEM.SH EXECUTION:" >> "$LOG"
    echo "" >> "$LOG";
}

# query power adapter presence. use wildcard as different adapters have different names...
powercheck () {
    until grep -q on-line /proc/acpi/ac_adapter/*/state; do
	echo -ne "${BOLD}${RED}NO AC ADAPTER DETECTED. CONNECT TO AC TO CONTINUE....${NC}"\\r
    done
    # I'm pretty sure it's not possible to ctrl-c out of the loop (but
    # not the script) without adding a trap, but better safe than
    # sorry!
    if grep -q on-line /proc/acpi/ac_adapter/*/state; then
	return 0
    else
	echo
	echo "${BOLD}${RED}YOU SNEAKY BUGGER! ABORTING.${NC}"
	echo
	exit 1
    fi
}

# give before an after feedback on state of disk
echopart () {
    echo
    echo "${BOLD}${GREEN}Partition Table:${NC}"
    echo "${BOLD}${GREEN}"
    echo "DISK DETAILS:" >> "$LOG" 2>&1
    echo >> "$LOG" 2>&1
    lsblk -o NAME,FSTYPE,LABEL,SIZE /dev/$1 | tee -a "$LOG"
    echo >> "$LOG" 2>&1
    echo -n "${NC}"
}

# infinite loop to get simple user input
ask () {
    while :
    do
	# -e for readline bindings, -n 1 for execution without return
	read -e -n 1 -p "$1" ans;
	case $ans in
	    [yY]*)
		return 0
		break
		;;
	    [nN]*)
		return 1
		break
		;;
	    [qQ]*)
		exit 1
		break
		;;
	    *)
		echo
		echo "${BOLD}${RED}Enter y or n, q to quit.${NC}";
		echo
		;;
	esac;
    done
}

# sgdisk wrapper to destroy partition table data structures
zap () {
    powercheck
    echo
    echo "${BOLD}${YELLOW}Zapping partition table...${NC}"
    sgdisk --zap-all /dev/$1 >> "$LOG" 2>&1
    # esoteric partition tables can leave disk in weird state when
    # only run once...
    sgdisk --zap-all /dev/$1 >> "$LOG" 2>&1
}

zero () {
    powercheck
    echo
    echo "${BOLD}${YELLOW}Zeroing first and last MB...${NC}"
    size=$(blockdev --getsz /dev/$1) # size in 512 blocks of disk
    # zero out first MB of disk
    dd if=/dev/zero of=/dev/$1 bs=512 count=2048 >> "$LOG" 2>&1
    # zero out last MB of disk
    dd if=/dev/zero of=/dev/$1 bs=512 count=2048 seek=$((size - 2048)) >> "$LOG" 2>&1
}

# use dcfldd as it provides nice progress feedback unlike dd
random () {
    powercheck
    echo
    echo "${BOLD}${YELLOW}Writing 2GB of random data...${NC}"
    echo "${BOLD}${GREEN}"
    # urandom faster but less cryptographically secure
    dcfldd if=/dev/urandom of=/dev/$1 bs=1M count=2048
    echo -n "${NC}"
}

nuke () {
    powercheck
    echo
    echo "${BOLD}${MAGENTA}This will take a really long time...${NC}"
    echo
    if ask "${BOLD}${CYAN}Are you sure you want to continue? ${NC}"; then
	echo
	echo "${BOLD}${YELLOW}Nuking disk...${NC}"
	echo "${BOLD}${GREEN}"
	# urandom faster but less cryptographically secure
	dcfldd if=/dev/urandom of=/dev/$1 bs=4M
	echo -n "${NC}"
    else
	echo
	echo "${BOLD}${MAGENTA}Aborting disk nuke.${NC}"
    fi
}

# check if type of erase is supported.
support () {
    if hdparm -I /dev/"$1" | egrep -q "not.*supported.*$2.*erase"; then
	echo
	echo "${BOLD}${MAGENTA}Skipping $2 erase. Not supported..${NC}"
	return 1
    else
	return 0
    fi
}

# Many BIOSes will protect your disks if you have a password set
# (security enabled) by issuing a SECURITY FREEZE command before
# booting an operating system.
#
# Only suspend or hotplugging the disk unfreezes the state of the
# disk. Hotplugging with a bash script is beyond my skillset! ;-)
frozen () {
    if [ $(hdparm -I /dev/$1 | awk '!/not/ && /frozen/') ]; then
	echo
	echo "${BOLD}${YELLOW}Disk is frozen. Suspending to unfreeze disk...${NC}"
	sleep 2
	rtcwake -m mem -s 2 >> "$LOG" 2>&1 & # automate resume from suspend :-) how cool is that?!
	wait $!
	if [ $? -ne 0 ]; then
	    echo
	    echo "${BOLD}${RED}Suspend failed.${NC}"
	    return 1
	else
	    echo
	    echo "${BOLD}${YELLOW}Suspend worked. Checking disk status...${NC}"
	    if  frozen "$1"; then
		return 0;
	    else
		echo
		echo "${BOLD}${RED}Unfreezing failed.${NC}"
		return 1
	    fi
	fi
    else
	echo
	echo "${BOLD}${CYAN}Disk not frozen."
	return 0
    fi
}

ssderase () {
    # get time estimate
    if [ "$2" == "secure" ]; then
	time=$(hdparm -I /dev/"$1" | awk -F. '/SECURITY ERASE/{print $1}' | sed 's/[^0-9]//g') # should be possible just with awk...
	erasetype="erase"
    elif [ "$2" == "enhanced" ]; then
	time=$(hdparm -I /dev/"$1" | awk -F. '/SECURITY ERASE/{print $2}' | sed 's/[^0-9]//g')
	erasetype="erase-enhanced"
    fi
    powercheck
    echo
    echo "${BOLD}${YELLOW}This may take up to $time minutes...${NC}"
    echo
    echo "${BOLD}${RED}DO NOT EXIT OR SHUTDOWN UNTIL THIS FINISHES!${NC}"
    hdparm --user-master u --security-set-pass PasSWorD /dev/"$1" >> "$LOG" 2>&1
    hdparm --user-master u --security-"$erasetype" PasSWorD /dev/"$1" >> "$LOG" 2>&1 &
    hdparm_pid=$!

    # https://stackoverflow.com/questions/12498304/using-bash-to-display-a-progress-working-indicator
    if [ "$time" -gt 2 ]; then
	spin='-\|/'
	i=0
	echo
	while kill -0 $hdparm_pid 2>/dev/null
	do
	    i=$(( (i+1) %4 ))
	    printf "${BOLD}${YELLOW}\rErasing SSD: ${spin:$i:1}"
	    sleep .1
	done
    fi
    echo "${NC}"

    wait $hdparm_pid
    if [ $? -eq 0 ]; then
	echo "${BOLD}${CYAN}Erase succeeded.${NC}"
    else
	echo "${BOLD}${RED}Erase failed.${NC}"
    fi
}

ssdcheck () {
    if support "$1" "secure"; then
	if frozen "$1"; then
	    ssderase "$1" "secure"
	fi
    fi
    if support "$1" "enhanced"; then
	if frozen "$1"; then
	    ssderase "$1" "enhanced"
	fi
    fi
}

powertimer () {
    poweroff -f -d "$1" > /dev/null 2>&1 &
    powerpid=$!
    clear

    echo
    echo "${BOLD}${CYAN}Wiping complete. Powering off in ${YELLOW}$1${CYAN} seconds. ${NC}"
    echo

    while :
    do
	read -e -n 1 -p "${BOLD}${MAGENTA}Enter c to cancel, q to shutdown now.${NC} " input
	case "$input" in
	    [cC])
		clear
		kill $powerpid
		exit 0
		;;
	    [qQ])
		clear
		kill $powerpid
		poweroff -f > /dev/null 2>&1 &
		;;
	    *)
		echo
		echo "${BOLD}${RED}Invalid character.${NP}"
		echo
		;;
	esac
    done
}

logentry

case "$1" in
    -a|--automate)
	for disk in "${DISKS[@]}"; do
	    powercheck
	    echo
	    echo "${BOLD}${CYAN}Found internal disk at /dev/$disk${NC}"
	    zap "$disk"
	    zero "$disk"
	    random "$disk"
	    type=$(cat /sys/block/$disk/queue/rotational)
	    if [ "$type" -eq 0 ]; then
		echo
		echo "${CYAN}${BOLD}SSD detected. Attempting to clear memory cells...${NC}"
		ssdcheck "$disk"
	    fi
	    powertimer 5
	done
	;;
    -i|--interactive)
	for disk in "${DISKS[@]}"; do
	    powercheck
	    echo
	    echo "${BOLD}${CYAN}Found internal disk at /dev/$disk${NC}"
	    echopart "$disk"

	    echo
	    if ask "${BOLD}${CYAN}Zap partition table? ${NC}"; then
		zap "$disk"
	    else
		echo
		echo "${BOLD}${MAGENTA}Not zapping partition table.${NC}"
	    fi

	    echo
	    if ask "${BOLD}${CYAN}Zero first and last 1MB? ${NC}"; then
		zero "$disk"
	    else
		echo
		echo "${BOLD}${MAGENTA}Not zeroing first and last 1MB.${NC}"
	    fi

	    echo
	    if ask "${BOLD}${CYAN}Write 2GB of random data? ${NC}"; then
		random "$disk"
	    else
		echo
		echo "${BOLD}${MAGENTA}Not writing 2GB of random data.${NC}"
	    fi

	    echo
	    if ask "${BOLD}${CYAN}Write random data to whole disk? ${NC}"; then
		nuke "$disk"
	    else
		echo
		echo "${BOLD}${MAGENTA}Not nuking disk from orbit!${NC}"
	    fi

	    type=$(cat /sys/block/$disk/queue/rotational) # get disk type

	    if [ "$type" -eq 0 ]; then
		echo
		if ask "${BOLD}${CYAN}SSD detected. Clear memory cells? ${NC}"; then
		    ssdcheck "$disk"
		else
		    echo
		    echo "${BOLD}${MAGENTA}Not clearing memory cells.${NC}"
		fi
	    fi
	    echopart "$disk"
	    powertimer 60
	done
	;;
    -h|--help)
	usage
	;;
    *)
	usage
	;;
esac
