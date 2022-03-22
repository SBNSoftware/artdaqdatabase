### Introduction
This page is intended to guide you thru an automated installation and recovery process of the artdaq database used by Icarus and SBND data acquisition software. Artdaq database stores configuration parameters for the online data-taking software called sbndaq. And hence, it is critical for running experiments. Each experiment has a dedicated pair of servers referred to as db01 and db02 (the actual hostnames are different), which run a MongoDB replica set, a distributed redundant database.

The baseline OS installation is the same for all online servers, including db01 and db02. And it is appropriate to note that all DAQ software, user home areas, run records, logs, and scratch areas are shared across all servers of the same DAQ cluster and mounted over NAS/NFS. All MongoDB software started from UPS, which is mounted over NAS/NFS as the "/daq/software" directory.

A typical installation of the artdaq database consists of two MongoDB Servers running on db01 and db02 and a MongoDB Arbiter running on db02. All processes are configured as SystemD services to run from the artdaq user account and started at boot. At the moment of writing, the artdaq database takes 20GB of disk space and has 8000 run history records.

### What you need
Before you begin the recovery procedure, request to be added to the ardaq user's ~/.k5login on the DAQ cluster, and optionally to /root/.k5login on db01 and db02. Also, coordinate all your work with DAQ and SLAM groups. You can also ask them to run the script as root if you are not in /root/.k5login on db01 and db02. 

The recommendation is to keep MongoDB data in a separate designated local partition and have it at least 500GB in size. The mount path of such a partition must be the same on db01 and db02. Always use a RAIDed disk for storing MongoDB data.

### Recovery procedure
1. Review the latest [README.md](https://github.com/SBNSoftware/artdaqdatabase) entirely.
2. ssh into the db02 server as artdaq with a forwardable Kerberos ticket (the -K flag).
3. Create ~/.mongodb_install.env with the following contents.

```bash=
EXPERIMENT=icarus
#path to the MongoDB data, e.g. /scratch_local/artdaq_database_001
INSTALL_PREFIX=change-me
MONGOD_HOSTS=${EXPERIMENT}-db01,${EXPERIMENT}-db02
MONGOD_ARB_HOST=${EXPERIMENT}-db02
#use 38047 for testing and 28047 for production
MONGOD_PORT=38047
#always ask
MONGOD_RW_PASSWORD=change-me
MONGOD_ADMIN_PASSWORD=change-me
```

4. Download software from github.

```bash=
cd ~
rm -rf ~/artdaqdatabase
git clone https://github.com/SBNSoftware/artdaqdatabase.git
cd ~/artdaqdatabase/scripts/
```

5. Run the connectivity verification script. It validates that all essential Linux utilities are installed, SELinux security policy is NOT enforced, your Kerberos ticket is forwarded, and both db01 and db02 servers can talk over ports MONGOD_PORT, MONGOD_PORT+1. Review the entire output from the verification script and resolve reported issues. If you don't have root login privileges ask members of SLAM or DAQ groups to run the install systemd services script.

```bash=
~/artdaqdatabase/scripts/verify-connectivity.sh
```

6. Run the install artdaq database script. This script configures a new MongoDB replica set with parameters specified in step 3. If you have root access, the script will also attempt to configure SystemD services on db01 and db02.

```bash=
~/artdaqdatabase/scripts/install-artdaq-database.sh
```

7. If you don't have root login privileges ask members of SLAM or DAQ groups to run the install systemd services script on db01 and db02. The script is called install-systemd-services.sh and is located in the INSTALL_PREFIX directory ( refer to step 3). Run it on db01 first, wait 10 seconds for services to warm up and then run it on db02. Wait another 20 seconds for servers to sync.
8. Run the conftool tests script. It is safe to run this script repeatedly. The restore database script will wipe out all test data.

```bash=
~/artdaqdatabase/scripts/conftoolpy-tests.sh
```

9. Run the restore database script. This script looks for daily backups in the /daq/software/backup/ directory that is mounted over NAS/NFS. It also expects that a MongoDB replica set is up and running. Each script execution wipes out all data, and it is safe to call this script more than once.

```bash=
~/artdaqdatabase/scripts/restore-database.sh
```

10. Finally, load any missing configurations.
