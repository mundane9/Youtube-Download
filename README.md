# yt-batch-downloader

Download YouTube videos and playlists on Windows without typing commands. Uses yt-dlp.

## Setup

Download `Start.bat` and `yt-batch-downloader.ps1` and keep them in the same folder.

You need winget (the Windows package manager). It comes with Windows 10 and 11, but to check, open PowerShell and run:

```
winget --version
```

If you get an error, install **App Installer** from the Microsoft Store, then try again. The script uses winget to install yt-dlp and FFmpeg for you.

## Use

1. Double-click `Start.bat`
2. Pick the folder to save to
3. Paste links, or pick a .txt file with one link per line
4. Pick a format: 1080p / 720p / 480p MP4, best quality, MP3 or M4A

The first run installs yt-dlp and FFmpeg. If it says it can't find them afterwards, close it and run it again.

Videos you already have get skipped, so running the same links again only downloads new ones.

Needs Windows 10 or 11 with winget.
