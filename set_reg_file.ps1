# Get the full path of compress_video.ps1
$scriptPath = (Get-Item "compress_video.ps1").FullName

# Escape backslashes for .reg file format
$escapedPath = $scriptPath.Replace("\", "\\")

# Read the content of add_compress.reg
$regContent = Get-Content "add_compress.reg" -Raw

# Create the pattern to match the last line with any path
$pattern = '@="powershell\.exe -ExecutionPolicy Bypass -File \\".*\\" \\"%1\\""$'

# Create the replacement line with the new path
$replacement = "@=`"powershell.exe -ExecutionPolicy Bypass -File \`"$escapedPath\`" \`"%1\`"`""

# Replace the line and write back to the file
$regContent -replace $pattern, $replacement | Set-Content "add_compress.reg" -Force