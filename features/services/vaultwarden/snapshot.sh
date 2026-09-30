# Invoked by the root-owned snapshot unit. Quiesce writers only while copying;
# restart before Restic uploads anything. A failed prepare must fail the backup.
set -euo pipefail

data_dir=$1
snapshot_dir=$2
database=$3
database_user=$4
socket_dir=$5
staging="$snapshot_dir/.staging"

systemctl is-active --quiet vaultwarden.service
test -d "$data_dir"
install -d -m 0700 "$snapshot_dir" "$staging"

restart_needed=0
cleanup() {
  local status=$?
  trap - EXIT
  if [ "$restart_needed" -eq 1 ]; then
    if ! systemctl start vaultwarden.service; then
      echo 'Vaultwarden snapshot: failed to restart the service' >&2
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
restart_needed=1
systemctl stop vaultwarden.service

rsync -a --delete --exclude=icon_cache --exclude=tmp "$data_dir/" "$staging/data/"
runuser -u "$database_user" -- pg_dump --host="$socket_dir" --format=custom --dbname="$database" > "$staging/database.dump"
pg_restore --list "$staging/database.dump" > /dev/null

systemctl start vaultwarden.service
restart_needed=0
systemctl is-active --quiet vaultwarden.service

# Keep the previous completed artifact until the new snapshot has passed validation.
rsync -a --delete "$staging/" "$snapshot_dir/current/"
