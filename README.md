# pbs-client
Proxmox Backup Server Client in Docker  
Heavily inspired and modified from [Aterfax's image](https://github.com/Aterfax/pbs-client-docker)  

## Usage
### Environment Variables
Assume no variables are configured by default.

#### Proxmox Backup Client Variables
When possible, all configuration should be performed via the supported Proxmox Environment Variables as defined [Here](https://pbs.proxmox.com/docs/backup-client.html#environment-variables).  
All variables with the prefixes `PBS_`, `PBC_`, or `PROXMOX_` will be passed to the cron job and scripts that call the proxmox backup client.
The `ALL_PROXY` environment variable will also be passed.  
The `PROXMOX_OUTPUT_FORMAT` is configured for `text` output by default.

#### Image Variables
| Variable | Description | Default |
| --- | --- | --- |
| PBC_DEBUG | Display all Env Vars that are written to the .env file. CAUTION: This will show secrets! |  |
| PBC_BACKUP_ON_START | Set to any non-falsy value to run a backup on start. Skipped if a script parameter is passed or unset. |  |
| PBC_CRON | Enable cron to backup on a schedule, must be set to a valid cron expression. |  |
| PBC_HEALTHCHECKS_URL | URL to your custom Healthchecks instance. | `https://hc-ping.com` |
| PBC_HEALTHCHECKS_UUID | UUID for your healthcheck. |  |
| PBC_HEALTHCHECKS_API_RETRIES | Number of times to retry the healthcheck API call | 5 |
| PBC_HEALTHCHECKS_API_TIMEOUT | Timeout value to consider an API call failed | 10s |
| PBC_OPT_NAMESPACE | Datastore Namespace for the backup |  |
| PBC_OPT_SKIP_LOST_AND_FOUND |  Set to any non-falsy value to skip Lost+Found directories |  |
| PBC_OPT_ARGS | Miscellaneous arguments to pass to the `proxmox-backup-client` command. |  |
| PBC_BACKUP_FINDMNT | Enable search for all mount points under the backup directory and add to backup list. | true |
| PBC_OPT_CHANGE_DETECTION_MODE | [See docs](https://pbs.proxmox.com/docs/backup-client.html#change-detection-mode) | metadata |

[<HIDDEN> | PBC_OPT_BACKUP_ID | ID for the backup, recommended to use the FQDN of the host. |  |]: #

#### Scripts
You can call any command or any script in the `/scripts/` directory by passing the command/script name and any arguments as a `command` to the container.
Calling a command/script will run and then exit.
Scripts will be will have their executable bit set if needed.

This allows you to perform useful commands such as calling `proxmox-backup-client` directly.

#### Backup
[<HIDDEN> **Always** configure `PBC_OPT_BACKUP_ID`!  ]: #
Configuration Directory: `/root/.config/proxmox-backup/` is defined as a volume in the Dockerfile.
Feel free to bind mount this to a local directory.

Mount `/tmp` and `/run` as `tmpfs`.

Mount the directories you would like backed up into `/backup/`.
Each directory will be created as it's own `PXAR` archive.
If you want to backup individual files, mount them to a subdirectory of `/backup/`.

For exclusions, create `.pxarexclude` files in your backup subdirectories. [Reference](https://pbs.proxmox.com/docs/backup-client.html#excluding-files-directories-from-a-backup)

Configure the container `hostname` to match the container host, or something unique and specific to you use-case.

Set restart to:
- `unless-stopped` when running cron.
- `never` when running a one-off backup or script.
- `always` is not recommended for any use-case.

#### Encryption
If you wish to enable encryption, you will need to interact with the client directly before the first run.
`docker run -it <image>:<tag> proxmox-backup-client key create encryption.key`
You will be prompted for a password which for subsequent runs should be set via one of the `PBS_PASSWORD` environment variables. [reference](https://pbs.proxmox.com/docs/backup-client.html#encryption)  
If you do not want to set a password on the encryption key, pass `--kdf none` to the above `docker run` command.

### Docker Compose
Here is an example compose definition
```yaml
services:
  pbs-client:
    image: ghcr.io/djarbz/pbs-client:latest
    container_name: pbs-client
    hostname: pbs-docker
    restart: unless-stopped
    tmpfs:
      - /tmp
      - /run
    volumes:
      # - "/mnt/sd-apps/config/pbs:/root/.config/proxmox-backup/"
      - "/host/dir/1/:/backup/dir1/"
      - "/host/dir/2/:/backup/dir2/"
      - "/host/dir/3/:/backup/dir3/"
      - "/host/dir/4/:/backup/dir4/"
    environment:
      - TZ=America/Chicago
      # <USER>@<DOMAIN>!<TOKEN>@<HOST>:<DATASTORE>
      - PBS_REPOSITORY=<USER>@<DOMAIN>!<TOKEN>@<HOST>:<DATASTORE>
      # User Password or Token Secret
      - PBS_PASSWORD=<Token UUID>
      - PBC_BACKUP_ON_START=true
      # Every hour at the half hour
      - PBC_CRON=30 * * * *
      - PBC_HEALTHCHECKS_URL=https://healthchecks.domain.com/ping
      - PBC_HEALTHCHECKS_UUID=<HC Check UUID>
      - PBC_OPT_NAMESPACE=docker
      - PBC_OPT_SKIP_LOST_AND_FOUND=true
```