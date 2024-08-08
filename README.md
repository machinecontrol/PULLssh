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

##Options
-h, --help: Show help message and exit.
-v, --verbose: Enable verbose logging.
-o, --output-dir: Specify a custom output directory.
-c, --config: Specify a configuration file.
-l, --log-file: Specify a log file for errors.

##Actions
[messages]: Pull iMessages from the device.

[contact]: Filter messages by contact.

[keyword]: Filter messages by keyword.

[start_date] [end_date]: Filter messages by date range.

[photos]: Pull photos from the device.

[start_date] [end_date]: Filter photos by date range.

[gps]: Filter photos by GPS coordinates.

[camera_model]: Filter photos by camera model.

[exposure_time]: Filter photos by exposure time.

[iso]: Filter photos by ISO setting.

[notes]: Pull Notes from the device.

[start_date] [end_date]: Filter notes by date range.

[contacts]: Pull Contacts from the device.

[contact_name]: Filter contacts by name.

[safari]: Pull Safari data from the device.

[history|bookmarks]: Specify whether to pull history or bookmarks.

##Examples

# Pull iMessages with a filter for a specific contact
./script.sh -v username remote_host messages "John Doe"

# Pull photos with filtering by date range and GPS coordinates
./script.sh username remote_host photos 2024-01-01 2024-08-08 gps "latitude,longitude"

# Pull Notes with a filter for a date range
./script.sh username remote_host notes 2024-01-01 2024-08-08

# Pull Contacts filtered by name
./script.sh username remote_host contacts "Jane Doe"

# Pull Safari browsing history
./script.sh username remote_host safari history



AUTHOR: Lanre Fakorede (OFF)
