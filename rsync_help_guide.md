# rsync Command Help and Examples

`rsync` is a powerful utility for synchronizing files and directories between locations over a network or locally. This guide simplifies the `rsync` options and includes examples to help beginners. In this guide, focus on the **options** section, as the `rsync`, `source`, and `destination` parts are already handled in your app.

---

## Basic Usage

```bash
rsync [options] source destination
```

- **source**: The path to the file(s) or directory you want to copy.
- **destination**: The target location where files will be copied.

> In rsync-manager, only provide the `options` part in the form; `source` and `destination` are set from the folder selector.

---

## Common Options and Flags

### Basic Flags
- `-a`: Archive mode. This preserves symbolic links, permissions, timestamps, and directories.
- `-v`: Verbose. Shows detailed output during transfer.
- `-z`: Compresses data during transfer to save bandwidth.
- `-r`: Recursively copy directories.
- `-h`: Human-readable output.
- `-n`: Dry run. Show what would happen without actually transferring files.

### Examples:

1. **Copy a file to another directory:**
   ```bash
   rsync file.txt /path/to/destination/
   ```

2. **Copy a directory recursively:**
   ```bash
   rsync -r /source/directory/ /destination/directory/
   ```

3. **Perform a dry run before syncing:**
   ```bash
   rsync -avhn /source/ /destination/
   ```

---

## Advanced Options

### Backup and Delete
- `--backup`: Creates a backup of each file before overwriting.
- `--backup-dir=dir`: Specifies a directory to store backup files.
- `--delete`: Deletes files in the destination that are no longer in the source.

### Examples:

1. **Backup files before overwriting:**
   ```bash
   rsync -av --backup --backup-dir=/backup/directory /source/ /destination/
   ```

2. **Sync and delete files in the destination not present in the source:**
   ```bash
   rsync -av --delete /source/ /destination/
   ```

### Filtering Files
- `--include=PATTERN`: Includes only files matching the pattern.
- `--exclude=PATTERN`: Excludes files matching the pattern.
- `--include-from=FILE`: Reads patterns to include from a file.
- `--exclude-from=FILE`: Reads patterns to exclude from a file.

### Examples:

1. **Exclude a specific file type:**
   ```bash
   rsync -av --exclude="*.tmp" /source/ /destination/
   ```

2. **Include only `.txt` files:**
   ```bash
   rsync -av --include="*.txt" --exclude="*" /source/ /destination/
   ```

---

## Network and Remote Transfers

### Options for Remote Transfers
- `-e program`: Specifies a remote shell program like SSH.
- `--port=PORT`: Sets the port for the remote connection.
- `--rsync-path=program`: Specifies the remote rsync executable.

### Examples:

1. **Sync to a remote server using SSH:**
   ```bash
   rsync -avz -e ssh /local/directory/ user@remote:/remote/directory/
   ```

2. **Use a specific port:**
   ```bash
   rsync -avz -e "ssh -p 2222" /local/ user@remote:/remote/
   ```

---

## Progress and Speed Control

### Options:
- `--progress`: Shows progress during transfer.
- `--bwlimit=KBPS`: Limits transfer speed.

### Examples:

1. **Show progress while transferring:**
   ```bash
   rsync -av --progress /source/ /destination/
   ```

2. **Limit bandwidth to 500 KB/s:**
   ```bash
   rsync -av --bwlimit=500 /source/ /destination/
   ```

---

## Special Scenarios

### Partial Transfers and Resuming
- `--partial`: Keeps partially transferred files if interrupted.
- `--append`: Appends data to partially transferred files.

### Examples:

1. **Resume an interrupted transfer:**
   ```bash
   rsync -av --partial /source/ /destination/
   ```

---

## Reference Link
For more details, see the [rsync manual](https://linux.die.net/man/1/rsync).

---

This simplified guide should make it easier for you to use `rsync` effectively. When configuring your app, remember to focus only on the `options` portion, as the rest is already pre-set!
