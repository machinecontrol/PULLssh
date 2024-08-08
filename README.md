# PULLssh

This script automates the process of pulling various types of data from a macOS device via SSH. It supports extracting iMessages, Photos, Notes, Contacts, and Safari data.

## Features

- **iMessages**: Pull iMessages with advanced filtering options.
- **Photos**: Pull photos with filtering by date range and metadata.
- **Notes**: Pull Notes with filtering by date range.
- **Contacts**: Pull Contacts with filtering by name.
- **Safari**: Pull Safari history or bookmarks.

## Prerequisites

- Bash shell
- `scp` command for file transfer
- `sqlite3` command for querying databases
- `exiftool` for photo metadata extraction
- Access to the target macOS device via SSH

## Usage

```bash
./script.sh [options] <remote_user> <remote_host> <action> [parameters...]
