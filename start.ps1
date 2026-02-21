<#
.SYNOPSIS
    Launcher für Foto_Viewer_V2

.DESCRIPTION
    Startet HTTP Server mit Hybrid PowerShell 5.1/7+ Support.
    Phase 4.1: Tools-Menü für .thumbs Verwaltung.

.PARAMETER Port
    Server Port (Default aus config.json)

.EXAMPLE
    .\start.ps1
    .\start.ps1 -Port 9999

.NOTES
    Autor: Herbert Schrotter
    Version: 0.4.7
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [int]$Port
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-Root ermitteln
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Libs laden
. (Join-Path $ScriptRoot "Lib\Lib_Config.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Http.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Dialogs.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Scanner.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_State.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_FileSystem.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_FFmpeg.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Tools.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_UI_Template.ps1")

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Foto Viewer V2 - Phase 4.1" -ForegroundColor White
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Config laden
try {
    $config = Get-Config
    Write-Host "✓ Config geladen" -ForegroundColor Green
} catch {
    Write-Error "Config konnte nicht geladen werden: $($_.Exception.Message)"
    return
}

# Port aus Config oder Parameter
if (-not $Port) {
    $Port = $config.Server.Port
}

# PowerShell Version Info
$psInfo = Get-PowerShellVersionInfo
Write-Host "✓ PowerShell: $($psInfo.DisplayName)" -ForegroundColor Green

if ($psInfo.IsPS7) {
    Write-Host "  → Parallel-Processing verfügbar" -ForegroundColor DarkGray
} else {
    Write-Host "  → Sequenziell (für Parallel: PS7+ installieren)" -ForegroundColor DarkGray
}

Write-Host ""

# FFmpeg Check
$script:FFmpegPath = Test-FFmpegInstalled -ScriptRoot $ScriptRoot
if ($script:FFmpegPath) {
    Write-Host "✓ FFmpeg gefunden: $script:FFmpegPath" -ForegroundColor Green
} else {
    Write-Warning "FFmpeg nicht gefunden - Video-Thumbnails deaktiviert"
}

Write-Host ""

# State laden
$script:State = Get-State
Write-Host "✓ State geladen" -ForegroundColor Green

# Root-Ordner wählen (wenn nicht im State)
if ([string]::IsNullOrWhiteSpace($script:State.RootPath) -or 
    -not (Test-Path -LiteralPath $script:State.RootPath)) {
    
    Write-Host ""
    Write-Host "Bitte wähle einen Root-Ordner..." -ForegroundColor Yellow
    
    $rootPath = Show-FolderDialog -Title "Root-Ordner für Foto-Gallery wählen" -InitialDirectory $script:State.RootPath
    
    if (-not $rootPath) {
        Write-Warning "Kein Ordner gewählt. Beende."
        return
    }
    
    $script:State.RootPath = $rootPath
    Write-Host "✓ Root gewählt: $rootPath" -ForegroundColor Green
} else {
    Write-Host "✓ Root aus State: $($script:State.RootPath)" -ForegroundColor Green
}

# Thumbnail-Cache Verzeichnis
$script:ThumbsDir = Join-Path $script:State.RootPath ".thumbs"
if (-not (Test-Path -LiteralPath $script:ThumbsDir)) {
    New-Item -Path $script:ThumbsDir -ItemType Directory -Force | Out-Null
    Write-Host "✓ Thumbnail-Cache erstellt: $script:ThumbsDir" -ForegroundColor Green
}

# Medien-Extensions aus Config
$mediaExtensions = $config.Media.ImageExtensions + $config.Media.VideoExtensions

# Ordner scannen
Write-Host ""
Write-Host "Scanne Ordner..." -ForegroundColor Cyan
try {
    $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtensions)
    
    $totalMedia = ($script:State.Folders | Measure-Object -Property MediaCount -Sum).Sum
    Write-Host "✓ Gefunden: $($script:State.Folders.Count) Ordner mit $totalMedia Medien" -ForegroundColor Green
    
    # State speichern
    Save-State -State $script:State
    
} catch {
    Write-Error "Scan fehlgeschlagen: $($_.Exception.Message)"
    return
}

Write-Host ""

# HttpListener starten
try {
    $listener = Start-HttpListener -Port $Port -Hostname $config.Server.Host
    Write-Host "✓ Server läuft auf: http://$($config.Server.Host):$Port" -ForegroundColor Green
} catch {
    Write-Error "Server-Start fehlgeschlagen: $($_.Exception.Message)"
    return
}

# Browser öffnen (wenn aktiviert)
if ($config.Server.AutoOpenBrowser) {
    try {
        Start-Process "http://$($config.Server.Host):$Port"
        Write-Host "✓ Browser geöffnet" -ForegroundColor Green
    } catch {
        Write-Warning "Browser konnte nicht automatisch geöffnet werden"
    }
}

Write-Host ""
Write-Host "Drücke Ctrl+C zum Beenden" -ForegroundColor Yellow
Write-Host ""

# Server-Loop
$ServerRunning = $true

try {
    while ($listener.IsListening -and $ServerRunning) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $path = $req.Url.AbsolutePath.ToLowerInvariant()
        
        try {
            # Route: / (Index)
            if ($path -eq "/" -and $req.HttpMethod -eq "GET") {
                
                # Ordner-Liste generieren mit JSON-Daten
                $folderListHtml = ""
                if ($script:State.Folders.Count -eq 0) {
                    $folderListHtml = "<div style='text-align:center;padding:40px;color:#718096;'>Keine Ordner mit Medien gefunden</div>"
                } else {
                    $folderRows = foreach ($folder in $script:State.Folders) {
                        $pathDisplay = if ($folder.RelativePath -eq ".") { "Root" } else { $folder.RelativePath }
                        $filesJson = ($folder.Files | ConvertTo-Json -Compress).Replace('"', '&quot;')
                        $relativePath = $folder.RelativePath.Replace('\', '/').Replace('"', '&quot;')
                        
                        @"
                        <div class="folder-card" data-path="$relativePath" data-files="$filesJson">
                            <div class="folder-header" onclick="toggleFolder(this)">
                                <span class="folder-icon">📁</span>
                                <span class="folder-name">$pathDisplay</span>
                                <span class="folder-count">$($folder.MediaCount) Medien</span>
                                <span class="toggle-icon">▼</span>
                            </div>
                            <div class="media-grid" style="display: none;"></div>
                        </div>
"@
                    }
                    $folderListHtml = $folderRows -join "`n"
                }
                
                # HTML aus Templates generieren
                $html = Get-IndexHTML -RootPath $script:State.RootPath -FolderCards $folderListHtml -Config $config
                
                
                Send-ResponseHtml -Response $res -Html $html
                continue
            }
            
            # Route: /changeroot
            if ($path -eq "/changeroot" -and $req.HttpMethod -eq "POST") {
                $newRoot = Show-FolderDialog -Title "Neuen Root-Ordner wählen" -InitialDirectory $script:State.RootPath
                if (-not $newRoot) {
                    $json = @{ cancelled = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                    continue
                }
                if (-not (Test-Path -LiteralPath $newRoot -PathType Container)) {
                    $json = @{ error = "Ordner existiert nicht" } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                    continue
                }
                $script:State.RootPath = $newRoot
                $script:ThumbsDir = Join-Path $script:State.RootPath ".thumbs"
                if (-not (Test-Path -LiteralPath $script:ThumbsDir)) {
                    New-Item -Path $script:ThumbsDir -ItemType Directory -Force | Out-Null
                }
                try {
                    $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtensions)
                    Save-State -State $script:State
                    $json = @{ ok = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/cache-stats
            if ($path -eq "/tools/cache-stats" -and $req.HttpMethod -eq "GET") {
                try {
                    $stats = Get-ThumbsCacheStats -RootPath $script:State.RootPath
                    $json = @{
                        success = $true
                        data = @{
                            ThumbsDirectories = $stats.ThumbsDirectories
                            ThumbnailFiles = $stats.ThumbnailFiles
                            TotalSize = $stats.TotalSize
                            TotalSizeFormatted = $stats.TotalSizeFormatted
                        }
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/list-thumbs
            if ($path -eq "/tools/list-thumbs" -and $req.HttpMethod -eq "GET") {
                try {
                    $list = Get-ThumbsDirectoriesList -RootPath $script:State.RootPath
                    $json = @{
                        success = $true
                        data = @($list | ForEach-Object {
                            @{
                                Path = $_.Path
                                RelativePath = $_.RelativePath
                                FileCount = $_.FileCount
                                Size = $_.Size
                                SizeFormatted = $_.SizeFormatted
                            }
                        })
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/delete-selected
            if ($path -eq "/tools/delete-selected" -and $req.HttpMethod -eq "POST") {
                try {
                    $reader = [System.IO.StreamReader]::new($req.InputStream)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    $data = $body | ConvertFrom-Json
                    $paths = $data.paths
                    if (-not $paths -or $paths.Count -eq 0) {
                        $json = @{ success = $false; error = "Keine Pfade" } | ConvertTo-Json -Compress
                        Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                        continue
                    }
                    $result = Remove-SelectedThumbsDirectories -Paths $paths
                    $json = @{
                        success = $true
                        data = @{
                            DeletedCount = $result.DeletedCount
                            DeletedSize = $result.DeletedSize
                        }
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/delete-all-thumbs
            if ($path -eq "/tools/delete-all-thumbs" -and $req.HttpMethod -eq "POST") {
                try {
                    $result = Remove-AllThumbsDirectories -RootPath $script:State.RootPath
                    $json = @{
                        success = $true
                        data = @{
                            DeletedCount = $result.DeletedCount
                            DeletedSize = $result.DeletedSize
                        }
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /settings/get
            if ($path -eq "/settings/get" -and $req.HttpMethod -eq "GET") {
                try {
                    $configPath = Join-Path $ScriptRoot "config.json"
                    $configJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                    Send-ResponseText -Response $res -Text $configJson -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /settings/save
            if ($path -eq "/settings/save" -and $req.HttpMethod -eq "POST") {
                try {
                    $reader = [System.IO.StreamReader]::new($req.InputStream)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $newSettings = $body | ConvertFrom-Json
                    $configPath = Join-Path $ScriptRoot "config.json"
                    $currentConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                    
                    $currentConfig.Server.Port = $newSettings.Server.Port
                    $currentConfig.Server.Host = $newSettings.Server.Host
                    $currentConfig.Server.AutoOpenBrowser = $newSettings.Server.AutoOpenBrowser
                    
                    $currentConfig.Media.ImageExtensions = $newSettings.Media.ImageExtensions
                    $currentConfig.Media.VideoExtensions = $newSettings.Media.VideoExtensions
                    
                    $currentConfig.Video.ThumbnailQuality = $newSettings.Video.ThumbnailQuality
                    $currentConfig.Video.EnableAutoConversion = $newSettings.Video.EnableAutoConversion
                    $currentConfig.Video.UseHLS = $newSettings.Video.UseHLS
                    $currentConfig.Video.HLSSegmentDuration = $newSettings.Video.HLSSegmentDuration
                    $currentConfig.Video.PreferredCodec = $newSettings.Video.PreferredCodec
                    $currentConfig.Video.ConversionPreset = $newSettings.Video.ConversionPreset
                    $currentConfig.Video.ThumbnailCount = $newSettings.Video.ThumbnailCount
                    $currentConfig.Video.ThumbnailFPS = $newSettings.Video.ThumbnailFPS
                    $currentConfig.Video.PreviewAsGIF = $newSettings.Video.PreviewAsGIF
                    $currentConfig.Video.GIFDuration = $newSettings.Video.GIFDuration
                    $currentConfig.Video.GIFFrameRate = $newSettings.Video.GIFFrameRate
                    $currentConfig.Video.GIFLoop = $newSettings.Video.GIFLoop
                    $currentConfig.Video.ThumbnailStartPercent = $newSettings.Video.ThumbnailStartPercent
                    $currentConfig.Video.ThumbnailEndPercent = $newSettings.Video.ThumbnailEndPercent
                    
                    $currentConfig.UI.Theme = $newSettings.UI.Theme
                    $currentConfig.UI.DefaultThumbSize = $newSettings.UI.DefaultThumbSize
                    $currentConfig.UI.ThumbnailSize = $newSettings.UI.ThumbnailSize
                    $currentConfig.UI.GridColumns = $newSettings.UI.GridColumns
                    $currentConfig.UI.PreviewThumbnailCount = $newSettings.UI.PreviewThumbnailCount
                    $currentConfig.UI.ShowVideoMetadata = $newSettings.UI.ShowVideoMetadata
                    $currentConfig.UI.ShowVideoCodec = $newSettings.UI.ShowVideoCodec
                    $currentConfig.UI.ShowVideoDuration = $newSettings.UI.ShowVideoDuration
                    $currentConfig.UI.ShowBrowserCompatibility = $newSettings.UI.ShowBrowserCompatibility
                    
                    $currentConfig.Performance.UseParallelProcessing = $newSettings.Performance.UseParallelProcessing
                    $currentConfig.Performance.MaxParallelJobs = $newSettings.Performance.MaxParallelJobs
                    $currentConfig.Performance.CacheThumbnails = $newSettings.Performance.CacheThumbnails
                    $currentConfig.Performance.LazyLoading = $newSettings.Performance.LazyLoading
                    $currentConfig.Performance.DeleteJobTimeout = $newSettings.Performance.DeleteJobTimeout
                    
                    $currentConfig.FileOperations.UseRecycleBin = $newSettings.FileOperations.UseRecycleBin
                    $currentConfig.FileOperations.ConfirmDelete = $newSettings.FileOperations.ConfirmDelete
                    $currentConfig.FileOperations.EnableMove = $newSettings.FileOperations.EnableMove
                    $currentConfig.FileOperations.EnableFlattenAndMove = $newSettings.FileOperations.EnableFlattenAndMove
                    $currentConfig.FileOperations.RangeRequestSupport = $newSettings.FileOperations.RangeRequestSupport
                    
                    $currentConfig.Cache.UseScanCache = $newSettings.Cache.UseScanCache
                    $currentConfig.Cache.CacheFolder = $newSettings.Cache.CacheFolder
                    $currentConfig.Cache.VideoMetadataCache = $newSettings.Cache.VideoMetadataCache
                    
                    $currentConfig.Features.ArchiveExtraction = $newSettings.Features.ArchiveExtraction
                    $currentConfig.Features.ArchiveExtensions = $newSettings.Features.ArchiveExtensions
                    $currentConfig.Features.VideoThumbnailPreGeneration = $newSettings.Features.VideoThumbnailPreGeneration
                    $currentConfig.Features.LazyVideoConversion = $newSettings.Features.LazyVideoConversion
                    $currentConfig.Features.OpenInVLC = $newSettings.Features.OpenInVLC
                    $currentConfig.Features.CollapsibleFolders = $newSettings.Features.CollapsibleFolders
                    $currentConfig.Features.LightboxViewer = $newSettings.Features.LightboxViewer
                    $currentConfig.Features.KeyboardNavigation = $newSettings.Features.KeyboardNavigation
                    
                    $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                    
                    $json = @{ success = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /settings/reset
            if ($path -eq "/settings/reset" -and $req.HttpMethod -eq "POST") {
                try {
                    $configPath = Join-Path $ScriptRoot "config.json"
                    
                    # Hardcoded Default-Config
                    $defaultConfig = @{
                        Server = @{
                            Port = 8888
                            AutoOpenBrowser = $true
                            Host = "localhost"
                        }
                        Paths = @{
                            RootFolder = ""
                            ThumbsFolder = ".thumbs"
                            TempFolder = ".temp"
                            ConvertedFolder = ".converted"
                        }
                        Media = @{
                            ImageExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff")
                            VideoExtensions = @(".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".wmv", ".flv", ".mpg", ".mpeg", ".3gp")
                        }
                        Video = @{
                            EnableAutoConversion = $true
                            PreferredCodec = "h264"
                            ThumbnailQuality = 85
                            ConversionPreset = "medium"
                            ThumbnailCount = 9
                            ThumbnailFPS = 1
                            ThumbnailStartPercent = 10
                            ThumbnailEndPercent = 90
                            PreviewAsGIF = $true
                            GIFDuration = 3
                            GIFFrameRate = 10
                            GIFLoop = $true
                            UseHLS = $true
                            HLSSegmentDuration = 10
                        }
                        UI = @{
                            PreviewThumbnailCount = 10
                            Theme = "light"
                            GridColumns = 3
                            ThumbnailSize = 200
                            DefaultThumbSize = "medium"
                            ShowVideoMetadata = $true
                            ShowVideoCodec = $true
                            ShowVideoDuration = $true
                            ShowBrowserCompatibility = $true
                        }
                        Performance = @{
                            UseParallelProcessing = $true
                            MaxParallelJobs = 8
                            CacheThumbnails = $true
                            LazyLoading = $true
                            DeleteJobTimeout = 10
                        }
                        FileOperations = @{
                            UseRecycleBin = $true
                            ConfirmDelete = $true
                            EnableMove = $false
                            EnableFlattenAndMove = $false
                            RangeRequestSupport = $true
                        }
                        Cache = @{
                            UseScanCache = $true
                            CacheFolder = ".cache"
                            VideoMetadataCache = $true
                        }
                        Features = @{
                            ArchiveExtraction = $false
                            ArchiveExtensions = @(".zip", ".rar", ".7z", ".tar", ".gz")
                            VideoThumbnailPreGeneration = $false
                            LazyVideoConversion = $true
                            OpenInVLC = $false
                            CollapsibleFolders = $true
                            LightboxViewer = $true
                            KeyboardNavigation = $true
                        }
                    }
                    
                    # Als JSON speichern
                    $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                    
                    $json = @{ success = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /delete-files
            if ($path -eq "/delete-files" -and $req.HttpMethod -eq "POST") {
                try {
                    $reader = [System.IO.StreamReader]::new($req.InputStream)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $data = $body | ConvertFrom-Json
                    $paths = $data.paths
                    
                    if (-not $paths -or $paths.Count -eq 0) {
                        $json = @{ success = $false; error = "Keine Dateien angegeben" } | ConvertTo-Json -Compress
                        Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                        continue
                    }
                    
                    $deletedCount = 0
                    $useRecycleBin = $config.FileOperations.UseRecycleBin
                    
                    foreach ($relativePath in $paths) {
                        $fullPath = Resolve-SafePath -RootPath $script:State.RootPath -RelativePath $relativePath
                        
                        if ($fullPath -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                            if ($useRecycleBin) {
                                # Papierkorb verwenden
                                $shell = New-Object -ComObject Shell.Application
                                $item = $shell.Namespace(0).ParseName($fullPath)
                                $item.InvokeVerb("delete")
                            } else {
                                # Permanent löschen
                                Remove-Item -LiteralPath $fullPath -Force
                            }
                            $deletedCount++
                        }
                    }
                    
                    $json = @{ 
                        success = $true
                        deletedCount = $deletedCount
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                    
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /img
            if ($path -eq "/img" -and $req.HttpMethod -eq "GET") {
                $relativePath = $req.QueryString["path"]
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-ResponseText -Response $res -Text "Missing path" -StatusCode 400
                    continue
                }
                $fullPath = Resolve-SafePath -RootPath $script:State.RootPath -RelativePath $relativePath
                if (-not $fullPath -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    Send-ResponseText -Response $res -Text "Not found" -StatusCode 404
                    continue
                }
                try {
                    if (Test-IsVideoFile -Path $fullPath) {
                        if ($script:FFmpegPath) {
                            $thumbPath = Get-VideoThumbnail -VideoPath $fullPath -CacheDir $script:ThumbsDir -ScriptRoot $ScriptRoot
                            if ($thumbPath -and (Test-Path -LiteralPath $thumbPath -PathType Leaf)) {
                                $fullPath = $thumbPath
                            }
                        }
                    }
                    $contentType = Get-MediaContentType -Path $fullPath
                    $fileInfo = [System.IO.FileInfo]::new($fullPath)
                    $res.StatusCode = 200
                    $res.ContentType = $contentType
                    $res.ContentLength64 = $fileInfo.Length
                    $fs = [System.IO.File]::OpenRead($fullPath)
                    try {
                        $fs.CopyTo($res.OutputStream)
                    }
                    finally {
                        $fs.Close()
                        $res.OutputStream.Close()
                    }
                } catch {
                    Write-Error "Fehler: $($_.Exception.Message)"
                    Send-ResponseText -Response $res -Text "Error" -StatusCode 500
                }
                continue
            }
            
            # Route: /ping
            if ($path -eq "/ping" -and $req.HttpMethod -eq "GET") {
                Send-ResponseText -Response $res -Text "OK" -StatusCode 200
                continue
            }
            
            # Route: /shutdown
            if ($path -eq "/shutdown" -and $req.HttpMethod -eq "POST") {
                $ServerRunning = $false
                Send-ResponseText -Response $res -Text "Beende..."
                break
            }
            
            Send-ResponseText -Response $res -Text "Not Found" -StatusCode 404
            
        } catch {
            Write-Error "Request-Fehler: $($_.Exception.Message)"
            Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host ""
    Write-Host "✓ Server beendet" -ForegroundColor Green
    Write-Host ""
}            