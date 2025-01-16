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

param([string]$inputFile)

# Function to determine which video codec the source file uses to decode it properly
function Get-VideoCodec {
    param([string]$inputFile)
    
    $codecInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $inputFile
    return $codecInfo.Trim()
}

# Function to detect available GPU and set appropriate encoder

# Function to detect available GPU and set appropriate encoder
function Get-GPUEncoder {
    param([string]$codec)
    
    try {
        # If input is AV1, check for hardware support first
        if ($codec -eq "av1") {
            # Check for NVIDIA GPU with AV1 support (RTX 40 series) 
            $nvidia = & nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>$null
            if ($nvidia -and $nvidia -like "*RTX 40*") {
                Write-Host "GPU Detected: NVIDIA $($nvidia.Trim()) with AV1 support" -ForegroundColor Green
                Write-Host "Using NVENC AV1 encoder (av1_nvenc)" -ForegroundColor Green
                return @{
                    hwaccel = "cuda"
                    hwaccel_output_format = "cuda"
                    decoder = "av1_cuvid"
                    encoder = "av1_nvenc"
                    scale_filter = "scale_cuda"
                    preset = "p4"
                    extra_params = @("-rc-lookahead", "32", "-tile-columns", "2")
                }
            }
            
            # Check for AMD GPU with AV1 support (RX 7000 series)
            $amd = amf-encoder-test 2>$null
            if ($LASTEXITCODE -eq 0) {
                $amdGpu = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Radeon*" }
                if ($amdGpu.Caption -like "*RX 7*") {
                    Write-Host "GPU Detected: $($amdGpu.Caption) with AV1 support" -ForegroundColor Green
                    Write-Host "Using AMF AV1 encoder (av1_amf)" -ForegroundColor Green
                    return @{
                        hwaccel = "amf"
                        hwaccel_output_format = "nv12"
                        decoder = "av1"
                        encoder = "av1_amf"
                        scale_filter = "scale"
                        preset = "quality"
                        extra_params = @("-quality", "quality", "-tiles", "2")
                    }
                }
            }
            
            # Check for Intel GPU with AV1 support (Arc series)
            $intel = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Arc*" }
            if ($intel) {
                Write-Host "GPU Detected: $($intel.Caption) with AV1 support" -ForegroundColor Green
                Write-Host "Using QuickSync AV1 encoder (av1_qsv)" -ForegroundColor Green
                return @{
                    hwaccel = "qsv"
                    hwaccel_output_format = "nv12"
                    decoder = "av1_qsv"
                    encoder = "av1_qsv"
                    scale_filter = "scale"
                    preset = "veryslow"
                    extra_params = @("-look_ahead", "32", "-tile_cols", "2")
                }
            }
            
            # If no hardware AV1 support, use CPU-based AV1 codec with better configuration
            Write-Host "No hardware AV1 support detected! Using CPU-based AV1 encoder (libaom-av1)" -ForegroundColor Red
            Write-Host "THIS WILL BE MUCH SLOWER!!!" -ForegroundColor Red
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "libdav1d"  # Use dav1d software decoder instead of generic av1
                encoder = "libaom-av1"
                scale_filter = "scale"
                preset = "5"
                extra_params = @(
                    "-strict", "experimental",
                    "-cpu-used", "4",       
                    "-row-mt", "1",         
                    "-tile-columns", "2",   
                    "-tile-rows", "1",      
                    "-threads", "8",
                    "-lag-in-frames", "25", # Better quality with slight memory increase
                    "-error-resilient", "1" # Help prevent decode errors
                )
            }
        }
        # If input is H264, use original H264 encoding logic
        elseif ($codec -eq "h264") {
            # Check for NVIDIA GPU
            $nvidia = & nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>$null
            if ($nvidia) {
                Write-Host "GPU Detected: NVIDIA $($nvidia.Trim())" -ForegroundColor Green
                Write-Host "Using NVENC encoder (h264_nvenc)" -ForegroundColor Green
                return @{
                    hwaccel = "cuda"
                    hwaccel_output_format = "cuda"
                    decoder = "h264_cuvid"
                    encoder = "h264_nvenc"
                    scale_filter = "scale_cuda"
                    preset = "p1"
                }
            }
            
            # Check for AMD GPU
            $amd = amf-encoder-test 2>$null
            if ($LASTEXITCODE -eq 0) {
                $amdGpu = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Radeon*" }
                Write-Host "GPU Detected: $($amdGpu.Caption)" -ForegroundColor Green
                Write-Host "Using AMF encoder (h264_amf)" -ForegroundColor Green
                return @{
                    hwaccel = "amf"
                    hwaccel_output_format = "nv12"
                    decoder = "h264"
                    encoder = "h264_amf"
                    scale_filter = "scale"
                    preset = "quality"
                }
            }
            
            # Check for Intel GPU
            $intel = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Intel*" }
            if ($intel) {
                Write-Host "GPU Detected: $($intel.Caption)" -ForegroundColor Green
                Write-Host "Using QuickSync encoder (h264_qsv)" -ForegroundColor Green
                return @{
                    hwaccel = "qsv"
                    hwaccel_output_format = "nv12"
                    decoder = "h264_qsv"
                    encoder = "h264_qsv"
                    scale_filter = "scale"
                    preset = "veryslow"
                }
            }
            
            Write-Host "No supported GPU detected. Using CPU encoding..." -ForegroundColor Yellow
            Write-Host "Using CPU encoder (libx264)" -ForegroundColor Yellow
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "h264"
                encoder = "libx264"
                scale_filter = "scale"
                preset = "medium"
            }
        }
        else {
            Write-Host "Unsupported codec: $codec. Falling back to H264..." -ForegroundColor Yellow
            return Get-GPUEncoder -codec "h264"
        }
    }
    catch {
        Write-Host "Error detecting GPU. Using CPU encoding..." -ForegroundColor Yellow
        if ($codec -eq "av1") {
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "libdav1d"
                encoder = "libaom-av1"
                scale_filter = "scale"
                preset = "5"
                extra_params = @(
                    "-strict", "experimental",
                    "-cpu-used", "4",
                    "-row-mt", "1",
                    "-tile-columns", "2",
                    "-tile-rows", "1",
                    "-threads", "8",
                    "-lag-in-frames", "25",
                    "-error-resilient", "1"
                )
            }
        }
        return @{
            hwaccel = $null
            hwaccel_output_format = $null
            decoder = "h264"
            encoder = "libx264"
            scale_filter = "scale"
            preset = "medium"
        }
    }
}

try {
    $startTime = Get-Date
    
    # Constants - using 93% of 10MB as target
    $MAX_SIZE_BYTES = 10485760 * 0.93
    
    # Set encoding parameters
    $MIN_AUDIO_BITRATE = 48
    
    # First get the input codec
    $inputCodec = Get-VideoCodec -inputFile $inputFile
    Write-Host "`nInput Video Codec: $inputCodec" -ForegroundColor Cyan
    
    # Get GPU encoder settings with codec information
    $gpu = Get-GPUEncoder -codec $inputCodec
    
    # Set codec-specific parameters
    if ($inputCodec -eq "av1") {
        $TUNE = "ssim"       # Visual quality tuning for AV1
        $PROFILE = "main"    # AV1 main profile
    } else {
        $TUNE = "hq"        # High quality tuning for H264
        $PROFILE = "high"   # H264 high profile
    }
    
    # Get video information
    $videoInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of json $inputFile | ConvertFrom-Json
    $width = $videoInfo.streams[0].width
    $height = $videoInfo.streams[0].height
    $originalFps = [math]::Round([decimal]($videoInfo.streams[0].r_frame_rate -split '/')[0] / ($videoInfo.streams[0].r_frame_rate -split '/')[1], 2)
    
    Write-Host "`nInput Video Details:" -ForegroundColor Cyan
    Write-Host "Resolution: ${width}x${height}"
    Write-Host "Framerate: $originalFps FPS"
    
    # Get video duration
    $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $inputFile
    $duration_int = [math]::Floor([double]$duration)
    
    # Determine target FPS based on duration
    if ($duration_int -gt 240) {
        $target_fps = 15
    } elseif ($duration_int -gt 80) {
        $target_fps = 24
    } elseif ($duration_int -gt 40) {
        $target_fps = 30
    } else {
        $target_fps = 60
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
        $target_height = $height
    }
    
    # Include FPS adjustment in scale filter
    $SCALE = "-vf `"$($gpu.scale_filter)=-2:$target_height,fps=$target_fps`""

    # Calculate bitrates
    $total_available_bytes = $MAX_SIZE_BYTES
    $audio_bytes = ($duration_int * $MIN_AUDIO_BITRATE * 1000 / 8)
    $video_bytes = $total_available_bytes - $audio_bytes
    $video_bitrate = [math]::Floor(($video_bytes * 8) / $duration_int / 1000 * 0.97)

    Write-Host "`nCompression Settings:" -ForegroundColor Cyan
    Write-Host "Target Resolution: ${target_height}p"
    Write-Host "Target Framerate: $target_fps FPS"
    Write-Host "Video Bitrate: $video_bitrate kbps"
    Write-Host "Audio Bitrate: $MIN_AUDIO_BITRATE kbps"
    Write-Host "Using encoder: $($gpu.encoder)`n"

    # Create output filename with codec-specific extension
    $output_file = [System.IO.Path]::GetDirectoryName($inputFile) + "\" + 
                  [System.IO.Path]::GetFileNameWithoutExtension($inputFile) + 
                  "_compressed.mp4"  # Keep mp4 as it supports both h264 and av1

    # Build ffmpeg command
    $ffmpeg_args = @(
        "-y",
        "-loglevel", "error",
        "-stats"
    )

    # Add hardware acceleration if available
    if ($gpu.hwaccel) {
        $ffmpeg_args += @(
            "-hwaccel", $gpu.hwaccel
        )
        if ($gpu.hwaccel_output_format) {
            $ffmpeg_args += @(
                "-hwaccel_output_format", $gpu.hwaccel_output_format
            )
        }
    }

    # Add input decoder and file
    $ffmpeg_args += @(
        "-c:v", $gpu.decoder,
        "-i", $inputFile,
        "-c:v", $gpu.encoder,
        "-preset", $gpu.preset
    )

    # Add codec-specific encoding parameters
    if ($inputCodec -eq "av1") {
        if ($gpu.extra_params) {
            foreach ($param in $gpu.extra_params) {
                $ffmpeg_args += $param
            }
        }
        # Add specific libaom-av1 quality parameters when using CPU encoding
        if ($gpu.encoder -eq "libaom-av1") {
            $ffmpeg_args += @(
                "-strict", "experimental",
                "-quality", "good",
                "-crf", "30"  # Adjust CRF value between 0-63 for quality (lower is better)
            )
        }
    } else {
        $ffmpeg_args += @(
            "-tune", $TUNE,
            "-rc", "cbr",
            "-profile:v", $PROFILE
        )
    }

    # Add common encoding parameters
    $ffmpeg_args += @(
        "-b:v", "${video_bitrate}k",
        "-maxrate", "${video_bitrate}k",
        "-minrate", "${video_bitrate}k",
        "-bufsize", "${video_bitrate}k"
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
    
    $endTime = Get-Date
    $processingTime = ($endTime - $startTime).TotalSeconds

    # Get final video info
    $finalVideoInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,bit_rate -of json $output_file | ConvertFrom-Json
    $finalBitrate = [math]::Round([int]$finalVideoInfo.streams[0].bit_rate / 1000)
    $finalFps = [math]::Round([decimal]($finalVideoInfo.streams[0].r_frame_rate -split '/')[0] / ($finalVideoInfo.streams[0].r_frame_rate -split '/')[1], 2)
    
    # Verify final size and show results
    $final_size_mb = (Get-Item $output_file).Length/1024/1024
    $original_size_mb = (Get-Item $inputFile).Length/1024/1024
    Write-Host "`nCompression Results:" -ForegroundColor Cyan
    Write-Host "Time taken: $([math]::Round($processingTime, 2)) seconds"
    Write-Host "Original size: $($original_size_mb.ToString('0.00')) MB"
    Write-Host "Final size: $($final_size_mb.ToString('0.00')) MB"
    Write-Host "Compression ratio: $([math]::Round($original_size_mb/$final_size_mb, 2)):1"
    Write-Host "Final resolution: $($finalVideoInfo.streams[0].width)x$($finalVideoInfo.streams[0].height)"
    Write-Host "Final framerate: $finalFps FPS"
    Write-Host "Final video bitrate: $finalBitrate kbps"
    Write-Host "Output saved as: $output_file"

    if ($final_size_mb -gt 10) {
        Write-Host "`nError!: File size exceeds 10MB limit! No video output file was made." -ForegroundColor Red
        Remove-Item $output_file
    }
}
catch {
    Write-Host "`nAn error occurred:"
    Write-Host $_
}

Write-Host "`nWindow will stay open for 100000 seconds. Press Ctrl+C to close immediately..."
Start-Sleep -Seconds 100000;