# This is a compression method that scales resolution and framerate with the goal of reducing file size while maintaining quality.
# Some notes:
# - This script requires FFmpeg to be installed and in your PATH.
# - The script will attempt to detect the video codec of the input file and choose the appropriate encoder. Default is H.264 due to it's widespread compatibility and compression efficiency.
# - The script will attempt to detect the GPU type and use hardware acceleration if available. If no compatible GPU is found, it will fall back to CPU encoding.
# - The script will calculate compression settings based on the target file size and original video properties.
# - The script will output a compressed video file with the same name as the input file, suffixed with "_compressed.mp4".
# - The script will display information about the original and final video files, including size, resolution, framerate, and bitrate.
# - If the final file size exceeds the target size, the script will delete the output file and display an error message.
# - The script will also display the time taken for the compression process.

param(
    [Parameter(Mandatory=$true)]
    [string]$inputFile,
   
    [Parameter(Mandatory=$false)]
    [int]$targetSizeMB = 10,  # Default to 10MB if not specified

    [Parameter(Mandatory=$false)]
    [int]$TrimStart = 0,  # NOT IN USE YET TODO: Default to 0 seconds if not specified

    [Parameter(Mandatory=$false)]
    [int]$TrimEnd = 0,  # NOT IN USE YET TODO: Default to 0 if not specified, if TrimEnd set to 0, the script will NOT crop and skip this step entirely

    [Parameter(Mandatory=$false)]
    [bool]$twoPassSet = $false,  # Set to true by default to enable two pass encoding

    [Parameter(Mandatory=$false)]
    [bool]$HardwareAccel = $true,  # NOT IN USE YET TODO Set to true by default to enable hardware acceleration

    [Parameter(Mandatory=$false)]
    [int]$QualitySetting = 6,  # NOT IN USE YET TODO Default to 6 if not specified

    [Parameter(Mandatory=$false)]
    [double]$FinalSizeSafetyRatio = 0.93  # NOT IN USE YET TODO This is the value that allows some extra space to ensure the output file stays under the specified target size Default to 0.93 if not specified, may need to be dropped for bigger input file sizes
)

#Keeping the window open in case of an error
if ($Host.Name -eq "ConsoleHost") {
    $host.UI.RawUI.WindowTitle = "Video Compression Tool"
    $ErrorActionPreference = "Stop"
    trap {
        Write-Host "`nAn error occurred:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

# Add window handling
if ($Host.Name -eq "Windows PowerShell ISE Host") {
    Write-Warning "Script is running in PowerShell ISE. Window closing prevention not needed."
} else {
    # Prevent the PowerShell window from closing
    $Host.UI.RawUI.WindowTitle = "Video Compression Tool"
    [Console]::TreatControlCAsInput = $true
}

# Function to handle script exit
function Show-ExitPrompt {
    Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

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

# Function to determine which video codec the source file uses, to determine if our script can handle it at all
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
        $codec = $codecInfo.Trim().ToLower()
        
        # Map codecs to our supported ones
        switch ($codec) {
            'prores' { return 'h264' }   # Convert ProRes to H.264
            'dnxhd' { return 'h264' }    # Convert DNxHD to H.264
            'mjpeg' { return 'h264' }    # Convert Motion JPEG to H.264
            'rawvideo' { return 'h264' } # Convert raw video to H.264
            'hevc' { return 'hevc' }     # HEVC/H.265
            'h265' { return 'hevc' }     # Alternative HEVC name
            default { return $codec }
        }
    }
    catch {
        Write-Host "Error detecting codec: $_" -ForegroundColor Red
        return 'h264' # Safe fallback
    }
}

# Helper function to detect GPU type with error handling
function Get-GPUType {
    try {
        # Check for GPUs using WMI first
        $gpus = Get-WmiObject -Query "SELECT * FROM Win32_VideoController"
        
        # Check for AMD GPU first
        $amd = $gpus | Where-Object { $_.Caption -like "*Radeon*" }
        if ($amd) {
            Write-Host "AMD GPU detected: $($amd.Caption)" -ForegroundColor DarkRed
            return 'amd'
        }
        
        # Then check for NVIDIA GPU
        $nvidia = $gpus | Where-Object { $_.Caption -like "*NVIDIA*" }
        if ($nvidia) {
            # Only try nvidia-smi if we actually found an NVIDIA GPU
            $nvidiaSmi = & nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Nvidia GPU Located: $($nvidiaSmi.Trim())" -ForegroundColor Green
                return 'nvidia'
            }
        }
        
        # Finally check for Intel GPU
        $intel = $gpus | Where-Object { $_.Caption -like "*Intel*" }
        if ($intel) {
            Write-Host "Intel GPU detected!" -ForegroundColor Blue
            return 'intel'
        }
    }
    catch {
        Write-Host "Error during GPU detection: $_" -ForegroundColor Red
    }
    
    Write-Host "No compatible GPU detected, falling back to CPU encoding" -ForegroundColor Yellow
    return 'cpu' # Safe fallback
}

function Get-CPUEncoder {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('h264','hevc','av1')]
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
        'hevc' {
            Write-Host "Using CPU encoder (libx265)" -ForegroundColor Yellow
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "hevc"
                encoder = "libx265"
                scale_filter = "scale"
                preset = "medium"
                extra_params = @("-x265-params", "log-level=error")
                valid = $true
            }
        }
        'av1' {
            Write-Host "Using CPU-based AV1 encoder (libaom-av1)" -ForegroundColor Yellow
            return @{
                hwaccel = $null
                hwaccel_output_format = $null
                decoder = "av1"
                encoder = "libaom-av1"
                scale_filter = "scale"
                preset = "5"
                extra_params = @(
                    "-strict", "experimental",
                    "-cpu-used", "4",
                    "-row-mt", "1",
                    "-tile-columns", "2",
                    "-tile-rows", "1",
                    "-threads", "8"
                )
                valid = $true
            }
        }
    }
}

function Get-GPUEncoder {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('h264','hevc','av1')]
        [string]$codec
    )
    
    try {
        $gpuType = Get-GPUType
        
        switch ($gpuType) {
            'nvidia' {
                $encoderConfig = switch ($codec) {
                    'h264' {
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
                    }
                    'hevc' {
                        Write-Host "Using NVENC encoder (hevc_nvenc)" -ForegroundColor Green
                        @{
                            hwaccel = "cuda"
                            hwaccel_output_format = "cuda"
                            decoder = "hevc_cuvid"
                            encoder = "hevc_nvenc"
                            scale_filter = "scale_cuda"
                            preset = "p1"
                            valid = $true
                        }
                    }
                    'av1' {
                        $nvidia = & nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>$null
                        if ($nvidia -like "*RTX 40*") {
                            Write-Host "Using NVENC AV1 encoder (av1_nvenc)" -ForegroundColor Green
                            @{
                                hwaccel = "cuda"
                                hwaccel_output_format = "cuda"
                                decoder = "av1_cuvid"
                                encoder = "av1_nvenc"
                                scale_filter = "scale_cuda"
                                preset = "p4"
                                extra_params = @("-rc-lookahead", "32")
                                valid = $true
                            }
                        }
                        else {
                            Get-CPUEncoder -codec $codec
                        }
                    }
                }
                break
            }
            'amd' {
                $encoderConfig = switch ($codec) {
                    'h264' {
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
                    }
                    'hevc' {
                        Write-Host "Using AMF encoder (hevc_amf)" -ForegroundColor Green
                        @{
                            hwaccel = "d3d11va"
                            hwaccel_output_format = "nv12"
                            decoder = "hevc"
                            encoder = "hevc_amf"
                            scale_filter = "scale"
                            preset = "quality"
                            valid = $true
                        }
                    }
                    'av1' {
                        $amdGpu = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Radeon*" }
                        if ($amdGpu.Caption -match "RX\s+7\d{3}|RX\s*7\d{3}\s*XT") {
                            Write-Host "Using AMF AV1 encoder (av1_amf)" -ForegroundColor Green
                            @{
                                hwaccel = "d3d11va"
                                hwaccel_output_format = "nv12"
                                decoder = "av1"
                                encoder = "av1_amf"
                                scale_filter = "scale"
                                preset = "quality"
                                valid = $true
                            }
                        }
                        else {
                            Get-CPUEncoder -codec $codec
                        }
                    }
                }
                break
            }
            'intel' {
                $encoderConfig = switch ($codec) {
                    'h264' {
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
                    }
                    'hevc' {
                        Write-Host "Using QuickSync encoder (hevc_qsv)" -ForegroundColor Green
                        @{
                            hwaccel = "qsv"
                            hwaccel_output_format = "nv12"
                            decoder = "hevc_qsv"
                            encoder = "hevc_qsv"
                            scale_filter = "scale"
                            preset = "veryslow"
                            valid = $true
                        }
                    }
                    'av1' {
                        $intel = Get-WmiObject -Query "SELECT * FROM Win32_VideoController" | Where-Object { $_.Caption -like "*Arc*" }
                        if ($intel) {
                            Write-Host "Using QuickSync AV1 encoder (av1_qsv)" -ForegroundColor Green
                            @{
                                hwaccel = "qsv"
                                hwaccel_output_format = "nv12"
                                decoder = "av1_qsv"
                                encoder = "av1_qsv"
                                scale_filter = "scale"
                                preset = "veryslow"
                                valid = $true
                            }
                        }
                        else {
                            Get-CPUEncoder -codec $codec
                        }
                    }
                }
                break
            }
            default {
                $encoderConfig = Get-CPUEncoder -codec $codec
                break
            }
        }
        
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

function Get-CompressionThresholds {
    param(
        [Parameter(Mandatory=$true)]
        [double]$compressionRatio
    )
    
    # Base settings
    $settings = @{
        resolution = $null  # null means keep original
        fps = $null        # null means keep original
        quality_preset = "medium"
    }
    
    # Apply thresholds based on compression ratio
    switch ($compressionRatio) {
        {$_ -le 1} {
            Write-Host "Compression ratio <= 1, maintaining original quality" -ForegroundColor Green
            return $settings
        }
        {$_ -le 3} {
            Write-Host "Low compression ratio ($compressionRatio), applying basic compression" -ForegroundColor Green
            $settings.quality_preset = "medium"
            return $settings
        }
        {$_ -le 6} {
            Write-Host "Medium compression ratio ($compressionRatio), scaling to 1080p" -ForegroundColor Yellow
            $settings.resolution = 1080
            return $settings
        }
        {$_ -le 10} {
            Write-Host "High compression ratio ($compressionRatio), scaling to 1080p/30fps" -ForegroundColor Yellow
            $settings.resolution = 1080
            $settings.fps = 30
            return $settings
        }
        {$_ -le 15} {
            Write-Host "Very high compression ratio ($compressionRatio), scaling to 720p/30fps" -ForegroundColor Red
            $settings.resolution = 720
            $settings.fps = 30
            return $settings
        }
        {$_ -le 20} {
            Write-Host "Extreme compression ratio ($compressionRatio), scaling to 720p/24fps" -ForegroundColor Red
            $settings.resolution = 720
            $settings.fps = 24
            return $settings
        }
        default {
            Write-Host "Maximum compression ratio ($compressionRatio), scaling to 480p/24fps" -ForegroundColor Red
            $settings.resolution = 480
            $settings.fps = 24
            return $settings
        }
    }
}


function Get-CompressionSettings {
    param(
        $videoInfo,
        [int]$targetSizeMB
    )
   
    try {
        # Calculate original size in MB
        $originalSizeMB = (Get-Item $inputFile).Length/1MB
        $compressionRatio = $originalSizeMB / $targetSizeMB
       
        Write-Host "`nCompression Analysis:" -ForegroundColor Cyan
        Write-Host "Original Size: $($originalSizeMB.ToString('0.00')) MB"
        Write-Host "Target Size: $targetSizeMB MB"
        Write-Host "Compression Ratio Needed: $($compressionRatio.ToString('0.00')):1"
       
        # Get threshold-based settings
        $thresholdSettings = Get-CompressionThresholds -compressionRatio $compressionRatio
       
        # Calculate target resolution and fps
        $target_height = if ($null -ne $thresholdSettings.resolution) { [int]$thresholdSettings.resolution } else { [int]$videoInfo.height }
        $target_fps = if ($null -ne $thresholdSettings.fps) { [int]$thresholdSettings.fps } else { [int]$videoInfo.fps }
       
        # Get original audio bitrate
        try {
            $audioStream = & ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $inputFile
            $originalAudioBitrate = if ($null -ne $audioStream -and $audioStream -ne '') {
                [Math]::Floor([int]$audioStream / 1000)  # Convert to kbps
            } else {
                64  # Default if can't detect
            }
        } catch {
            $originalAudioBitrate = 64  # Default if error
        }

        # Determine audio bitrate based on compression ratio
        [int]$audio_bitrate = if ($compressionRatio -le 20) {
            # Keep original bitrate but ensure it's at least 48kbps
            [Math]::Max(48, $originalAudioBitrate)
        }
        elseif ($compressionRatio -le 30) {
            32
        }
        elseif ($compressionRatio -le 40) {
            24
        }
        else {
            16
        }
       
        # Calculate video bitrate with more explicit steps
        [double]$targetSizeBitsDouble = [double]$targetSizeMB * 8.0 * 1024.0 * 1024.0 * 0.92
        [double]$durationDouble = [double]$videoInfo.duration
        [double]$bitsPerSecondDouble = $targetSizeBitsDouble / $durationDouble
        [int]$totalBitrateKbps = [Math]::Floor($bitsPerSecondDouble / 1000.0)
        [int]$video_bitrate = [Math]::Max(100, $totalBitrateKbps - $audio_bitrate)
       
        Write-Host "`nCompression Settings:" -ForegroundColor Cyan
        Write-Host "Target Resolution: $($target_height)p"
        Write-Host "Target Framerate: $target_fps FPS"
        Write-Host "Video Bitrate: $video_bitrate kbps"
        Write-Host "Audio Bitrate: $audio_bitrate kbps (Original: $originalAudioBitrate kbps)"
       
        return @{
            target_fps = $target_fps
            target_height = $target_height
            video_bitrate = $video_bitrate
            audio_bitrate = $audio_bitrate
            quality_preset = $thresholdSettings.quality_preset
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
    $ffmpeg_args.Add("-y") > $null
    $ffmpeg_args.Add("-hide_banner") > $null
    
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
    
    # Encoding preset
    $ffmpeg_args.Add("-preset") > $null
    $ffmpeg_args.Add($gpu.preset) > $null
    
    # Video bitrate
    $safe_bitrate = [Math]::Max(100, $compressionSettings.video_bitrate)
    $ffmpeg_args.Add("-b:v") > $null
    $ffmpeg_args.Add([string]$safe_bitrate + "k") > $null
    
    # Max bitrate (1.5x target for VBV buffer)
    $maxBitrate = [Math]::Max(150, [math]::Floor($safe_bitrate * 1.5))
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
    $ffmpeg_args.Add("+faststart") > $null
    
    return $ffmpeg_args
}

function RunFFmpegCommand {
    param(
        [Parameter(Mandatory=$true)]
        [System.Collections.ArrayList]$ffmpeg_args,
        [Parameter(Mandatory=$true)]
        [bool]$twoPassSet,
        [Parameter(Mandatory=$true)]
        [string]$outputFile
    )
    
    if ($twoPassSet) {
        Write-Host "Two-pass encoding enabled" -ForegroundColor Green
        Write-Host "Running first pass..." -ForegroundColor Cyan
        
        # Add first pass specific parameters
        $ffmpeg_args.Add("-pass") > $null
        $ffmpeg_args.Add("1") > $null
        $ffmpeg_args.Add("-f") > $null
        $ffmpeg_args.Add("null") > $null
        $ffmpeg_args.Add("nul") > $null
        
        & ffmpeg $ffmpeg_args
        
        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg first pass encoding failed with exit code $LASTEXITCODE"
        }
        
        # Modify for second pass
        $ffmpeg_args.RemoveRange($ffmpeg_args.Count - 3, 3)  # Remove null output
        $passIndex = $ffmpeg_args.IndexOf("-pass")
        $ffmpeg_args[$passIndex + 1] = "2"
        $ffmpeg_args.Add($outputFile) > $null
        
        Write-Host "Running second pass..." -ForegroundColor Cyan
    } else {
        Write-Host "Single-pass encoding mode..." -ForegroundColor Cyan
        $ffmpeg_args.Add($outputFile) > $null
    }
    
    & ffmpeg $ffmpeg_args
    
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg encoding failed with exit code $LASTEXITCODE"
    }
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
    $compressionSettings = Get-CompressionSettings -videoInfo $videoInfo -targetSizeMB $targetSizeMB
    
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
    
    # Build and run FFmpeg command
    $ffmpeg_args = BuildFFmpegCommand -gpu $gpu -inputFile $inputFile -outputFile $output_file `
        -compressionSettings $compressionSettings -inputCodec $inputCodec
    
    RunFFmpegCommand -ffmpeg_args $ffmpeg_args -twoPassSet $twoPassSet -outputFile $output_file
    
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

    if ($final_size_mb -gt $targetSizeMB) {
        Write-Host "`nError: File size exceeds $targetSizeMB MB limit! Removing output file..." -ForegroundColor Red
        Remove-Item $output_file -ErrorAction SilentlyContinue
        throw "Final file size exceeds $targetSizeMB MB limit"
    }
} catch {
    Write-Host "`nError Details:" -ForegroundColor Red
    Write-Host "----------------" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "Line Number: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Command: $($_.InvocationInfo.MyCommand)" -ForegroundColor Red
    Write-Host "----------------" -ForegroundColor Red
    
    Remove-Item "$env:TEMP\ffmpeg2pass*" -ErrorAction SilentlyContinue
    $exitCode = 1
} finally {
    if (Test-Path "ffmpeg2pass-*.log") {
        Remove-Item "ffmpeg2pass-*.log" -ErrorAction SilentlyContinue
    }
    
    if (Test-Path "ffmpeg2pass-*.log.mbtree") {
        Remove-Item "ffmpeg2pass-*.log.mbtree" -ErrorAction SilentlyContinue
    }
    
    Show-ExitPrompt
    exit $exitCode
}