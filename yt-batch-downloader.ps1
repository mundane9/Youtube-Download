#Requires -Version 5.1
# yt-batch-downloader - simple yt-dlp wrapper for Windows

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$Host.UI.RawUI.WindowTitle = "YT Batch Downloader"

function Write-Header([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function New-TopForm {
    # keeps dialogs in front of the console
    $f = New-Object System.Windows.Forms.Form
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    return $f
}

function Install-Dependencies {
    Write-Header "Checking requirements"

    if (-not (Test-Command 'winget')) {
        Write-Host "winget was not found." -ForegroundColor Red
        Write-Host "Install 'App Installer' from the Microsoft Store, then run this again."
        Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1"
        Read-Host "Press Enter to exit"
        exit 1
    }

    $packages = @(
        @{ Cmd = 'yt-dlp'; Id = 'yt-dlp.yt-dlp'; Name = 'yt-dlp' },
        @{ Cmd = 'ffmpeg'; Id = 'Gyan.FFmpeg';   Name = 'FFmpeg' }
    )

    foreach ($p in $packages) {
        if (Test-Command $p.Cmd) {
            Write-Host "[ok] $($p.Name) found" -ForegroundColor Green
            continue
        }
        Write-Host "Installing $($p.Name)..." -ForegroundColor Yellow
        winget install --id $p.Id -e --accept-source-agreements --accept-package-agreements
        Update-SessionPath
        if (Test-Command $p.Cmd) {
            Write-Host "[ok] $($p.Name) installed" -ForegroundColor Green
        } else {
            Write-Host "$($p.Name) was installed but Windows hasn't picked it up yet." -ForegroundColor Red
            Write-Host "Close this window and run the script again."
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    Write-Host "Checking for yt-dlp updates..."
    winget upgrade --id yt-dlp.yt-dlp -e --silent --accept-source-agreements --accept-package-agreements *> $null
    Update-SessionPath
}

function Select-Folder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose where to save the downloads"
    $dlg.ShowNewFolderButton = $true
    $owner = New-TopForm
    try {
        if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dlg.SelectedPath
        }
        return $null
    } finally { $owner.Dispose() }
}

function Read-PastedLinks {
    Write-Host ""
    Write-Host "Paste links (videos or playlists). One per line, or several separated by spaces."
    Write-Host "Press Enter on an empty line when you're done." -ForegroundColor DarkGray
    $links = @()
    while ($true) {
        $line = Read-Host "link"
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $links += ($line -split '\s+' | Where-Object { $_ })
    }
    return $links
}

function Read-LinkFile {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = "Select a .txt file with one link per line"
    $dlg.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $owner = New-TopForm
    try {
        if ($dlg.ShowDialog($owner) -ne [System.Windows.Forms.DialogResult]::OK) { return @() }
        Write-Host "Using list: $($dlg.FileName)"
        return Get-Content -LiteralPath $dlg.FileName |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
    } finally { $owner.Dispose() }
}

function Read-Choice([string]$Prompt, [string[]]$Valid, [string]$Default) {
    while ($true) {
        $c = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($c)) { return $Default }
        $c = $c.Trim().ToLower()
        if ($Valid -contains $c) { return $c }
        Write-Host "Please enter one of: $($Valid -join ', ')" -ForegroundColor Yellow
    }
}

Install-Dependencies

Write-Header "Destination folder"
$dest = Select-Folder
if (-not $dest) {
    Write-Host "No folder selected. Exiting."
    Read-Host "Press Enter to exit"
    exit 0
}
Write-Host "Saving to: $dest" -ForegroundColor Green

do {
    Write-Header "Links"
    Write-Host "  1) Paste links"
    Write-Host "  2) Pick a .txt file with links"
    $src = Read-Choice "Choose" @('1','2') '1'
    if ($src -eq '1') { $raw = @(Read-PastedLinks) } else { $raw = @(Read-LinkFile) }

    $links = @($raw | Where-Object { $_ -match '^https?://' } | Select-Object -Unique)
    $bad   = @($raw | Where-Object { $_ -notmatch '^https?://' })
    foreach ($b in $bad) { Write-Host "Skipping (not a link): $b" -ForegroundColor Yellow }

    if ($links.Count -eq 0) {
        Write-Host "No valid links found." -ForegroundColor Red
    } else {
        Write-Host "$($links.Count) link(s) queued." -ForegroundColor Green

        Write-Header "Format"
        Write-Host "  Video (MP4, H.264 - plays on Raspberry Pi, TVs, phones)"
        Write-Host "    1) 1080p"
        Write-Host "    2) 720p  (smaller)"
        Write-Host "    3) 480p  (smallest)"
        Write-Host "  Video (best available, up to 4K, MKV - big files, not Pi-friendly)"
        Write-Host "    4) Best quality"
        Write-Host "  Audio only"
        Write-Host "    5) MP3 (works everywhere)"
        Write-Host "    6) M4A (original quality, no conversion)"
        $fmt = Read-Choice "Choose" @('1','2','3','4','5','6') '1'

        $sub = Read-Choice "Put each playlist in its own subfolder? (y/n)" @('y','n') 'n'
        if ($sub -eq 'y') {
            $template = '%(playlist_title|Singles)s/%(title)s [%(id)s].%(ext)s'
        } else {
            $template = '%(title)s [%(id)s].%(ext)s'
        }

        $h264 = 'vcodec:h264,acodec:m4a'
        switch ($fmt) {
            '1' { $fmtArgs = @('-S', "res:1080,$h264", '--merge-output-format', 'mp4'); $kind = 'video' }
            '2' { $fmtArgs = @('-S', "res:720,$h264",  '--merge-output-format', 'mp4'); $kind = 'video' }
            '3' { $fmtArgs = @('-S', "res:480,$h264",  '--merge-output-format', 'mp4'); $kind = 'video' }
            '4' { $fmtArgs = @('-f', 'bv*+ba/b', '--merge-output-format', 'mkv');      $kind = 'video' }
            '5' { $fmtArgs = @('-x', '--audio-format', 'mp3', '--audio-quality', '0', '--embed-thumbnail'); $kind = 'audio' }
            '6' { $fmtArgs = @('-f', 'ba[ext=m4a]/ba', '-x', '--audio-format', 'm4a', '--embed-thumbnail'); $kind = 'audio' }
        }

        # separate archive for audio/video
        $archive = Join-Path $dest ".yt-archive-$kind.txt"

        $batch = Join-Path $env:TEMP ("yt-links-" + [guid]::NewGuid().ToString() + ".txt")
        [System.IO.File]::WriteAllLines($batch, [string[]]$links)

        $ytArgs = @(
            '--ignore-errors',
            '--no-overwrites',
            '--continue',
            '--embed-metadata',
            '--download-archive', $archive,
            '-P', $dest,
            '-o', $template,
            '--batch-file', $batch
        ) + $fmtArgs

        Write-Header "Downloading"
        & yt-dlp @ytArgs
        $code = $LASTEXITCODE
        Remove-Item -LiteralPath $batch -ErrorAction SilentlyContinue

        Write-Host ""
        if ($code -eq 0) {
            Write-Host "All done!" -ForegroundColor Green
        } else {
            Write-Host "Finished, but some items failed (see messages above). Run again to retry them." -ForegroundColor Yellow
        }
    }

    $again = Read-Choice "Download more into the same folder? (y/n)" @('y','n') 'n'
} while ($again -eq 'y')

$open = Read-Choice "Open the folder now? (y/n)" @('y','n') 'y'
if ($open -eq 'y') { Start-Process explorer.exe $dest }
