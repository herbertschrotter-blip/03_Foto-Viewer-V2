<#
ManifestHint:
  ExportFunctions = @("Get-Config", "Save-Config", "Get-DefaultConfig", "Clear-ConfigCache", "Merge-ConfigWithDefaults")
  Description     = "Konfigurationsverwaltung mit Caching"
  Category        = "Core"
  Tags            = @("Config", "Settings", "Cache")
  Dependencies    = @()

Zweck:
  - Lädt und speichert config.json
  - Caching für Performance (60s TTL)
  - Fallback zu Defaults bei Fehler
  - Merge mit vollständigen Defaults

Funktionen:
  - Get-Config: Lädt Config mit Cache
  - Save-Config: Speichert Config zu Disk
  - Get-DefaultConfig: Gibt vollständige Defaults zurück
  - Clear-ConfigCache: Invalidiert Cache
  - Merge-ConfigWithDefaults: Ergänzt fehlende Keys

Abhängigkeiten:
  - Keine

.NOTES
    Autor: Herbert Schrotter
    Version: 0.3.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cache-Variablen (Module-Scope)
$script:ConfigCache = $null
$script:ConfigCacheTime = $null
$script:ConfigCacheTTL = 60  # Sekunden

function Get-Config {
    <#
    .SYNOPSIS
        Lädt config.json aus Projekt-Root mit Caching
    
    .DESCRIPTION
        Lädt Konfiguration mit 60s Cache für Performance.
        Merged mit Defaults für fehlende Keys.
        Bei Fehler: Gibt vollständige Default-Config zurück.
    
    .PARAMETER Force
        Ignoriert Cache, lädt neu von Disk
    
    .EXAMPLE
        $config = Get-Config
        $port = $config.Server.Port
    
    .EXAMPLE
        $config = Get-Config -Force
        # Erzwingt Neu-Laden, ignoriert Cache
    
    .OUTPUTS
        [hashtable]
        Vollständige Konfiguration
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$Force
    )
    
    # Cache-Check
    $now = Get-Date
    $cacheAge = if ($script:ConfigCacheTime) { 
        ($now - $script:ConfigCacheTime).TotalSeconds 
    } else { 
        999 
    }
    
    $cacheValid = $script:ConfigCache -and 
                  ($cacheAge -lt $script:ConfigCacheTTL)
    
    if ($cacheValid -and -not $Force) {
        Write-Verbose "Config aus Cache ($([math]::Round($cacheAge, 1))s alt)"
        return $script:ConfigCache
    }
    
    # Config-Pfad bestimmen
    $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $configPath = Join-Path $scriptRoot "config.json"
    
    Write-Verbose "Lade Config von: $configPath"
    
    # Datei existiert?
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Warning "config.json nicht gefunden, verwende Defaults"
        $config = Get-DefaultConfig
        
        # Cache speichern
        $script:ConfigCache = $config
        $script:ConfigCacheTime = $now
        
        return $config
    }
    
    # Laden
    try {
        $json = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        
        # Merge mit Defaults (falls Keys fehlen)
        $defaults = Get-DefaultConfig
        $config = Merge-ConfigWithDefaults -Config $config -Defaults $defaults
        
        # Cache speichern
        $script:ConfigCache = $config
        $script:ConfigCacheTime = $now
        
        Write-Verbose "Config erfolgreich geladen und gecacht"
        return $config
    }
    catch {
        Write-Error "Fehler beim Laden von config.json: $($_.Exception.Message)"
        Write-Warning "Verwende Defaults als Fallback"
        
        # Fallback zu Defaults
        $config = Get-DefaultConfig
        $script:ConfigCache = $config
        $script:ConfigCacheTime = $now
        
        return $config
    }
}

function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Gibt vollständige Standard-Konfiguration zurück
    
    .DESCRIPTION
        Fallback wenn config.json nicht geladen werden kann.
        Enthält alle 9 Config-Bereiche mit allen Standard-Werten.
        
        WICHTIG: Hardcoded Werte sind NUR hier erlaubt!
        Überall sonst: Get-Config verwenden!
    
    .OUTPUTS
        [hashtable]
        Vollständige Default-Konfiguration
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    # WICHTIG: Hier dürfen hardcoded Werte stehen!
    # Überall sonst: Get-Config verwenden!
    
    $defaults = @{
        Video = @{
            ConversionPreset = "medium"
            GIFLoop = $true
            PreferredCodec = "h264"
            EnableAutoConversion = $true
            ThumbnailQuality = 85
            GIFDuration = 3
            ThumbnailStartPercent = 10
            PreviewAsGIF = $true
            ThumbnailEndPercent = 90
            UseHLS = $true
            ThumbnailCount = 5
            HLSSegmentDuration = 10
            GIFFrameRate = 10
            ThumbnailFPS = 1
        }
        Cache = @{
            UseScanCache = $true
            VideoMetadataCache = $true
            CacheFolder = ".cache"
        }
        FileOperations = @{
            EnableFlattenAndMove = $false
            UseRecycleBin = $true
            EnableMove = $false
            ConfirmDelete = $true
            RangeRequestSupport = $true
        }
        UI = @{
            GridColumns = 3
            ShowVideoDuration = $true
            PreviewThumbnailCount = 10
            Theme = "light"
            ShowVideoMetadata = $true
            ShowVideoCodec = $true
            ThumbnailSize = 200
            DefaultThumbSize = "medium"
            ShowBrowserCompatibility = $true
        }
        Features = @{
            CollapsibleFolders = $true
            KeyboardNavigation = $true
            OpenInVLC = $false
            LightboxViewer = $true
            ArchiveExtensions = @(".zip", ".rar", ".7z", ".tar", ".gz")
            VideoThumbnailPreGeneration = $false
            ArchiveExtraction = $false
            LazyVideoConversion = $true
        }
        Paths = @{
            ThumbsFolder = ".thumbs"
            TempFolder = ".temp"
            ConvertedFolder = ".converted"
            RootFolder = ""
        }
        Server = @{
            Host = "localhost"
            Port = 8888
            AutoOpenBrowser = $true
        }
        Performance = @{
            DeleteJobTimeout = 10
            UseParallelProcessing = $true
            LazyLoading = $true
            MaxParallelJobs = 8
            CacheThumbnails = $true
        }
        Media = @{
            ImageExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff")
            VideoExtensions = @(".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".wmv", ".flv", ".mpg", ".mpeg", ".3gp")
        }
    }
    
    return $defaults
}

function Save-Config {
    <#
    .SYNOPSIS
        Speichert Konfiguration in config.json
    
    .DESCRIPTION
        Konvertiert PSCustomObject zu JSON und speichert formatiert.
    
    .PARAMETER Config
        Konfigurations-Objekt zum Speichern
    
    .EXAMPLE
        $config.Server.Port = 9999
        Save-Config -Config $config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $configPath = Join-Path $scriptRoot "config.json"
        
        $json = $Config | ConvertTo-Json -Depth 10
        $json | Out-File -LiteralPath $configPath -Encoding UTF8 -Force
        
        Write-Verbose "Config gespeichert: $configPath"
        
    } catch {
        Write-Error "Fehler beim Speichern der Config: $($_.Exception.Message)"
        throw
    }
}

function Clear-ConfigCache {
    <#
    .SYNOPSIS
        Leert Config-Cache (erzwingt Neu-Laden)
    
    .DESCRIPTION
        Invalidiert Cache, nächster Get-Config lädt neu von Disk.
        Nützlich nach manuellen config.json Änderungen.
    
    .EXAMPLE
        Clear-ConfigCache
        $config = Get-Config  # Lädt neu von Disk
    #>
    [CmdletBinding()]
    param()
    
    $script:ConfigCache = $null
    $script:ConfigCacheTime = $null
    
    Write-Verbose "Config-Cache geleert"
}

function Merge-ConfigWithDefaults {
    <#
    .SYNOPSIS
        Merged geladene Config mit Defaults (für fehlende Keys)
    
    .DESCRIPTION
        Stellt sicher dass alle Keys vorhanden sind,
        auch wenn config.json unvollständig ist.
        Verwendet rekursiven Merge für verschachtelte Hashtables.
    
    .PARAMETER Config
        Geladene Config (kann unvollständig sein)
    
    .PARAMETER Defaults
        Default-Config (vollständig)
    
    .EXAMPLE
        $merged = Merge-ConfigWithDefaults -Config $loaded -Defaults $defaults
        # $merged hat garantiert alle Keys aus Defaults
    
    .OUTPUTS
        [hashtable]
        Vollständige Config mit allen Keys
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [hashtable]$Defaults
    )
    
    $merged = @{}
    
    # Alle Keys aus Defaults übernehmen
    foreach ($key in $Defaults.Keys) {
        if ($Config.ContainsKey($key)) {
            # Key existiert in Config
            if ($Config[$key] -is [hashtable] -and $Defaults[$key] -is [hashtable]) {
                # Nested Hashtable → rekursiv mergen
                $merged[$key] = Merge-ConfigWithDefaults -Config $Config[$key] -Defaults $Defaults[$key]
            }
            else {
                # Primitiver Wert → aus Config übernehmen
                $merged[$key] = $Config[$key]
            }
        }
        else {
            # Key fehlt → Default verwenden
            $merged[$key] = $Defaults[$key]
            Write-Verbose "Fehlender Key '$key' mit Default ergänzt"
        }
    }
    
    return $merged
}