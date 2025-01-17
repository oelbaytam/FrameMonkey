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

param(
    [Parameter(Mandatory=$true)]
    [string]$inputFile
)

# Verify required tools are available
function Test-Requirements {
    try {
        $ffmpeg = & ffmpeg -version 2>$null
        $ffprobe = & ffprobe -version 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg/FFprobe not found. Please ensure FFmpeg is installed and in your PATH."
        }
        
        if (-not (Test-Path $inputFile)) {
            throw "Input file not found: $inputFile"
        }
        
        $fileInfo = Get-Item $inputFile
        if ($fileInfo.Length -eq 0) {
            throw "Input file is empty"
        }
        
        return $true
    }
    catch {
        Write-Host "Requirement check failed: $_" -ForegroundColor Red
        return $false
    }
}
# Function to determine which video codec the source file uses
function Get-VideoCodec {
    param(
        [Parameter(Mandatory=$true)]
        [string]$inputFile
    )
    
    try {
        $codecInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $inputFile
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to detect codec"
        }
        return $codecInfo.Trim().ToLower()
    }
    catch {
        Write-Host "Error detecting codec: $_" -ForegroundColor Red
        return 'h264' # Safe fallback
    }
}

# Helper function to detect GPU type with improved error handling
function Get-GPUType {
    try {
        # Check for GPUs using WMI first
        $gpus = Get-WmiObject -Query "SELECT * FROM Win32_VideoController"
        
        # Check for AMD GPU first
        $amd = $gpus | Where-Object { $_.Caption -like "*Radeon*" }
        if ($amd) {
            Write-Host "AMD GPU detected: $($amd.Caption)" -ForegroundColor Green
            return 'amd'
        }
        
        # Then check for NVIDIA GPU
        $nvidia = $gpus | Where-Object { $_.Caption -like "*NVIDIA*" }
        if ($nvidia) {
            # Only try nvidia-smi if we actually found an NVIDIA GPU
            $nvidiaSmi = & nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>$null
            if ($LASTEXITCODE -eq 0) {
                return 'nvidia'
            }
        }
        
        # Finally check for Intel GPU
        $intel = $gpus | Where-Object { $_.Caption -like "*Intel*" }
        if ($intel) {
            return 'intel'
        }
    }
    catch {
        Write-Host "Error during GPU detection: $_" -ForegroundColor Red
    }
    
    Write-Host "No compatible GPU detected, falling back to CPU encoding" -ForegroundColor Yellow
    return 'cpu' # Safe fallback
}

# Update the Get-CPUEncoder function
function Get-CPUEncoder {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('h264','av1')]
        [string]$codec
    )
    
    switch ($codec) {
        'h264' {
            Write-Host "Using CPU encoder (libx264)" -ForegroundColor Yellow
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "h264"
                encoder = "libx264"
                scale_filter = "scale"
                preset = "medium"
                valid = $true
            }
        }
        'av1' {
            Write-Host "Using CPU-based AV1 encoder (libaom-av1)" -ForegroundColor Red
            Write-Host "THIS WILL BE MUCH SLOWER!!!" -ForegroundColor Red
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "av1"  # Changed from libdav1d to av1
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
                valid = $true
            }
        }
    }
}

function Get-GPUEncoder {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('h264','av1')]
        [string]$codec
    )
    
    try {
        $gpuType = Get-GPUType
        
        # Main GPU switch
        switch ($gpuType) {
            'nvidia' {
                $encoderConfig = switch ($codec) {
                    'h264' {
                        Write-Host "GPU Detected: NVIDIA with H264 support" -ForegroundColor Green
                        Write-Host "Using NVENC encoder (h264_nvenc)" -ForegroundColor Green
                        @{
                            hwaccel = "cuda"
                            hwaccel_output_format = "cuda"
                            decoder = "h264_cuvid"
                            encoder = "h264_nvenc" 
                            scale_filter = "scale_cuda"
                            preset = "p1"
                            valid = $true
                        }
                        break
                    }
                    'av1' {
                        # Check if GPU supports AV1 (RTX 40 series)
                        $nvidia = & nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>$null
                        if ($nvidia -like "*RTX 40*") {
                            Write-Host "GPU Detected: NVIDIA $($nvidia.Trim()) with AV1 support" -ForegroundColor Green
                            Write-Host "Using NVENC AV1 encoder (av1_nvenc)" -ForegroundColor Green
                            @{
                                hwaccel = "cuda"
                                hwaccel_output_format = "cuda"
                                decoder = "av1_cuvid"
                                encoder = "av1_nvenc"
                                scale_filter = "scale_cuda"
                                preset = "p4"
                                extra_params = @("-rc-lookahead", "32", "-tile-columns", "2")
                                valid = $true
                            }
                        }
                        else {
                            Get-CPUEncoder -codec $codec
                        }
                        break
                    }
                }
                break
            }
            'amd' {
                $encoderConfig = switch ($codec) {
                    'h264' {
                        $amdGpu = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Radeon*" }
                        Write-Host "GPU Detected: $($amdGpu.Caption)" -ForegroundColor Green
                        Write-Host "Using AMF encoder (h264_amf)" -ForegroundColor Green
                        @{
                            hwaccel = "d3d11va"
                            hwaccel_output_format = "nv12"
                            decoder = "h264"
                            encoder = "h264_amf"
                            scale_filter = "scale"
                            preset = "quality"
                            valid = $true
                        }
                        break
                    }
                    'av1' {
                        $amdGpu = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Radeon*" }
                        # Updated regex pattern to match RX 7000 series
                        if ($amdGpu.Caption -match "RX\s+7\d{3}|RX\s*7\d{3}\s*XT") {
                            Write-Host "GPU Detected: $($amdGpu.Caption) with AV1 support" -ForegroundColor Green
                            Write-Host "Using AMF AV1 encoder (av1_amf)" -ForegroundColor Green
                            @{
                                hwaccel = "d3d11va"
                                hwaccel_output_format = "nv12"
                                decoder = "av1"
                                encoder = "av1_amf"
                                scale_filter = "scale"
                                preset = "quality"
                                extra_params = @(
                                    "-quality", "quality",
                                    "-usage", "transcoding",
                                    "-rc", "vbr_latency",
                                    "-async_depth", "1",
                                    "-max_lab", "1",
                                    # "-header_insertion_mode", "idr",
                                    "-gops_per_idr", "1",
                                    "-tiles", "2",
                                    "-bf_delta_qp", "0",
                                    "-refs", "2"
                                )
                                valid = $true
                            }
                        }
                        else {
                            Get-CPUEncoder -codec $codec
                        }
                        break
                    }
                }
                break
            }
            'intel' {
                $encoderConfig = switch ($codec) {
                    'h264' {
                        $intel = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Intel*" }
                        Write-Host "GPU Detected: $($intel.Caption)" -ForegroundColor Green
                        Write-Host "Using QuickSync encoder (h264_qsv)" -ForegroundColor Green
                        @{
                            hwaccel = "qsv"
                            hwaccel_output_format = "nv12"
                            decoder = "h264_qsv"
                            encoder = "h264_qsv"
                            scale_filter = "scale"
                            preset = "veryslow"
                            valid = $true
                        }
                        break
                    }
                    'av1' {
                        $intel = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Arc*" }
                        if ($intel) {
                            Write-Host "GPU Detected: $($intel.Caption) with AV1 support" -ForegroundColor Green
                            Write-Host "Using QuickSync AV1 encoder (av1_qsv)" -ForegroundColor Green
                            @{
                                hwaccel = "qsv"
                                hwaccel_output_format = "nv12"
                                decoder = "av1_qsv"
                                encoder = "av1_qsv"
                                scale_filter = "scale"
                                preset = "veryslow"
                                extra_params = @("-look_ahead", "32", "-tile_cols", "2")
                                valid = $true
                            }
                        }
                        else {
                            Get-CPUEncoder -codec $codec
                        }
                        break
                    }
                }
                break
            }
            default {
                $encoderConfig = Get-CPUEncoder -codec $codec
                break
            }
        }
        
        # Validate encoder configuration
        if ($null -eq $encoderConfig -or -not $encoderConfig.valid) {
            Write-Host "Invalid encoder configuration detected. Falling back to CPU..." -ForegroundColor Yellow
            return Get-CPUEncoder -codec $codec
        }
        
        return $encoderConfig
    }
    catch {
        Write-Host "Error in GPU encoder selection: $_" -ForegroundColor Red
        return Get-CPUEncoder -codec $codec
    }
}

function Get-VideoInfo {
    param([string]$inputFile)
    
    try {
        $videoInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of json $inputFile | ConvertFrom-Json
        $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $inputFile
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get video information"
        }

        return @{
            width = $videoInfo.streams[0].width
            height = $videoInfo.streams[0].height
            fps = [math]::Round([decimal]($videoInfo.streams[0].r_frame_rate -split '/')[0] / ($videoInfo.streams[0].r_frame_rate -split '/')[1], 2)
            duration = [math]::Floor([double]$duration)
        }
    }
    catch {
        Write-Host "Error getting video information: $_" -ForegroundColor Red
        throw
    }
}

function Get-CompressionSettings {
    param($videoInfo)
    
    try {
        # Determine target FPS based on duration
        $duration = $videoInfo.duration
        $target_fps = if ($duration -gt 240) { 15 }
                     elseif ($duration -gt 80) { 24 }
                     elseif ($duration -gt 40) { 30 }
                     else { 60 }

        # Calculate target resolution based on duration
        $target_height = if ($duration -gt 600) { 480 }        # > 10 minutes
                        elseif ($duration -gt 300) { 540 }     # > 5 minutes
                        elseif ($duration -gt 120) { 620 }     # > 2 minutes
                        elseif ($duration -gt 20) { 720 }      # > 20 seconds
                        elseif ($duration -gt 10) { 1080 }     # > 10 seconds
                        else { $videoInfo.height }             # <= 10 seconds - keep original

        # Calculate bitrates
        $MAX_SIZE_BYTES = 10485760 * 0.93  # 93% of 10MB
        $MIN_AUDIO_BITRATE = 48
        
        $total_available_bytes = $MAX_SIZE_BYTES
        $audio_bytes = $duration * $MIN_AUDIO_BITRATE * 1000 / 8
        $video_bytes = $total_available_bytes - $audio_bytes
        $video_bitrate = [Math]::Floor(($video_bytes * 8) / $duration / 1000 * 0.97)
        
        Write-Host "`nCompression Settings:" -ForegroundColor Cyan
        Write-Host "Target Resolution: $($target_height)p"
        Write-Host "Target Framerate: $target_fps FPS"
        Write-Host "Video Bitrate: $video_bitrate kbps"
        Write-Host "Audio Bitrate: $MIN_AUDIO_BITRATE kbps"
        
        return @{
            target_fps = $target_fps
            target_height = $target_height
            video_bitrate = $video_bitrate
            audio_bitrate = $MIN_AUDIO_BITRATE
        }
    }
    catch {
        Write-Host "Error calculating compression settings: $_" -ForegroundColor Red
        throw
    }
}

function BuildFFmpegCommand {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$gpu,
        
        [Parameter(Mandatory=$true)]
        [string]$inputFile,
        
        [Parameter(Mandatory=$true)]
        [string]$outputFile,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$compressionSettings,
        
        [Parameter(Mandatory=$true)]
        [string]$inputCodec
    )
    
    $ffmpeg_args = [System.Collections.ArrayList]@()
    
    # Global options
    $ffmpeg_args.Add("-y") > $null                           # Overwrite output file without asking
    $ffmpeg_args.Add("-hide_banner") > $null                 # Hide FFmpeg compilation info
    
    # Input options
    if ($gpu.hwaccel) {
        $ffmpeg_args.Add("-hwaccel") > $null
        $ffmpeg_args.Add($gpu.hwaccel) > $null
        
        if ($gpu.hwaccel_output_format) {
            $ffmpeg_args.Add("-hwaccel_output_format") > $null
            $ffmpeg_args.Add($gpu.hwaccel_output_format) > $null
        }
    }
    
    # Input file
    $ffmpeg_args.Add("-i") > $null
    $ffmpeg_args.Add($inputFile) > $null
    
    # Video encoding options
    $ffmpeg_args.Add("-c:v") > $null
    $ffmpeg_args.Add($gpu.encoder) > $null
    
    # Two-pass encoding parameters
    $ffmpeg_args.Add("-pass") > $null
    $ffmpeg_args.Add("2") > $null        # Second pass
    
    # Encoding preset
    $ffmpeg_args.Add("-preset") > $null
    $ffmpeg_args.Add($gpu.preset) > $null
    
    # Video bitrate
    $ffmpeg_args.Add("-b:v") > $null
    $ffmpeg_args.Add([string]$compressionSettings.video_bitrate + "k") > $null
    
    # Max bitrate (1.5x target for VBV buffer)
    $maxBitrate = [math]::Floor($compressionSettings.video_bitrate * 1.5)
    $ffmpeg_args.Add("-maxrate") > $null
    $ffmpeg_args.Add([string]$maxBitrate + "k") > $null
    $ffmpeg_args.Add("-bufsize") > $null
    $ffmpeg_args.Add([string]$maxBitrate + "k") > $null
    
    # Frame rate
    if ($compressionSettings.target_fps -lt 60) {
        $ffmpeg_args.Add("-r") > $null
        $ffmpeg_args.Add($compressionSettings.target_fps) > $null
    }
    
    # Resolution scaling
    if ($gpu.scale_filter -eq "scale_cuda") {
        $ffmpeg_args.Add("-vf") > $null
        $ffmpeg_args.Add("$($gpu.scale_filter)=w=-2:h=$($compressionSettings.target_height)") > $null
    } else {
        $ffmpeg_args.Add("-vf") > $null
        $ffmpeg_args.Add("$($gpu.scale_filter)=-2:$($compressionSettings.target_height)") > $null
    }
    
    # GOP size (2 seconds worth of frames)
    $gopSize = [math]::Floor($compressionSettings.target_fps * 2)
    $ffmpeg_args.Add("-g") > $null
    $ffmpeg_args.Add($gopSize) > $null
    
    # Audio encoding options
    $ffmpeg_args.Add("-c:a") > $null
    $ffmpeg_args.Add("aac") > $null
    $ffmpeg_args.Add("-b:a") > $null
    $ffmpeg_args.Add([string]$compressionSettings.audio_bitrate + "k") > $null
    
    # Add extra encoder-specific parameters if they exist
    if ($gpu.extra_params) {
        foreach ($param in $gpu.extra_params) {
            $ffmpeg_args.Add($param) > $null
        }
    }
    
    # Output options
    $ffmpeg_args.Add("-movflags") > $null
    $ffmpeg_args.Add("+faststart") > $null    # Enable streaming-friendly output
    
    # Output file
    $ffmpeg_args.Add($outputFile) > $null
    
    return $ffmpeg_args
}

# Main execution block

try {
    # Verify requirements first
    if (-not (Test-Requirements)) {
        throw "Failed requirements check"
    }
    
    $startTime = Get-Date
    
    # Get input codec
    $inputCodec = Get-VideoCodec -inputFile $inputFile
    Write-Host "`nInput Video Codec: $inputCodec" -ForegroundColor Cyan
    
    # Get GPU encoder settings
    $gpu = Get-GPUEncoder -codec $inputCodec
    
    # Get video information
    $videoInfo = Get-VideoInfo -inputFile $inputFile
    
    Write-Host "`nInput Video Details:" -ForegroundColor Cyan
    Write-Host "Resolution: $($videoInfo.width)x$($videoInfo.height)"
    Write-Host "Framerate: $($videoInfo.fps) FPS"
    Write-Host "Duration: $($videoInfo.duration) seconds"
    
    # Calculate compression settings
    $compressionSettings = Get-CompressionSettings -videoInfo $videoInfo
    
    Write-Host "`nCompression Settings:" -ForegroundColor Cyan
    Write-Host "Target Resolution: $($compressionSettings.target_height)p"
    Write-Host "Target Framerate: $($compressionSettings.target_fps) FPS"
    Write-Host "Video Bitrate: $($compressionSettings.video_bitrate) kbps"
    Write-Host "Audio Bitrate: $($compressionSettings.audio_bitrate) kbps"
    Write-Host "Using encoder: $($gpu.encoder)`n"
    
    # Create output filename
    $output_file = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($inputFile),
        [System.IO.Path]::GetFileNameWithoutExtension($inputFile) + "_compressed.mp4"
    )
    
    # Build and execute FFmpeg commands, for first and second passes:
    
   # Build FFmpeg command
    $ffmpeg_args = BuildFFmpegCommand -gpu $gpu -inputFile $inputFile -outputFile $output_file `
    -compressionSettings $compressionSettings -inputCodec $inputCodec

    # First pass
    $firstpass_args = New-Object System.Collections.ArrayList
    $firstpass_args.AddRange($ffmpeg_args)

    # Remove the last element (output file)
    $firstpass_args.RemoveAt($firstpass_args.Count - 1)

    # Change pass number
    $index = $firstpass_args.IndexOf("-pass")
    if ($index -ge 0) {
        $firstpass_args[$index + 1] = "1"  # Set to pass 1
    }

    # Add format and null output for Windows
    $firstpass_args.Add("-f") > $null
    $firstpass_args.Add("null") > $null
    $firstpass_args.Add("nul") > $null  # Windows null device, lowercase without colon

    Write-Host "Running first pass..."
    & ffmpeg $firstpass_args

    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg first pass encoding failed with exit code $LASTEXITCODE"
    }
    # Second pass (using original ffmpeg_args which already has pass 2)
    Write-Host "Running second pass..."
    & ffmpeg $ffmpeg_args
    
    # Verify results
    $endTime = Get-Date
    $processingTime = ($endTime - $startTime).TotalSeconds
    
    $finalVideoInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,bit_rate -of json $output_file | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get final video information"
    }
    
    $finalBitrate = [math]::Round([int]$finalVideoInfo.streams[0].bit_rate / 1000)
    $finalFps = [math]::Round([decimal]($finalVideoInfo.streams[0].r_frame_rate -split '/')[0] / ($finalVideoInfo.streams[0].r_frame_rate -split '/')[1], 2)
    
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
        Write-Host "`nError: File size exceeds 10MB limit! Removing output file..." -ForegroundColor Red
        Remove-Item $output_file -ErrorAction SilentlyContinue
        throw "Final file size exceeds 10MB limit"
    }
}
catch {
    Write-Host "`nAn error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    Write-Host "`nPress Ctrl+C to exit..." -ForegroundColor Yellow
    while ($true) {
        Start-Sleep -Seconds 10000
    }
}