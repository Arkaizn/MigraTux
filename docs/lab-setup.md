# MigraTux test lab setup

You have three zip files. Each one is a VM for VMware Workstation.

| VM | What it is | RAM |
|---|---|---|
| `mtx-server` | the MigraTux server (Ubuntu Server with Docker) | 4 GB |
| Windows Client | the Windows 10 PC that gets migrated | 4 GB |
| `mtx-client-pxe` | an empty PC; Linux gets installed on it | **8 GB** |

The test guides call the Windows Client `mtx-win` and the empty PC `mtx-pxe`.

Your computer needs 16 GB RAM, 150 GB free disk space and internet.

## 1. Open the VMs

1. Unpack each zip into its own folder.
2. In VMware: **File → Open** and choose the `.vmx` file. Do this for all three.
3. If VMware asks "moved or copied?", choose **I Copied It**.
4. Open the settings of each VM and check:
   - Network Adapter is **NAT** (all three)
   - `mtx-client-pxe` has **8 GB** memory
5. Take a snapshot of `mtx-client-pxe` (**VM → Snapshot → Take Snapshot**) and name it `pxe-empty`.

## 2. Set up the server

Start `mtx-server`, log in and type these commands.

1. Get the newest code:
   ```bash
   cd ~/MigraTux
   git pull
   ```
2. Look up the server's network name and IP address:
   ```bash
   ip -4 -br addr
   ```
   Example output: `ens33  UP  192.168.80.130/24`. Here the name is `ens33` and the IP is `192.168.80.130`. Write yours down.
3. Create the settings file:
   ```bash
   cd server
   cp .env.example .env
   nano .env
   ```
   Change `SERVER_IP=` and `PXE_INTERFACE=` to your two values. Save with Ctrl+O, Enter. Close with Ctrl+X.
4. Run the setup (downloads 3.9 GB, takes a while):
   ```bash
   ./setup.sh
   ```
   The last line must say `setup: done`.
5. Start the server:
   ```bash
   docker compose up -d
   docker compose ps
   ```
   `samba`, `pxe` and `http` must all say "running".
6. Shut the VM down (`sudo poweroff`), take a snapshot and name it `server-clean`.

## 3. Set up Windows

Start the Windows Client, log in and open **Windows PowerShell**.

1. Put the MigraTux code into `C:\migratux`:
   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
   Invoke-WebRequest https://github.com/Arkaizn/MigraTux/archive/refs/heads/main.zip -OutFile $env:TEMP\mtx.zip
   Remove-Item C:\migratux, C:\MigraTux-main -Recurse -Force -ErrorAction SilentlyContinue
   Expand-Archive $env:TEMP\mtx.zip C:\
   Rename-Item C:\MigraTux-main migratux
   ```
   Run the same block again whenever you need the newest code.
2. Shut Windows down, take a snapshot and name it `win-clean`.

## 4. Test

Yes, every guide must be tested. Do them in this order:

1. [M3: server and network boot](testing/M3-server-pxe.md)
2. [M4: Linux installs by itself](testing/M4-autoinstall.md)
3. [M1: Windows inventory](testing/M1-inventory.md)
4. [M0: scripts on Windows PowerShell 5.1](testing/M0-ps51-checker.md)
5. [M2: backup](testing/M2-backup.md)
6. [M5: full chain, apps and files arrive on Linux](testing/M5-reconfigure.md)
7. [M6: rollback to Windows](testing/M6-rollback.md)
8. [M7: control command and info screen](testing/M7-cli.md)

Every guide starts from the clean snapshots (`server-clean`, `win-clean`, `pxe-empty`) and tells you which VMs it needs.
At the end of each guide, fill in "What to send back" and send it with the log files.
