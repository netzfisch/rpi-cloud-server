# Cloud Server for the Raspberry PI

Turn your [Raspberry PI](http://raspberrypi.org) within **15 minutes** into a **Cloud Server** allowing **access from remote** networks as well as serving any **Docker Container**.

Inspired by he [The MagPi Magazine](https://magpi.raspberrypi.org/articles/build-a-raspberry-pi-nas) about **creating a cloud server with the new Raspberry Pi 4** I added

* [cloud-init](https://cloud-init.io/) for automatic **provisioning of customized cloud instances**,
* [rpi-dyndns](https://github.com/netzfisch/rpi-dyndns) for **dynamic DNS** resolution and
* [rpi-vpn-server](https://github.com/netzfisch/rpi-vpn-server) to **access the server** from a remote network and
* based it on **Ubuntu Server 25.10** (ARM64) for **docker host/server** functionality.

If you find this useful, **do not forget to star** the repository ;-)

## Requirements

- [Raspberry PI](http://raspberrypi.org)
- other [Hardware](https://magpi.raspberrypi.org/articles/build-a-raspberry-pi-nas)
- Dynamic DNS service provider, e.g. from [Securepoint](https://www.spdns.de/)

### Setup

#### Step 1: Configure Secrets

- **Create secrets file** from the example template:

```sh
$ cp secrets.env.example secrets.env
```

- **Edit secrets.env** and replace ALL placeholder values with your actual configuration:
  - User credentials (admin password, Samba passwords)
  - Network settings (static IP, gateway, DNS servers)
  - VLAN configuration (VLAN IDs, DHCP ranges, upstream DNS server)
  - Dynamic DNS hostname and token

**IMPORTANT:** Never commit `secrets.env` to version control - it's already in `.gitignore`.

#### Step 2: Generate User-Data

- **Make the generation script executable** (first time only):

```sh
$ chmod +x generate-userdata.sh
```

- **Run the generation script** to generate the final user-data file:

```sh
$ ./generate-userdata.sh
```

This will:
- Validate that all required secrets are configured
- Warn about placeholder values (CHANGE_ME)
- Generate the final `user-data` file with your secrets
- Validate the cloud-init schema (if cloud-init is installed)

#### Step 3: Flash SD Card

- Download the latest **Ubuntu Server image** for Raspberry Pi from [ubuntu.com/download/raspberry-pi](https://ubuntu.com/download/raspberry-pi)
- Flash the SD-Card using `dd` and copy the generated user-data file to the system-boot partition:

```sh
$ unxz ubuntu-25.10-preinstalled-server-arm64+raspi.img.xz
$ pv ubuntu-25.10-preinstalled-server-arm64+raspi.img | \
  sudo dd iflag=fullblock of=/dev/mmcblk0 bs=64M oflag=direct && sync
$ cp user-data /media/$USER/system-boot/user-data
```

- Put the SD-Card back into the Raspberry and boot. The server will be **automatically provisioned** and set up.

#### Step 4: Configure Your Router

**This step is mandatory for the network features to work correctly.** Your main network router (e.g., FritzBox, Unifi Dream Machine) must be configured to work with the Raspberry Pi's VLANs and DNS server.

1.  **Add Static Routes:**
    Your router needs to know how to reach the IoT and Guest networks. Add static routes in your router's network settings, pointing to the Raspberry Pi.

    - **IoT Network Route:**
      - **Network:** `192.168.20.0`
      - **Subnet Mask:** `255.255.255.0`
      - **Gateway/Next-Hop:** `192.168.10.10` (the Pi's static IP)

    - **Guest Network Route:**
      - **Network:** `192.168.30.0`
      - **Subnet Mask:** `255.255.255.0`
      - **Gateway/Next-Hop:** `192.168.10.10` (the Pi's static IP)

2.  **Set Local DNS Server:**
    To resolve local hostnames like `printer.home`, your router must tell clients to use the Raspberry Pi for DNS.

    - In your router's DHCP settings for your main LAN, set the **Local DNS Server** to the Raspberry Pi's static IP (`192.168.10.10`).
    - After changing this, devices on your network must get a new DHCP lease (e.g., by rebooting them or reconnecting to the network) to receive the new DNS setting.

With these settings, your router will correctly forward traffic to the VLANs and all devices on your main network will be able to use the `.home` domain.

## Network Topology

The system implements **VLAN-based network segmentation** for enhanced security and organization:

- **Privat VLAN (untagged)** - `192.168.10.0/24`: Management network for server administration
  - Pi static IP: `192.168.10.10`
  - Manual DHCP management via router (e.g., FritzBox)
 
- **IoT VLAN 20** - `192.168.20.0/24`: Isolated network for IoT devices
  - Pi gateway: `192.168.20.1`
  - DHCP range: `192.168.20.50` - `192.168.20.200` (managed by dnsmasq)
 
- **Guest VLAN 30** - `192.168.30.0/24`: Isolated network for guest access
  - Pi gateway: `192.168.30.1`
  - DHCP range: `192.168.30.50` - `192.168.30.200` (managed by dnsmasq)

**Security Features:**
- The Pi acts as DHCP/DNS server for IoT and Guest VLANs
- iptables provides NAT for WAN access from all VLANs
- Firewall rules enforce isolation: IoT and Guest VLANs **cannot** access Privat network
- Management access (SSH, Samba, Unifi) only from Privat VLAN

**Prerequisites:**
- Network switch with VLAN support (802.1Q tagging)
- VLAN configuration on upstream router/switch matching VLAN IDs

## Automatic Provisioning

- The system will automatically set up:
  - RAID1 storage with two external drives (/dev/sda, /dev/sdb)
    - **Note**: The provisioning script handles all RAID scenarios (fresh disks, existing arrays, or reused drives) by automatically cleaning any previous RAID metadata before creating the array. This ensures the RAID is always created as `md0` instead of auto-assembling as `md127`.
    - **CRITICAL WARNING**: Setting `fs_setup: overwrite: true` will destroy RAID data! Always set `overwrite: false` for existing partitions.
  - VLAN networking with netplan (Privat/IoT/Guest segmentation)
  - dnsmasq DHCP/DNS server for IoT and Guest VLANs
  - iptables firewall with NAT and inter-VLAN isolation
  - Samba shares (user1, user2, shared, public)
  - Docker containers: **Unifi Controller** (network management) and **ddclient** (dynamic DNS)
  - Custom MOTD with system status display (RAID, Docker, Samba, dnsmasq, DHCP leases)
- **First login**: SSH as `pirate@192.168.10.10` with password `hypriot`
  - You will be prompted to change the password immediately
  - After changing the password, the session will close (this is expected)
  - Log in again with your new password
- For configuration of DynDNS and VPN check the respective documentation,
  especially
  - set the update token for [rpi-dyndns](https://github.com/netzfisch/rpi-dyndns),
  - import/generate the secrets for [rpi-vpn-server](https://github.com/netzfisch/rpi-vpn-server), and
  - enable port forwarding at your firewall for the UDP ports 500 and 4500.
- Access the system via SSH: `ssh pirate@192.168.10.10` (default password: hypriot, must change on first login)
- Access Unifi Controller web UI: `https://192.168.10.10:8443`
- **Done!**

### Debugging

Before debugging, ensure you have completed the **Router Configuration** steps in this guide. Many network issues are caused by missing static routes or incorrect DNS settings on the main router.

Log into the instance, check the logs at `/var/log/cloud-init-output.log`, and run single commands to verify:

    $ sudo cloud-init single --name users --frequency always
    $ sudo cloud-init single --name disk_setup --frequency always
    $ sudo cloud-init single --name runcmd --frequency always

Check RAID status and system configuration:

    $ cat /proc/mdstat
    $ mdadm --detail /dev/md0
    $ df -h /mnt/raid1
    $ docker ps

Check VLAN networking:

    $ ip addr show
    $ ip route
    $ systemctl status dnsmasq
    $ cat /var/lib/misc/dnsmasq.leases
    $ iptables -L -n -v -t nat
    $ iptables -L -n -v -t filter

Trace network paths to diagnose routing issues:

    $ mtr 192.168.20.184  # Example: trace path to a device on the IoT network

Run comprehensive network diagnostics:

    $ sudo check-network

This helper script checks:
- VLAN interface status (eth0, eth0.20, eth0.30)
- dnsmasq DHCP/DNS service status and lease count
- IP forwarding configuration
- iptables NAT and FORWARD rules
- DNS resolution test
- Gateway connectivity

### Re-running Cloud-Init (Safe Procedure)

The configuration includes **automatic RAID protection** - the RAID array will NOT be destroyed when re-running cloud-init thanks to conditional checks in the provisioning script.

**Safe re-run procedure:**

1. **Wait for RAID sync** to complete:
   ```sh
   $ watch cat /proc/mdstat  # wait until status shows [UU]
   ```

2. **Clean up auto-generated files:**
   ```sh
   $ sudo rm -R /etc/dnsmasq.d/*.conf /etc/iptables/rules.v4 /etc/netplan/50-cloud-init.yaml \
     /usr/local/bin/show-dhcp-leases /usr/local/bin/check-network \
     /etc/mdadm/mdadm.conf /etc/samba/smb.conf \
     /opt/unifi/compose.yml /opt/unifi/unifi.service
   ```

3. **Stop and remove Docker containers:**
   ```sh
   $ docker stop ddclient unifi && docker rm ddclient unifi
   ```

4. **Re-run cloud-init** (RAID data will be preserved):
   ```sh
   $ sudo cloud-init clean --logs --reboot
   ```

**How RAID protection works:**
- The `runcmd` section checks if `/dev/md0` exists before creating RAID
- If RAID exists, creation is skipped and existing array is used
- `disk_setup: overwrite: false` and `fs_setup: overwrite: false` prevent partition/filesystem recreation
- Your data in `/mnt/raid1` remains completely intact

Edit `/boot/firmware/user-data` for advanced configuration, see the [documentation](https://cloudinit.readthedocs.io/) for details.

## Project Structure

```
rpi-cloud-server/
├── .gitignore              # Ensures secrets stay private
├── generate-userdata.sh    # Script to generate user-data from template
├── README.md               # This tradional file ;-)
├── secrets.env             # Your actual secrets (gitignored, never commit!)
├── secrets.env.example     # Example template (commit to git)
├── user-data               # Generated file (gitignored, created by generate-userdata.sh)
└── user-data.template      # Template with variable placeholders (commit to git)
```

## TODO

- [x] Reference and load secrets from local environment file via generation script
- [ ] Add uninterruptible power supply, e.g. USB powerbank
- [ ] Add script to act on "power loss" to shutdown server properly

## License

The MIT License (MIT), see [LICENSE](https://github.com/netzfisch/rpi-cloud-server/blob/master/LICENSE) file.
