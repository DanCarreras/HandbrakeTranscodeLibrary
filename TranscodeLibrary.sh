#!/bin/bash

# --- Configuration ---
VIDEO_LIBRARY_PATH="/path/to/your/video/library"  # Your library path here without trailing slash
OUTPUT_EXTENSION="mp4" # Desired output file extension - either mp4 or m4v
HANDBRAKE_PRESET="Hardware/H.265 Apple VideoToolbox 1080p" - # HandBrake preset to use - Apple VideoToolbox preset for H.265 encoding and to use hardware acceleration
LOG_RETENTION_DAYS=30 # Number of days to keep log files

# --- Create required directories ---
LOGS_DIR="${VIDEO_LIBRARY_PATH}/Logs"
FAILED_DIR="${VIDEO_LIBRARY_PATH}/Failed_Transcodes"
REVIEW_DIR="${VIDEO_LIBRARY_PATH}/Manual_Review"
TEMP_DIR="${VIDEO_LIBRARY_PATH}/Temp"

# Check HandBrakeCLI is available
if ! command -v HandBrakeCLI &> /dev/null; then
    echo "Error: HandBrakeCLI is not installed or not in the PATH"
    echo "Install with: brew install handbrake"
    exit 1
fi

# Log HandBrakeCLI version
HB_VERSION_OUTPUT=$(HandBrakeCLI --version 2>&1) # Capture stderr too, as version info might be there
HB_VERSION=$(echo "$HB_VERSION_OUTPUT" | head -n 1)
# Log any initial output from HandBrakeCLI if it's verbose
echo "HandBrakeCLI --version output (first line): $HB_VERSION"
# Consider logging more of HB_VERSION_OUTPUT to the main log if needed for debugging startup.

# Create directories if they don't exist
mkdir -p "${LOGS_DIR}" "${FAILED_DIR}" "${REVIEW_DIR}" "${TEMP_DIR}"

# --- Cleanup old log files ---
if [ -d "${LOGS_DIR}" ]; then
    echo "Cleaning up log files older than ${LOG_RETENTION_DAYS} days..."
    find "${LOGS_DIR}" -type f -name "*.txt" -mtime +${LOG_RETENTION_DAYS} -delete
    echo "Log cleanup complete."
fi

LOG_FILE="${LOGS_DIR}/transcoding_log_$(date +%Y%m%d_%H%M%S).txt"
ERROR_LOG_FILE="${LOGS_DIR}/transcoding_error_log_$(date +%Y%m%d_%H%M%S).txt"

# Initial message to main log
echo "Script run started at $(date +'%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
echo "Using HandBrakeCLI version line: $HB_VERSION" >> "$LOG_FILE"

# Check if VIDEO_LIBRARY_PATH is properly set
if [[ "${VIDEO_LIBRARY_PATH}" == "/path/to/your/video/library" ]]; then
    echo "Error: Please set VIDEO_LIBRARY_PATH to your actual library path in the script."
    exit 1
fi
if [[ ! -d "${VIDEO_LIBRARY_PATH}" ]]; then
    echo "Error: VIDEO_LIBRARY_PATH '${VIDEO_LIBRARY_PATH}' does not exist or is not a directory."
    exit 1
fi

# --- Logging Function ---
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$ERROR_LOG_FILE"
}

# --- Find Video Files ---
find "$VIDEO_LIBRARY_PATH" -type f \( \
    -iname "*.mp4" -o \
    -iname "*.mkv" -o \
    -iname "*.avi" -o \
    -iname "*.mov" -o \
    -iname "*.wmv" -o \
    -iname "*.flv" \
    \) -print0 | while IFS= read -r -d $'\0' inputFile; do

    # Skip files that are already in the target format (by naming convention)
    if [[ "$inputFile" == *"_H265.$OUTPUT_EXTENSION" ]]; then
        log_message "Skipping already transcoded (by naming convention): $inputFile"
        continue
    fi

    # Skip files in our special directories
    if [[ "$inputFile" == "${LOGS_DIR}/"* || \
          "$inputFile" == "${FAILED_DIR}/"* || \
          "$inputFile" == "${REVIEW_DIR}/"* || \
          "$inputFile" == "${TEMP_DIR}/"* ]]; then
        log_message "Skipping file in special directory: $inputFile"
        continue
    fi

    # --- Define file paths ---
    inputDir="$(dirname "$inputFile")"
    inputBasenameNoExt="$(basename "${inputFile%.*}")"

    # lib_path_for_strip needs the library path to have a trailing slash for # stripping
    lib_path_for_strip="${VIDEO_LIBRARY_PATH}/"
    relative_path_to_file="${inputFile#$lib_path_for_strip}"
    
    sanitized_base_for_temp=$(echo "${relative_path_to_file%.*}" | tr '/' '_')
    sanitized_base_for_temp=$(echo "$sanitized_base_for_temp" | sed 's/__*/_/g' | sed 's/^_//' | sed 's/_$//')

    tempOutputFile="${TEMP_DIR}/${sanitized_base_for_temp}_temp.$OUTPUT_EXTENSION"
    outputFileName="${inputDir}/${inputBasenameNoExt}_H265.$OUTPUT_EXTENSION"

    log_message "Starting transcode for: $inputFile"
    log_message "Temporary output will be: $tempOutputFile"
    log_message "Final output will be: $outputFileName"

    # MODIFICATION: Added < /dev/null to redirect HandBrakeCLI's stdin
    if HandBrakeCLI --verbose \
        -i "$inputFile" \
        -o "$tempOutputFile" \
        -Z "$HANDBRAKE_PRESET" \
        --encoder vt_h265 \
        --quality 60 \
        --audio-copy-mask aac,ac3,eac3,dts \
        --aencoder copy:aac \
        --ab 160 \
        --mixdown stereo \
        --format av_mp4 >>"$LOG_FILE" 2>>"$ERROR_LOG_FILE" < /dev/null; then # ADDED < /dev/null HERE
        
        file_size=0
        if [[ -f "$tempOutputFile" ]]; then
            if [[ "$(uname)" == "Darwin" ]] || [[ "$(uname)" == *"BSD"* ]]; then
                file_size=$(stat -f%z "$tempOutputFile")
            else
                file_size=$(stat -c%s "$tempOutputFile")
            fi
        fi

        if [ "$file_size" -gt 1000000 ]; then
            log_message "Successfully transcoded: $inputFile (size: $file_size bytes)"

            if mv "$tempOutputFile" "$outputFileName"; then
                log_message "Moved transcoded file to: $outputFileName"
                if rm "$inputFile"; then
                    log_message "Deleted original: $inputFile"
                else
                    log_error "Failed to delete original: $inputFile. Both original and transcoded files might exist."
                fi
            else
                log_error "Failed to move $tempOutputFile to $outputFileName"
                if [ -f "$tempOutputFile" ]; then
                     mv "$tempOutputFile" "${FAILED_DIR}/FAILED_MOVE_$(basename "$tempOutputFile")"
                fi
            fi
        else
            log_error "Transcoded file missing, zero size, or too small: $tempOutputFile (size: $file_size bytes)"
            if [ -f "$tempOutputFile" ]; then
                mv "$tempOutputFile" "${FAILED_DIR}/TOO_SMALL_OR_MISSING_$(basename "$tempOutputFile")"
            fi
        fi
    else
        hb_exit_code=$? # Capture exit code immediately
        log_error "HandBrakeCLI failed for: $inputFile (Exit code: $hb_exit_code)"
        if [ -f "$tempOutputFile" ]; then
            mv "$tempOutputFile" "${FAILED_DIR}/HB_ERROR_$(basename "$tempOutputFile")_exit${hb_exit_code}" # Add exit code to failed filename
            log_message "Moved failed temporary output to: ${FAILED_DIR}/HB_ERROR_$(basename "$tempOutputFile")_exit${hb_exit_code}"
        fi
    fi
    log_message "-----------------------------------------------------"
done

log_message "Script finished."
echo "Transcoding process complete. Check logs: $LOG_FILE and $ERROR_LOG_FILE"