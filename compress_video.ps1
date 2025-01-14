param([string]$inputFile)

try {
    # Constants
    $MAX_SIZE_BYTES = 10 * 1024 * 1024  # Exactly 10MB in bytes
    $OVERHEAD_FACTOR = 1.02  # Account for container overhead (2%)

    # Get video duration
    Write-Host "Getting video duration..."
    $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $inputFile
    $duration_int = [math]::Floor([double]$duration)

    # Calculate available bits accounting for overhead
    $total_available_bytes = $MAX_SIZE_BYTES / $OVERHEAD_FACTOR
    $audio_bytes = 1048576  # Reserve 1MB for audio
    $video_bytes = $total_available_bytes - $audio_bytes

    # Calculate target video bitrate (in kbps)
    $video_bitrate = [math]::Floor(($video_bytes * 8) / $duration_int / 1000)

    Write-Host "Starting compression..."
    Write-Host "Target total size: $($MAX_SIZE_BYTES/1024/1024)MB"
    Write-Host "Video bitrate: $video_bitrate kbps"
    Write-Host "Duration: $duration_int seconds"

    # Create temp and output filenames
    $temp_video = [System.IO.Path]::GetDirectoryName($inputFile) + "\temp_video.mp4"
    $output_file = [System.IO.Path]::GetDirectoryName($inputFile) + "\" + [System.IO.Path]::GetFileNameWithoutExtension($inputFile) + "_compressed.mp4"

    # First pass: Compress video only
    Write-Host "Compressing video..."
    & ffmpeg -y -i $inputFile -an -c:v libx264 -preset ultrafast `
      -b:v "${video_bitrate}k" -maxrate "${video_bitrate}k" -bufsize "${video_bitrate}k" `
      -vf "scale=-2:720" $temp_video

    # Calculate audio bitrate based on remaining space
    $video_size = (Get-Item $temp_video).Length
    $remaining_bytes = $MAX_SIZE_BYTES - $video_size
    $audio_bitrate = [math]::Floor(($remaining_bytes * 8) / $duration_int / 1000)
    $audio_bitrate = [math]::Min(128, [math]::Max(64, $audio_bitrate))
    
    Write-Host "Audio bitrate: $audio_bitrate kbps"

    # Final pass: Add audio to the compressed video
    Write-Host "Adding audio..."
    & ffmpeg -y -i $temp_video -i $inputFile -map 0:v -map 1:a `
      -c:v copy -c:a aac -b:a "${audio_bitrate}k" -movflags +faststart $output_file

    # Clean up temp file
    Remove-Item $temp_video -ErrorAction SilentlyContinue

    # Verify final size
    $final_size = (Get-Item $output_file).Length
    if ($final_size -gt $MAX_SIZE_BYTES) {
        Write-Host "Warning: File exceeded 10MB, attempting one more compression pass..."
        $new_bitrate = [math]::Floor($video_bitrate * ($MAX_SIZE_BYTES / $final_size))
        $final_attempt = $output_file + ".tmp"
        
        & ffmpeg -y -i $output_file -c:v libx264 -preset ultrafast `
          -b:v "${new_bitrate}k" -maxrate "${new_bitrate}k" -bufsize "${new_bitrate}k" `
          -c:a copy $final_attempt
        
        Move-Item -Force $final_attempt $output_file
    }

    $final_size_mb = (Get-Item $output_file).Length/1024/1024
    Write-Host "`nCompression complete!"
    Write-Host "Final file size: $($final_size_mb.ToString('0.00'))MB"
    Write-Host "Output saved as: $output_file"
}
catch {
    Write-Host "`nAn error occurred:"
    Write-Host $_
}

Write-Host "`nWindow will stay open for 30 seconds. Press Ctrl+C to close immediately..."
Start-Sleep -Seconds 30