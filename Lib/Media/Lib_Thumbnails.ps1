<#
ManifestHint:
  ExportFunctions = @("Get-MediaThumbnail", "Get-MediaThumbnails", "Test-ThumbnailCacheValid", "Update-ThumbnailCache", "Remove-OrphanedThumbnails", "Test-OneDriveProtection", "Enable-OneDriveProtection")
  Description     = "Master Thumbnail-Lib - Orchestriert Image und Video Thumbnails"
  Category        = "Media"
  Tags            = @("Thumbnails", "Images", "Videos", "FFmpeg", "Cache", "OneDrive", "Master")
  Dependencies    = @("Lib_ImageThumbnails.ps1", "Lib_VideoThumbnails.ps1")

Zweck:
  - Master-Library für Thumbnail-Generierung
  - Routing: Bild → Lib_ImageThumbnails, Video → Lib_VideoThumbnails
  - Cache-Management (Validation, Rebuild, Cleanup)
  - OneDrive-Schutz (Hidden+System + Registry)

Funktionen:
  - Get-MediaThumbnail: Single Thumbnail (universal)
  - Get-MediaThumbnails: Multi-Thumbnails (Video)
  - Test-ThumbnailCacheValid: Cache-Validierung
  - Update-ThumbnailCache: Cache-Rebuild
  - Remove-OrphanedThumbnails: Cleanup
  - Test-OneDriveProtection: OneDrive-Schutz prüfen
  - Enable-OneDriveProtection: OneDrive-Schutz aktivieren

ÄNDERUNGEN v0.4.0:
  - Refactoring: Aufgeteilt in 3 Libs (Master + Image + Video)
  - Multi-Thumbnail Support für Videos (ThumbnailCount)
  - Zufällige sortierte Positionen (StartPercent - EndPercent)
  - Backwards Compatible: Alte Funktions-Signaturen bleiben

ÄNDERUNGEN v0.3.4:
  - Fix: FFmpeg Pfade mit Leerzeichen escapen (Quotes)

ÄNDERUNGEN v0.3.1:
  - thumbs.db Filter: Verhindert Crash bei Windows Thumbnail-Cache

ÄNDERUNGEN v0.3.0:
  - OneDrive-Schutz: Hidden+System Attribute + Registry

.NOTES
    Autor: Herbert Schrotter
    Version: 0.4.0
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Libs laden
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Image Thumbnails
$libImagePath = Join-Path $ScriptDir "Lib_ImageThumbnails.ps1"
if (Test-Path -LiteralPath $libImagePath) {
    . $libImagePath
} else {
    throw "Lib_ImageThumbnails.ps1 nicht gefunden: $libImagePath"
}

# Video Thumbnails
$libVideoPath = Join-Path $ScriptDir "Lib_VideoThumbnails.ps1"
if (Test-Path -LiteralPath $libVideoPath) {
    . $libVideoPath
} else {
    throw "Lib_VideoThumbnails.ps1 nicht gefunden: $libVideoPath"
}

#region OneDrive Protection

function New-ThumbnailCacheFolder {
    <#
    .SYNOPSIS
        Erstellt .thumbs Ordner mit OneDrive-Schutz
    
    .DESCRIPTION
        Erstellt lokalen Thumbnail-Cache Ordner mit HYBRID OneDrive-Schutz:
        
        STUFE 1: Hidden + System Attribute (IMMER)
        - Windows/OneDrive ignoriert System-Ordner standardmäßig
        
        STUFE 2: Registry EnableODIgnoreListFromGPO (OPTIONAL)
        - Zusätzlicher Schutz
        - Wird beim Server-Start geprüft/gesetzt
    
    .PARAMETER FolderPath
        Übergeordneter Ordner (nicht der .thumbs Ordner selbst!)
    
    .EXAMPLE
        New-ThumbnailCacheFolder -FolderPath "C:\Photos\Urlaub"
    
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
        Prüft ob OneDrive-Schutz konfiguriert ist
    
    .DESCRIPTION
        Prüft Registry EnableODIgnoreListFromGPO für .thumbs Pattern
    
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO"
        
        if (-not (Test-Path $regPath)) {
            Write-Verbose "Registry-Schutz nicht konfiguriert"
            return $false
        }
        
        $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        
        if ($null -eq $properties) {
            return $false
        }
        
        foreach ($prop in $properties.PSObject.Properties) {
            if ($prop.Value -eq ".thumbs\*") {
                Write-Verbose "Registry-Schutz gefunden: $($prop.Name) = .thumbs\*"
                return $true
            }
        }
        
        return $false
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
        Setzt Registry-Schutz für .thumbs Ordner
        WICHTIG: Benötigt ADMIN-RECHTE!
    
    .OUTPUTS
        Boolean - $true bei Erfolg
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $regBase = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
        $regPath = "$regBase\EnableODIgnoreListFromGPO"
        
        if (-not (Test-Path $regBase)) {
            New-Item -Path $regBase -Force -ErrorAction Stop | Out-Null
        }
        
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }
        
        $existingProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $nextNumber = 1
        
        if ($null -ne $existingProps) {
            foreach ($prop in $existingProps.PSObject.Properties) {
                if ($prop.Name -match '^\d+$') {
                    $num = [int]$prop.Name
                    if ($num -ge $nextNumber) {
                        $nextNumber = $num + 1
                    }
                }
            }
        }
        
        New-ItemProperty -Path $regPath -Name "$nextNumber" -Value ".thumbs\*" -PropertyType String -Force -ErrorAction Stop | Out-Null
        
        Write-Verbose "OneDrive-Schutz erfolgreich aktiviert"
        return $true
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "Admin-Rechte benötigt!"
        return $false
    }
    catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Universal Thumbnail Functions

function Get-MediaThumbnail {
    <#
    .SYNOPSIS
        Universelle Thumbnail-Generierung für Fotos UND Videos
    
    .DESCRIPTION
        Single Thumbnail - routet automatisch zu Image oder Video Lib
        Für Multi-Thumbnails (Videos): Verwende Get-MediaThumbnails!
    
    .PARAMETER Path
        Pfad zur Medien-Datei
    
    .PARAMETER ScriptRoot
        Projekt-Root (für FFmpeg bei Videos)
    
    .PARAMETER MaxSize
        Maximale Größe (Default: 300px)
    
    .PARAMETER Quality
        JPEG-Qualität (Default: 85)
    
    .PARAMETER ThumbnailQuality
        Video: JPEG-Qualität (Default: 85)
    
    .PARAMETER ThumbnailStartPercent
        Video: Position in Prozent (Default: 10)
    
    .EXAMPLE
        $thumb = Get-MediaThumbnail -Path "C:\foto.jpg" -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        String - Pfad zum Thumbnail
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter()]
        [string]$ScriptRoot,
        
        [Parameter()]
        [int]$MaxSize,
        
        [Parameter()]
        [int]$Quality,
        
        [Parameter()]
        [int]$ThumbnailQuality,
        
        [Parameter()]
        [int]$ThumbnailStartPercent
    )
    
    # Defaults
    if ($MaxSize -eq 0) { $MaxSize = 300 }
    if ($Quality -eq 0) { $Quality = 85 }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = 85 }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = 10 }
    
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Warning "Datei nicht gefunden: $Path"
            return $null
        }
        
        # Cache-Dir mit OneDrive-Schutz
        $parentFolder = Split-Path -Parent $Path
        $cacheDir = New-ThumbnailCacheFolder -FolderPath $parentFolder
        
        # Route zu Image oder Video
        if (Test-IsImageFile -Path $Path) {
            return Get-ImageThumbnail -ImagePath $Path -CacheDir $cacheDir -MaxSize $MaxSize -Quality $Quality
        }
        elseif (Test-IsVideoFile -Path $Path) {
            if ([string]::IsNullOrEmpty($ScriptRoot)) {
                Write-Warning "ScriptRoot benötigt für Video-Thumbnails"
                return $null
            }
            return Get-VideoThumbnail -VideoPath $Path -CacheDir $cacheDir -ScriptRoot $ScriptRoot -MaxSize $MaxSize -ThumbnailQuality $ThumbnailQuality -ThumbnailStartPercent $ThumbnailStartPercent
        }
        else {
            Write-Warning "Unbekannter Dateityp: $Path"
            return $null
        }
        
    } catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return $null
    }
}

function Get-MediaThumbnails {
    <#
    .SYNOPSIS
        Multi-Thumbnail Generierung (nur Videos)
    
    .DESCRIPTION
        Erstellt mehrere Thumbnails für Videos.
        Für Bilder: Verwende Get-MediaThumbnail (nur 1 Thumbnail)!
    
    .PARAMETER Path
        Pfad zum Video
    
    .PARAMETER ScriptRoot
        Projekt-Root (für FFmpeg)
    
    .PARAMETER MaxSize
        Maximale Größe (Default: 300px)
    
    .PARAMETER ThumbnailQuality
        JPEG Quality (Default: 85)
    
    .PARAMETER ThumbnailCount
        Anzahl Thumbnails (Default: 9)
    
    .PARAMETER ThumbnailStartPercent
        Start-Position (Default: 10)
    
    .PARAMETER ThumbnailEndPercent
        End-Position (Default: 90)
    
    .EXAMPLE
        $thumbs = Get-MediaThumbnails -Path "C:\video.mp4" -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        Array of PSCustomObject mit Path, Position, Index
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
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
    
    # Defaults
    if ($MaxSize -eq 0) { $MaxSize = 300 }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = 85 }
    if ($ThumbnailCount -eq 0) { $ThumbnailCount = 9 }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = 10 }
    if ($ThumbnailEndPercent -eq 0) { $ThumbnailEndPercent = 90 }
    
    try {
        # Nur für Videos
        if (-not (Test-IsVideoFile -Path $Path)) {
            Write-Warning "Multi-Thumbnails nur für Videos: $Path"
            return @()
        }
        
        # Cache-Dir
        $parentFolder = Split-Path -Parent $Path
        $cacheDir = New-ThumbnailCacheFolder -FolderPath $parentFolder
        
        return Get-VideoThumbnails `
            -VideoPath $Path `
            -CacheDir $cacheDir `
            -ScriptRoot $ScriptRoot `
            -MaxSize $MaxSize `
            -ThumbnailQuality $ThumbnailQuality `
            -ThumbnailCount $ThumbnailCount `
            -ThumbnailStartPercent $ThumbnailStartPercent `
            -ThumbnailEndPercent $ThumbnailEndPercent
        
    } catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Cache Management

function Test-ThumbnailCacheValid {
    <#
    .SYNOPSIS
        Prüft ob Thumbnail-Cache valide ist
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner
    
    .OUTPUTS
        Boolean
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
        
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-Verbose "Cache ungültig: Kein Manifest in $FolderPath"
            return $false
        }
        
        $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifest = $manifestJson | ConvertFrom-Json
        
        # Aktuelle Medien (thumbs.db Filter!)
        $currentFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Name -ne 'Thumbs.db' -and 
                $_.Name -ne 'thumbs.db' -and
                ((Test-IsImageFile -Path $_.FullName) -or (Test-IsVideoFile -Path $_.FullName))
            })
        
        if ($currentFiles.Count -ne $manifest.mediaCount) {
            Write-Verbose "Cache ungültig: Anzahl $($currentFiles.Count) vs $($manifest.mediaCount)"
            return $false
        }
        
        foreach ($file in $currentFiles) {
            if (-not $manifest.files.PSObject.Properties.Name.Contains($file.Name)) {
                Write-Verbose "Cache ungültig: Neue Datei $($file.Name)"
                return $false
            }
            
            $manifestEntry = $manifest.files.($file.Name)
            $currentModified = $file.LastWriteTimeUtc.ToString('o')
            
            if ($currentModified -ne $manifestEntry.lastModified) {
                Write-Verbose "Cache ungültig: $($file.Name) geändert"
                return $false
            }
        }
        
        Write-Verbose "Cache valide: $FolderPath"
        return $true
        
    } catch {
        Write-Warning "Fehler: $($_.Exception.Message)"
        return $false
    }
}

function Update-ThumbnailCache {
    <#
    .SYNOPSIS
        Rebuilt Thumbnail-Cache für einen Ordner
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg)
    
    .PARAMETER MaxSize
        Maximale Größe (Default: 300)
    
    .PARAMETER Quality
        JPEG Quality (Default: 85)
    
    .PARAMETER ThumbnailQuality
        Video Quality (Default: 85)
    
    .PARAMETER ThumbnailStartPercent
        Video Start (Default: 10)
    
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
        [int]$MaxSize,
        
        [Parameter()]
        [int]$Quality,
        
        [Parameter()]
        [int]$ThumbnailQuality,
        
        [Parameter()]
        [int]$ThumbnailStartPercent
    )
    
    # Defaults
    if ($MaxSize -eq 0) { $MaxSize = 300 }
    if ($Quality -eq 0) { $Quality = 85 }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = 85 }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = 10 }
    
    try {
        Write-Verbose "Rebuilding cache: $FolderPath"
        
        $thumbsDir = New-ThumbnailCacheFolder -FolderPath $FolderPath
        $manifestPath = Join-Path $thumbsDir "manifest.json"
        
        # Medien (thumbs.db Filter!)
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
        
        foreach ($file in $mediaFiles) {
            try {
                $thumbPath = Get-MediaThumbnail -Path $file.FullName -ScriptRoot $ScriptRoot -MaxSize $MaxSize -Quality $Quality -ThumbnailQuality $ThumbnailQuality -ThumbnailStartPercent $ThumbnailStartPercent
                
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
            }
        }
        
        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestJson | Out-File -LiteralPath $manifestPath -Encoding UTF8 -Force
        
        Write-Verbose "Cache rebuilt: $generated von $($mediaFiles.Count) Thumbnails"
        return $generated
        
    } catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return 0
    }
}

function Remove-OrphanedThumbnails {
    <#
    .SYNOPSIS
        Löscht verwaiste Thumbnails ohne Original
    
    .PARAMETER FolderPath
        Vollständiger Pfad zum Ordner
    
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
            return 0
        }
        
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            return 0
        }
        
        $manifestJson = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifest = $manifestJson | ConvertFrom-Json
        
        $validHashes = @($manifest.files.PSObject.Properties.Value | ForEach-Object { $_.hash })
        $thumbnails = @(Get-ChildItem -LiteralPath $thumbsDir -Filter "*.jpg" -File -ErrorAction SilentlyContinue)
        
        $deleted = 0
        
        foreach ($thumb in $thumbnails) {
            # Hash extrahieren (ohne _Index falls vorhanden)
            $baseName = $thumb.BaseName
            $hash = if ($baseName -match '^(.+)_\d+$') { $matches[1] } else { $baseName }
            
            if ($hash -notin $validHashes) {
                Remove-Item -LiteralPath $thumb.FullName -Force
                Write-Verbose "Gelöscht: $($thumb.Name)"
                $deleted++
            }
        }
        
        if ($deleted -gt 0) {
            Write-Verbose "Cleanup: $deleted Thumbnails gelöscht"
        }
        
        return $deleted
        
    } catch {
        Write-Warning "Fehler: $($_.Exception.Message)"
        return 0
    }
}

#endregion