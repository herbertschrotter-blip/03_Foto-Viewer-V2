<#
.SYNOPSIS
    Routes Handler für Settings-Menü

.DESCRIPTION
    Behandelt alle /settings/* Routes:
    - /settings/get - Config laden
    - /settings/save - Config speichern
    - /settings/reset - Config auf Standard zurücksetzen

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Handle-SettingsRoute {
    <#
    .SYNOPSIS
        Behandelt alle /settings/* Routes
    
    .PARAMETER Context
        HttpListenerContext
    
    .PARAMETER ScriptRoot
        Script-Root Pfad für config.json
    
    .EXAMPLE
        Handle-SettingsRoute -Context $ctx -ScriptRoot $root
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    $req = $Context.Request
    $res = $Context.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()
    
    try {
        # Route: /settings/get
        if ($path -eq "/settings/get" -and $req.HttpMethod -eq "GET") {
            try {
                $configPath = Join-Path $ScriptRoot "config.json"
                $configJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                Send-ResponseText -Response $res -Text $configJson -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
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
                
                # Server
                $currentConfig.Server.Port = $newSettings.Server.Port
                $currentConfig.Server.Host = $newSettings.Server.Host
                $currentConfig.Server.AutoOpenBrowser = $newSettings.Server.AutoOpenBrowser
                
                # Media
                $currentConfig.Media.ImageExtensions = $newSettings.Media.ImageExtensions
                $currentConfig.Media.VideoExtensions = $newSettings.Media.VideoExtensions
                
                # Video
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
                
                # UI
                $currentConfig.UI.Theme = $newSettings.UI.Theme
                $currentConfig.UI.DefaultThumbSize = $newSettings.UI.DefaultThumbSize
                $currentConfig.UI.ThumbnailSize = $newSettings.UI.ThumbnailSize
                $currentConfig.UI.GridColumns = $newSettings.UI.GridColumns
                $currentConfig.UI.PreviewThumbnailCount = $newSettings.UI.PreviewThumbnailCount
                $currentConfig.UI.ShowVideoMetadata = $newSettings.UI.ShowVideoMetadata
                $currentConfig.UI.ShowVideoCodec = $newSettings.UI.ShowVideoCodec
                $currentConfig.UI.ShowVideoDuration = $newSettings.UI.ShowVideoDuration
                $currentConfig.UI.ShowBrowserCompatibility = $newSettings.UI.ShowBrowserCompatibility
                
                # Performance
                $currentConfig.Performance.UseParallelProcessing = $newSettings.Performance.UseParallelProcessing
                $currentConfig.Performance.MaxParallelJobs = $newSettings.Performance.MaxParallelJobs
                $currentConfig.Performance.CacheThumbnails = $newSettings.Performance.CacheThumbnails
                $currentConfig.Performance.LazyLoading = $newSettings.Performance.LazyLoading
                $currentConfig.Performance.DeleteJobTimeout = $newSettings.Performance.DeleteJobTimeout
                
                # FileOperations
                $currentConfig.FileOperations.UseRecycleBin = $newSettings.FileOperations.UseRecycleBin
                $currentConfig.FileOperations.ConfirmDelete = $newSettings.FileOperations.ConfirmDelete
                $currentConfig.FileOperations.EnableMove = $newSettings.FileOperations.EnableMove
                $currentConfig.FileOperations.EnableFlattenAndMove = $newSettings.FileOperations.EnableFlattenAndMove
                $currentConfig.FileOperations.RangeRequestSupport = $newSettings.FileOperations.RangeRequestSupport
                
                # Cache
                $currentConfig.Cache.UseScanCache = $newSettings.Cache.UseScanCache
                $currentConfig.Cache.CacheFolder = $newSettings.Cache.CacheFolder
                $currentConfig.Cache.VideoMetadataCache = $newSettings.Cache.VideoMetadataCache
                
                # Features
                $currentConfig.Features.ArchiveExtraction = $newSettings.Features.ArchiveExtraction
                $currentConfig.Features.ArchiveExtensions = $newSettings.Features.ArchiveExtensions
                $currentConfig.Features.VideoThumbnailPreGeneration = $newSettings.Features.VideoThumbnailPreGeneration
                $currentConfig.Features.LazyVideoConversion = $newSettings.Features.LazyVideoConversion
                $currentConfig.Features.OpenInVLC = $newSettings.Features.OpenInVLC
                $currentConfig.Features.CollapsibleFolders = $newSettings.Features.CollapsibleFolders
                $currentConfig.Features.LightboxViewer = $newSettings.Features.LightboxViewer
                $currentConfig.Features.KeyboardNavigation = $newSettings.Features.KeyboardNavigation
                
                # Speichern
                $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                
                $json = @{ success = $true } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }
        
        # Route: /settings/reset
        if ($path -eq "/settings/reset" -and $req.HttpMethod -eq "POST") {
            try {
                $configPath = Join-Path $ScriptRoot "config.json"
                
                # Default-Config
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
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }
        
        # Route nicht gefunden in Settings
        return $false
        
    } catch {
        Write-Error "Settings Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}