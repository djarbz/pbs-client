#!/usr/bin/env bash
# shellcheck shell=bash

#==================================================
# Validate Cron Expression
#==================================================
validate_cron_expression() {
  local cron_expression="$1"
  # https://stackoverflow.com/a/63729682
  # https://regex101.com/r/RtLgqG
  # https://github.com/Aterfax/pbs-client-docker/blob/main/docker/src/helper_scripts/cron-validation-functions
  local regex='^((((\d+,)+\d+|(\d+(\/|-|#)\d+)|\d+L?|\*(\/\d+)?|L(-\d+)?|\?|[A-Z]{3}(-[A-Z]{3})?) ?){5,7})|(@(annually|yearly|monthly|weekly|daily|hourly|reboot))|(@every (\d+(ns|us|µs|ms|s|m|h))+)$'

  if echo "$cron_expression" | grep -Pq "$regex"; then
    return 0 # Valid cron expression
  else
    return 1 # Invalid cron expression
  fi
}

#==================================================
# Export Needed Environment Variables
#==================================================
export_env_vars() {
  local output_file="${1:-.env}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Create or truncate the file with a header
  cat > "$output_file" <<- EOF
		# Environment variables with PBS_, PBC_, or PROXMOX_ prefix, and ALL_PROXY
		# Generated on: $timestamp
		# ------------------------------------------
		EOF

  # Process environment variables
  while IFS='=' read -r name value; do
    # Skip if the value is empty
    [ -z "$value" ] && continue

    # Check if variable starts with PBS_, PBC_, or PROXMOX_
    if [[ $name =~ ^(PBS_|PBC_|PROXMOX_) ]] || [ "$name" == "ALL_PROXY" ]; then
      # Properly escape special characters in the value
      escaped_value=$(printf '%s\n' "$value" | sed 's/"/\\"/g; s/=/\\=/g')

      # Write to file in export format
      printf 'export %s="%s"\n' "$name" "$escaped_value" >>"$output_file"
    fi
  done < <(env | sort)

  # Set appropriate permissions
  chmod 600 "$output_file"

  # Provide feedback
  echo "Environment variables exported to: $output_file"
  echo "Total variables exported: $(grep -c '^export' "$output_file")"
}

#==================================================
# Run Script
#==================================================

# Export important variables for use in cron scripts later
export_env_vars "/tmp/pbs-client.env"

#==================================================
# Run Called Command or Script
#==================================================
# Add the /scripts directory to the PATH
export PATH="/scripts:$PATH"

if [ -n "$1" ]; then
  # Check if the first argument is in the /scripts directory
  script_path="/scripts/$1"
  if [ ! -f "$script_path" ]; then
    # If the first argument is not in the /scripts directory, just run it
    "$1" "${@:2}"
    exit $?
  fi

  # Check if the file is a binary
  if ! file "$script_path" | grep -q "executable"; then
    # If it's not a binary, run it with Bash
    bash "$script_path" "${@:2}"
    exit $?
  fi
  
  # If it's a binary, check if it's executable
  if [ -x "$script_path" ]; then
    # Run the binary
    "$script_path" "${@:2}"
    exit $?
  else
    # Binary is not executable, error out
    echo "Error: '$1' is a binary file but not executable." >&2
    exit 1
  fi
fi

#==================================================
# Configure Healthchecks Reporting
#==================================================
hc_cmd=
if [ -n "${PBC_HEALTHCHECKS_URL:-}" ] && [ -n "${PBC_HEALTHCHECKS_UUID:-}" ]; then
  hc_cmd=/usr/local/bin/runitor
  
  if [ -n "${PBC_HEALTHCHECKS_API_RETRIES:-}" ]; then
    hc_cmd+=" -api-retries ${PBC_HEALTHCHECKS_API_RETRIES}"
  fi
  
  if [ -n "${PBC_HEALTHCHECKS_API_TIMEOUT:-}" ]; then
    hc_cmd+=" -api-timeout ${PBC_HEALTHCHECKS_API_TIMEOUT}"
  fi

  hc_cmd+=" --"
fi

#==================================================
# Validate Action
#==================================================
if [ -z "${PBC_BACKUP_ON_START:-}" ] && [ -z "${PBC_CRON:-}" ]; then
  echo "You must enable PBC_BACKUP_ON_START or PBC_CRON to perform a backup!"
  exit 1
fi

#==================================================
# Run Backup on Start
#==================================================
if [ -n "${PBC_BACKUP_ON_START:-}" ] && [ "$PBC_BACKUP_ON_START" != "0" ] && [ "${PBC_BACKUP_ON_START,,}" != "false" ] && [ "${PBC_BACKUP_ON_START,,}" != "no" ]; then
  echo "Performing backup on start..."
  ${hc_cmd} /scripts/backup
fi

#==================================================
# Validate Cron
#==================================================
if [ -z "${PBC_CRON:-}" ]; then
  echo "Warning: PBC_CRON environment variable is not set" >&2
  exit 1
fi

if ! validate_cron_expression "$PBC_CRON"; then
  echo "Error: Invalid cron expression in [${PBC_CRON}]" >&2
  exit 1
fi

#==================================================
# Configure Cron
#==================================================
# * * * * * root /scripts/backup > /proc/1/fd/1 2>/proc/1/fd/2
echo "Configuring cron with expression: $PBC_CRON"
cron_file="/etc/cron.d/pbc-backup"
echo "Writing cron entry to $cron_file"
echo "$PBC_CRON root ${hc_cmd} /scripts/backup > /proc/1/fd/1 2>/proc/1/fd/2" > "$cron_file"
chmod 600 "$cron_file"

#==================================================
# Start Cron
#==================================================
echo "Starting cron..."
# -f Run in foreground
# -L Log Level as sum of values below (1-16)
#   1 - will log the start of all cron jobs
#   2 - will log the end of all cron jobs
#   4 - will log all failed jobs (exit status != 0)
#   8 - will log the process number of all cron jobs
#  -l Enable LSB compliant names for /etc/cron.d files.
#     This setting, however, does not affect the parsing of files under /etc/cron.hourly, /etc/cron.daily, /etc/cron.weekly or /etc/cron.monthly.
cron -f -L 15 -l
