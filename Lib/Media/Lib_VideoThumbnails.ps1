<#
ManifestHint:
  ExportFunctions = @("Get-VideoThumbnail", "Get-VideoThumbnails", "Test-IsVideoFile")
  Description     = "Thumbnail-Generierung für Videos mit FFmpeg - Multi-Thumbnail Support"
  Category        = "Media"
  Tags            = @("Thumbnails", "Videos", "FFmpeg", "Cache", "Multi-Thumbnail", "Parallel")
  Dependencies    = @("FFmpeg", "Lib_ImageThumbnails.ps1", "Lib_Config.ps1")

Zweck:
  - Thumbnail-Generierung für Videos (FFmpeg)
  - Single-Thumbnail: Ein Frame an bestimmter Position
  - Multi-Thumbnail: Mehrere zufällige Frames für Preview
  - Hash-basierter Cache mit Index
  - Parallel-Processing (PowerShell 7)

Funktionen:
  - Get-VideoThumbnail: Einzelnes Thumbnail (Legacy-Kompatibilität)
  - Get-VideoThumbnails: Mehrere Thumbnails (mit Parallel-Support)
  - Test-IsVideoFile: Prüft ob Datei ein Video ist

ÄNDERUNGEN v0.2.0:
  - Parallel-Processing Support (PowerShell 7)
  - Config-gesteuert: UseParallelProcessing + MaxParallelJobs
  - Automatischer Fallback zu Sequential wenn disabled
  - Performance-Logging (PARALLEL vs SEQUENTIAL Mode)

ÄNDERUNGEN v0.1.0:
  - Initial: Multi-Thumbnail Unterstützung
  - ThumbnailCount: Anzahl Thumbnails
  - ThumbnailStartPercent/EndPercent: Zeitbereich
  - Zufällige Positionen, sortiert generiert

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config laden
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"

if (Test-Path -LiteralPath $libConfigPath) {
    . $libConfigPath
    $script:config = Get-Config
} else {
    Write-Warning "Lib_Config.ps1 nicht gefunden - verwende Fallback-Defaults"
    $script:config = $null
}

#region Helper Functions

function Test-IsVideoFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Video ist
    
    .PARAMETER Path
        Pfad zur Datei
    
    .EXAMPLE
        Test-IsVideoFile -Path "C:\video.mp4"
    
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $videoExtensions = @('.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.3gp')
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    return $ext -in $videoExtensions
}

#endregion

#region Single Thumbnail (Legacy)

function Get-VideoThumbnail {
    <#
    .SYNOPSIS
        Generiert EINZELNES Thumbnail für Video (Legacy-Kompatibilität)
    
    .DESCRIPTION
        Erstellt ein Thumbnail an ThumbnailStartPercent Position.
        Für mehrere Thumbnails: Verwende Get-VideoThumbnails!
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg)
    
    .PARAMETER MaxSize
        Maximale Breite/Höhe (Default: 300px)
    
    .PARAMETER ThumbnailQuality
        JPEG Quality 0-100 (Default: 85)
    
    .PARAMETER ThumbnailStartPercent
        Position im Video in Prozent (Default: 10)
    
    .EXAMPLE
        $thumb = Get-VideoThumbnail -VideoPath "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        String - Pfad zum Thumbnail oder $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot,
        
        [Parameter()]
        [int]$MaxSize,
        
        [Parameter()]
        [int]$ThumbnailQuality,
        
        [Parameter()]
        [int]$ThumbnailStartPercent
    )
    
    # Defaults
    if ($MaxSize -eq 0) { $MaxSize = 300 }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = 85 }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = 10 }
    
    # Multi-Thumbnail Funktion aufrufen mit Count=1
    $thumbs = Get-VideoThumbnails `
        -VideoPath $VideoPath `
        -CacheDir $CacheDir `
        -ScriptRoot $ScriptRoot `
        -MaxSize $MaxSize `
        -ThumbnailQuality $ThumbnailQuality `
        -ThumbnailCount 1 `
        -ThumbnailStartPercent $ThumbnailStartPercent `
        -ThumbnailEndPercent $ThumbnailStartPercent
    
    # Erstes (und einziges) Thumbnail zurückgeben
    if ($thumbs -and $thumbs.Count -gt 0) {
        return $thumbs[0].Path
    }
    
    return $null
}

#endregion

#region Multi-Thumbnail Generation

function Get-VideoThumbnails {
    <#
    .SYNOPSIS
        Generiert MEHRERE Thumbnails für Video (mit Parallel-Processing)
    
    .DESCRIPTION
        Erstellt mehrere Thumbnails an zufälligen, sortierten Positionen.
        Nutzt PowerShell 7 Parallel-Processing wenn UseParallelProcessing=true.
        
        Workflow:
        1. Generiere ThumbnailCount zufällige Positionen zwischen Start/End
        2. Sortiere Positionen aufsteigend
        3. Erstelle Thumbnails parallel oder sequenziell
        4. Dateinamen: {Hash}_{Index}.jpg
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg)
    
    .PARAMETER MaxSize
        Maximale Breite/Höhe (Default: aus Config)
    
    .PARAMETER ThumbnailQuality
        JPEG Quality 0-100 (Default: aus Config)
    
    .PARAMETER ThumbnailCount
        Anzahl Thumbnails (Default: aus Config)
    
    .PARAMETER ThumbnailStartPercent
        Start-Position in Prozent (Default: aus Config)
    
    .PARAMETER ThumbnailEndPercent
        End-Position in Prozent (Default: aus Config)
    
    .EXAMPLE
        $thumbs = Get-VideoThumbnails -VideoPath "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot
        # Erstellt Thumbnails mit Config-Einstellungen
    
    .EXAMPLE
        $thumbs = Get-VideoThumbnails -VideoPath "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot -ThumbnailCount 5
        # Erstellt 5 Thumbnails (überschreibt Config)
    
    .OUTPUTS
        Array of PSCustomObject - Jedes mit Properties: Path, Position, Index
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot,
        
        [Parameter()]
        [int]$MaxSize,
        
        [Parameter()]
        [int]$ThumbnailQuality,
        
        [Parameter()]
        [int]$ThumbnailCount,
        
        [Parameter()]
        [int]$ThumbnailStartPercent,
        
        [Parameter()]
        [int]$ThumbnailEndPercent
    )
    
    # Defaults aus Config (falls vorhanden) oder Fallback
    if ($MaxSize -eq 0) { 
        $MaxSize = if ($script:config) { $script:config.UI.ThumbnailSize } else { 300 }
    }
    if ($ThumbnailQuality -eq 0) { 
        $ThumbnailQuality = if ($script:config) { $script:config.Video.ThumbnailQuality } else { 85 }
    }
    if ($ThumbnailCount -eq 0) { 
        $ThumbnailCount = if ($script:config) { $script:config.Video.ThumbnailCount } else { 9 }
    }
    if ($ThumbnailStartPercent -eq 0) { 
        $ThumbnailStartPercent = if ($script:config) { $script:config.Video.ThumbnailStartPercent } else { 10 }
    }
    if ($ThumbnailEndPercent -eq 0) { 
        $ThumbnailEndPercent = if ($script:config) { $script:config.Video.ThumbnailEndPercent } else { 90 }
    }
    
    # Performance Settings aus Config
    $useParallel = if ($script:config -and $ThumbnailCount -gt 1) { 
        $script:config.Performance.UseParallelProcessing 
    } else { 
        $false 
    }
    $maxParallelJobs = if ($script:config) { 
        $script:config.Performance.MaxParallelJobs 
    } else { 
        4 
    }
    
    try {
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
            Write-Warning "Video nicht gefunden: $VideoPath"
            return @()
        }
        
        # CacheDir sicherstellen
        if (-not (Test-Path -LiteralPath $CacheDir -PathType Container)) {
            Write-Verbose "CacheDir fehlt, erstelle: $CacheDir"
            New-Item -Path $CacheDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        # FFmpeg-Pfad
        $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        
        if (-not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf)) {
            Write-Warning "FFmpeg nicht gefunden: $ffmpegPath"
            return @()
        }
        
        $mode = if ($useParallel) { "PARALLEL ($maxParallelJobs threads)" } else { "SEQUENTIAL" }
        Write-Verbose "Generiere $ThumbnailCount Video-Thumbnails ($mode) für: $VideoPath"
        
        # Video-Dauer ermitteln
        $durationArgs = @("-i", $VideoPath, "-hide_banner")
        $durationOutput = & $ffmpegPath $durationArgs 2>&1 | Out-String
        
        $totalSeconds = 0
        
        if ($durationOutput -match 'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})') {
            $hours = [int]$matches[1]
            $minutes = [int]$matches[2]
            $seconds = [int]$matches[3]
            $totalSeconds = ($hours * 3600) + ($minutes * 60) + $seconds
            
            Write-Verbose "Video-Dauer: ${totalSeconds}s"
        } else {
            Write-Warning "Konnte Video-Dauer nicht ermitteln"
            return @()
        }
        
        # Start/End in Sekunden
        $startSeconds = [int]($totalSeconds * ($ThumbnailStartPercent / 100.0))
        $endSeconds = [int]($totalSeconds * ($ThumbnailEndPercent / 100.0))
        
        if ($startSeconds -gt $endSeconds) {
            Write-Warning "StartPercent ($ThumbnailStartPercent%) > EndPercent ($ThumbnailEndPercent%)"
            return @()
        }
        
        Write-Verbose "Zeitbereich: ${startSeconds}s - ${endSeconds}s (${ThumbnailStartPercent}% - ${ThumbnailEndPercent}%)"
        
        # SCHRITT 1: Zufällige Positionen generieren
        $random = [System.Random]::new()
        $positions = @()
        
        for ($i = 0; $i -lt $ThumbnailCount; $i++) {
            $randomPos = $random.Next($startSeconds, $endSeconds + 1)
            $positions += $randomPos
        }
        
        # SCHRITT 2: Sortieren (aufsteigend)
        $positions = $positions | Sort-Object
        
        Write-Verbose "Generiere Thumbnails an Positionen (s): $($positions -join ', ')"
        
        # FFmpeg Quality-Mapping (0-100 → 2-31)
        $qValue = [Math]::Max(2, [Math]::Min(31, 31 - [int](($ThumbnailQuality / 100.0) * 29)))
        
        Write-Verbose "Thumbnail Quality: $ThumbnailQuality% → FFmpeg q:v $qValue"
        
        # Get-ThumbnailCachePath laden (aus Lib_ImageThumbnails.ps1)
        $libImagePath = Join-Path $ScriptRoot "Lib\Media\Lib_ImageThumbnails.ps1"
        if (-not (Test-Path -LiteralPath $libImagePath)) {
            Write-Warning "Lib_ImageThumbnails.ps1 nicht gefunden - benötigt für Get-ThumbnailCachePath"
            return @()
        }
        . $libImagePath
        
        # SCHRITT 3: Thumbnails erstellen (PARALLEL oder SEQUENTIAL)
        
        if ($useParallel) {
            # === PARALLEL MODE ===
            Write-Verbose "Parallel-Processing mit $maxParallelJobs Threads"
            
            # Index-Mapping erstellen (Position → Index)
            $indexMap = @{}
            for ($i = 0; $i -lt $positions.Count; $i++) {
                $indexMap[$positions[$i]] = $i + 1
            }
            
            $results = $positions | ForEach-Object -ThrottleLimit $maxParallelJobs -Parallel {
                $posSeconds = $_
                $indexMap = $using:indexMap
                $index = $indexMap[$posSeconds]
                
                # Variablen aus outer scope
                $VideoPath = $using:VideoPath
                $CacheDir = $using:CacheDir
                $ffmpegPath = $using:ffmpegPath
                $MaxSize = $using:MaxSize
                $qValue = $using:qValue
                $libImagePath = $using:libImagePath
                
                # Lib laden (in parallel runspace)
                . $libImagePath
                
                try {
                    $seekTime = [TimeSpan]::FromSeconds($posSeconds).ToString('hh\:mm\:ss')
                    
                    # Cache-Pfad mit Index
                    $thumbPath = Get-ThumbnailCachePath -MediaPath $VideoPath -CacheDir $CacheDir -Index $index
                    
                    # Cache-Hit?
                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        return [PSCustomObject]@{
                            Path = $thumbPath
                            Position = $posSeconds
                            Index = $index
                        }
                    }
                    
                    # FFmpeg Args
                    $ffmpegArgs = @(
                        "-i", "`"$VideoPath`"",
                        "-ss", $seekTime,
                        "-vframes", "1",
                        "-vf", "scale=${MaxSize}:${MaxSize}:force_original_aspect_ratio=decrease",
                        "-q:v", "$qValue",
                        "-y",
                        "`"$thumbPath`""
                    )
                    
                    # Ausführen
                    $process = Start-Process -FilePath $ffmpegPath -ArgumentList $ffmpegArgs -Wait -NoNewWindow -PassThru
                    
                    if ($process.ExitCode -ne 0) {
                        Write-Warning "FFmpeg Fehler bei Thumbnail $index"
                        return $null
                    }
                    
                    # Verifizieren
                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        return [PSCustomObject]@{
                            Path = $thumbPath
                            Position = $posSeconds
                            Index = $index
                        }
                    }
                    
                    return $null
                    
                } catch {
                    Write-Warning "Fehler bei Thumbnail ${index}: $($_.Exception.Message)"
                    return $null
                }
            }
            
            # Filtern (null entfernen) und sortieren
            $results = @($results | Where-Object { $_ -ne $null } | Sort-Object Index)
            
        } else {
            # === SEQUENTIAL MODE ===
            Write-Verbose "Sequential Processing"
            
            $results = @()
            $index = 1
            
            foreach ($posSeconds in $positions) {
                try {
                    $seekTime = [TimeSpan]::FromSeconds($posSeconds).ToString('hh\:mm\:ss')
                    
                    # Cache-Pfad mit Index
                    $thumbPath = Get-ThumbnailCachePath -MediaPath $VideoPath -CacheDir $CacheDir -Index $index
                    
                    # Cache-Hit?
                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        Write-Verbose "Thumbnail $index aus Cache: $thumbPath"
                        
                        $results += [PSCustomObject]@{
                            Path = $thumbPath
                            Position = $posSeconds
                            Index = $index
                        }
                        
                        $index++
                        continue
                    }
                    
                    Write-Verbose "Erstelle Thumbnail $index bei $seekTime ($posSeconds s)"
                    
                    # FFmpeg Args
                    $ffmpegArgs = @(
                        "-i", "`"$VideoPath`"",
                        "-ss", $seekTime,
                        "-vframes", "1",
                        "-vf", "scale=${MaxSize}:${MaxSize}:force_original_aspect_ratio=decrease",
                        "-q:v", "$qValue",
                        "-y",
                        "`"$thumbPath`""
                    )
                    
                    # Ausführen
                    $process = Start-Process -FilePath $ffmpegPath -ArgumentList $ffmpegArgs -Wait -NoNewWindow -PassThru
                    
                    if ($process.ExitCode -ne 0) {
                        Write-Warning "FFmpeg Fehler bei Thumbnail $index (Exit Code: $($process.ExitCode))"
                        $index++
                        continue
                    }
                    
                    # Verifizieren
                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        Write-Verbose "Thumbnail $index gespeichert: $thumbPath"
                        
                        $results += [PSCustomObject]@{
                            Path = $thumbPath
                            Position = $posSeconds
                            Index = $index
                        }
                    } else {
                        Write-Warning "Thumbnail $index wurde nicht erstellt"
                    }
                    
                    $index++
                    
                } catch {
                    Write-Warning "Fehler bei Thumbnail ${index}: $($_.Exception.Message)"
                    $index++
                }
            }
        }
        
        Write-Verbose "Erfolgreich: $($results.Count) von $ThumbnailCount Thumbnails erstellt"
        
        return $results
        
    } catch {
        Write-Error "Fehler beim Erstellen der Video-Thumbnails: $($_.Exception.Message)"
        return @()
    }
}

#endregion
