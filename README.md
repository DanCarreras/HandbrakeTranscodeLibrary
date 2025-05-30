# HandbrakeTranscodeLibrary
A bash script to transcode and reduce your entire media library using Handbrake CLI and Apple H.265 VideoToolbox.

# How to Use

This script automates the process of finding video files in a specified library, transcoding them to H.265 MP4 format using HandBrakeCLI with hardware acceleration (Apple VideoToolbox), and organizing the results.

## 1. Prerequisites

Before running the script, ensure you have the following:

* **macOS:** This script is designed for macOS, particularly because it uses Apple's VideoToolbox for hardware-accelerated H.265 encoding.
* **HandBrakeCLI:** The command-line interface for HandBrake must be installed.
    * You can install it using Homebrew:
        ```bash
        brew install handbrake
        ```
    * Verify it's installed and in your PATH by running `HandBrakeCLI --version` in your terminal.
* **Bash:** The script is written for bash, which is the default shell on older macOS versions and available on all.
* **Sufficient Disk Space:** Transcoding can temporarily require significant disk space for the new files before originals are deleted. Ensure your `VIDEO_LIBRARY_PATH` and the drive it's on have ample free space. The `Temp` directory will also be used during transcoding.

## 2. Configuration

You need to configure a few variables at the top of the `TranscodeLibrary.sh` script (or whatever you name it):

1.  **`VIDEO_LIBRARY_PATH`**:
    * This is the most important setting. Change it to the **absolute path** of your main video library directory.
    * Example: `VIDEO_LIBRARY_PATH="/Volumes/MyExternalHardDrive/Movies_and_TV"`
    * **Important:** Do not include a trailing slash (`/`) at the end of this path.

2.  **`OUTPUT_EXTENSION`** (Optional):
    * Defaults to `mp4`. This is the extension for the transcoded files. It's generally recommended to keep this as `mp4` for H.265.

3.  **`HANDBRAKE_PRESET`** (Optional, but important for quality/speed):
    * Defaults to `"Hardware/H.265 Apple VideoToolbox 1080p"`. This preset is optimized for 1080p output using Apple's hardware H.265 encoder.
    * You can list available presets in HandBrakeCLI by running: `HandBrakeCLI --preset-list`
    * Choose a preset that matches your desired output resolution and encoding method. Using hardware presets (like VideoToolbox or Video Decode Acceleration Framework on macOS) is generally faster.

4.  **`LOG_RETENTION_DAYS`** (Optional):
    * Defaults to `30`. Log files older than this number of days will be automatically deleted when the script starts.

## 3. Making the Script Executable

Before you can run the script, you need to make it executable:

1.  Save the script to a file, for example, `TranscodeLibrary.sh`.
2.  Open your Terminal.
3.  Navigate to the directory where you saved the script:
    ```bash
    cd /path/to/your/script/directory
    ```
4.  Make it executable:
    ```bash
    chmod +x TranscodeLibrary.sh
    ```

## 4. Running the Script

1.  Open your Terminal.
2.  Navigate to the directory where you saved the script (if you're not already there).
3.  Run the script:
    ```bash
    ./TranscodeLibrary.sh
    ```

**Important Considerations When Running:**

* **Time:** Transcoding an entire library can take a very long time, potentially hours or even days, depending on the size of your library, the speed of your computer, and the chosen preset.
* **System Resources:** Transcoding is CPU and sometimes GPU intensive. Your computer may become slower and generate more heat while the script is running.
* **Single Instance:** It's generally recommended to run only one instance of this script at a time, especially when using hardware encoders which are often limited to one process at a time.
* **Test First:** Consider testing the script on a small subfolder of your library first to ensure it works as expected and the output quality/size is acceptable. You can do this by temporarily changing `VIDEO_LIBRARY_PATH` to a smaller test directory.

## 5. What the Script Does

* **Creates Directories:** It will create `Logs`, `Failed_Transcodes`, `Manual_Review`, and `Temp` subdirectories within your `VIDEO_LIBRARY_PATH` if they don't already exist.
* **Cleans Old Logs:** Deletes log files older than `LOG_RETENTION_DAYS`.
* **Finds Videos:** It searches for video files (`.mp4`, `.mkv`, `.avi`, `.mov`, `.wmv`, `.flv`) within your `VIDEO_LIBRARY_PATH`.
    * It will **skip** any files found within a directory named "Downloads".
    * It will **skip** files that already have `_H265.mp4` (or your configured `OUTPUT_EXTENSION`) in their name, assuming they've been processed.
    * It will **skip** files within the special `Logs`, `Failed_Transcodes`, `Manual_Review`, and `Temp` directories.
* **Transcodes:** For each found video:
    * It creates a unique temporary filename in the `Temp` directory.
    * It uses `HandBrakeCLI` with the specified preset and audio settings:
        * Video: H.265 (via Apple VideoToolbox).
        * Audio: Tries to copy `aac`, `ac3`, `eac3`, `dts` tracks. If it needs to re-encode audio (or for other tracks), it will create a stereo AAC track at 160kbps.
    * Logs detailed output from HandBrakeCLI to a timestamped log file in the `Logs` directory. Errors are logged to a separate error log file.
* **Verifies Output:** Checks if the transcoded file in `Temp` exists and is larger than 1MB.
* **Replaces Original:**
    * If successful and the file is of reasonable size, it moves the transcoded file from `Temp` to the original file's directory, appending `_H265` to the original filename (before the extension).
    * It then **deletes the original video file**.
* **Handles Failures:**
    * If HandBrakeCLI fails, the temporary output (if any) is moved to the `Failed_Transcodes` directory, named with `HB_ERROR_` prefix and the exit code.
    * If the transcoded file is too small or missing, the temporary output (if any) is moved to `Failed_Transcodes` with a `TOO_SMALL_OR_MISSING_` prefix.
    * If renaming/moving the successfully transcoded file fails, it's moved to `Failed_Transcodes` with a `FAILED_MOVE_` prefix.

## 6. Checking Progress and Logs

* **Terminal Output:** The script will print basic status messages to the terminal as it runs (e.g., "Starting transcode for...", "Successfully transcoded...").
* **Log Files:**
    * **Main Log:** Located in `VIDEO_LIBRARY_PATH/Logs/transcoding_log_YYYYMMDD_HHMMSS.txt`. This file contains detailed output from HandBrakeCLI for each transcode attempt, success messages, and file operations.
    * **Error Log:** Located in `VIDEO_LIBRARY_PATH/Logs/transcoding_error_log_YYYYMMDD_HHMMSS.txt`. This file specifically captures error messages from the script or HandBrakeCLI.
    * Review these logs, especially the error log, if you encounter any issues or if files end up in `Failed_Transcodes`.

## 7. Output Files and Structure

* Successfully transcoded files will be in the same directory as their original files, but with `_H265.mp4` appended to their name (e.g., `MyMovie.mkv` becomes `MyMovie_H265.mp4`).
* Original files are deleted after successful transcoding and replacement.
* Problematic files or failed transcodes will be moved to the `Failed_Transcodes` directory for manual review. Files needing other types of review might be intended for the `Manual_Review` directory (though the script doesn't explicitly move files there automatically based on current logic, it creates the folder).

## 8. Customizing HandBrakeCLI Options

You can further customize the HandBrakeCLI command within the script if you have specific needs. The relevant section is:
```bash
    if HandBrakeCLI --verbose \
        -i "$inputFile" \
        -o "$tempOutputFile" \
        -Z "$HANDBRAKE_PRESET" \
        --audio-copy-mask aac,ac3,eac3,dts \
        --aencoder copy:aac \
        --ab 160 \
        --mixdown stereo \
        --format av_mp4 >>"$LOG_FILE" 2>>"$ERROR_LOG_FILE" < /dev/null; then
```

Refer to the [HandBrakeCLI documentation](https://handbrake.fr/docs/en/latest/cli/command-line-reference.html) for all available options. For example, you might want to adjust:

* Video quality/bitrate settings (though be cautious when using presets, as they often manage this).
* Audio track selection and encoding parameters.
* Subtitle handling.

Remember to test any changes thoroughly.
