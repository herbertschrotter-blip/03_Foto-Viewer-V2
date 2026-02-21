<#
.SYNOPSIS
    Zentrale Thumbnail-Generierung für Foto_Viewer_V2

.DESCRIPTION
    Generiert Thumbnails für Fotos (System.Drawing) und Videos (FFmpeg).
    Cache-basiert mit MD5-Hash für schnelle Zugriffe.

.EXAMPLE
    $thumb = Get-MediaThumbnail -Path "C:\foto.jpg" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot
    
.EXAMPLE
    $thumb = Get-MediaThumbnail -Path "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot -FFmpegPath "C:\ffmpeg\ffmpeg.exe"

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
    
    ÄNDERUNGEN v0.2.0:
    - Lokale .thumbs/ pro Ordner (statt zentral)
    - Windows Hidden Attribute
    - manifest.json für Cache-Validierung
    - Test-ThumbnailCacheValid
    - Update-ThumbnailCache
    - Remove-OrphanedThumbnails
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Helper: File-Type Detection
function Test-IsImageFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Bild ist
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $imageExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff')
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    return $ext -in $imageExtensions
}

function Test-IsVideoFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Video ist
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

# Cache Helper
function Get-ThumbnailCachePath {
    <#
    .SYNOPSIS
        Generiert Cache-Pfad für Thumbnail (Hash-basiert)
    
    .DESCRIPTION
        Erstellt MD5-Hash aus: FullPath + LastWriteTimeUtc
        Format: {CacheDir}/{Hash}.jpg
    
    .EXAMPLE
        $cachePath = Get-ThumbnailCachePath -MediaPath "C:\foto.jpg" -CacheDir "C:\cache"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$MediaPath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir
    )
    
    try {
        $fileInfo = [System.IO.FileInfo]::new($MediaPath)
        
        if (-not $fileInfo.Exists) {
            throw "Datei existiert nicht: $MediaPath"
        }
        
        # Hash aus Pfad + LastWriteTime (damit Cache invalidiert wird bei Änderung)
        $hashInput = "$($fileInfo.FullName)-$($fileInfo.LastWriteTimeUtc.Ticks)"
        
        $hash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($hashInput)
            )
        ).Replace('-', '').ToLowerInvariant()
        
        $cachePath = Join-Path $CacheDir "$hash.jpg"
        
        Write-Verbose "Cache-Path: $cachePath"
        return $cachePath
        
    } catch {
        Write-Error "Fehler beim Generieren des Cache-Pfads: $($_.Exception.Message)"
        throw
    }
}

# FOTO-THUMBNAILS
function Get-ImageThumbnail {
    <#
    .SYNOPSIS
        Generiert Thumbnail für Foto (System.Drawing)
    
    .PARAMETER ImagePath
        Vollständiger Pfad zum Bild
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER MaxSize
        Maximale Breite/Höhe (Default: 300px)
    
    .PARAMETER Quality
        JPEG Quality 0-100 (Default: 85)
    
    .EXAMPLE
        $thumb = Get-ImageThumbnail -ImagePath "C:\foto.jpg" -CacheDir "C:\cache"
    
    .OUTPUTS
        String - Pfad zum Thumbnail oder $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir,
        
        [Parameter()]
        [int]$MaxSize = 300,
        
        [Parameter()]
        [int]$Quality = 85
    )
    
    try {
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
            Write-Warning "Bild nicht gefunden: $ImagePath"
            return $null
        }
        
        # Cache-Dir erstellen
        if (-not (Test-Path -LiteralPath $CacheDir -PathType Container)) {
            New-Item -Path $CacheDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Cache-Verzeichnis erstellt: $CacheDir"
        }
        
        # Cache-Pfad generieren
        $thumbPath = Get-ThumbnailCachePath -MediaPath $ImagePath -CacheDir $CacheDir
        
        # Cache-Hit?
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Thumbnail aus Cache: $thumbPath"
            return $thumbPath
        }
        
        # System.Drawing laden
        Add-Type -AssemblyName System.Drawing
        
        Write-Verbose "Generiere Thumbnail für: $ImagePath"
        
        # Original-Bild laden
        $originalImage = $null
        $thumbnail = $null
        
        try {
            $originalImage = [System.Drawing.Image]::FromFile($ImagePath)
            
            # Neue Dimensionen berechnen (Aspect Ratio beibehalten)
            $ratio = [Math]::Min(
                ($MaxSize / $originalImage.Width),
                ($MaxSize / $originalImage.Height)
            )
            
            $newWidth = [int]($originalImage.Width * $ratio)
            $newHeight = [int]($originalImage.Height * $ratio)
            
            Write-Verbose "Original: $($originalImage.Width)x$($originalImage.Height) → Thumbnail: ${newWidth}x${newHeight}"
            
            # Thumbnail erstellen (High Quality)
            $thumbnail = [System.Drawing.Bitmap]::new($newWidth, $newHeight)
            $graphics = [System.Drawing.Graphics]::FromImage($thumbnail)
            
            try {
                # High-Quality Settings
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                
                # Resize
                $graphics.DrawImage($originalImage, 0, 0, $newWidth, $newHeight)
                
                # JPEG Encoder mit Quality-Setting
                $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | 
                    Where-Object { $_.MimeType -eq 'image/jpeg' } | 
                    Select-Object -First 1
                
                $encoderParams = [System.Drawing.Imaging.EncoderParameters]::new(1)
                $encoderParams.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
                    [System.Drawing.Imaging.Encoder]::Quality,
                    [long]$Quality
                )
                
                # Speichern
                $thumbnail.Save($thumbPath, $jpegCodec, $encoderParams)
                
                Write-Verbose "Thumbnail gespeichert: $thumbPath"
                
            } finally {
                if ($graphics) { $graphics.Dispose() }
            }
            
        } finally {
            if ($thumbnail) { $thumbnail.Dispose() }
            if ($originalImage) { $originalImage.Dispose() }
        }
        
        # Verifizieren
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            return $thumbPath
        } else {
            Write-Warning "Thumbnail wurde nicht erstellt: $thumbPath"
            return $null
        }
        
    } catch {
        Write-Error "Fehler beim Generieren von Foto-Thumbnail: $($_.Exception.Message)"
        return $null
    }
}

# VIDEO-THUMBNAILS
function Get-VideoThumbnail {
    <#
    .SYNOPSIS
        Generiert Thumbnail für Video (FFmpeg)
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER FFmpegPath
        Pfad zu ffmpeg.exe (wenn nicht angegeben: Suche in ScriptRoot/ffmpeg/)
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg-Suche)
    
    .PARAMETER TimePosition
        Position im Video (Default: 00:00:01)
    
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
        
        [Parameter()]
        [string]$FFmpegPath,
        
        [Parameter()]
        [string]$ScriptRoot,
        
        [Parameter()]
        [string]$TimePosition = "00:00:01"
    )
    
    try {
        # Video existiert?
        if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
            Write-Warning "Video nicht gefunden: $VideoPath"
            return $null
        }
        
        # Cache-Dir erstellen
        if (-not (Test-Path -LiteralPath $CacheDir -PathType Container)) {
            New-Item -Path $CacheDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Cache-Verzeichnis erstellt: $CacheDir"
        }
        
        # Cache-Pfad generieren
        $thumbPath = Get-ThumbnailCachePath -MediaPath $VideoPath -CacheDir $CacheDir
        
        # Cache-Hit?
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Thumbnail aus Cache: $thumbPath"
            return $thumbPath
        }
        
        # FFmpeg-Pfad ermitteln
        if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
            if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
                Write-Warning "FFmpeg-Pfad und ScriptRoot nicht angegeben"
                return $null
            }
            
            $FFmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        }
        
        # FFmpeg verfügbar?
        if (-not (Test-Path -LiteralPath $FFmpegPath -PathType Leaf)) {
            Write-Warning "FFmpeg nicht gefunden: $FFmpegPath"
            return $null
        }
        
        # Thumbnail generieren
        Write-Verbose "Generiere Video-Thumbnail für: $VideoPath"
        
        $ffmpegArgs = @(
            '-ss', $TimePosition
            '-i', $VideoPath
            '-vframes', '1'
            '-q:v', '2'
            '-y'
            $thumbPath
        )
        
        $process = Start-Process -FilePath $FFmpegPath `
                                 -ArgumentList $ffmpegArgs `
                                 -NoNewWindow `
                                 -Wait `
                                 -PassThru `
                                 -RedirectStandardError "$env:TEMP\ffmpeg_error.log"
        
        if ($process.ExitCode -ne 0) {
            Write-Warning "FFmpeg Fehler (Exit: $($process.ExitCode)) für: $VideoPath"
            
            if (Test-Path "$env:TEMP\ffmpeg_error.log") {
                $errorLog = Get-Content "$env:TEMP\ffmpeg_error.log" -Raw
                Write-Verbose "FFmpeg Error Log: $errorLog"
            }
            
            return $null
        }
        
        # Verifizieren
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Video-Thumbnail generiert: $thumbPath"
            return $thumbPath
        } else {
            Write-Warning "Video-Thumbnail wurde nicht erstellt: $thumbPath"
            return $null
        }
        
    } catch {
        Write-Error "Fehler beim Generieren von Video-Thumbnail: $($_.Exception.Message)"
        return $null
    }
}

# UNIVERSAL ENTRY POINT
function Get-MediaThumbnail {
    <#
    .SYNOPSIS
        Universal Thumbnail-Generator (Auto-detect: Foto oder Video)
    
    .DESCRIPTION
        Erkennt automatisch ob Foto oder Video und generiert entsprechendes Thumbnail.
        Cache liegt lokal im .thumbs/ Ordner neben der Datei.
    
    .PARAMETER Path
        Pfad zur Media-Datei (Foto oder Video)
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg bei Videos)
    
    .PARAMETER MaxSize
        Maximale Breite/Höhe für Fotos (Default: 300px)
    
    .PARAMETER Quality
        JPEG Quality für Fotos (Default: 85)
    
    .EXAMPLE
        $thumb = Get-MediaThumbnail -Path "C:\Photos\Urlaub\foto.jpg" -ScriptRoot $PSScriptRoot
        # Thumbnail wird in C:\Photos\Urlaub\.thumbs\ erstellt
    
    .OUTPUTS
        String - Pfad zum Thumbnail oder $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter()]
        [string]$ScriptRoot,
        
        [Parameter()]
        [int]$MaxSize = 300,
        
        [Parameter()]
        [int]$Quality = 85
    )
    
    try {
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Warning "Datei nicht gefunden: $Path"
            return $null
        }
        
        Write-Verbose "Thumbnail-Request für: $Path"
        
        # Cache-Dir = Ordner der Datei + .thumbs
        $mediaDir = Split-Path -Parent $Path
        $cacheDir = Join-Path $mediaDir ".thumbs"
        
        # Erstellen + Hidden setzen
        if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            
            # Windows Hidden Attribute
            $folder = Get-Item -LiteralPath $cacheDir -Force
            $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::Hidden
            
            Write-Verbose "Erstellt: $cacheDir (Hidden)"
        }
        
        # Auto-detect: Foto oder Video?
        if (Test-IsImageFile -Path $Path) {
            Write-Verbose "→ Erkannt als Foto"
            return Get-ImageThumbnail -ImagePath $Path `
                                     -CacheDir $cacheDir `
                                     -MaxSize $MaxSize `
                                     -Quality $Quality
        }
        elseif (Test-IsVideoFile -Path $Path) {
            Write-Verbose "→ Erkannt als Video"
            return Get-VideoThumbnail -VideoPath $Path `
                                     -CacheDir $cacheDir `
                                     -ScriptRoot $ScriptRoot
        }
        else {
            Write-Warning "Unbekannter Dateityp: $Path"
            return $null
        }
        
    } catch {
        Write-Error "Fehler in Get-MediaThumbnail: $($_.Exception.Message)"
        return $null
    }
}


# ============================================
# TEIL 3: CACHE-MANAGEMENT
# ============================================

function Test-ThumbnailCacheValid {
    <#
    .SYNOPSIS
        Prüft ob Thumbnail-Cache für Ordner valide ist
    
    .DESCRIPTION
        Validiert manifest.json gegen aktuelle Medien-Dateien.
        Checks:
        - Anzahl Dateien gleich?
        - Alle Dateien vorhanden?
        - LastModified gleich?
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner
    
    .EXAMPLE
        if (Test-ThumbnailCacheValid -FolderPath "C:\Photos\Urlaub") {
            Write-Host "Cache OK"
        }
    
    .OUTPUTS
        Boolean - $true wenn Cache valide, $false wenn rebuild nötig
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    
    try {
        $thumbsDir = Join-Path $FolderPath ".thumbs"
        $manifestPath = Join-Path $thumbsDir "manifest.json"
        
        # Kein Manifest? → Ungültig
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-Verbose "Cache ungültig: Kein Manifest in $FolderPath"
            return $false
        }
        
        # Manifest laden
        $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifest = $manifestJson | ConvertFrom-Json
        
        # Aktuelle Medien im Ordner
        $currentFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue | 
            Where-Object { (Test-IsImageFile -Path $_.FullName) -or (Test-IsVideoFile -Path $_.FullName) })
        
        # Quick Check: Anzahl unterschiedlich?
        if ($currentFiles.Count -ne $manifest.mediaCount) {
            Write-Verbose "Cache ungültig: Anzahl $($currentFiles.Count) vs Manifest $($manifest.mediaCount)"
            return $false
        }
        
        # Deep Check: Dateien geändert?
        foreach ($file in $currentFiles) {
            $fileName = $file.Name
            
            # Datei nicht in Manifest?
            if (-not $manifest.files.PSObject.Properties.Name.Contains($fileName)) {
                Write-Verbose "Cache ungültig: Neue Datei $fileName"
                return $false
            }
            
            $manifestEntry = $manifest.files.$fileName
            
            # LastModified geändert?
            $currentModified = $file.LastWriteTimeUtc.ToString('o')
            if ($currentModified -ne $manifestEntry.lastModified) {
                Write-Verbose "Cache ungültig: $fileName geändert ($currentModified vs $($manifestEntry.lastModified))"
                return $false
            }
        }
        
        # Alle Checks bestanden
        Write-Verbose "Cache valide: $FolderPath"
        return $true
        
    } catch {
        Write-Warning "Fehler beim Validieren von Cache: $($_.Exception.Message)"
        return $false
    }
}

function Update-ThumbnailCache {
    <#
    .SYNOPSIS
        Rebuilt Thumbnail-Cache für einen Ordner
    
    .DESCRIPTION
        Generiert Thumbnails für alle Medien im Ordner und
        erstellt manifest.json mit Metadaten.
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg)
    
    .PARAMETER MaxSize
        Maximale Thumbnail-Größe (Default: 300)
    
    .PARAMETER Quality
        JPEG Quality (Default: 85)
    
    .EXAMPLE
        Update-ThumbnailCache -FolderPath "C:\Photos\Urlaub" -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        Int - Anzahl generierter Thumbnails
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        
        [Parameter()]
        [string]$ScriptRoot,
        
        [Parameter()]
        [int]$MaxSize = 300,
        
        [Parameter()]
        [int]$Quality = 85
    )
    
    try {
        Write-Verbose "Rebuilding cache for: $FolderPath"
        
        $thumbsDir = Join-Path $FolderPath ".thumbs"
        $manifestPath = Join-Path $thumbsDir "manifest.json"
        
        # .thumbs erstellen
        if (-not (Test-Path -LiteralPath $thumbsDir -PathType Container)) {
            New-Item -Path $thumbsDir -ItemType Directory -Force | Out-Null
            $folder = Get-Item -LiteralPath $thumbsDir -Force
            $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::Hidden
        }
        
        # Aktuelle Medien
        $mediaFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue | 
            Where-Object { (Test-IsImageFile -Path $_.FullName) -or (Test-IsVideoFile -Path $_.FullName) })
        
        if ($mediaFiles.Count -eq 0) {
            Write-Verbose "Keine Medien in $FolderPath"
            return 0
        }
        
        # Manifest aufbauen
        $manifest = @{
            generated = (Get-Date).ToUniversalTime().ToString('o')
            version = '1.0'
            mediaCount = $mediaFiles.Count
            thumbnailSettings = @{
                maxSize = $MaxSize
                quality = $Quality
            }
            files = @{}
        }
        
        $generated = 0
        
        # Thumbnails generieren + Manifest füllen
        foreach ($file in $mediaFiles) {
            $thumbPath = Get-MediaThumbnail -Path $file.FullName -ScriptRoot $ScriptRoot -MaxSize $MaxSize -Quality $Quality
            
            if ($thumbPath) {
                $hash = [System.IO.Path]::GetFileNameWithoutExtension($thumbPath)
                
                $manifest.files[$file.Name] = @{
                    hash = $hash
                    lastModified = $file.LastWriteTimeUtc.ToString('o')
                    size = $file.Length
                    type = if (Test-IsImageFile -Path $file.FullName) { 'image' } else { 'video' }
                }
                
                $generated++
            }
        }
        
        # Manifest speichern
        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestJson | Out-File -LiteralPath $manifestPath -Encoding UTF8 -Force
        
        Write-Verbose "Cache rebuilt: $generated von $($mediaFiles.Count) Thumbnails generiert"
        return $generated
        
    } catch {
        Write-Error "Fehler beim Rebuilden von Cache: $($_.Exception.Message)"
        return 0
    }
}

function Remove-OrphanedThumbnails {
    <#
    .SYNOPSIS
        Löscht verwaiste Thumbnails ohne Original
    
    .DESCRIPTION
        Vergleicht Thumbnails im .thumbs/ Ordner mit manifest.json
        und löscht Thumbnails die keine Original-Datei mehr haben.
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner
    
    .EXAMPLE
        Remove-OrphanedThumbnails -FolderPath "C:\Photos\Urlaub"
    
    .OUTPUTS
        Int - Anzahl gelöschter Thumbnails
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    
    try {
        $thumbsDir = Join-Path $FolderPath ".thumbs"
        $manifestPath = Join-Path $thumbsDir "manifest.json"
        
        if (-not (Test-Path -LiteralPath $thumbsDir -PathType Container)) {
            Write-Verbose "Kein .thumbs Ordner in $FolderPath"
            return 0
        }
        
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-Verbose "Kein Manifest - Skip Cleanup"
            return 0
        }
        
        $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifest = $manifestJson | ConvertFrom-Json
        
        # Valide Hashes aus Manifest
        $validHashes = @($manifest.files.PSObject.Properties.Value | ForEach-Object { $_.hash })
        
        # Alle Thumbnails im Cache
        $thumbnails = @(Get-ChildItem -LiteralPath $thumbsDir -Filter "*.jpg" -File -ErrorAction SilentlyContinue)
        
        $deleted = 0
        
        # Lösche Thumbnails ohne Manifest-Eintrag
        foreach ($thumb in $thumbnails) {
            $hash = $thumb.BaseName
            
            if ($hash -notin $validHashes) {
                Remove-Item -LiteralPath $thumb.FullName -Force
                Write-Verbose "Gelöscht: Orphaned Thumbnail $hash"
                $deleted++
            }
        }
        
        if ($deleted -gt 0) {
            Write-Verbose "Cleanup: $deleted verwaiste Thumbnails gelöscht"
        }
        
        return $deleted
        
    } catch {
        Write-Warning "Fehler beim Cleanup: $($_.Exception.Message)"
        return 0
    }
}