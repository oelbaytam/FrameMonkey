param([string]$inputFile)

# This is a compression method that scales resolution and framerate with the length of the video it is compressing, below are the thresholds for the resolution and framerate:

# Resolution:
# - Videos longer than 10 minutes will be scaled to 480p
# - Videos longer than 5 minutes will be scaled to 540p
# - Videos longer than 2 minutes will be scaled to 620p
# - Videos longer than 20 seconds will be scaled to 720p
# - Videos shorter than 20 seconds will be scaled to 1080p
# - Videos shorter than 10 seconds will maintain their native resolution

# Framerate:
# - Videos longer than 1 minute and 20 seconds will be compressed to 24fps
# - Videos longer than 40 seconds will be compressed to 30fps
# - Videos shorter than 40 seconds will maintain their native framerate

try {
    # Constants - using 93% of 10MB as target
    $MAX_SIZE_BYTES = 10485760 * 0.93
    
    # Set encoding parameters
    $NVENC_PRESET = "p1"
    $MIN_AUDIO_BITRATE = 48
    $TUNE = "hq"
    $PROFILE = "high"
    
    # Get video resolution and fps
    $resolution = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $inputFile
    $width, $height = $resolution.Split('x')
    
    # Dynamic scaling based on video length and resolution
    $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $inputFile
    $duration_int = [math]::Floor([double]$duration)
    
    # Determine target FPS based on duration
    if ($duration_int -gt 240 ) {
        $target_fps = 15
        Write-Host "Video longer than 4 minutes - targeting 15fps for better quality"
    } elseif ($duration_int -gt 80) {
        $target_fps = 24
        Write-Host "Video longer than 80 seconds - targeting 24fps for better quality"
    } elseif ($duration_int -gt 40) {
        $target_fps = 30
        Write-Host "Video longer than 40 seconds - targeting 30fps for better quality"
    } else {
        $target_fps = 60
        Write-Host "Video shorter than 30 sec - maintaining 60fps"
    }
    
    # Calculate target resolution based on duration
    if ($duration_int -gt 600) {      # > 10 minutes
        $target_height = 480
    } elseif ($duration_int -gt 300) { # > 5 minutes
        $target_height = 540
    } elseif ($duration_int -gt 120) { # > 2 minutes
        $target_height = 620
    } elseif ($duration_int -gt 20) {  # > 20 seconds
        $target_height = 720
    } elseif ($duration_int -gt 10) {  # > 10 seconds
        $target_height = 1080
    } else {                           # <= 10 seconds
        # Keep native resolution
        $target_height = $height
        Write-Host "Video shorter than 10 seconds - maintaining native resolution"
    }
    
    # Include FPS adjustment in scale filter
    $SCALE = "-vf `"scale_cuda=-2:$target_height,fps=$target_fps`""

    # Calculate bitrates
    $total_available_bytes = $MAX_SIZE_BYTES
    $audio_bytes = ($duration_int * $MIN_AUDIO_BITRATE * 1000 / 8)
    $video_bytes = $total_available_bytes - $audio_bytes
    $video_bitrate = [math]::Floor(($video_bytes * 8) / $duration_int / 1000 * 0.97)

    Write-Host "Starting hardware-accelerated compression..."
    Write-Host "Target total size: $($MAX_SIZE_BYTES/1024/1024)MB"
    Write-Host "Video bitrate: $video_bitrate kbps"
    Write-Host "Audio bitrate: $MIN_AUDIO_BITRATE kbps"
    Write-Host "Target resolution: ${target_height}p"
    Write-Host "Target FPS: $target_fps"

    # Create output filename
    $output_file = [System.IO.Path]::GetDirectoryName($inputFile) + "\" + 
                  [System.IO.Path]::GetFileNameWithoutExtension($inputFile) + 
                  "_compressed.mp4"

    # Build ffmpeg command - Using CBR for strict size control
    $ffmpeg_args = @(
        "-y",
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda",
        "-c:v", "h264_cuvid",
        "-i", $inputFile,
        "-c:v", "h264_nvenc",
        "-preset", $NVENC_PRESET,
        "-tune", $TUNE,
        "-rc", "cbr",              # Constant Bitrate mode
        "-b:v", "${video_bitrate}k",
        "-maxrate", "${video_bitrate}k",
        "-minrate", "${video_bitrate}k",  # Force constant bitrate
        "-bufsize", "${video_bitrate}k",  # Match bitrate for CBR
        "-profile:v", $PROFILE,
        "-gpu", "any"
    )

    # Add scaling and fps adjustment
    if ($SCALE) {
        $ffmpeg_args += $SCALE.Split(" ")
    }

    # Add audio settings
    $ffmpeg_args += @(
        "-c:a", "aac",
        "-b:a", "${MIN_AUDIO_BITRATE}k",
        "-movflags", "+faststart",
        $output_file
    )

    # Execute ffmpeg
    Write-Host "Compressing video and audio..."
    & ffmpeg $ffmpeg_args

    # Verify final size
    $final_size_mb = (Get-Item $output_file).Length/1024/1024
    Write-Host "`nCompression complete!"
    Write-Host "Final file size: $($final_size_mb.ToString('0.00'))MB"
    Write-Host "Output saved as: $output_file"

    if ($final_size_mb -gt 10) {
        Write-Host "`nError: File size exceeds 10MB limit! Please try again with a lower quality setting."
        Remove-Item $output_file
        exit 1
    }
}
catch {
    Write-Host "`nAn error occurred:"
    Write-Host $_
    exit 1
}

Write-Host "`nWindow will stay open for 30 seconds. Press Ctrl+C to close immediately..."
Start-Sleep -Seconds 30