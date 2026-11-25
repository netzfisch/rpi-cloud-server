# Raspberry Pi Cloud Server

One cloud-init file provisions a headless Raspberry Pi (Ubuntu Server 26.04 LTS, ARM64) as
VLAN router with DHCP/DNS, RAID1 NAS with Samba, UniFi OS Server and Docker host.

## Source of truth

- `user-data.template`: the configuration, with `${VARIABLE}` placeholders. Edit here.
- `secrets.env.example`: every variable with a safe example value. Tracked.
- `generate-userdata.sh`: checks the variables, renders `user-data`, validates the schema.
- `secrets.env` and `user-data`: local only, gitignored. `user-data` is generated output.

## Changing the configuration

1. Edit `user-data.template`.
2. For a new variable, add it to `secrets.env.example` and to `REQUIRED_VARS` in
   `generate-userdata.sh`. Only variables listed there are substituted; everything else
   (`$RELEASE`, shell expansions like `${entry%%=*}`) passes through unchanged.
3. Run `./generate-userdata.sh`. Done when it prints "Cloud-init schema validation passed".
   Without a `secrets.env`, render in a scratch copy with `secrets.env.example` as `secrets.env`.
4. Describe the changed behaviour in `README.md` (users) and `DEVELOPMENT.md` (details).

Rendering proves syntax, not behaviour. A change counts as tested once it ran on the Pi or on
a freshly flashed card; report which of the two happened.

## Rules

- **Variables over literals.** IPs, host names, URLs and credentials come from `secrets.env`.
- **Idempotent `runcmd`.** Re-running cloud-init must be safe: guard every create or install
  (`if ! mdadm --detail /dev/md0`, `command -v uosserver`, `grep -q` before appending).
- **RAID data survives.** Keep `overwrite: false` in `disk_setup` and `fs_setup` and keep the
  `/dev/md0` guard. They are the only protection of the data in `/mnt/raid1` on a re-run.
- **Network config is netplan**, written by `write_files` to `/etc/netplan/50-cloud-init.yaml`.
- **Boot partition path** on the Pi is `/boot/firmware/user-data`.

## Architecture decisions

- **cloud-init**: the whole system state lives in one versioned file; nothing is configured
  by hand after flashing.
- **RAID1 with mdadm**: two USB drives (`/dev/sda`, `/dev/sdb`) mirrored to `/mnt/raid1`.
- **VLANs**: Privat (untagged, `192.168.10.0/24`), IoT (VLAN 20), Guest (VLAN 30). The Pi
  routes between them, dnsmasq serves DHCP and DNS for IoT and Guest, iptables does NAT and
  blocks IoT and Guest from Privat (`FORWARD` policy `DROP`).
- **Local DNS names** come from `LOCAL_DNS_HOSTS`. Devices carry the last IP octet (`gate1`),
  services do not (`nas`, `unifi`), so a service can move without changing its name.
- **UniFi OS Server** is installed by Ubiquiti's installer and runs as a rootless podman
  container under the user `uosserver`. It coexists with Docker and leaves iptables alone.
  Web UI on `:11443`, device inform on `:8080`.
- **Docker** runs `ddclient` (dynamic DNS) and the optional `vpnserver`.
- **zram swap** (2 GiB, compressed, in RAM) keeps swapping off the SD card.
- **Users**: `pirate` is the admin (sudo, Docker, SSH keys from GitHub). `USER1` and `USER2`
  are Samba-only accounts without login.

## Working on the running Pi

The Pi is router, DNS server and NAS for the whole network. Before a change, snapshot
`iptables -S`, `iptables -t nat -S` and `ss -tulpn`; afterwards diff them and run
`sudo check-network`. Ask before a reboot or a restart of dnsmasq.

## Where to look

- [README.md](README.md): setup from secrets to flashed card, the mandatory router
  configuration (static routes, local DNS server), and the safe procedure to re-run
  cloud-init. Read it before changing deploy or re-run steps.
- [DEVELOPMENT.md](DEVELOPMENT.md): variables, services (UniFi OS Server, ddclient, VPN),
  zram, Samba shares, RAID, and debugging of provisioning, VLAN routing and DNS. Read it
  when diagnosing the target system.
- [switch-config.template](switch-config.template): Juniper switch VLAN and trunk
  configuration. Read it when VLAN IDs or port assignments change.
