# to execute this command, please run this in a powershell admin window:
# powershell -ExecutionPolicy Bypass -File PATH_TO_DIRECTORY\remove_compress_menu.ps1

Write-Host "Starting registry cleanup..."

# Try to remove command key first
$result1 = cmd /c 'reg delete "HKLM\SOFTWARE\Classes\*\shell\CompressTo10MB\command" /f'
Write-Host $result1

# Then remove main key
$result2 = cmd /c 'reg delete "HKLM\SOFTWARE\Classes\*\shell\CompressTo10MB" /f'
Write-Host $result2

# Verify if keys still exist
$check1 = cmd /c 'reg query "HKLM\SOFTWARE\Classes\*\shell\CompressTo10MB\command" 2>nul'
$check2 = cmd /c 'reg query "HKLM\SOFTWARE\Classes\*\shell\CompressTo10MB" 2>nul'

if ($check1 -or $check2) {
    Write-Host "Warning: Some registry entries may still exist"
} else {
    Write-Host "Registry entries removed successfully"
}

Write-Host "Done."