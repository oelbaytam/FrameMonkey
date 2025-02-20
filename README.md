# FrameMonkey
A Windows context menu application designed to quickly crop, compress and use local GPU hardware acceleration to encode videos.

A PowerShell script is used to make FFMPEG calls to handle compression, and PyQt6 along with qt_material is used for the GUI interface.

In its current state, the context menu can only handle compressing a file to 10MB or less, while the full application is capable of trimming and video playback.

### Why 10MB
FrameMonkey is designed to compress video to 10MB or under in h264 so that people can share small video files over Discord with their friends and be viewable as a chat-embedded video.

### What is currently working?
FrameMonkey currently only accepts videos that are avi, mov, mp4, and mkv and so far, can only decode av1 and h264, however, it is still functional and in a useable state.

FrameMonkey also only is working on Windows, and we are unsure when we will update for Linux and Mac support but it is in the works.

# Installation
FrameMonkey depends on FFmpeg for compression so it is important to have FFmpeg on your device as well as adding it to the path, this is achievable by using Chocolatey or winget to install it.

FrameMonkey also requires Python and the Python libraries PyQt6 and qt_material.

### Installing Chocolatey and dependencies.
Run the following commands in an administrative terminal to install Chocolatey, python, and FFmpeg respectively. \
\
`Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))`

`choco install python`

`choco install FFmpeg`

### Installing Python libraries.
Open an administrative terminal and run the following commands to install PyQt6 and qt_material.\
\
`pip install PyQt6`

`pip install qt_material`

### Adding FrameMonkey to the context menu.
- To add FrameMonkey to the context menu first make sure the files are in the desired location. 
- Run the set_reg_file PowerShell script to update the add_compress registry file. 
- Run the add_compress registry file to allow it to be added to the context menu.
\

# How to access the GUI
For now, the only way to access the GUI is by finding the FrameMonkey/GUI/main.py file and opening it with Python manually, adding the GUI to the context menu is a planned feature for the near future.


### ⭐If you like the project, please consider starring it to give it more traction! ⭐

