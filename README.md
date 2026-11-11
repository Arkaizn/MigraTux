# MigraTux

Automated migration of Windows PCs to Linux for small Swiss businesses (KMU). Prototype for the GBS St.Gallen project "Die Höhle der Löwen".

The idea: a technician starts MigraTux, and each PC is migrated with as little manual work as possible:

1. **Collect**: a PowerShell script reads what is on the Windows PC (apps, user folders, printers, network drives, hardware) into a CSV.
2. **Back up**: user data and the CSV go to a file share on the MigraTux server.
3. **Install**: the PC boots from the network (PXE) and Ubuntu 24.04 installs itself without input.
4. **Reconfigure**: on first boot, Linux reads the CSV, installs the Linux alternatives for the Windows apps and restores the data.
5. **Rollback**: a disk image taken before the wipe can bring Windows back.

Status: prototype. All parts (M1–M7) are written and pass the automatic tests, but **none has been tested on real VMs yet**. Plain-language overview: [docs/progress.md](docs/progress.md).

## How a migration runs

```
Windows PC:   .\collect\Get-Inventory.ps1          -> inventory CSV
              .\collect\Backup-ToServer.ps1        -> files + CSV on the server, verified
Server:       ./migratux start <PC-NAME>           -> job for the next network boot
PC:           boot from the network (PXE)          -> disk image to the server, Ubuntu installs,
                                                      first boot installs apps and restores files
Server:       ./migratux status                    -> follow every step
If it fails:  ./migratux rollback <PC-NAME>, boot from the network -> Windows is back
```

Server setup: [server/README.md](server/README.md).

## Folders

| Folder | What | Runs on |
|---|---|---|
| `collect/` | Windows inventory and backup scripts (PowerShell) | Windows PC |
| `server/` | Docker Compose: Samba share, PXE (dnsmasq proxy-DHCP + TFTP), HTTP; the `migratux` command | MigraTux server |
| `install/` | Ubuntu 24.04 autoinstall files, disk image and rollback, first-boot hook | PC during install |
| `reconfigure/` | Post-install: apps, users, data, report, info screen | Linux PC after install |
| `mapping/` | `apps.csv` (Windows app → Linux alternative) and `map-apps.sh` | anywhere |
| `lib/` | Shell functions shared by server and client scripts | – |
| `docs/contracts/` | Formats shared between steps: [inventory CSV](docs/contracts/inventory-csv.md), [server layout](docs/contracts/server-layout.md) | – |
| `docs/testing/` | Step-by-step manual VM tests, one per milestone ([template](docs/testing/TEMPLATE.md)) | – |
| `tests/` | Automatic tests (Pester, bats) and fixtures | dev machine |

## Running the tests

No VM needed. You need PowerShell 7 (`pwsh`) with Pester 5, and Docker (or local `shellcheck` and `bats`).

```bash
# once: install Pester for your user
pwsh -c 'Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck'

tests/run.sh            # everything: Pester, shellcheck, bats, server check
tests/run.sh pester     # PowerShell tests only
tests/run.sh lint       # shellcheck only
tests/run.sh bats       # shell tests only
tests/run.sh server     # build the server images and check them with the rendered config
tests/run.sh --local    # use local shellcheck/bats instead of Docker
```

Docker mode builds a small Ubuntu 24.04 image (`tests/docker/Dockerfile`), so shell code is tested with the same `awk` and `bash` as on the migrated PCs. Your user must be in the `docker` group.

These tests use mocks and files instead of Windows, disks and network boot. Whether the real thing works is shown only by the manual VM tests in `docs/testing/`, in this order: M3, M4, M1, M2, M5, M6, M7.

## For the inventory script author

Match [docs/contracts/inventory-csv.md](docs/contracts/inventory-csv.md). In short: 8 columns `Hostname,Category,Name,Version,Publisher,Path,SizeMB,Extra`, comma, UTF-8 with BOM, `Export-Csv -NoTypeInformation -Encoding UTF8`. Check your output with `collect\Test-InventoryCsv.ps1 -Path <file>`.

## License

GPLv3, see [LICENSE](LICENSE).
