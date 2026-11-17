# Manual test results

Results of the manual VM tests, next to the guides in [`docs/testing/`](../).

## What is in here

| Path | What it is |
|---|---|
| `M<n>-<date>.md` | one result file per test day, e.g. `M3-2026-11-16.md`. It is the filled-in "What to send back" block of the guide, plus notes on each run. |
| `m<n>/` | logs and screenshots for that test, e.g. `m3/m3-grub-menu.png`, `m3/m3-compose.log`. |

## How to add a result

1. Copy the "What to send back" block from the guide into a new file `M<n>-<YYYY-MM-DD>.md`.
2. Fill it in. Write one line per expected-result box: `OK`, `FAILED` or `pending`.
3. If a test needed more than one run, describe every run. A failed run is a result too.
4. Put the log files and screenshots into `m<n>/` and link them from the result file. Name them `m<n>-<what>.<ext>`.
5. Add a link to the result file in the "Results" section at the end of the guide.

## Rules

- **This repo is public. No passwords in result files, logs or screenshots.** Name the setting instead (e.g. "`SMB_PASSWORD` from `server/.env`"). Check logs before you add them.
- Do not change an old result file after the fact. A new test day gets a new file.

## Results so far

| Test | Date | Result | File |
|---|---|---|---|
| M3 | 2026-11-16 | OK | [M3-2026-11-16.md](M3-2026-11-16.md) |
| M4 | 2026-11-16 | FAILED (the ISO did not fit into RAM; led to the switch to NFS) | [M4-2026-11-16.md](M4-2026-11-16.md) |
| M4 | 2026-11-17 | OK in runs 3 and 4 (NFS netboot; needs internet; e1000 hang fixed with vmxnet3; works with 4 GB RAM) | [M4-2026-11-17.md](M4-2026-11-17.md) |
| M1 | 2026-11-17 | OK (Windows 10, PowerShell 5.1; Store apps not listed: known limit) | [M1-2026-11-17.md](M1-2026-11-17.md) |
| M0 | 2026-11-17 | OK (contract checker and Pester on Windows PowerShell 5.1: Failed 0, Skipped 3) | [M0-2026-11-17.md](M0-2026-11-17.md) |
