# server/ (Docker Compose on the MigraTux server)

Milestones M3 (stack), M6 (disk images) and M7 (`migratux` command). Runs on `mtx-server` (Ubuntu Server 24.04 with Docker) or the server laptop. **Lab prototype: no TLS, passwords are served over plain HTTP.**

## Start

```bash
cd server
cp .env.example .env      # set SERVER_IP and PXE_INTERFACE (ip -4 -br addr)
./setup.sh                # builds images, downloads the Ubuntu ISO (3.9 GB), renders the config
docker compose up -d
./migratux status
```

Run `./setup.sh` again after every `git pull` or change of `.env`: it keeps the downloads and rebuilds config and client scripts.

## Services

| Service | What | Network |
|---|---|---|
| `samba` | share `\\SERVER_IP\migratux`, one folder per client | port 445 |
| `pxe` | dnsmasq: proxy-DHCP (boot info only, the router keeps handing out IPs) + TFTP. UEFI clients only. | host network |
| `http` | nginx: ISO, autoinstall files, client scripts; receives status events and disk images | `HTTP_PORT` (8080) |

## The `migratux` command

```
./migratux status [HOST]                 clients, backup, disk image, PXE job, last step
./migratux start HOST [--no-image|--new-image] [--force]
./migratux start MAC                     install only, for a PC without inventory
./migratux rollback HOST [--no-verify]   write the disk image back (Windows)
./migratux stop HOST|MAC                 remove the PXE job
./migratux assign HOST MAC               lab: install HOST on another machine
./migratux unassign HOST
```

A PC installs **only** when it has a job (`start`/`rollback`). Without a job, a PC that boots from the network just starts from its disk. `start HOST` refuses when the backup is not finished or the disk is too small. The client removes its job itself when it is done.

## Files

| File | What |
|---|---|
| `.env.example` | all settings; copy to `.env` (not in git) |
| `setup.sh` | one-time and repeatable setup |
| `migratux` | control command |
| `lib.sh` | shared shell functions |
| `docker-compose.yml`, `samba/`, `pxe/`, `http/nginx.conf` | the stack |
| `setup/` | helper image: signed UEFI boot loader, ISO download |
| `templates/` | config templates, `@KEY@` is replaced by the value from `.env` |
| `data/` | downloads, share, images, logs (not in git). Layout: [docs/contracts/server-layout.md](../docs/contracts/server-layout.md) |

Logs: `data/log/setup.log`, `data/log/migratux.log`, `docker compose logs`.

Tests: `tests/run.sh` (bats + a container check of the rendered config). Manual: [M3](../docs/testing/M3-server-pxe.md), [M6](../docs/testing/M6-rollback.md), [M7](../docs/testing/M7-cli.md).
