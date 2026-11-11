# install/ (unattended Linux install)

Milestones M4 (install) and M6 (disk image and rollback). **Ubuntu 24.04 LTS autoinstall** (Subiquity), booted over PXE from the server in `server/`. The desktop packages come from the internet during the install.

| File | Runs | What |
|---|---|---|
| `user-data.tmpl` | – | the autoinstall answers: locale `de_CH`, keyboard `ch`, admin user, OpenSSH, whole disk. Rendered by `server/setup.sh`. |
| `mtx-early.sh` | in the installer, **before** the disk is touched | does the PXE job: `install`, `migrate` (upload a disk image first), `restore` (write the image back and reboot). Without a job it refuses. |
| `mtx-late.sh` | in the installer, after the install | copies the MigraTux scripts and the first-boot hook into the new system, switches the network to NetworkManager, removes the PXE job on the server. |
| `migratux-firstboot.service` | first boot, before the login screen | starts `firstboot.sh` once. |
| `firstboot.sh` | first boot | fetches the newest scripts from the server and starts `reconfigure/reconfigure.sh`. Again by hand: `sudo migratux-firstboot --force`. |

How a PC is recognised after the install: by the **MAC address** of its network card, which the Windows inventory recorded.

The disk image is a compressed copy of the whole disk (`dd | zstd`), sent to the server over HTTP. It is slow for large disks but works with every partition layout and file system.

Logs on the client: `/var/log/migratux/install.log`, `firstboot.log`. In the installer: `/var/log/migratux-early.log`.

Tests: `tests/run.sh bats` (disk image and restore with files as disks, YAML checks). Manual: [M4](../docs/testing/M4-autoinstall.md), [M6](../docs/testing/M6-rollback.md).
