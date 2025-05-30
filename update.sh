#!/bin/bash

# --- Configuration ---
REPO_URL="https://github.com/lostyawolfer/lostyas_tag.git"
MAIN_BRANCH="master"
MAPMAKER_BRANCH="mapmaker"

LOG_FILE="update.log"
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

# --- Step 0: Check dependencies and settings ---
echo "Checking dependencies for update..."
log_to_file_only "Phase 0: Checking dependencies and settings..."
if ! command -v git &> /dev/null; then
    log_to_file_only "ERROR: Dependency 'git' is not installed."
    echo "ERROR: 'git' is not installed." >&2
    exit 1
else
    log_to_file_only "Dependency 'git' found."
fi

DOWNLOAD_CUSTOM_MAPS_FLAG="no"
OLD_MASTER_LT_ITEMS_STR=""

if [ -f "$SETTINGS_FILE" ]; then
    source "$SETTINGS_FILE" 
    DOWNLOAD_CUSTOM_MAPS_FLAG="${DOWNLOAD_CUSTOM_MAPS:-no}"
    OLD_MASTER_LT_ITEMS_STR="${MASTER_LT_ITEMS:-}"
    log_to_file_only "Loaded settings: DOWNLOAD_CUSTOM_MAPS='$DOWNLOAD_CUSTOM_MAPS_FLAG', current MASTER_LT_ITEMS='$OLD_MASTER_LT_ITEMS_STR'."
else
    log_to_file_only "WARNING: $SETTINGS_FILE not found. Assuming defaults."
fi
log_to_file_only "Dependencies and settings checked."

# --- Step 1: Update files from master branch ---
echo_to_console_and_log "Checking for updates in $MAIN_BRANCH branch..."
log_to_file_only "Phase 1: Updating files from $MAIN_BRANCH to server root..."
TEMP_DIR_UPDATE_MAIN="temp_repo_update_main"
new_master_lt_items_list=()

log_to_file_only "Cloning $MAIN_BRANCH into $TEMP_DIR_UPDATE_MAIN..."
if git clone --depth 1 --branch "$MAIN_BRANCH" "$REPO_URL" "$TEMP_DIR_UPDATE_MAIN" >> "$LOG_FILE" 2>&1; then
    log_to_file_only "Successfully cloned $MAIN_BRANCH."

    CORE_FILES_TO_UPDATE=("config" "server.properties" "server-icon.png" "versions.toml")
    for item in "${CORE_FILES_TO_UPDATE[@]}"; do
        if [ -e "$TEMP_DIR_UPDATE_MAIN/$item" ]; then
            echo_to_console_and_log "Updating in root: $item"
            rm -rf "./$item" >> "$LOG_FILE" 2>&1
            if cp -r "$TEMP_DIR_UPDATE_MAIN/$item" . >> "$LOG_FILE" 2>&1; then
                log_to_file_only "Updated '$item' in root from $MAIN_BRANCH."
            else
                log_to_file_only "ERROR: Failed to update '$item' in root from $MAIN_BRANCH."
            fi
        else
            log_to_file_only "WARNING: Core item '$item' not found in $MAIN_BRANCH. Local version in root (if any) untouched."
        fi
    done

    log_to_file_only "Updating 'lt_*' items from $MAIN_BRANCH in server root..."
    if compgen -G "$TEMP_DIR_UPDATE_MAIN/lt_*" > /dev/null; then
        for item_path in "$TEMP_DIR_UPDATE_MAIN"/lt_*; do
            item_name=$(basename "$item_path")
            echo_to_console_and_log "Updating in root: $item_name"
            rm -rf "./$item_name" >> "$LOG_FILE" 2>&1 
            if cp -r "$item_path" . >> "$LOG_FILE" 2>&1; then
                log_to_file_only "Updated '$item_name' in root from $MAIN_BRANCH."
                new_master_lt_items_list+=("$item_name")
            else
                log_to_file_only "ERROR: Failed to update '$item_name' in root from $MAIN_BRANCH."
            fi
        done
    else
        log_to_file_only "No 'lt_*' items found in current $MAIN_BRANCH to update in root."
    fi

    declare -A new_master_items_set
    for item in "${new_master_lt_items_list[@]}"; do new_master_items_set["$item"]=1; done
    
    for old_item in $OLD_MASTER_LT_ITEMS_STR; do
        if [[ -z "${new_master_items_set[$old_item]}" ]]; then
            log_to_file_only "Item '$old_item' was in MASTER_LT_ITEMS but not in current $MAIN_BRANCH. Deleting local copy."
            echo_to_console_and_log "Deleting from root: $old_item (removed from master)"
            rm -rf "./$old_item" >> "$LOG_FILE" 2>&1
        fi
    done
    
    printf -v joined_new_master_lt_items '%s ' "${new_master_lt_items_list[@]}"
    if [ -f "$SETTINGS_FILE" ]; then
      if grep -q "^MASTER_LT_ITEMS=" "$SETTINGS_FILE"; then
          sed -i "s|^MASTER_LT_ITEMS=.*|MASTER_LT_ITEMS=\"${joined_new_master_lt_items% }\"|" "$SETTINGS_FILE"
      else
          echo "MASTER_LT_ITEMS=\"${joined_new_master_lt_items% }\"" >> "$SETTINGS_FILE"
      fi
    else
      echo "MASTER_LT_ITEMS=\"${joined_new_master_lt_items% }\"" > "$SETTINGS_FILE"
      echo "DOWNLOAD_CUSTOM_MAPS=\"$DOWNLOAD_CUSTOM_MAPS_FLAG\"" >> "$SETTINGS_FILE"
    fi
    log_to_file_only "Updated MASTER_LT_ITEMS in $SETTINGS_FILE: ${joined_new_master_lt_items% }"
    MASTER_LT_ITEMS="${joined_new_master_lt_items% }" 

    rm -rf "$TEMP_DIR_UPDATE_MAIN" >> "$LOG_FILE" 2>&1
    log_to_file_only "Removed $TEMP_DIR_UPDATE_MAIN."
else
    log_to_file_only "ERROR: Failed to clone $MAIN_BRANCH. Git output in log."
    echo_to_console_and_log "ERROR: Could not fetch updates from $MAIN_BRANCH. Check $LOG_FILE."
    exit 1
fi
log_to_file_only "Finished updating from $MAIN_BRANCH."

# --- Step 1.5: Update JARs from versions.toml ---
echo_to_console_and_log "Checking for JAR updates from versions.toml..."
log_to_file_only "Phase 1.5: Processing versions.toml and updating JARs..."
if [ ! -f versions.toml ]; then
    log_to_file_only "ERROR: versions.toml not found. Skipping JAR updates."
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
            log_to_file_only "Skipping section [$item_name_log_toml] for JAR update: 'url' or 'name_format' missing."
            return
        fi

        local filename_toml="$name_format"
        if [[ -n "$version" ]]; then
            filename_toml="${filename_toml//\{version\}/$version}"
        fi

        echo_to_console_and_log "Checking/Downloading JAR: $filename_toml"
        log_to_file_only "JAR update details for '$filename_toml' from section [$item_name_log_toml]."

        local download_path_toml="$filename_toml"
        if [[ -n "$subdir" ]]; then
            if ! mkdir -p "$subdir" >> "$LOG_FILE" 2>&1; then
                log_to_file_only "ERROR: Failed to create subdir '$subdir' for JAR update."
                return
            fi
            download_path_toml="$subdir/$filename_toml"
            log_to_file_only "Target for '$filename_toml' (JAR update): $subdir"
        fi
        
        # Логіка для уникнення завантаження, якщо файл існує і хеш збігається
        local should_download=true
        if [[ -f "$download_path_toml" && -n "$hash_full" ]]; then
            local expected_hash_algo_toml=$(echo "$hash_full" | cut -d':' -f1)
            local expected_hash_value_toml=$(echo "$hash_full" | cut -d':' -f2)
            if [[ "$expected_hash_algo_toml" == "SHA256" ]]; then
                log_to_file_only "Local file '$download_path_toml' exists. Checking SHA256 hash..."
                local local_file_hash=$(sha256sum "$download_path_toml" 2>> "$LOG_FILE" | awk '{print $1}')
                if [[ "$local_file_hash" == "$expected_hash_value_toml" ]]; then
                    log_to_file_only "Local file '$download_path_toml' hash matches. Skipping download."
                    echo_to_console_and_log "JAR $filename_toml is up to date (hash match)."
                    should_download=false
                else
                    log_to_file_only "Local file '$download_path_toml' hash mismatch (local: $local_file_hash, expected: $expected_hash_value_toml). Will re-download."
                fi
            fi
        fi

        if ! $should_download; then
            return
        fi
        
        log_to_file_only "Attempting to download '$filename_toml' to '$download_path_toml.tmp'..."
        if curl -Lfo "$download_path_toml.tmp" "$url" >> "$LOG_FILE" 2>&1; then
            log_to_file_only "Downloaded '$filename_toml' to '$download_path_toml.tmp'."
            local downloaded_successfully_toml=false
            if [[ -n "$hash_full" ]]; then
                local expected_hash_algo_toml=$(echo "$hash_full" | cut -d':' -f1)
                local expected_hash_value_toml=$(echo "$hash_full" | cut -d':' -f2)

                if [[ "$expected_hash_algo_toml" == "SHA256" ]]; then
                    log_to_file_only "Verifying SHA256 for downloaded $filename_toml..."
                    actual_hash_toml=$(sha256sum "$download_path_toml.tmp" 2>> "$LOG_FILE" | awk '{print $1}')
                    if [[ $? -ne 0 && -z "$actual_hash_toml" ]]; then
                        log_to_file_only "ERROR: sha256sum failed for '$download_path_toml.tmp'."
                    elif [[ "$actual_hash_toml" == "$expected_hash_value_toml" ]]; then
                        if mv "$download_path_toml.tmp" "$download_path_toml" >> "$LOG_FILE" 2>&1; then
                            log_to_file_only "Verified and updated $filename_toml to $download_path_toml."
                            downloaded_successfully_toml=true
                        else
                             log_to_file_only "ERROR: Verified $filename_toml, but failed to move."
                        fi
                    else
                        log_to_file_only "ERROR: Hash mismatch for downloaded $filename_toml. Expected $expected_hash_value_toml, got $actual_hash_toml."
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
            log_to_file_only "ERROR: Failed to download $filename_toml from $url for update."
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
            log_to_file_only "Parsing TOML section for JAR update: [$current_section_toml]"
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
    log_to_file_only "Finished processing versions.toml for JAR updates."
fi


# --- Step 2: Update custom maps if previously installed ---
if [[ "$DOWNLOAD_CUSTOM_MAPS_FLAG" == "yes" ]]; then
    echo_to_console_and_log "Checking for custom map updates from $MAPMAKER_BRANCH branch (target: server root)..."
    log_to_file_only "Phase 2: Updating custom maps from $MAPMAKER_BRANCH to server root."
    TEMP_DIR_UPDATE_MAPS="temp_repo_update_maps"

    current_master_lt_items_for_check_str="$MASTER_LT_ITEMS" 
    declare -A master_items_set_for_check
    for item in $current_master_lt_items_for_check_str; do master_items_set_for_check["$item"]=1; done
    
    current_local_custom_maps_list=()
    # Використовуємо find для надійності, якщо немає lt_* файлів
    while IFS= read -r local_lt_item_path; do
        if [ -e "$local_lt_item_path" ]; then
            local_lt_item_base=$(basename "$local_lt_item_path")
            if [[ -z "${master_items_set_for_check[$local_lt_item_base]}" ]]; then
                current_local_custom_maps_list+=("$local_lt_item_base")
            fi
        fi
    done < <(find . -maxdepth 1 -name "lt_*" -type d 2>/dev/null; find . -maxdepth 1 -name "lt_*" -type f 2>/dev/null)

    log_to_file_only "Current local items presumed to be custom maps: ${current_local_custom_maps_list[*]}"

    log_to_file_only "Cloning $MAPMAKER_BRANCH into $TEMP_DIR_UPDATE_MAPS..."
    if git ls-remote --exit-code --heads "$REPO_URL" "$MAPMAKER_BRANCH" &>/dev/null; then
        if git clone --depth 1 --branch "$MAPMAKER_BRANCH" "$REPO_URL" "$TEMP_DIR_UPDATE_MAPS" >> "$LOG_FILE" 2>&1; then
            log_to_file_only "Successfully cloned $MAPMAKER_BRANCH for maps."

            declare -A remote_mapmaker_lt_items_set
            if compgen -G "$TEMP_DIR_UPDATE_MAPS/lt_*" > /dev/null; then
                for item_path in "$TEMP_DIR_UPDATE_MAPS"/lt_*; do
                    item_name=$(basename "$item_path")
                    remote_mapmaker_lt_items_set["$item_name"]=1

                    if [[ -n "${master_items_set_for_check[$item_name]}" ]]; then
                        log_to_file_only "Skipping update for custom map '$item_name': conflicts with a master branch item."
                        echo_to_console_and_log "Skipping custom map '$item_name' (conflicts with master item)."
                    else
                        echo_to_console_and_log "Updating/Copying custom map to root: $item_name"
                        rm -rf "./$item_name" >> "$LOG_FILE" 2>&1
                        if cp -r "$item_path" . >> "$LOG_FILE" 2>&1; then
                            log_to_file_only "Updated map '$item_name' in root."
                        else
                            log_to_file_only "ERROR: Failed to update map '$item_name' in root."
                        fi
                    fi
                done
            else
                log_to_file_only "No 'lt_*' items (maps) found in remote $MAPMAKER_BRANCH to update."
            fi
            
            for local_map_name in "${current_local_custom_maps_list[@]}"; do
                if [[ -z "${remote_mapmaker_lt_items_set[$local_map_name]}" ]]; then
                    if [[ -z "${master_items_set_for_check[$local_map_name]}" ]]; then
                         log_to_file_only "Custom map '$local_map_name' no longer in $MAPMAKER_BRANCH. Deleting local copy."
                         echo_to_console_and_log "Deleting custom map from root: $local_map_name (removed from mapmaker)"
                         rm -rf "./$local_map_name" >> "$LOG_FILE" 2>&1
                    fi
                fi
            done

            rm -rf "$TEMP_DIR_UPDATE_MAPS" >> "$LOG_FILE" 2>&1
            log_to_file_only "Removed $TEMP_DIR_UPDATE_MAPS."
        else
            log_to_file_only "ERROR: Failed to clone $MAPMAKER_BRANCH for maps."
            echo_to_console_and_log "ERROR: Could not fetch map updates. Check $LOG_FILE."
        fi
    else
        log_to_file_only "INFO: Branch '$MAPMAKER_BRANCH' for maps not found. Skipping map updates."
        echo_to_console_and_log "Branch '$MAPMAKER_BRANCH' for maps not found. Cannot update maps."
    fi
else
    log_to_file_only "Skipping custom map update (DOWNLOAD_CUSTOM_MAPS was not 'yes')."
    echo "Custom map updates skipped (not enabled during installation or $SETTINGS_FILE missing)."
fi
log_to_file_only "Finished custom map update check."

# --- Final Messages ---
log_to_file_only "Update script finished."
echo ""
echo "Update process complete. Details are in $LOG_FILE."
if grep -q "ERROR:" "$LOG_FILE"; then
    echo "Errors occurred. Check $LOG_FILE."
else
    echo "Update successful. Check $LOG_FILE for details."
fi

exit 0