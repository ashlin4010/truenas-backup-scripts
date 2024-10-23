# TrueNAS Backup Scripts #

This repository contains a number of scripts to backup various things on TrueNAS Scale.
These scrips depend on the [TrueNAS cli](https://github.com/truenas/midcli) tool


## Unverified HTTPS request ##
The TrueNAS cli tool uses an HTTPS WS connection to the local system. By default the system uses unsigned keys. If you force only secure connections in the system settings you may experience problems.


## backup-system-config.sh ##
This script will export the system config including the system Password Secret Seed it to the specified path. It will retain the last 5 configurations.

This script does a simple check to ensure that the backup tar is and contains the expected files, however it does not validate the integrity of the database file beyond it's existence.

### Recommended Installation ###
Create a new dataset named `Backup`, place this file at the root of the path. Add a new cron job to run this file once a week. If you want more frequent you should consider increasing the number of backups to retain.