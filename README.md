# MigraTux

Automated migration of Windows PCs to Linux for small Swiss businesses (KMU). Prototype for the GBS St.Gallen project "Die Höhle der Löwen".

The idea: a technician starts MigraTux, and each PC is migrated with as little manual work as possible:

1. **Collect**: a PowerShell script reads what is on the Windows PC (apps, user folders, printers, network drives, hardware) into a CSV.
2. **Back up**: user data and the CSV go to a file share on the MigraTux server.
3. **Install**: the PC boots from the network (PXE) and Ubuntu 24.04 installs itself without input.
4. **Reconfigure**: on first boot, Linux reads the CSV, installs the Linux alternatives for the Windows apps and restores the data.
5. **Rollback**: a disk image taken before the wipe can bring Windows back.

Status: early prototype. Milestones M0–M9; M0 (repo foundation) is done.

## Folders

| Folder | What | Runs on |
|---|---|---|
| `collect/` | Windows inventory and backup scripts (PowerShell) | Windows PC |
| `server/` | Docker Compose: Samba share, PXE (dnsmasq proxy-DHCP + TFTP), HTTP | MigraTux server |
| `install/` | Ubuntu 24.04 autoinstall files | PC during install |
| `reconfigure/` | Post-install: apps, data, printers | Linux PC after install |
| `mapping/` | `apps.csv` (Windows app → Linux alternative) and `map-apps.sh` | anywhere |
| `docs/contracts/` | File formats shared between steps, e.g. [inventory CSV](docs/contracts/inventory-csv.md) | – |
| `docs/testing/` | Step-by-step manual VM tests, one per milestone ([template](docs/testing/TEMPLATE.md)) | – |
| `tests/` | Automatic tests (Pester, bats) and fixtures | dev machine |

## Running the tests

No VM needed. You need PowerShell 7 (`pwsh`) with Pester 5, and Docker (or local `shellcheck` and `bats`).

```bash
# once: install Pester for your user
pwsh -c 'Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck'

tests/run.sh            # everything: Pester, shellcheck, bats
tests/run.sh pester     # PowerShell tests only
tests/run.sh lint       # shellcheck only
tests/run.sh bats       # shell tests only
tests/run.sh --local    # use local shellcheck/bats instead of Docker
```

Docker mode builds a small Ubuntu 24.04 image (`tests/docker/Dockerfile`), so shell code is tested with the same `awk` and `bash` as on the migrated PCs. Your user must be in the `docker` group.

Manual tests on VMs: see `docs/testing/`.

## For the inventory script author

Match [docs/contracts/inventory-csv.md](docs/contracts/inventory-csv.md). In short: 8 columns `Hostname,Category,Name,Version,Publisher,Path,SizeMB,Extra`, comma, UTF-8 with BOM, `Export-Csv -NoTypeInformation -Encoding UTF8`. Check your output with `collect\Test-InventoryCsv.ps1 -Path <file>`.

## License

GPLv3, see [LICENSE](LICENSE).
