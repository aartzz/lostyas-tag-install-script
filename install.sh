#!/bin/bash

# --- Configuration ---
REPO_URL="https://github.com/lostyawolfer/lostyas_tag.git"
MAIN_BRANCH="master"
MAPMAKER_BRANCH="mapmaker"

LOG_FILE="install.log"
SETTINGS_FILE=".server_settings"
# --- End Configuration ---

> "$LOG_FILE"

log_to_file_only() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

echo_to_console_and_log() {
    echo "$1"
    log_to_file_only "CONSOLE: $1"
}

echo "DOWNLOAD_CUSTOM_MAPS=no" > "$SETTINGS_FILE"
echo "MASTER_LT_ITEMS=\"\"" >> "$SETTINGS_FILE"
log_to_file_only "Initialized $SETTINGS_FILE."

# --- Step 0: Check dependencies ---
echo "Checking dependencies..."
log_to_file_only "Phase 0: Checking dependencies..."
dependencies=("java" "git" "curl" "sha256sum")
all_deps_found=true
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        log_to_file_only "ERROR: Dependency '$dep' is not installed."
        all_deps_found=false
    else
        log_to_file_only "Dependency '$dep' found."
    fi
done

if ! $all_deps_found; then
    log_to_file_only "ERROR: Not all dependencies are met. Exiting."
    echo "ERROR: Dependency check failed. Check $LOG_FILE for details." >&2
    exit 1
fi
log_to_file_only "All dependencies are present."

# --- Step 1: Copy files from master branch ---
log_to_file_only "Phase 1: Copying files from $MAIN_BRANCH to server root..."
TEMP_DIR_MAIN="temp_repo_main_install"
current_master_lt_items_list=()

echo_to_console_and_log "Downloading $MAIN_BRANCH branch from $REPO_URL..."
log_to_file_only "Cloning $MAIN_BRANCH into $TEMP_DIR_MAIN..."
if git clone --depth 1 --branch "$MAIN_BRANCH" "$REPO_URL" "$TEMP_DIR_MAIN" >> "$LOG_FILE" 2>&1; then
    log_to_file_only "Successfully cloned $MAIN_BRANCH."
    FILES_TO_COPY_FROM_REPO=("config" "server.properties" "server-icon.png" "versions.toml")
    
    for item in "${FILES_TO_COPY_FROM_REPO[@]}"; do
        if [ -e "$TEMP_DIR_MAIN/$item" ]; then
            echo_to_console_and_log "Copying to root: $item"
            if cp -r "$TEMP_DIR_MAIN/$item" . >> "$LOG_FILE" 2>&1; then
                log_to_file_only "Successfully copied '$item' to root."
            else
                log_to_file_only "ERROR: Failed to copy '$item' to root."
            fi
        else
            log_to_file_only "WARNING: Item '$item' not found in $MAIN_BRANCH."
        fi
    done

    log_to_file_only "Copying 'lt_*' items from $MAIN_BRANCH to server root..."
    if compgen -G "$TEMP_DIR_MAIN/lt_*" > /dev/null; then
        for item_path in "$TEMP_DIR_MAIN"/lt_*; do
            item_name=$(basename "$item_path")
            echo_to_console_and_log "Copying to root: $item_name"
            if cp -r "$item_path" . >> "$LOG_FILE" 2>&1; then
                 log_to_file_only "Successfully copied '$item_name' from $MAIN_BRANCH to root."
                 current_master_lt_items_list+=("$item_name")
            else
                log_to_file_only "ERROR: Failed to copy '$item_name' from $MAIN_BRANCH to root."
            fi
        done
    else
        log_to_file_only "INFO: No 'lt_*' items found in $MAIN_BRANCH to copy to root."
    fi
    
    printf -v joined_master_lt_items '%s ' "${current_master_lt_items_list[@]}"
    sed -i "s|^MASTER_LT_ITEMS=.*|MASTER_LT_ITEMS=\"${joined_master_lt_items% }\"|" "$SETTINGS_FILE"
    log_to_file_only "Updated MASTER_LT_ITEMS in $SETTINGS_FILE: ${joined_master_lt_items% }"

    rm -rf "$TEMP_DIR_MAIN" >> "$LOG_FILE" 2>&1
    log_to_file_only "Removed temporary directory $TEMP_DIR_MAIN."
else
    log_to_file_only "ERROR: Failed to clone $MAIN_BRANCH. Git output is in log."
    echo "ERROR: Failed to clone repository. Check $LOG_FILE for details." >&2
    exit 1
fi

# --- Step 2: Download jars from versions.toml ---
log_to_file_only "Phase 2: Processing versions.toml and downloading JARs..."
if [ ! -f versions.toml ]; then
    log_to_file_only "ERROR: versions.toml not found. Skipping JAR downloads."
else
    current_section_toml=""
    declare -A section_data_toml

    process_and_download_item_toml() {
        local url="${section_data_toml[url]}"
        local name_format="${section_data_toml[name_format]}"
        local version="${section_data_toml[version]}"
        local subdir="${section_data_toml[subdir]}"
        local hash_full="${section_data_toml[hash]}"
        local item_name_log_toml="$current_section_toml"

        if [[ -z "$url" || -z "$name_format" ]]; then
            log_to_file_only "Skipping section [$item_name_log_toml]: 'url' or 'name_format' missing."
            return
        fi

        local filename_toml="$name_format"
        if [[ -n "$version" ]]; then
            filename_toml="${filename_toml//\{version\}/$version}"
        fi

        echo_to_console_and_log "Downloading jars: $filename_toml"
        log_to_file_only "Download details for '$filename_toml' from section [$item_name_log_toml]."

        local download_path_toml="$filename_toml"
        if [[ -n "$subdir" ]]; then
            if ! mkdir -p "$subdir" >> "$LOG_FILE" 2>&1; then
                log_to_file_only "ERROR: Failed to create subdir '$subdir'."
                return
            fi
            download_path_toml="$subdir/$filename_toml"
            log_to_file_only "Target for '$filename_toml': $subdir"
        fi

        if curl -Lfo "$download_path_toml.tmp" "$url" >> "$LOG_FILE" 2>&1; then
            log_to_file_only "Downloaded '$filename_toml' to '$download_path_toml.tmp'."
            local downloaded_successfully_toml=false
            if [[ -n "$hash_full" ]]; then
                local expected_hash_algo_toml=$(echo "$hash_full" | cut -d':' -f1)
                local expected_hash_value_toml=$(echo "$hash_full" | cut -d':' -f2)

                if [[ "$expected_hash_algo_toml" == "SHA256" ]]; then
                    log_to_file_only "Verifying SHA256 for $filename_toml..."
                    actual_hash_toml=$(sha256sum "$download_path_toml.tmp" 2>> "$LOG_FILE" | awk '{print $1}')
                    if [[ $? -ne 0 && -z "$actual_hash_toml" ]]; then
                        log_to_file_only "ERROR: sha256sum failed for '$download_path_toml.tmp'."
                    elif [[ "$actual_hash_toml" == "$expected_hash_value_toml" ]]; then
                        if mv "$download_path_toml.tmp" "$download_path_toml" >> "$LOG_FILE" 2>&1; then
                            log_to_file_only "Verified $filename_toml to $download_path_toml."
                            downloaded_successfully_toml=true
                        else
                             log_to_file_only "ERROR: Verified $filename_toml, but failed to move."
                        fi
                    else
                        log_to_file_only "ERROR: Hash mismatch for $filename_toml. Expected $expected_hash_value_toml, got $actual_hash_toml."
                    fi
                else
                    log_to_file_only "WARNING: Unsupported hash '$expected_hash_algo_toml' for $filename_toml."
                    if mv "$download_path_toml.tmp" "$download_path_toml" >> "$LOG_FILE" 2>&1; then
                        downloaded_successfully_toml=true
                    else
                        log_to_file_only "ERROR: Failed to move '$download_path_toml.tmp' (unsupported hash)."
                    fi
                fi
            else
                log_to_file_only "WARNING: No hash for $filename_toml."
                 if mv "$download_path_toml.tmp" "$download_path_toml" >> "$LOG_FILE" 2>&1; then
                    downloaded_successfully_toml=true
                else
                    log_to_file_only "ERROR: Failed to move '$download_path_toml.tmp' (no hash)."
                fi
            fi
            if ! $downloaded_successfully_toml && [ -f "$download_path_toml.tmp" ]; then
                rm "$download_path_toml.tmp" >> "$LOG_FILE" 2>&1
                log_to_file_only "Removed '$download_path_toml.tmp' after failed processing."
            fi
        else
            log_to_file_only "ERROR: Failed to download $filename_toml from $url."
            if [ -f "$download_path_toml.tmp" ]; then
                rm "$download_path_toml.tmp" >> "$LOG_FILE" 2>&1
            fi
        fi
    }
    
    temp_toml_processed=$(mktemp)
    sed 's/\r$//' versions.toml | grep -Ev '^\s*#|^\s*$' > "$temp_toml_processed"

    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed_line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
        
        if [[ "$trimmed_line" =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
            if [[ -n "$current_section_toml" && -n "${section_data_toml[url]}" ]]; then
                process_and_download_item_toml
            fi
            current_section_toml="${BASH_REMATCH[1]}"
            section_data_toml=()
            declare -A section_data_toml 
            log_to_file_only "Parsing TOML section: [$current_section_toml]"
            continue
        fi

        if [[ -n "$current_section_toml" && "$trimmed_line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*\'(.*?)\' ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            section_data_toml["$key"]="$value"
        fi
    done < "$temp_toml_processed"
    
    if [[ -n "$current_section_toml" && -n "${section_data_toml[url]}" ]]; then
         process_and_download_item_toml
    fi
    rm "$temp_toml_processed" >> "$LOG_FILE" 2>&1
    log_to_file_only "Finished processing versions.toml."
fi

# --- Step 3: Handle custom maps ---
log_to_file_only "Phase 3: Handling custom maps..."
DOWNLOAD_CUSTOM_MAPS_USER_CHOICE=""
while true; do
    echo -n "Download custom maps from '$MAPMAKER_BRANCH' branch to server root? (yes/no): " > /dev/tty
    log_to_file_only "Prompted user for custom maps from '$MAPMAKER_BRANCH' to server root."
    
    read -r yn < /dev/tty
    log_to_file_only "User input for maps: '$yn'"

    case $yn in
        [Yy]|[Yy][Ee][Ss]) DOWNLOAD_CUSTOM_MAPS_USER_CHOICE="yes"; break;;
        [Nn]|[Nn][Oo]) DOWNLOAD_CUSTOM_MAPS_USER_CHOICE="no"; break;;
        * ) echo "Please answer yes or no." > /dev/tty; log_to_file_only "Invalid input. Asking again.";;
    esac
done

if [[ "$DOWNLOAD_CUSTOM_MAPS_USER_CHOICE" == "yes" ]]; then
    sed -i "s|^DOWNLOAD_CUSTOM_MAPS=.*|DOWNLOAD_CUSTOM_MAPS=yes|" "$SETTINGS_FILE"
    log_to_file_only "User agreed to download maps. Updated $SETTINGS_FILE."
    
    MAP_TEMP_DIR="temp_repo_mapmaker_install"
    echo_to_console_and_log "Downloading $MAPMAKER_BRANCH branch (for maps) from $REPO_URL..."
    log_to_file_only "Cloning $MAPMAKER_BRANCH into $MAP_TEMP_DIR..."

    master_lt_items_str=""
    if [ -f "$SETTINGS_FILE" ]; then
        source "$SETTINGS_FILE" 
        master_lt_items_str="$MASTER_LT_ITEMS"
    fi
    
    declare -A master_items_set
    for item in $master_lt_items_str; do master_items_set["$item"]=1; done


    if git ls-remote --exit-code --heads "$REPO_URL" "$MAPMAKER_BRANCH" &>/dev/null; then
        if git clone --depth 1 --branch "$MAPMAKER_BRANCH" "$REPO_URL" "$MAP_TEMP_DIR" >> "$LOG_FILE" 2>&1; then
            log_to_file_only "Successfully cloned $MAPMAKER_BRANCH."
            
            if compgen -G "$MAP_TEMP_DIR/lt_*" > /dev/null; then
                for item_path in "$MAP_TEMP_DIR"/lt_*; do
                    item_name=$(basename "$item_path")
                    if [[ -n "${master_items_set[$item_name]}" ]]; then
                        log_to_file_only "Skipping custom map '$item_name': conflicts with a master branch item."
                        echo_to_console_and_log "Skipping custom map '$item_name' (conflicts with master item)."
                    else
                        echo_to_console_and_log "Copying custom map to root: $item_name"
                        if cp -r "$item_path" . >> "$LOG_FILE" 2>&1; then
                             log_to_file_only "Successfully copied map '$item_name' to root."
                        else
                            log_to_file_only "ERROR: Failed to copy map '$item_name' to root."
                        fi
                    fi
                done
            else
                log_to_file_only "INFO: No 'lt_*' items (maps) found in $MAPMAKER_BRANCH."
            fi
            rm -rf "$MAP_TEMP_DIR" >> "$LOG_FILE" 2>&1
            log_to_file_only "Removed temporary directory $MAP_TEMP_DIR."
        else
            log_to_file_only "ERROR: Failed to clone $MAPMAKER_BRANCH."
        fi
    else
        log_to_file_only "INFO: Branch '$MAPMAKER_BRANCH' not found. Skipping maps."
    fi
else
    log_to_file_only "User declined custom maps. $SETTINGS_FILE: DOWNLOAD_CUSTOM_MAPS=no."
    echo "Skipping custom map download." > /dev/tty
fi
log_to_file_only "Finished handling custom maps."

# --- Step 4: Create start.sh ---
log_to_file_only "Phase 4: Creating start.sh script..."
echo "java -Xmx1G -Xms1G -jar server.jar nogui" > start.sh
if chmod +x start.sh >> "$LOG_FILE" 2>&1; then
    log_to_file_only "start.sh created and made executable."
else
    log_to_file_only "ERROR: Failed to make start.sh executable."
fi

# --- Step 5: Final message ---
log_to_file_only "Phase 5: Finalizing installation..."
log_to_file_only "Installation successful!"
log_to_file_only "To start the server, run: ./start.sh"
log_to_file_only "Log saved to: $LOG_FILE."

echo ""
echo "Installation process complete. Details are in $LOG_FILE."
if grep -q "ERROR:" "$LOG_FILE"; then
    echo "Errors occurred. Check $LOG_FILE."
elif grep -q "Installation successful!" "$LOG_FILE"; then
    echo "Installation successful. Run ./start.sh to start."
else
    echo "Process finished. Check $LOG_FILE."
fi

exit 0