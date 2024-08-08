#!/bin/bash

# Function to print usage information
print_usage() {
    echo "Usage: $0 [options] <remote_user> <remote_host> <action> [parameters...]"
    echo
    echo "Options:"
    echo "  -h, --help             Show this help message and exit."
    echo "  -v, --verbose          Enable verbose logging."
    echo "  -o, --output-dir       Specify a custom output directory."
    echo "  -c, --config           Specify a configuration file."
    echo "  -l, --log-file         Specify a log file for errors."
    echo
    echo "Actions:"
    echo "  messages               Pull iMessages from the device."
    echo "  photos                 Pull photos from the device."
    echo "  notes                  Pull Notes from the device."
    echo "  contacts               Pull Contacts from the device."
    echo "  safari                 Pull Safari data from the device."
    echo
    echo "Parameters for 'messages':"
    echo "  [contact]              Filter messages by contact."
    echo "  [keyword]              Filter messages by keyword."
    echo "  [start_date] [end_date] Filter messages by date range."
    echo
    echo "Parameters for 'photos':"
    echo "  [start_date] [end_date] Filter photos by date range."
    echo "  [gps]                  Filter photos by GPS coordinates."
    echo "  [camera_model]         Filter photos by camera model."
    echo "  [exposure_time]        Filter photos by exposure time."
    echo "  [iso]                  Filter photos by ISO setting."
    echo
    echo "Parameters for 'notes':"
    echo "  [start_date] [end_date] Filter notes by date range."
    echo
    echo "Parameters for 'contacts':"
    echo "  [contact_name]         Filter contacts by name."
    echo
    echo "Parameters for 'safari':"
    echo "  [history|bookmarks]    Specify whether to pull history or bookmarks."
    echo
    echo "Examples:"
    echo "  $0 -v username remote_host messages \"John Doe\""
    echo "  $0 username remote_host photos 2024-01-01 2024-08-08 gps \"latitude,longitude\""
    echo "  $0 username remote_host notes 2024-01-01 2024-08-08"
    echo "  $0 username remote_host contacts \"Jane Doe\""
    echo "  $0 username remote_host safari history"
}

# Function to enable verbose logging
verbose_logging() {
    if [ "$VERBOSE" = true ]; then
        set -x
    fi
}

# Function to handle errors and log them
handle_error() {
    local ERROR_MSG=$1
    local EXIT_CODE=${2:-1}
    echo "$(date): $ERROR_MSG" >> "$LOG_FILE"
    echo "Error: $ERROR_MSG. Check $LOG_FILE for details."
    exit "$EXIT_CODE"
}

# Function to retry a command on failure
retry_command() {
    local RETRY_COUNT=5
    local WAIT_TIME=5
    local COMMAND="$*"
    local EXIT_CODE

    for ((i=1; i<=RETRY_COUNT; i++)); do
        echo "Attempt $i: $COMMAND"
        if eval "$COMMAND"; then
            return 0
        else
            EXIT_CODE=$?
            echo "Failed with exit code $EXIT_CODE. Retrying in $WAIT_TIME seconds..."
            sleep "$WAIT_TIME"
        fi
    done

    handle_error "Command failed after $RETRY_COUNT attempts: $COMMAND" "$EXIT_CODE"
}

# Function to pull iMessages with advanced search and filtering
pull_messages() {
    echo "Pulling iMessages from device..."

    LOCAL_DB_PATH="${OUTPUT_DIR}/chat.db"
    REMOTE_DB_PATH="~/Library/Messages/chat.db"

    # Use scp to copy the database file from the remote machine to the local machine
    retry_command scp "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DB_PATH" "$LOCAL_DB_PATH"

    echo "Messages database copied successfully to $LOCAL_DB_PATH"

    # Construct SQL query based on parameters
    SQL_QUERY="SELECT datetime(m.date/1000000000 + strftime('%s','2001-01-01 00:00:00'), 'unixepoch') as date,
                m.is_from_me, 
                m.text,
                h.id as contact
                FROM message m 
                JOIN handle h ON m.handle_id = h.rowid"

    # Apply filters
    if [ -n "$CONTACT" ]; then
        SQL_QUERY+=" WHERE h.id LIKE '%$CONTACT%'"
    fi

    if [ -n "$KEYWORD" ]; then
        if [ -z "$CONTACT" ]; then
            SQL_QUERY+=" WHERE"
        else
            SQL_QUERY+=" AND"
        fi
        SQL_QUERY+=" m.text LIKE '%$KEYWORD%'"
    fi

    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        if [ -z "$CONTACT" ] && [ -z "$KEYWORD" ]; then
            SQL_QUERY+=" WHERE"
        else
            SQL_QUERY+=" AND"
        fi
        SQL_QUERY+=" m.date BETWEEN strftime('%s', '$START_DATE') * 1000000000 AND strftime('%s', '$END_DATE') * 1000000000"
    fi

    SQL_QUERY+=" ORDER BY date DESC"

    if ! sqlite3 "$LOCAL_DB_PATH" "$SQL_QUERY" | tee "${OUTPUT_DIR}/messages_output.txt"; then
        handle_error "Failed to query messages database."
    fi

    echo "Messages pulled successfully. Check ${OUTPUT_DIR}/messages_output.txt for details."
}

# Function to extract and filter photo metadata
extract_photo_metadata() {
    local PHOTO_FILE=$1
    local METADATA=$(exiftool "$PHOTO_FILE")
    echo "$METADATA"
}

# Function to pull Photos with advanced metadata filtering
pull_photos() {
    echo "Pulling Photos from device..."

    LOCAL_PHOTOS_PATH="${OUTPUT_DIR}/PhotosBackup"
    mkdir -p "$LOCAL_PHOTOS_PATH"

    # Construct find command based on parameters
    FIND_COMMAND="find ~/Pictures/Photos Library.photoslibrary/originals -type f"

    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        FIND_COMMAND+=" -newermt '$START_DATE' ! -newermt '$END_DATE'"
    fi

    # Filter photos by metadata using exiftool
    FILTER_COMMAND="sh -c 'extract_photo_metadata \"{}\""
    if [ -n "$GPS" ]; then
        FILTER_COMMAND+=" | grep -q \"GPS Latitude: $GPS\""
    fi
    if [ -n "$CAMERA_MODEL" ]; then
        FILTER_COMMAND+=" | grep -q \"Camera Model: $CAMERA_MODEL\""
    fi
    if [ -n "$EXPOSURE_TIME" ]; then
        FILTER_COMMAND+=" | grep -q \"Exposure Time: $EXPOSURE_TIME\""
    fi
    if [ -n "$ISO" ]; then
        FILTER_COMMAND+=" | grep -q \"ISO: $ISO\""
    fi
    FILTER_COMMAND+="'"

    FIND_COMMAND+=" -exec $FILTER_COMMAND \\;"

    PHOTO_FILES=$(ssh "$REMOTE_USER@$REMOTE_HOST" "$FIND_COMMAND")

    if [ -n "$PHOTO_FILES" ]; then
        # Parallel processing to speed up large transfers
        echo "$PHOTO_FILES" | xargs -I {} -P 4 sh -c 'retry_command scp "$REMOTE_USER@$REMOTE_HOST:{}" "$LOCAL_PHOTOS_PATH/"'

        echo "Photos copied successfully to $LOCAL_PHOTOS_PATH"
    else
        echo "No photos found for the specified criteria."
    fi
}

# Function to pull Notes content
pull_notes() {
    echo "Pulling Notes from device..."

    LOCAL_NOTES_PATH="${OUTPUT_DIR}/NotesBackup"
    REMOTE_NOTES_DB="~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"

    mkdir -p "$LOCAL_NOTES_PATH"

    # Use scp to copy the Notes database file from the remote machine to the local machine
    retry_command scp "$REMOTE_USER@$REMOTE_HOST:$REMOTE_NOTES_DB" "$LOCAL_NOTES_PATH/NoteStore.sqlite"

    echo "Notes database copied successfully to $LOCAL_NOTES_PATH/NoteStore.sqlite"

    # Construct SQL query to extract notes content
    SQL_QUERY="SELECT ZTITLE as title, ZCREATIONDATE as creation_date, ZMODIFICATIONDATE as modification_date, ZNOTE as note
                FROM ZNOTE"

    if ! sqlite3 "$LOCAL_NOTES_PATH/NoteStore.sqlite" "$SQL_QUERY" | tee "${OUTPUT_DIR}/notes_output.txt"; then
        handle_error "Failed to query notes database."
    fi

    echo "Notes pulled successfully. Check ${OUTPUT_DIR}/notes_output.txt for details."
}

# Function to pull Contacts information
pull_contacts() {
    echo "Pulling Contacts from device..."

    LOCAL_CONTACTS_PATH="${OUTPUT_DIR}/ContactsBackup"
    REMOTE_CONTACTS_DB="~/Library/Application Support/AddressBook/AddressBook-v22.abcddb"

    mkdir -p "$LOCAL_CONTACTS_PATH"

    #     # Use scp to copy the Contacts database file from the remote machine to the local machine
    retry_command scp "$REMOTE_USER@$REMOTE_HOST:$REMOTE_CONTACTS_DB" "$LOCAL_CONTACTS_PATH/AddressBook-v22.abcddb"

    echo "Contacts database copied successfully to $LOCAL_CONTACTS_PATH/AddressBook-v22.abcddb"

    # Construct SQL query to extract contacts information
    SQL_QUERY="SELECT ZFIRSTNAME as first_name, ZLASTNAME as last_name, ZPHONE as phone_number, ZEMAIL as email, ZADDRESS as address
                FROM ZABCD"

    if ! sqlite3 "$LOCAL_CONTACTS_PATH/AddressBook-v22.abcddb" "$SQL_QUERY" | tee "${OUTPUT_DIR}/contacts_output.txt"; then
        handle_error "Failed to query contacts database."
    fi

    echo "Contacts pulled successfully. Check ${OUTPUT_DIR}/contacts_output.txt for details."
}

# Function to pull Safari browsing history or bookmarks
pull_safari() {
    local DATA_TYPE=$1
    echo "Pulling Safari $DATA_TYPE from device..."

    LOCAL_SAFARI_PATH="${OUTPUT_DIR}/SafariBackup"
    REMOTE_SAFARI_DB_PATH

    if [ "$DATA_TYPE" = "history" ]; then
        REMOTE_SAFARI_DB_PATH="~/Library/Safari/History.db"
        LOCAL_SAFARI_DB_PATH="${LOCAL_SAFARI_PATH}/History.db"
    elif [ "$DATA_TYPE" = "bookmarks" ]; then
        REMOTE_SAFARI_DB_PATH="~/Library/Safari/Bookmarks.plist"
        LOCAL_SAFARI_DB_PATH="${LOCAL_SAFARI_PATH}/Bookmarks.plist"
    else
        handle_error "Invalid data type for Safari. Use 'history' or 'bookmarks'."
    fi

    mkdir -p "$LOCAL_SAFARI_PATH"

    # Use scp to copy the Safari data file from the remote machine to the local machine
    retry_command scp "$REMOTE_USER@$REMOTE_HOST:$REMOTE_SAFARI_DB_PATH" "$LOCAL_SAFARI_DB_PATH"

    echo "Safari $DATA_TYPE copied successfully to $LOCAL_SAFARI_PATH"

    if [ "$DATA_TYPE" = "history" ]; then
        # Construct SQL query to extract browsing history
        SQL_QUERY="SELECT datetime(visit_time + strftime('%s','2001-01-01 00:00:00'), 'unixepoch') as visit_date, url, title
                    FROM history_visits JOIN history_items ON history_visits.history_item = history_items.id
                    ORDER BY visit_date DESC"

        if ! sqlite3 "$LOCAL_SAFARI_DB_PATH" "$SQL_QUERY" | tee "${OUTPUT_DIR}/safari_history_output.txt"; then
            handle_error "Failed to query Safari history database."
        fi

        echo "Safari browsing history pulled successfully. Check ${OUTPUT_DIR}/safari_history_output.txt for details."
    elif [ "$DATA_TYPE" = "bookmarks" ]; then
        # Convert plist to a readable format (XML)
        /usr/bin/plutil -convert xml1 "$LOCAL_SAFARI_DB_PATH" -o "$LOCAL_SAFARI_DB_PATH.xml"

        echo "Safari bookmarks pulled successfully. Check ${OUTPUT_DIR}/SafariBackup/Bookmarks.plist.xml for details."
    fi
}

# Parse command-line arguments
while [[ "$1" =~ ^- ]]; do
    case $1 in
        -h|--help) print_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift ;;
        -c|--config) CONFIG_FILE="$2"; shift ;;
        -l|--log-file) LOG_FILE="$2"; shift ;;
        *) handle_error "Unknown option $1" ;;
    esac
    shift
done

# Check for required arguments
if [[ $# -lt 3 ]]; then
    print_usage
    exit 1
fi

REMOTE_USER=$1
REMOTE_HOST=$2
ACTION=$3
shift 3

# Create output directory if it does not exist
mkdir -p "$OUTPUT_DIR"

# Set default log file if not provided
if [ -z "$LOG_FILE" ]; then
    LOG_FILE="${OUTPUT_DIR}/script.log"
fi

# Enable verbose logging if requested
verbose_logging

# Execute the selected action
case $ACTION in
    messages) pull_messages "$@" ;;
    photos) pull_photos "$@" ;;
    notes) pull_notes "$@" ;;
    contacts) pull_contacts "$@" ;;
    safari) pull_safari "$1" ;;
    *) handle_error "Unknown action $ACTION" ;;
esac


