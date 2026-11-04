# install/ (unattended Linux install)

Milestone M4. Planned, not built yet.

**Ubuntu 24.04 LTS autoinstall** (Subiquity, cloud-init `user-data` YAML), booted over PXE from the server in `server/`.

Planned contents:
- `user-data` / `meta-data`: disk layout, locale `de_CH`, keyboard `ch`, a local admin user, OpenSSH, desktop packages.
- First-boot hook that fetches the client's inventory CSV from the server and starts `reconfigure/`.
