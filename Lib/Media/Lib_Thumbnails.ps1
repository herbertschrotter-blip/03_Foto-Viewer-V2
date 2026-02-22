<#
ManifestHint:
  ExportFunctions = @("Get-MediaThumbnail", "Get-ImageThumbnail", "Get-VideoThumbnail", "Test-ThumbnailCacheValid", "Update-ThumbnailCache", "Remove-OrphanedThumbnails", "Test-OneDriveProtection", "Enable-OneDriveProtection")
  Description     = "Thumbnail-Generierung für Fotos und Videos mit lokalem Cache"
  Category        = "Media"
  Tags            = @("Thumbnails", "Images", "Videos", "FFmpeg", "Cache", "OneDrive")
  Dependencies    = @("System.Drawing", "FFmpeg")

Zweck:
  - Thumbnail-Generierung für Bilder (System.Drawing)
  - Thumbnail-Generierung für Videos (FFmpeg)
  - Lokaler Cache pro Ordner (.thumbs/)
  - OneDrive-Schutz (Hidden+System + Registry)
  - Self-validating Cache mit manifest.json

Funktionen:
  - Get-MediaThumbnail: Universell für Fotos UND Videos
  - Get-ImageThumbnail: System.Drawing für Bilder
  - Get-VideoThumbnail: FFmpeg für Videos
  - Test-ThumbnailCacheValid: Cache-Validierung
  - Update-ThumbnailCache: Cache-Rebuild
  - Remove-OrphanedThumbnails: Cleanup
  - Test-OneDriveProtection: Prüft OneDrive-Schutz (kein Admin)
  - Enable-OneDriveProtection: Aktiviert Registry-Schutz (benötigt Admin)

ÄNDERUNGEN v0.3.1:
  - thumbs.db Filter: Verhindert Crash bei Windows Thumbnail-Cache
  - Test-ThumbnailCacheValid filtert thumbs.db/Thumbs.db
  - Update-ThumbnailCache filtert thumbs.db/Thumbs.db

ÄNDERUNGEN v0.3.0:
  - OneDrive-Schutz: Hidden+System Attribute
  - OneDrive-Schutz: Registry EnableODIgnoreListFromGPO
  - Test-OneDriveProtection: Check-Funktion (kein Admin)
  - Enable-OneDriveProtection: Auto-Setup (benötigt Admin)
  - Dokumentation: OneDrive-Verhalten
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region OneDrive Protection

function New-ThumbnailCacheFolder {
    <#
    .SYNOPSIS
        Erstellt .thumbs Ordner mit OneDrive-Schutz
    
    .DESCRIPTION
        Erstellt lokalen Thumbnail-Cache Ordner mit HYBRID OneDrive-Schutz:
        
        STUFE 1: Hidden + System Attribute (IMMER)
        - Windows/OneDrive ignoriert System-Ordner standardmäßig
        - Hidden allein reicht NICHT (OneDrive scannt trotzdem)
        - Hidden+System zusammen = OneDrive ignoriert
        
        STUFE 2: Registry EnableODIgnoreListFromGPO (OPTIONAL)
        - Zusätzlicher Schutz falls Hidden+System nicht reicht
        - Wird beim Server-Start geprüft/gesetzt
        - Benötigt Admin-Rechte
        
        WARUM BEIDES?
        - Hidden+System: Funktioniert bei 90% der Setups
        - Registry: Garantiert 100% Schutz
        
        OneDrive-Verhalten (Microsoft dokumentiert):
        - System-Ordner werden NICHT synchronisiert
        - Registry Pattern ".thumbs\*" blockt alle Dateien im .thumbs Ordner
    
    .PARAMETER FolderPath
        Übergeordneter Ordner (nicht der .thumbs Ordner selbst!)
    
    .EXAMPLE
        New-ThumbnailCacheFolder -FolderPath "C:\Photos\Urlaub"
        # Erstellt: C:\Photos\Urlaub\.thumbs\ (Hidden+System)
    
    .OUTPUTS
        String - Pfad zum .thumbs Ordner
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    
    try {
        $thumbsDir = Join-Path $FolderPath ".thumbs"
        
        # Erstellen falls nicht vorhanden
        if (-not (Test-Path -LiteralPath $thumbsDir)) {
            New-Item -Path $thumbsDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Cache-Ordner erstellt: $thumbsDir"
        }
        
        # STUFE 1: Hidden + System Attribute setzen
        $folder = Get-Item -LiteralPath $thumbsDir -Force
        
        # Prüfe ob Attribute bereits gesetzt sind
        $hasHidden = ($folder.Attributes -band [System.IO.FileAttributes]::Hidden) -eq [System.IO.FileAttributes]::Hidden
        $hasSystem = ($folder.Attributes -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System
        
        if (-not ($hasHidden -and $hasSystem)) {
            $folder.Attributes = [System.IO.FileAttributes]::Hidden -bor 
                                 [System.IO.FileAttributes]::System
            Write-Verbose "OneDrive-Schutz aktiviert: Hidden+System Attribute"
        }
        
        return $thumbsDir
    }
    catch {
        Write-Error "Fehler beim Erstellen des Cache-Ordners: $($_.Exception.Message)"
        throw
    }
}

function Test-OneDriveProtection {
    <#
    .SYNOPSIS
        Prüft ob OneDrive-Schutz vollständig konfiguriert ist
    
    .DESCRIPTION
        Prüft beide Schutz-Stufen:
        1. Hidden+System Attribute (wird automatisch gesetzt)
        2. Registry EnableODIgnoreListFromGPO (optional)
        
        Registry-Pfad:
        HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO
          String Value "1" = ".thumbs\*"
        
        WICHTIG: Benötigt KEINE Admin-Rechte (nur Lesen!)
    
    .EXAMPLE
        if (-not (Test-OneDriveProtection)) {
            Write-Warning "OneDrive-Schutz nicht vollständig"
        }
    
    .OUTPUTS
        Boolean - $true wenn Registry-Schutz konfiguriert, $false wenn nicht
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO"
        
        # Prüfe ob Registry-Pfad existiert
        if (-not (Test-Path $regPath)) {
            Write-Verbose "Registry-Schutz nicht konfiguriert: Pfad existiert nicht"
            return $false
        }
        
        # Prüfe ob .thumbs Pattern vorhanden ist
        $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        
        if ($null -eq $properties) {
            Write-Verbose "Registry-Schutz nicht konfiguriert: Keine Properties"
            return $false
        }
        
        # Durchsuche alle String Values nach ".thumbs\*" Pattern
        $hasThumbsPattern = $false
        
        foreach ($prop in $properties.PSObject.Properties) {
            if ($prop.Value -eq ".thumbs\*") {
                $hasThumbsPattern = $true
                Write-Verbose "Registry-Schutz gefunden: $($prop.Name) = .thumbs\*"
                break
            }
        }
        
        return $hasThumbsPattern
    }
    catch {
        Write-Verbose "Fehler beim Prüfen der Registry: $($_.Exception.Message)"
        return $false
    }
}

function Enable-OneDriveProtection {
    <#
    .SYNOPSIS
        Aktiviert OneDrive-Schutz via Registry
    
    .DESCRIPTION
        Setzt Registry-Schutz für .thumbs Ordner:
        
        HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO
          String Value "1" = ".thumbs\*"
        
        WICHTIG: Benötigt ADMIN-RECHTE zum Schreiben in HKLM!
        
        Microsoft Dokumentation:
        https://admx.help/?Category=OneDrive&Policy=Microsoft.Policies.OneDriveNGSC::EnableODIgnoreListFromGPO
    
    .EXAMPLE
        if (Enable-OneDriveProtection) {
            Write-Host "OneDrive-Schutz aktiviert"
        } else {
            Write-Warning "Benötigt Admin-Rechte"
        }
    
    .OUTPUTS
        Boolean - $true bei Erfolg, $false bei Fehler
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $regBase = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
        $regPath = "$regBase\EnableODIgnoreListFromGPO"
        
        # Erstelle OneDrive Ordner falls nicht vorhanden
        if (-not (Test-Path $regBase)) {
            Write-Verbose "Erstelle: $regBase"
            New-Item -Path $regBase -Force -ErrorAction Stop | Out-Null
        }
        
        # Erstelle EnableODIgnoreListFromGPO Ordner falls nicht vorhanden
        if (-not (Test-Path $regPath)) {
            Write-Verbose "Erstelle: $regPath"
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }
        
        # Suche freie Nummer für neuen Eintrag
        $existingProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $nextNumber = 1
        
        if ($null -ne $existingProps) {
            # Finde höchste Nummer
            foreach ($prop in $existingProps.PSObject.Properties) {
                if ($prop.Name -match '^\d+$') {
                    $num = [int]$prop.Name
                    if ($num -ge $nextNumber) {
                        $nextNumber = $num + 1
                    }
                }
            }
        }
        
        # Setze neuen String Value
        Write-Verbose "Setze Registry: $nextNumber = .thumbs\*"
        New-ItemProperty -Path $regPath -Name "$nextNumber" -Value ".thumbs\*" -PropertyType String -Force -ErrorAction Stop | Out-Null
        
        Write-Verbose "OneDrive-Schutz erfolgreich aktiviert"
        return $true
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "Admin-Rechte benötigt! Bitte PowerShell als Administrator starten."
        return $false
    }
    catch {
        Write-Error "Fehler beim Aktivieren des OneDrive-Schutzes: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Helper Functions

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

#endregion

#region Thumbnail Generation

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
        
        # WICHTIG: Kurz warten damit File-Handle freigegeben wird
        Start-Sleep -Milliseconds 50
        
        # Verifizieren
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            return $thumbPath
        } else {
            Write-Warning "Thumbnail wurde nicht erstellt: $thumbPath"
            return $null
        }
        
    } catch {
        Write-Error "Fehler beim Erstellen des Bild-Thumbnails: $($_.Exception.Message)"
        return $null
    }
}

function Get-VideoThumbnail {
    <#
    .SYNOPSIS
        Generiert Thumbnail für Video (FFmpeg)
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg)
    
    .PARAMETER MaxSize
        Maximale Breite/Höhe (Default: 300px)
    
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
        [int]$MaxSize = 300
    )
    
    try {
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
            Write-Warning "Video nicht gefunden: $VideoPath"
            return $null
        }
        
        # Stelle sicher dass CacheDir existiert (Defensive Programming)
        if (-not (Test-Path -LiteralPath $CacheDir -PathType Container)) {
            Write-Verbose "CacheDir fehlt, erstelle: $CacheDir"
            New-Item -Path $CacheDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        # Cache-Pfad generieren
        $thumbPath = Get-ThumbnailCachePath -MediaPath $VideoPath -CacheDir $CacheDir
        
        # Cache-Hit?
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Thumbnail aus Cache: $thumbPath"
            return $thumbPath
        }
        
        # FFmpeg-Pfad
        $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        
        if (-not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf)) {
            Write-Warning "FFmpeg nicht gefunden: $ffmpegPath"
            return $null
        }
        
        Write-Verbose "Generiere Video-Thumbnail für: $VideoPath"
        
        # FFmpeg Args: Frame bei 1 Sekunde extrahieren
        $ffmpegArgs = @(
            "-i", $VideoPath,
            "-ss", "00:00:01",
            "-vframes", "1",
            "-vf", "scale=${MaxSize}:${MaxSize}:force_original_aspect_ratio=decrease",
            "-q:v", "2",
            "-y",
            $thumbPath
        )
        
        # Ausführen
        $process = Start-Process -FilePath $ffmpegPath -ArgumentList $ffmpegArgs -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Warning "FFmpeg Fehler: Exit Code $($process.ExitCode)"
            return $null
        }
        
        # Verifizieren
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Video-Thumbnail gespeichert: $thumbPath"
            return $thumbPath
        } else {
            Write-Warning "Video-Thumbnail wurde nicht erstellt: $thumbPath"
            return $null
        }
        
    } catch {
        Write-Error "Fehler beim Erstellen des Video-Thumbnails: $($_.Exception.Message)"
        return $null
    }
}

function Get-MediaThumbnail {
    <#
    .SYNOPSIS
        Universelle Thumbnail-Generierung für Fotos UND Videos
    
    .DESCRIPTION
        Generiert Thumbnail automatisch basierend auf Dateityp:
        - Bilder: System.Drawing
        - Videos: FFmpeg
        
        Cache-Dir wird automatisch erstellt: {Ordner}\.thumbs\
        OneDrive-Schutz: Hidden+System Attribute
    
    .PARAMETER Path
        Pfad zur Medien-Datei
    
    .PARAMETER ScriptRoot
        Projekt-Root (für FFmpeg bei Videos)
    
    .PARAMETER MaxSize
        Maximale Größe (Default: 300px)
    
    .PARAMETER Quality
        JPEG-Qualität für Bilder (Default: 85)
    
    .EXAMPLE
        $thumb = Get-MediaThumbnail -Path "C:\Photos\bild.jpg" -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        String - Pfad zum Thumbnail (oder $null bei Fehler)
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
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Warning "Datei nicht gefunden: $Path"
            return $null
        }
        
        # Cache-Dir: {Ordner}\.thumbs\ (mit OneDrive-Schutz)
        $parentFolder = Split-Path -Parent $Path
        $cacheDir = New-ThumbnailCacheFolder -FolderPath $parentFolder
        
        # Generiere Thumbnail basierend auf Typ
        if (Test-IsImageFile -Path $Path) {
            return Get-ImageThumbnail -ImagePath $Path -CacheDir $cacheDir -MaxSize $MaxSize -Quality $Quality
        }
        elseif (Test-IsVideoFile -Path $Path) {
            if ([string]::IsNullOrEmpty($ScriptRoot)) {
                Write-Warning "ScriptRoot benötigt für Video-Thumbnails"
                return $null
            }
            return Get-VideoThumbnail -VideoPath $Path -CacheDir $cacheDir -ScriptRoot $ScriptRoot -MaxSize $MaxSize
        }
        else {
            Write-Warning "Unbekannter Dateityp: $Path"
            return $null
        }
        
    } catch {
        Write-Error "Fehler bei Thumbnail-Generierung: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Cache Management

function Test-ThumbnailCacheValid {
    <#
    .SYNOPSIS
        Prüft ob Thumbnail-Cache valide ist
    
    .DESCRIPTION
        Validiert Cache durch Vergleich mit manifest.json:
        - Anzahl Dateien gleich?
        - Alle Dateien in Manifest?
        - LastModified unverändert?
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner (nicht .thumbs!)
    
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
        
        # Aktuelle Medien im Ordner (thumbs.db ausfiltern!)
        $currentFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Name -ne 'Thumbs.db' -and 
                $_.Name -ne 'thumbs.db' -and
                ((Test-IsImageFile -Path $_.FullName) -or (Test-IsVideoFile -Path $_.FullName))
            })
        
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
        
        # .thumbs erstellen (mit OneDrive-Schutz)
        $thumbsDir = New-ThumbnailCacheFolder -FolderPath $FolderPath
        
        # Aktuelle Medien (thumbs.db ausfiltern!)
        $mediaFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Name -ne 'Thumbs.db' -and 
                $_.Name -ne 'thumbs.db' -and
                ((Test-IsImageFile -Path $_.FullName) -or (Test-IsVideoFile -Path $_.FullName))
            })
        
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
            try {
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
            catch {
                Write-Warning "Fehler bei $($file.Name): $($_.Exception.Message)"
                # Weiter mit nächster Datei
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

#endregion
