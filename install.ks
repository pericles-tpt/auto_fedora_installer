%pre
#!/bin/sh
# 1. Get the target drive
TARGET_DISK=""
echo "Which disk would you like to install to? Provide the 'ID' of the target:"

LIST_DISKS_OUT=$(
# FN_LIST_DISKS
echo "$(printf "%-8s\t%4s\t%8s\t%5s\t%s\n" "ID" "TYPE" "CAPACITY" "%USED" "MODEL")"
lsblk | grep disk | while read j; do	
	id=$(echo $j | awk '{print $1}')
	size=$(echo $j | awk '{print $4}')

	if [ $size = "0B" ]; then
		continue
	fi
	totalSizeBytes=$(fdisk -l "/dev/$id" | head -n 1 | awk '{print int($5)}')
	freeBytes=$(sfdisk --list-free "/dev/$id" | head -n 1 | awk '{print int($6)}')
	usedBytes=$((totalSizeBytes - freeBytes))
	capacityUsedPc="?"
	if [ $usedBytes -ge 0 ]; then
		capacityUsedPc=$(echo "scale=3; (($usedBytes/$totalSizeBytes) * 100)" | bc | awk '{printf "%.1f", $1}')
	fi

	maybe_model=""
	if [ -e "/sys/class/block/$id/device/model" ]; then
		maybe_model=$(cat /sys/class/block/"$id"/device/model | tr -d ' ')
	fi
	model="?"
	if [ "$maybe_model" != "" ]; then
		model="$maybe_model"
	fi
	type="?"
	if [ $(find /dev/disk/by-id/ -lname "*""$id" | grep usb | wc -l) -gt 0 ]; then 
		type="USB"
	else
		case "$id" in
			"sda"*)
				type="SATA";;
			"mmc"*)
				type="SD";;
			"nvme"*)
				type="NVME";;
			*)
				;;
		esac							
	fi
	echo "$(printf "%-8s\t%-4s\t%8s\t%5s\t%s\n" "$id" "$type" "$size" "$capacityUsedPc" "$model")"
done
)
echo "$LIST_DISKS_OUT"

VALID_DISKS_LIST=$(echo "$LIST_DISKS_OUT" | tail -n +2 | awk '{print $1}')

TARGET_VALID=0
while [ $TARGET_VALID -eq 0 ]; do
	IFS='|' read TARGET_DISK < <( zenity --entry --text="Provide the 'ID' of the target disk" )
	TARGET_VALID=$(echo "$VALID_DISKS_LIST" | grep "^${TARGET_DISK}$" | wc -l)
	if [ $TARGET_VALID -gt 0 ]
	then
		break
	fi
	echo "! invalid disk: Type an id from the list above should look similar to 'sdX', 'nvmeX', etc"
done

# 2. Prompt user for them to decide whether to wipe the disk or not
WIPE_TARGET=0
echo "Would you like to wipe '$TARGET_DISK'? Will use remaining capacity otherwise [Y/n]"
WIPE_TARGET=$(FN_PROMPT_YN)
%end


%post
FN_TEST_WIFI(){
	ifaces=$(ip addr | grep ': <' | sed 's/://' | awk '{print $2}' | tr -d ':')

	fail_iface=0
	total_iface=0
	WIFI_FOUND_IFACE=""

	if [ "$WIFI_SSID" = "" ] || [ "$WIFI_PASS" = "" ]
	then
		echo "WARNING: WiFi credentials not set, if you wish to setup wifi, restart this script"
	else
		for i in $ifaces; do
			total_iface=$((total_iface+1))
			con_resp=$(iwctl --passphrase=$WIFI_PASS station $i connect $WIFI_SSID | grep 'not found\|Operation failed\|Argument format is invalid\|Invalid network name')
			if [ "$con_resp" != "" ]
			then
				a="not found"
				b="Invalid network name"
				if [ -z "${con_resp##*$a*}" ]
				then
					blah=1
					# echo "FAILED: Network device not found for $i" 
				elif [ -z "${con_resp##$b*}" ];
				then
					echo "FAILED: SID not found on $i"
				else
					echo "FAILED: Password is invalid on $i"
				fi
				fail_iface=$((fail_iface+1))
			else
				# echo "SUCCESS: Connected to interface $i"
				WIFI_FOUND_IFACE="$i"
				break
			fi
		done

		# Check how many of the network interfaces failed
		if [ $fail_iface -lt $total_iface ]
		then
			success_iface=$((total_iface-fail_iface))
			echo ""
			echo "Found a valid wifi interface: $WIFI_FOUND_IFACE"
			sleep_sec=3
			ping_count=5
			echo "Testing wifi connection, this will take a few seconds..."
			sleep $sleep_sec
			pingOutput=$(ping -c $ping_count google.com 2>&1)
			ping_has_err=$(echo "$pingOutput" | wc -l)
			if [ "$ping_has_err" = "1" ]
			then
				echo "WARNING: Connected to $WIFI_FOUND_IFACE BUT not connected to the internet"					
			else
				pingSuccessCount=$(echo "$pingOutput" | grep transmitted | awk '{print int($1)}')
				if [ $pingSuccessCount -gt 0 ]; then
					echo "SUCCESS: Connected to the internet!"
				else
					echo "WARNING: Connected to $WIFI_FOUND_IFACE BUT not connected to the internet"
				fi
			fi
		else
			echo "Failure on ALL network interfaces"
		fi
	fi

	if [ $fail_iface -eq $total_iface ]
	then
		echo "WARNING: WiFi credentials have not been set OR WiFI setup failed, either restart the script and set them OR
		complete the next ethernet connection step
		"
		echo "Plug in your ethernet cable to connect to the internet via ethernet, click ENTER when you're done"
		read -r ETH_CONNECTED
		echo "Waiting 10s before 'ping' test on ethernet..."
		sleep 10

		con_test=$(ping -c 3 linux.org 2>&1 | grep 'cannot' | wc -l)
		if [ $con_test -gt 0 ]
		then
			echo "FAILED: Unable to connect to ethernet"
			exit 1
		else
			echo "SUCCESS: Successfully connect to ethernet!"
		fi
	fi
}

# 1. Wifi
WIFI_SSID=""
WIFI_PASS=""
WIFI_FILE_NAME=""
WIFI_FILE_CONTENTS=""
echo ""
echo "STEP 1:  Setup Wifi"
if [ "$WIFI_SSID" != "" ]
then
	echo "Please provide your WIFI password below:"
	while [ "$WIFI_PASS" = "" ]; do
		read -s -p "> " WIFI_PASS
		if [ "$WIFI_PASS" = "" ]
		then
			echo "! No value provided for wifi password, please specify:"
		fi
	done
	echo ""

	FN_TEST_WIFI

	if [ $WIFI_SAVE_CONFIG -eq 1 ]
	then
		WIFI_FILE_NAME="${WIFI_SSID}.psk"
		WIFI_FILE_CONTENTS=$(printf "[Security]\nPassphrase=%s\n\n[Settings]\nAutoConnect=true" "$WIFI_PASS")
	fi
else
	echo "Wifi not configured, skipping wifi setup..."
fi
echo ""
%end