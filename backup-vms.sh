#!/bin/bash

# Note:
# Set the systems max ARC size otherwise the system might dynamically
# reallocated memory when the VM turns off.
MAX_ARC="8589934592" # bytes

# Change as needed, note that BACKUP_DIR will be made if missing but DATASET_PATH will not
BACKUP_DIR="virtual-machines"
DATASET_PATH="/mnt/primary/Backup"
BACKUP_PATH="$DATASET_PATH/$BACKUP_DIR"

# Change this to the desired number of VM backups to keep
BACKUP_RETENTION=3
SNAPSHOT_RETENTION=3

# This function will send an email if you have that setup
send_error_message() {
    local script_name=$(basename "${BASH_SOURCE[1]}")
    local subject="Backup Error ($script_name)"
    local message="$1"
    cli -c "system mail send {\"subject\": \"$subject\", \"text\": \"$message\"}"
}

# Check if DATASET_PATH exists
if [ -d "$DATASET_PATH" ]; then
    # If BACKUP_DIR does not exist, create it and check for errors
    if [ ! -d "$BACKUP_PATH" ]; then
        mkdir "$BACKUP_PATH"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create backup directory '$BACKUP_PATH'! Exiting." >&2
            send_error_message "Failed to create backup directory '$BACKUP_PATH'!"
            exit 1
        fi
    fi
else
    echo "Error: Dataset '$DATASET_PATH' does not exist! Exiting." >&2
    send_error_message "Dataset '$DATASET_PATH' does not exist!"
    exit 1
fi

# Get vm ids
output=$(cli -c 'service vm query id' -m csv)
if [ $? -ne 0 ]; then
    echo "Error: Failed to query VM IDs."
    send_error_message "Error: Failed to query VM IDs."
    exit 1
fi

# Convert CSV to a space-separated list of VM IDs (skipping the header)
vm_ids=$(echo "$output" | tail -n +2 | tr '\n' ' ' | tr -d '\r' | xargs)

# Loop over each VM ID
for vm_id in $vm_ids; do
    # Ensure that the vm_id is not empty
    if [ -n "$vm_id" ]; then

        # Get name for vm
        output=$(cli -c "service vm query name WHERE id==$vm_id" -m csv)
        vm_name=$(echo "$output" | awk -F',' 'NR==2 {print $1}' | tr -d '\r' | xargs)

        # Get shutdown timout for vm
        output=$(cli -c "service vm query shutdown_timeout WHERE id==$vm_id" -m csv)
        timeout=$(echo "$output" | awk -F',' 'NR==2 {print $1}' | tr -d '\r' | xargs)

        echo ""
        echo "Taking snapshot of $vm_name (id: $vm_id)"

        # Check the running status
        output=$(cli -c "service vm status id=$vm_id" -m csv)
        state=$(echo "$output" | awk -F',' 'NR==2 {print $1}')
        if [ "$state" == "RUNNING" ]; then
            is_running=true
        fi

        # Get VM disks
        output=$(cli -c "service vm query devices WHERE id==$vm_id" -m csv)
        # Extract the JSON part from the output and fix double quotes
        json_data=$(echo "$output" | awk 'NR>1' | tr -d '\r' | sed 's/""/"/g')
        json_array=$(echo "$json_data" | sed 's/^"\(.*\)"$/\1/') # Remove the surrounding quotes
        disks=$(echo "$json_array" | jq -c '[.[] | select(.dtype == "DISK") ]' | jq -c '.[] .attributes.path')
        vm_zvols=$(echo "$disks" | sed 's/^"\(.*\)"$/\1/' | sed 's|^/dev/zvol/||g')

        echo "Disks: $vm_zvols"

        # if vm is running stop it
        if [ "$is_running" == true ]; then
            echo "Stopping VM (timeout: $timeout)"
            # The command looks to wait for shutdown
            output=$(cli -c "service vm stop id=$vm_id")
            sleep 2
            output=$(cli -c "service vm status id=$vm_id" -m csv)
            state=$(echo "$output" | awk -F',' 'NR==2 {print $1}')
            if [ "$state" == "RUNNING" ]; then
                send_error_message "Dataset '$DATASET_PATH' does not exist!"
                echo "Unable to stop vm... moving into the next vm"
                continue
            fi
        fi

        # Create a snapshot for each disk and remove old snapshots
        for dataset in $vm_zvols; do
            echo "Taking snapshot of $dataset"
            # Create snapshot
            output=$(cli -c "storage snapshot create dataset=\"$dataset\" naming_schema=\"auto-%Y-%m-%d_%H-%M\"")
            if [ $? -ne 0 ]; then
                echo "Error: Failed to create snapshot for $dataset"
                send_error_message "Error: Failed to create snapshot for $dataset"
                continue # Skip this vzol
            fi
            snapshot_num=$(cli -c "storage dataset snapshot_count dataset=\"$dataset\"" | tr -d '\r' | xargs)

            # Delete oldest snapshot if more then SNAPSHOT_RETENTION
            if [ "$snapshot_num" -gt "$SNAPSHOT_RETENTION" ]; then
                snapshots=$(cli -c "storage snapshot query name WHERE dataset==\"$dataset\"" -m csv | tail -n +2)
                oldest_snapshot=$(echo "$snapshots" | grep '@auto' | sort | head -n 1 | tr -d '\r' | xargs)
                echo "More than $SNAPSHOT_RETENTION snapshot, deleting oldest ($oldest_snapshot)"

                # delete snapshot
                output=$(cli -c "storage snapshot delete id=\"$oldest_snapshot\"")
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to delete snapshot for $oldest_snapshot"
                    send_error_message "Error: Failed to delete snapshot for $oldest_snapshot"
                    continue # Skip this vzol
                fi
            fi
        done

        # Restart VM
        if [ "$is_running" == true ]; then
            echo "Starting VM"
            output=$(cli -c "service vm start id=$vm_id")
        fi
    fi
done

# Rewrite the max arc value
echo $MAX_ARC >> /sys/module/zfs/parameters/zfs_arc_max

for vm_id in $vm_ids; do
    # Get name for vm
    output=$(cli -c "service vm query name WHERE id==$vm_id" -m csv)
    vm_name=$(echo "$output" | awk -F',' 'NR==2 {print $1}' | tr -d '\r' | xargs)
    VM_BACKUP_PATH="$BACKUP_PATH/$vm_name"
    echo ""
    echo "Making backup of $vm_name (id: $vm_id, path: $VM_BACKUP_PATH)"

    # Make backup folder
    mkdir -p "$VM_BACKUP_PATH"
    if [ $? -ne 0 ]; then
        echo "Error: Unable to create backup path '$VM_BACKUP_PATH'"
        send_error_message "Error: Unable to create backup path '$VM_BACKUP_PATH'"
        continue
    fi


    # Get VM disks
    output=$(cli -c "service vm query devices WHERE id==$vm_id" -m csv)
    # Extract the JSON part from the output and fix double quotes
    json_data=$(echo "$output" | awk 'NR>1' | tr -d '\r' | sed 's/""/"/g')
    json_array=$(echo "$json_data" | sed 's/^"\(.*\)"$/\1/') # Remove the surrounding quotes
    disks=$(echo "$json_array" | jq -c '[.[] | select(.dtype == "DISK") ]' | jq -c '.[] .attributes.path')
    vm_zvols=$(echo "$disks" | sed 's/^"\(.*\)"$/\1/' | sed 's|^/dev/zvol/||g')
    echo "Disks: $vm_zvols"


    for dataset in $vm_zvols; do
        snapshots=$(cli -c "storage snapshot query name WHERE dataset==\"$dataset\"" -m csv | tail -n +2)
        newest_snapshot=$(echo "$snapshots" | grep '@auto' | sort -r | head -n 1 | tr -d '\r' | xargs)
        snapshot_name=$(basename "$newest_snapshot")
        zvol_name=$(basename "$dataset")
        echo "Creating backup of '$snapshot_name', this may take some time"
        backup_path="$VM_BACKUP_PATH/$snapshot_name.zst"
        hash_path="$backup_path.sha256"

        # Backup the snapshot
        zfs send -ec "$newest_snapshot" | zstd > "$backup_path"
        if [ $? -ne 0 ]; then
            echo "Error: Unable to create backup path '$backup_path'"
            send_error_message "Error: Unable to create backup path '$backup_path'"
            continue
        fi
        sha256sum $backup_path > $hash_path
        backup_size=$(du -sh "$backup_path" | cut -f1)
        echo "Backup complete. (size: $backup_size)"

        # delete old backups
        backup_num=$(find $VM_BACKUP_PATH -type f -name "$zvol_name*.zst" | wc -l)
        if [ "$backup_num" -gt "$BACKUP_RETENTION" ]; then
            oldest_backup=$(find $VM_BACKUP_PATH -type f -name "$zvol_name*.zst" | sort -n | head -n 1 | tr -d '\r' | xargs)
            if [ -n "$oldest_backup" ]; then
                echo "Removing old backup '$oldest_backup'"
                rm -f "$oldest_backup"
                rm -f "$oldest_backup.sha256"
            fi
        fi
    done
done