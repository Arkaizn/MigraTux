# Contract: what lies where on the server

Everything the steps of the chain hand to each other goes through the MigraTux server. This page defines the folders and files. Version 1, 2026-11-11. `<DATA>` is `DATA_DIR` from `server/.env` (default `server/data`).

## Share `\\SERVER\migratux` = `<DATA>/share`

One folder per client, named like the Windows computer name.

| Path | Written by | Read by | Content |
|---|---|---|---|
| `<HOST>/inventory-<HOST>.csv` | `collect/Backup-ToServer.ps1` | `migratux`, `reconfigure.sh` | the inventory, see [inventory-csv.md](inventory-csv.md) |
| `<HOST>/data/<user>/<Folder>/…` | `Backup-ToServer.ps1` | `reconfigure.sh` | user files. `<user>` and `<Folder>` are the `user=` value and the `Name` of the `userfolder` row |
| `<HOST>/manifest.sha256` | `Backup-ToServer.ps1`, **last** | `migratux start`, `reconfigure.sh` | one line per file, see below. **If this file exists, the backup is complete.** |
| `<HOST>/backup.log` | `Backup-ToServer.ps1` | people | log of the backup |
| `<HOST>/report.txt` | `reconfigure.sh` | people | what was installed, what is missing |
| `<HOST>/reconfigure.log` | `reconfigure.sh` | people | log of the first boot |
| `_assign/<mac-with-hyphens>` | `migratux assign` | `migratux`, `reconfigure.sh` | one line: the `<HOST>` this MAC counts as. While a host has assignments, jobs go only to these MACs, not to the ones in its inventory. |

### manifest.sha256

The format of `sha256sum`, so Linux checks it with `sha256sum -c manifest.sha256` inside `<HOST>/`:

```
<64 hex digits, lower case><two spaces>data/<user>/<Folder>/<path with forward slashes>
```

UTF-8 **without** BOM, LF line ends, one line per file.

## Outside the share

| Path | Written by | Read by | Content |
|---|---|---|---|
| `<DATA>/tftp/grub/hosts/<mac>.cfg` | `migratux start\|rollback` | GRUB on the client | the PXE job: `set mtx_mode=…` and `set mtx_host=…`. `<mac>` lower case with colons. Deleted by the client over HTTP when the job is done. |
| `<DATA>/images/<HOST>/disk.img.zst` (or `.gz`) | `install/mtx-early.sh` (HTTP PUT) | the same script in restore mode | compressed copy of the whole disk |
| `<DATA>/images/<HOST>/disk.info` | `mtx-early.sh`, **last** | `migratux`, `mtx-early.sh` | `key=value` lines: `host`, `disk`, `size_bytes`, `ext`, `sha256` (of the compressed file), `mac`, `date`. **If this file exists, the image is complete.** |
| `<DATA>/events/<mac-with-hyphens>/<step>` | the client (HTTP PUT) | `migratux status` | one line of text per step; the file time is the time of the event |
| `<DATA>/log/` | `setup.sh`, `migratux` | people | `setup.log`, `migratux.log` |

## PXE job modes

| Mode | Set by | What the client does at the next network boot |
|---|---|---|
| `install` | `migratux start MAC`, `start HOST --no-image` | install Ubuntu |
| `migrate` | `migratux start HOST` | upload a disk image (unless one exists), then install |
| `migrate-new` | `migratux start HOST --new-image` | upload a new disk image, then install |
| `restore` | `migratux rollback HOST` | write the disk image back, reboot, no install |

A client without a job boots from its disk.

## HTTP (port `HTTP_PORT`)

| URL | Methods | For |
|---|---|---|
| `/ubuntu.iso`, `/autoinstall/`, `/files/` | GET | installer, `user-data`, `migratux-client.tar.gz`, `client.env` |
| `/pxe/hosts/<mac>.cfg` | GET, DELETE | a client removes its own job |
| `/events/<mac>/<step>` | GET, PUT | status |
| `/images/<HOST>/<file>` | GET, PUT | disk images |

No login and no TLS: lab prototype.
