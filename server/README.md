# server/ (Docker Compose on the MigraTux server)

Milestone M3. Planned, not built yet. Runs on `mtx-server` (Ubuntu Server 24.04) or the server laptop.

Planned services:
- **samba**: share `migratux`, one folder per client: `\\server\migratux\<hostname>\` (inventory CSV, user data, disk image).
- **dnsmasq**: proxy-DHCP (gives only the PXE boot info; the existing router keeps handing out IPs) + TFTP for the UEFI/BIOS boot files. Needs host networking.
- **http**: serves the Ubuntu ISO / kernel / initrd and the autoinstall files from `install/`.

Decisions: PXE (brain adr-008), Ubuntu 24.04 autoinstall (brain adr-009).
