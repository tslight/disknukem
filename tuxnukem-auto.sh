#!/usr/bin/env bash

# N.B. tuxnukem.sh is much better commented!!!

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

DISKS=$(lsblk -io KNAME,TRAN | grep sata | awk '{print $1}')
LOG="/tmp/$(basename $0)-$(date '+%Y-%m-%d').log"

logentry () {
    echo "" >> "$LOG";
    echo "DATE: "$(date "+%A %d %B %Y") >> "$LOG";
    echo "TIME: "$(date "+%H:%M:%S") >> "$LOG";
    echo "Output from $(basename $0) execution:" >> "$LOG"
    echo "" >> "$LOG";
}

powercheck () {
    until grep -q on-line /proc/acpi/ac_adapter/*/state; do
	echo -ne "${BOLD}${RED}NO AC ADAPTER DETECTED. CONNECT TO AC TO CONTINUE....${NC}"\\r
    done
    if grep -q on-line /proc/acpi/ac_adapter/*/state; then
	return 0
    else
	echo
	echo "${BOLD}${RED}YOU SNEAKY BUGGER! ABORTING.${NC}"
	echo
	exit 1
    fi
}

zap () {
    powercheck
    echo
    echo "${BOLD}${YELLOW}Zapping partition table...${NC}"
    sgdisk --zap-all /dev/$1 >> "$LOG" 2>&1
    # I'm OCD... and sometimes sgdisk spams an error message...
    sgdisk --zap-all /dev/$1 >> "$LOG" 2>&1
}

zero () {
    powercheck
    echo
    echo "${BOLD}${YELLOW}Zeroing first and last MB...${NC}"
    size=$(blockdev --getsz /dev/$1) # size in 512 blocks of drive
    # zero out first MB of drive
    dd if=/dev/zero of=/dev/$1 bs=512 count=2048 >> "$LOG" 2>&1
    # zero out last MB of drive
    dd if=/dev/zero of=/dev/$1 bs=512 count=2048 seek=$((size - 2048)) >> "$LOG" 2>&1
}

random () {
    powercheck
    echo
    echo "${BOLD}${YELLOW}Writing 2GB of random data...${NC}"
    echo "${BOLD}${GREEN}"
    # urandom faster but less cryptographically secure
    dcfldd if=/dev/urandom of=/dev/$1 bs=1M count=2048
    echo -n "${NC}"
}

support () {
    echo
    echo "${BOLD}${YELLOW}Checking for $2 erase support...${NC}"
    if hdparm -I /dev/"$1" | egrep -q "not.*supported.*$2.*erase"; then
	echo
	echo "${BOLD}${MAGENTA}Skipping $2 erase. Not supported..${NC}"
	return 1
    else
	echo
	echo "${BOLD}${YELLOW}$2 erase supported. Continuing...${NC}"
	return 0
    fi
}

# Many BIOSes will protect your drives if you have a password set
# (security enabled) by issuing a SECURITY FREEZE command before
# booting an operating system.
#
# Only suspend or hotplugging the drive unfreezes the state of the
# drive. Hotplugging with a bash script is beyond my skillset! ;-)
frozen () {
    echo
    echo "${BOLD}${YELLOW}Checking whether or not disk is frozen...${NC}"
    if [ $(hdparm -I /dev/$1 | awk '!/not/ && /frozen/') ]; then
	echo
	echo "${BOLD}${YELLOW}Disk frozen. Suspending to unfreeze...${NC}"
	rtcwake -m mem -s 3 >> "$LOG" 2>&1 & # automate resume from suspend :-) how cool is that?!
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
    powercheck
    if [ "$2" == "secure" ]; then
	time=$(hdparm -I /dev/"$1" | awk -F. '/SECURITY ERASE/{print $1}' | sed 's/[^0-9]//g')
	erasetype="erase"
    elif [ "$2" == "enhanced" ]; then
	time=$(hdparm -I /dev/"$1" | awk -F. '/SECURITY ERASE/{print $2}' | sed 's/[^0-9]//g')
	erasetype="erase-enhanced"
    fi
    echo
    echo "${BOLD}${MAGENTA}This may take up to $time minutes...${NC}"
    echo
    echo "${BOLD}${YELLOW}Starting $2 erase...${NC}"
    echo
    echo "${BOLD}${RED}DO NOT EXIT OR SHUTDOWN UNTIL THIS FINISHES!${NC}"
    hdparm --user-master u --security-set-pass PasSWorD /dev/"$1" >> "$LOG" 2>&1
    hdparm --user-master u --security-"$erasetype" PasSWorD /dev/"$1" >> "$LOG" 2>&1 &
    wait $!
    if [ $? -eq 0 ]; then
	echo
	echo "${BOLD}${CYAN}$2 erase succeeded.${NC}"
    else
	echo
	echo "${BOLD}${RED}$2 erase failed.${NC}"
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

logentry
clear

for disk in "${DISKS[@]}"; do
    powercheck
    echo
    echo "${BOLD}${CYAN}Found internal drive at /dev/$disk${NC}"
    zap "$disk"
    zero "$disk"
    random "$disk"
    type=$(cat /sys/block/$disk/queue/rotational)
    if [ "$type" -eq 0 ]; then
	echo
	echo "${CYAN}${BOLD}SSD detected. Attempting to clear memory cells...${NC}"
	ssdcheck "$disk"
    fi
    echo
    echo "${BOLD}${CYAN}Disk nuking complete. Shutting down.${NC}"
done

clear
poweroff
