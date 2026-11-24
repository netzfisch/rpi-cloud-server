# Raspberry Pi Cloud Server - Technical Documentation

This document provides deep technical details for the project described in `README.md`. It assumes you are familiar with the project's basic architecture and goals.

**Target OS**: Ubuntu Server 26.04 LTS ARM64+Raspi  
**Cloud-init Version**: 24.x+

## System Architecture Details

### Network Configuration
- **Hostname**: `liberty10` (configurable via `HOSTNAME` in secrets.env)
- **Static IP**: `192.168.10.10` (configurable via `STATIC_IP` in secrets.env)
- **Gateway**: `192.168.10.1` (configurable via `GATEWAY_IP` in secrets.env) 
- **DNS**: `192.168.10.1`, `8.8.8.8` (configurable via `DNS_SERVERS` in secrets.env)
- **Dynamic DNS**: liberty.spdns.eu (configurable via `DDNS_HOSTNAME` in secrets.env)

### Storage Layout

```
/dev/sda1 + /dev/sdb1 → /dev/md0 (RAID1) → /mnt/raid1/
                                             ├── user1/     (700, user: user1)
                                             ├── user2/     (700, user: user2)
                                             ├── shared/    (777, all users)
                                             └── public/    (777, guest access)
```

## Configuration Variables

The following variables are defined in `secrets.env` and substituted into `user-data.template`:

### System Configuration
- **HOSTNAME**: System hostname (e.g., liberty10, homeserver)

### User Configuration
- **USER1**: First Samba user name
- **USER1_SAMBA_PASSWORD**: Samba password for USER1
- **USER2**: Second Samba user name
- **USER2_SAMBA_PASSWORD**: Samba password for USER2

**Note**: The `pirate` admin user has a fixed password `hypriot` which MUST be changed on first SSH login (cloud-init enforces password expiration).

### Network Configuration
- **STATIC_IP**: Static IP address for the Pi (e.g., 192.168.10.10)
- **GATEWAY_IP**: Gateway/router IP address (e.g., 192.168.10.1)
- **DNS_SERVERS**: Space-separated DNS servers (e.g., "[192.168.10.1, 8.8.8.8]")

### Dynamic DNS Configuration
- **DDNS_HOSTNAME**: Your dynamic DNS hostname (e.g., homeserver.spdns.eu)
- **DDNS_TOKEN**: Update token from your DDNS provider

## User Management

Three users are configured:

1. **pirate** (default admin)
   - Groups: users, docker, video
   - Sudo: passwordless
   - Shell: /bin/bash
   - SSH: enabled with GitHub key import (gh:netzfisch)
   - Initial password: hypriot (expires on first login)

2. **user1** (Samba-only user)
   - Inactive system user (no login)
   - Samba password: configured via USER1_SAMBA_PASSWORD
   - Access: user1 share + user2 share (read/write)

3. **user2** (Samba-only user)
   - Inactive system user (no login)
   - Samba password: configured via USER2_SAMBA_PASSWORD
   - Access: user2 share + shared share (read/write)

## Packages Installed

**System utilities:**
- avahi-daemon (mDNS/Bonjour)
- byobu, tmux (terminal multiplexers)
- mc (Midnight Commander file manager)
- vim (text editor)

**Storage:**
- mdadm (RAID management)
- samba, samba-common-bin (file sharing)

**Docker:**
- docker-ce, docker-ce-cli
- containerd.io
- docker-buildx-plugin
- docker-compose-plugin

## Services

### 1. UniFi OS Server (podman, not Docker)

**Purpose**: Manage UniFi network devices (access points, switches, etc.)

Installed by Ubiquiti's official installer (`unifiosinstaller --non-interactive`, URL in
`UOS_INSTALLER_URL`). It runs as a rootless podman container named `uosserver` under the
system user `uosserver`. Docker is not involved.

**Location**:
- `/var/lib/uosserver/` - config (`server.conf`, `portmap.json`), binaries, logs
- `/home/uosserver/.local/share/containers/` - image and data volumes
- `/usr/local/bin/uosserver`, `/usr/local/bin/uosserver-purge`

**Access**:
- Web UI: https://192.168.10.10:11443
- Inform: http://192.168.10.10:8080/inform

**Management:**
```bash
sudo systemctl status uosserver uosserver-updater
sudo systemctl restart uosserver
uosserver help
# Network application log inside the container
sudo -u uosserver -H bash -c 'cd /tmp && podman exec uosserver tail -f /data/unifi/logs/server.log'
```

The installer recommends at least 2 GiB of swap; none is configured by this template.

### 2. Dynamic DNS Client (ddclient)

**Purpose**: Keep dynamic DNS updated with current public IP

**Configuration:**
- Hostname: configured via DDNS_HOSTNAME
- Update Token: configured via DDNS_TOKEN
- Image: netzfisch/rpi-dyndns
- Restart policy: unless-stopped

**Management:**
```bash
docker logs ddclient
docker restart ddclient
```

### 3. VPN Server (Optional, commented out)

**Purpose**: Remote access to server from external networks

**Configuration:**
- Ports: 500/udp, 4500/udp (requires port forwarding)
- Config location: /mnt/raid1/shared/configs/vpn
- Image: netzfisch/rpi-vpn-server

**To enable:**
1. Uncomment the runcmd line in user-data.template
2. Generate VPN secrets (see rpi-vpn-server documentation)
3. Configure firewall port forwarding

## Samba Shares

Four shares are configured:

1. **[user1]** - Private share for user 'user1'
   - Path: /mnt/raid1/user1
   - Permissions: 700 (owner only)
   - Access: user1 (read/write)

2. **[user2]** - Shared between user2 and user1
   - Path: /mnt/raid1/user2
   - Permissions: 700 (owner only)
   - Access: user2, user1 (read/write)

3. **[shared]** - Private but accessible to authenticated users
   - Path: /mnt/raid1/shared
   - Permissions: 777 (all users)
   - Access: authenticated users

4. **[public]** - Guest accessible
   - Path: /mnt/raid1/public
   - Permissions: 777 (all users)
   - Access: everyone (guest ok)

**Access from clients:**
- Windows: `\\192.168.10.10\share_name`
- macOS: `smb://192.168.10.10/share_name`
- Linux: `smb://192.168.10.10/share_name` or mount via fstab

## RAID Configuration

**Type**: RAID1 (mirror) - data written to both drives

**Setup Process** (automated by cloud-init):
```bash
# Create RAID array
mdadm --create --run --verbose /dev/md0 \
  --level=mirror --raid-devices=2 /dev/sda1 /dev/sdb1

# Format filesystem
mkfs.ext4 /dev/md0

# Mount and configure auto-mount
mkdir -p /mnt/raid1
mount /dev/md0 /mnt/raid1/
echo '/dev/md0 /mnt/raid1/ ext4 defaults,nofail,noatime 0 1' >> /etc/fstab

# Save RAID configuration
mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf
```

**Monitoring:**
```bash
# Check RAID status
cat /proc/mdstat
mdadm --detail /dev/md0
df -h /mnt/raid1

# Monitor rebuild/sync progress
watch cat /proc/mdstat

# Stop sync if needed
echo none | sudo tee /sys/block/md0/md/sync_action
```

## Debugging and Maintenance

### Cloud-init Logs

Primary log file: `/var/log/cloud-init-output.log`

```bash
# View cloud-init output
sudo cat /var/log/cloud-init-output.log
sudo journalctl -u cloud-init

# Check cloud-init status
cloud-init status --long
cloud-init analyze show
```

### Testing Individual Modules

```bash
# Test user/group creation
sudo cloud-init single --name users_groups --frequency always

# Test package installation
sudo cloud-init single --name package_update_upgrade_install --frequency always

# Test disk setup
sudo cloud-init single --name disk_setup --frequency always
```

### Modifying Configuration

**CRITICAL WARNING**: Setting `fs_setup: overwrite: true` will destroy RAID data!

**Safe modification process:**

1. **Before editing**, set overwrite to false for existing partitions in `user-data.template`:
   ```yaml
   fs_setup:
     - label: raid1-disk1
       filesystem: ext4
       device: /dev/sda1
       overwrite: false  # CRITICAL: prevents data loss
   ```

2. **Edit configuration** in `user-data.template`

3. **Regenerate configuration**:
   ```bash
   ./generate-userdata.sh
   sudo cp user-data /boot/firmware/user-data
   ```

4. **Clean up before reboot:**
   ```bash
   # Wait for RAID sync to complete
   watch cat /proc/mdstat
   
   # Stop Docker containers
   docker stop ddclient && docker rm ddclient
   
   # Remove generated configuration files
   sudo rm -R /etc/dnsmasq.d/*.conf /etc/iptables/rules.v4 /etc/netplan/50-cloud-init.yaml \
     /usr/local/bin/show-dhcp-leases /usr/local/bin/check-network \
     /etc/mdadm/mdadm.conf /etc/samba/smb.conf
   
   # Clean cloud-init state and reboot
   sudo cloud-init clean --logs --reboot
   ```

5. **System will reboot** and re-apply cloud-init configuration.

### Common Issues

#### RAID Array Not Created
```bash
# Check if drives are detected
lsblk

# Check mdadm status
cat /proc/mdstat
mdadm --detail /dev/md0

# Manually create if needed
sudo mdadm --create --run --verbose /dev/md0 \
  --level=mirror --raid-devices=2 /dev/sda1 /dev/sdb1
```

#### Network Not Configured
```bash
# Check network status
ip addr show eth0
systemctl status systemd-networkd

# Verify netplan configuration (static IP and VLAN interfaces)
sudo cat /etc/netplan/50-cloud-init.yaml
sudo netplan apply
sudo check-network
```

#### Docker Service Not Starting
```bash
# Check Docker status
systemctl status docker
docker info

# Restart Docker
sudo systemctl restart docker

# Check logs
journalctl -u docker -n 50
```

#### Samba Shares Not Accessible
```bash
# Check Samba status
systemctl status smbd

# Test configuration
testparm -s

# Verify share permissions
ls -la /mnt/raid1/

# Check Samba users
pdbedit -L -v

# Restart Samba
sudo systemctl restart smbd
```

## Security Considerations

### Credentials Management

**Current state**: Secrets managed via external environment file

**Security model**:
- Secrets stored in `secrets.env` (gitignored, never committed)
- Template (`user-data.template`) committed to version control without secrets
- `generate-userdata.sh` validates and generates final `user-data` locally
- Generated `user-data` contains secrets but is gitignored
- Only `secrets.env.example` (with placeholders) is committed

**Security considerations**:
- Samba passwords visible in generated `user-data` runcmd section (plaintext)
- Dynamic DNS token visible in docker run command (plaintext)
- SSH default password "hypriot" must be changed on first login (enforced)
- `secrets.env` should have restricted permissions (chmod 600)

**Future improvements**: 
- [ ] Encrypt secrets file (e.g., ansible-vault, sops, age)
- [ ] Use cloud-init's built-in secret management features
- [ ] Store secrets in external vault (HashiCorp Vault, pass, etc.)

### Network Security

- Change default password on first login (enforced by `chpasswd: expire: true`)
- Use SSH keys instead of password authentication
- Configure firewall (not currently implemented)
- VPN for remote access (optional, configure with rpi-vpn-server)

### Samba Security

- User shares have restricted permissions (700)
- Public share allows guest access (consider disabling if not needed)
- Update Samba passwords regularly

## Development Workflow

### Making Changes

1. **Edit** `user-data.template` in this repository
2. **Update secrets** in `secrets.env` if needed
3. **Regenerate** user-data: `./generate-userdata.sh`
4. **Validate** syntax: `cloud-init schema --config-file user-data`
5. **Test** in development environment (spare Pi or VM)
6. **Document** changes in commit message
7. **Deploy** by copying to /boot/firmware/user-data and following cleanup procedure

### Version Control

```bash
# Track changes
git diff user-data.template

# Commit with descriptive message
git add user-data.template
git commit -m "feat: add new Docker service for monitoring"

# Tag releases
git tag -a v2.0.0 -m "Ubuntu 26.04 LTS with UniFi OS Server"
```

## Future Enhancements

- [x] Load secrets from external environment file (implemented via generate-userdata.sh)
- [ ] Encrypt secrets file (e.g., with ansible-vault or sops)
- [ ] Add UPS (uninterruptible power supply) support
- [ ] Implement graceful shutdown script on power loss
- [ ] Add monitoring (Prometheus/Grafana)
- [ ] Configure firewall (ufw or iptables)
- [ ] Backup automation for RAID array
- [ ] Health check notifications
- [ ] Email alerts for RAID degradation

## External Resources

### Official Documentation
- [cloud-init docs](https://cloudinit.readthedocs.io/)
- [Ubuntu Server Raspberry Pi](https://ubuntu.com/download/raspberry-pi)
- [Docker documentation](https://docs.docker.com/)
- [mdadm man page](https://linux.die.net/man/8/mdadm)
- [Samba documentation](https://www.samba.org/samba/docs/)

### Related Projects
- [rpi-dyndns](https://github.com/netzfisch/rpi-dyndns) - Dynamic DNS updater
- [rpi-vpn-server](https://github.com/netzfisch/rpi-vpn-server) - VPN server setup
- [Self-Hosting UniFi](https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi) - UniFi OS Server

### Community Resources
- [MagPi Magazine NAS Guide](https://magpi.raspberrypi.org/articles/build-a-raspberry-pi-nas)
- [cloud-init examples](https://cloudinit.readthedocs.io/en/latest/reference/examples.html)

## License

MIT License - See LICENSE file

## Contact & Support

For issues with this configuration, check:
1. `/var/log/cloud-init-output.log` on the target system
2. The project's GitHub repository issues.
3. Ubuntu Server and cloud-init community forums.

---

**Document Version**: 2.0  
**Last Updated**: 2026-11-25