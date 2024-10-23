#!/bin/bash

# Change as needed, note that BACKUP_DIR will be made if missing but DATASET_PATH will not
BACKUP_DIR="system-config"
DATASET_PATH="/mnt/primary/Backup"
BACKUP_PATH="$DATASET_PATH/$BACKUP_DIR"

# Change this to the desired number of backups to keep
NUM_BACKUPS=5

# Check if DATASET_PATH exists
if [ -d "$DATASET_PATH" ]; then
    # If BACKUP_DIR does not exist, create it and check for errors
    if [ ! -d "$BACKUP_PATH" ]; then
        mkdir "$BACKUP_PATH"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create backup directory '$BACKUP_PATH'. Exiting." >&2
            exit 1
        fi
    fi
else
    echo "Error: Dataset '$DATASET_PATH' does not exist. Exiting." >&2
    exit 1
fi

# Set backup file name with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="backup_$TIMESTAMP.tar"
BACKUP_FULL_PATH="$BACKUP_PATH/$BACKUP_FILE"


# Save the system config with secret
if ! cli -c 'system config save {"secretseed": true} > '"$BACKUP_FULL_PATH"''; then
    echo "Error: Failed to save the system config!" >&2
    exit 1
fi

# Check if the backup is a valid tar file and contains the expected files
if ! tar -tf "$BACKUP_FULL_PATH" | grep -q -E 'freenas-v1.db|pwenc_secret'; then
    echo "Error: Backup does not contain the expected files!" >&2
    exit 1
fi

# Keep only the last $NUM_BACKUPS backups, delete older ones
cd "$BACKUP_PATH" || exit
if ! ls -t | grep 'backup_*.tar' | tail -n +$((NUM_BACKUPS+1)) | xargs rm -f; then
    echo "Error: Failed to clean up old backups!" >&2
    exit 1
fi
