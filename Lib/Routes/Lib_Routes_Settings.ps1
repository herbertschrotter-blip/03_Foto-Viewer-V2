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
    Version: 0.3.0

    ÄNDERUNGEN v0.2.0:
    - Lib_Config.ps1 dot-source hinzugefügt (war fehlend)
    - /settings/reset nutzt Get-DefaultConfig statt hardcoded Werte
    - #Requires auf 7.0 korrigiert
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest

# Libs laden
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

. (Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1")

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

    .EXAMPLE
        Handle-SettingsRoute -Context $ctx -ScriptRoot "C:\PhotoFolder"
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    $req  = $Context.Request
    $res  = $Context.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()

    try {
        # Route: /settings/get
        if ($path -eq "/settings/get" -and $req.HttpMethod -eq "GET") {
            try {
                $configPath = Join-Path $ScriptRoot "config.json"
                $configJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                Send-ResponseText -Response $res -Text $configJson -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            }
            catch {
                $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route: /settings/save
        if ($path -eq "/settings/save" -and $req.HttpMethod -eq "POST") {
            try {
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $body   = $reader.ReadToEnd()
                $reader.Close()

                $newSettings  = $body | ConvertFrom-Json
                $configPath   = Join-Path $ScriptRoot "config.json"
                $currentConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

                # Server
                $currentConfig.Server.Port            = $newSettings.Server.Port
                $currentConfig.Server.Host            = $newSettings.Server.Host
                $currentConfig.Server.AutoOpenBrowser = $newSettings.Server.AutoOpenBrowser

                # Media
                $currentConfig.Media.ImageExtensions = $newSettings.Media.ImageExtensions
                $currentConfig.Media.VideoExtensions = $newSettings.Media.VideoExtensions

                # Video
                $currentConfig.Video.ThumbnailQuality      = $newSettings.Video.ThumbnailQuality
                $currentConfig.Video.UseHLS                 = $newSettings.Video.UseHLS
                $currentConfig.Video.HLSSegmentDuration     = $newSettings.Video.HLSSegmentDuration
                $currentConfig.Video.HLSPreloadSeconds      = $newSettings.Video.HLSPreloadSeconds
                $currentConfig.Video.ConversionPreset       = $newSettings.Video.ConversionPreset
                $currentConfig.Video.ThumbnailCount         = $newSettings.Video.ThumbnailCount
                $currentConfig.Video.ThumbnailFPS           = $newSettings.Video.ThumbnailFPS
                $currentConfig.Video.PreviewAsGIF           = $newSettings.Video.PreviewAsGIF
                $currentConfig.Video.GIFDuration            = $newSettings.Video.GIFDuration
                $currentConfig.Video.GIFFrameRate           = $newSettings.Video.GIFFrameRate
                $currentConfig.Video.GIFLoop                = $newSettings.Video.GIFLoop
                $currentConfig.Video.ThumbnailStartPercent  = $newSettings.Video.ThumbnailStartPercent
                $currentConfig.Video.ThumbnailEndPercent    = $newSettings.Video.ThumbnailEndPercent

                # UI
                $currentConfig.UI.Theme                    = $newSettings.UI.Theme
                $currentConfig.UI.DefaultThumbSize         = $newSettings.UI.DefaultThumbSize
                $currentConfig.UI.ThumbnailSize            = $newSettings.UI.ThumbnailSize
                $currentConfig.UI.GridColumns              = $newSettings.UI.GridColumns
                $currentConfig.UI.FolderPreviewCount       = $newSettings.UI.FolderPreviewCount
                $currentConfig.UI.FolderPreviewMode        = $newSettings.UI.FolderPreviewMode
                $currentConfig.UI.ShowVideoMetadata        = $newSettings.UI.ShowVideoMetadata
                $currentConfig.UI.ShowVideoCodec           = $newSettings.UI.ShowVideoCodec
                $currentConfig.UI.ShowVideoDuration        = $newSettings.UI.ShowVideoDuration
                $currentConfig.UI.ShowBrowserCompatibility = $newSettings.UI.ShowBrowserCompatibility

                # Performance
                $currentConfig.Performance.UseParallelProcessing = $newSettings.Performance.UseParallelProcessing
                $currentConfig.Performance.MaxParallelJobs       = $newSettings.Performance.MaxParallelJobs
                $currentConfig.Performance.CacheThumbnails       = $newSettings.Performance.CacheThumbnails
                $currentConfig.Performance.LazyLoading           = $newSettings.Performance.LazyLoading
                $currentConfig.Performance.DeleteJobTimeout      = $newSettings.Performance.DeleteJobTimeout

                # FileOperations
                $currentConfig.FileOperations.UseRecycleBin        = $newSettings.FileOperations.UseRecycleBin
                $currentConfig.FileOperations.ConfirmDelete        = $newSettings.FileOperations.ConfirmDelete
                $currentConfig.FileOperations.EnableMove           = $newSettings.FileOperations.EnableMove
                $currentConfig.FileOperations.EnableFlattenAndMove = $newSettings.FileOperations.EnableFlattenAndMove
                $currentConfig.FileOperations.RangeRequestSupport  = $newSettings.FileOperations.RangeRequestSupport

                # Cache
                $currentConfig.Cache.UseScanCache      = $newSettings.Cache.UseScanCache
                $currentConfig.Cache.CacheFolder       = $newSettings.Cache.CacheFolder
                $currentConfig.Cache.VideoMetadataCache = $newSettings.Cache.VideoMetadataCache

                # Features
                $currentConfig.Features.ArchiveExtraction          = $newSettings.Features.ArchiveExtraction
                $currentConfig.Features.ArchiveExtensions          = $newSettings.Features.ArchiveExtensions
                $currentConfig.Features.VideoThumbnailPreGeneration = $newSettings.Features.VideoThumbnailPreGeneration
                $currentConfig.Features.OpenInVLC                  = $newSettings.Features.OpenInVLC
                $currentConfig.Features.CollapsibleFolders         = $newSettings.Features.CollapsibleFolders
                $currentConfig.Features.LightboxViewer             = $newSettings.Features.LightboxViewer
                $currentConfig.Features.KeyboardNavigation         = $newSettings.Features.KeyboardNavigation

                # Speichern
                $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

                $json = @{ success = $true } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            }
            catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route: /settings/reset
        if ($path -eq "/settings/reset" -and $req.HttpMethod -eq "POST") {
            try {
                $configPath    = Join-Path $ScriptRoot "config.json"

                # Defaults aus zentraler Quelle - KEINE hardcoded Werte hier!
                $defaultConfig = Get-DefaultConfig

                # Als JSON speichern
                $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

                # Config-Cache invalidieren damit nächster Get-Config neu lädt
                Clear-ConfigCache

                $json = @{ success = $true } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            }
            catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route nicht gefunden in Settings
        return $false

    }
    catch {
        Write-Error "Settings Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}
