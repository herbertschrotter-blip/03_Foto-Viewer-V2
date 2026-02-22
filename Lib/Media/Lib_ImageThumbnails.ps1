<#
ManifestHint:
  ExportFunctions = @("Get-ImageThumbnail", "Test-IsImageFile", "Get-ThumbnailCachePath")
  Description     = "Thumbnail-Generierung für Bilder mit System.Drawing"
  Category        = "Media"
  Tags            = @("Thumbnails", "Images", "Cache")
  Dependencies    = @("System.Drawing", "Lib_Config.ps1")

Zweck:
  - Thumbnail-Generierung für Bilder (System.Drawing)
  - Hash-basierter Cache-Pfad
  - High-Quality JPEG Encoding
  - Config-gesteuerte Image-Extension Erkennung

Funktionen:
  - Get-ImageThumbnail: Generiert Thumbnail für Foto
  - Test-IsImageFile: Prüft ob Datei ein Bild ist (nutzt Config)
  - Get-ThumbnailCachePath: Hash-basierter Cache-Pfad

Abhängigkeiten:
  - System.Drawing (Thumbnail-Generierung)
  - Lib_Config.ps1 (Settings: ImageExtensions, ThumbnailSize, Quality)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config laden (über Lib_Config.ps1)
$ScriptDir = if ($PSScriptRoot) { 
    $PSScriptRoot 
} else { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
}
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"

if (Test-Path -LiteralPath $libConfigPath) {
    . $libConfigPath
    $script:config = Get-Config
} else {
    throw "FEHLER: Lib_Config.ps1 nicht gefunden! Lib_ImageThumbnails benötigt Config."
}

#region Helper Functions

function Test-IsImageFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Bild ist
    
    .DESCRIPTION
        Prüft Extension gegen Config.Media.ImageExtensions.
        Config wird von Lib_Config.ps1 bereitgestellt (automatisch geladen).
    
    .PARAMETER Path
        Pfad zur Datei
    
    .EXAMPLE
        Test-IsImageFile -Path "C:\foto.jpg"
    
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    # Image-Extensions aus Config (PFLICHT!)
    if (-not $script:config -or -not $script:config.Media.ImageExtensions) {
        throw "Config nicht verfügbar oder Media.ImageExtensions fehlt!"
    }
    
    return $ext -in $script:config.Media.ImageExtensions
}

function Get-ThumbnailCachePath {
    <#
    .SYNOPSIS
        Generiert Cache-Pfad für Thumbnail (Hash-basiert)
    
    .DESCRIPTION
        Erstellt MD5-Hash aus: FullPath + LastWriteTimeUtc
        Format: {CacheDir}/{Hash}.jpg
    
    .PARAMETER MediaPath
        Pfad zur Medien-Datei
    
    .PARAMETER CacheDir
        Cache-Verzeichnis
    
    .PARAMETER Index
        Optional: Index für Multi-Thumbnails (z.B. Video)
    
    .EXAMPLE
        $cachePath = Get-ThumbnailCachePath -MediaPath "C:\foto.jpg" -CacheDir "C:\cache"
    
    .EXAMPLE
        $cachePath = Get-ThumbnailCachePath -MediaPath "C:\video.mp4" -CacheDir "C:\cache" -Index 3
    
    .OUTPUTS
        String - Pfad zum Thumbnail
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$MediaPath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir,
        
        [Parameter()]
        [int]$Index = 0
    )
    
    try {
        $fileInfo = [System.IO.FileInfo]::new($MediaPath)
        
        if (-not $fileInfo.Exists) {
            throw "Datei existiert nicht: $MediaPath"
        }
        
        # Hash aus Pfad + LastWriteTime
        $hashInput = "$($fileInfo.FullName)-$($fileInfo.LastWriteTimeUtc.Ticks)"
        
        $hash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($hashInput)
            )
        ).Replace('-', '').ToLowerInvariant()
        
        # Dateiname mit optionalem Index
        $fileName = if ($Index -gt 0) {
            "${hash}_${Index}.jpg"
        } else {
            "${hash}.jpg"
        }
        
        $cachePath = Join-Path $CacheDir $fileName
        
        Write-Verbose "Cache-Path: $cachePath"
        return $cachePath
        
    } catch {
        Write-Error "Fehler beim Generieren des Cache-Pfads: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Image Thumbnail Generation

function Get-ImageThumbnail {
    <#
    .SYNOPSIS
        Generiert Thumbnail für Foto (System.Drawing)
    
    .DESCRIPTION
        Erstellt optimiertes JPEG-Thumbnail mit High-Quality Settings.
        Verwendet Hash-basierten Cache für Performance.
    
    .PARAMETER ImagePath
        Vollständiger Pfad zum Bild
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER MaxSize
        Maximale Breite/Höhe in Pixel (Default: 300)
    
    .PARAMETER Quality
        JPEG Quality 0-100 (Default: 85)
    
    .EXAMPLE
        $thumb = Get-ImageThumbnail -ImagePath "C:\foto.jpg" -CacheDir "C:\cache"
    
    .EXAMPLE
        $thumb = Get-ImageThumbnail -ImagePath "C:\foto.jpg" -CacheDir "C:\cache" -MaxSize 400 -Quality 90
    
    .OUTPUTS
        String - Pfad zum Thumbnail oder $null bei Fehler
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir,
        
        [Parameter()]
        [int]$MaxSize,
        
        [Parameter()]
        [int]$Quality
    )
    
    # Defaults aus Config (PFLICHT!)
    if ($MaxSize -eq 0) {
        if (-not $script:config -or -not $script:config.UI.ThumbnailSize) {
            throw "Config nicht verfügbar oder UI.ThumbnailSize fehlt!"
        }
        $MaxSize = $script:config.UI.ThumbnailSize
    }
    
    if ($Quality -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailQuality) {
            throw "Config nicht verfügbar oder Video.ThumbnailQuality fehlt!"
        }
        $Quality = $script:config.Video.ThumbnailQuality
    }
    
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
        
        # Original-Bild laden (mit FileStream für sauberes Dispose)
        $fileStream = $null
        $originalImage = $null
        $thumbnail = $null
        $graphics = $null
        $memoryStream = $null
        
        try {
            # FileStream öffnen (bessere Handle-Kontrolle)
            $fileStream = [System.IO.File]::OpenRead($ImagePath)
            $originalImage = [System.Drawing.Image]::FromStream($fileStream)
            
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
            
            # High-Quality Settings
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            
            # Resize
            $graphics.DrawImage($originalImage, 0, 0, $newWidth, $newHeight)
            
            # Graphics sofort freigeben (vor Save!)
            $graphics.Dispose()
            $graphics = $null
            
            # Original sofort freigeben (vor Save!)
            $originalImage.Dispose()
            $originalImage = $null
            $fileStream.Close()
            $fileStream.Dispose()
            $fileStream = $null
            
            # JPEG Encoder mit Quality-Setting
            $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | 
                Where-Object { $_.MimeType -eq 'image/jpeg' } | 
                Select-Object -First 1
            
            $encoderParams = [System.Drawing.Imaging.EncoderParameters]::new(1)
            $encoderParams.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
                [System.Drawing.Imaging.Encoder]::Quality,
                [long]$Quality
            )
            
            # Via MemoryStream speichern (vermeidet File-Lock)
            $memoryStream = [System.IO.MemoryStream]::new()
            $thumbnail.Save($memoryStream, $jpegCodec, $encoderParams)
            
            # MemoryStream zu Datei schreiben
            $fileBytes = $memoryStream.ToArray()
            [System.IO.File]::WriteAllBytes($thumbPath, $fileBytes)
            
            Write-Verbose "Thumbnail gespeichert: $thumbPath"
            
        } finally {
            # WICHTIG: Alles freigeben in richtiger Reihenfolge
            if ($memoryStream) { 
                $memoryStream.Dispose() 
                $memoryStream = $null
            }
            if ($graphics) { 
                $graphics.Dispose() 
                $graphics = $null
            }
            if ($thumbnail) { 
                $thumbnail.Dispose() 
                $thumbnail = $null
            }
            if ($originalImage) { 
                $originalImage.Dispose() 
                $originalImage = $null
            }
            if ($fileStream) { 
                $fileStream.Close()
                $fileStream.Dispose() 
                $fileStream = $null
            }
            
            # GC forcieren (wichtig bei GDI+!)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()
        }
        
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

#endregion