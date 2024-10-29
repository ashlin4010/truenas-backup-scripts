# TrueNAS Backup Scripts #

This repository contains a two scripts to backup VMs and the system config on TrueNAS Scale.
These scrips depend on the [TrueNAS cli](https://github.com/truenas/midcli) tool.

### Important ###
`backup-vms.sh` will set your system `zfs_arc_max` to 8GiB. This is because turning VMs on and off causes TrueNas to re-evaluate the `zfs_arc_max` default value and it does so incorrectly. This will cause the system to over allocate memory to the ZFS ARC, this will prevent the system from allowing the VM to restart. The solution is to force `zfs_arc_max` to a lower value. You may wish to adjust this value appropriate to your system and needs.

## backup-system-config.sh (Exports system Config) ##
This script will export the system config including the system Password Secret Seed to the specified path. It will retain the last 5 configurations.

This script does a simple check to ensure that the backup tar is valid and contains the expected files, however it does not validate the integrity of the database file beyond it's existence.

## backup-vms.sh (Exports VM Zvol Disks As Files) ##
This script will automatically shutdown VMs, take a snapshot, backup it up and restart the VM. Backups are saved to the specified path. Backups and snapshots will automatically be removed after 3 copies exist. Any VM that is not currently running is still snapshotted and backed up but is not power cycled and will remain off.

It does not check the validity of the backs but it does generate a sha256 file. The script has not been tested with vms with multiple disks however it should work just fine. Additionally VM configurations are not backed up, they should be included as part of the system configuration.

## Recommended Installation ##
Create a new dataset named `Backup`, this is where backup files will be saved to. Ensure that `Backup` is included in any cloud sync tasks. In `Backup` create a new folder called scripts and download `backup-system-config.sh` and `backup-vms.sh` into it. Remember to set the execution bit.

Add a new cron job for each backup script. Setting `Hide Standard Output` to false is recommended.
```bash
/bin/bash /mnt/primary/Backup/scripts/backup-system-config.sh
/bin/bash /mnt/primary/Backup/scripts/backup-vms.sh
```

## Unverified HTTPS request ##
The TrueNAS cli tool uses an HTTPS WS connection to the local system. By default the system uses unsigned keys. If you force only secure connections in the system settings you may experience problems.