<#
ManifestHint:
  ExportFunctions = @("Get-MediaThumbnail", "Get-MediaThumbnails", "Test-ThumbnailCacheValid", "Update-ThumbnailCache", "Remove-OrphanedThumbnails", "Test-OneDriveProtection", "Enable-OneDriveProtection")
  Description     = "Master Thumbnail-Lib - Orchestriert Image und Video Thumbnails"
  Category        = "Media"
  Tags            = @("Thumbnails", "Images", "Videos", "FFmpeg", "Cache", "OneDrive", "Master")
  Dependencies    = @("Lib_ImageThumbnails.ps1", "Lib_VideoThumbnails.ps1", "Lib_Config.ps1")

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

ÄNDERUNGEN v0.5.0:
  - PowerShell 7.0 ONLY (Performance)
  - Config-Integration: KEINE Fallback-Werte
  - Alle Defaults aus Config (UI.ThumbnailSize, Video.*)
  - Wirft Fehler wenn Config fehlt (strict dependency)
  - Dependencies: + Lib_Config.ps1

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
    Version: 0.5.0
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config laden (über Lib_Config.ps1)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"

if (Test-Path -LiteralPath $libConfigPath) {
    . $libConfigPath
    $script:config = Get-Config
} else {
    throw "FEHLER: Lib_Config.ps1 nicht gefunden! Lib_Thumbnails benötigt Config."
}

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
    
    if ($ThumbnailQuality -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailQuality) {
            throw "Config nicht verfügbar oder Video.ThumbnailQuality fehlt!"
        }
        $ThumbnailQuality = $script:config.Video.ThumbnailQuality
    }
    
    if ($ThumbnailStartPercent -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailStartPercent) {
            throw "Config nicht verfügbar oder Video.ThumbnailStartPercent fehlt!"
        }
        $ThumbnailStartPercent = $script:config.Video.ThumbnailStartPercent
    }
    
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
    
    # Defaults aus Config (PFLICHT!)
    if ($MaxSize -eq 0) {
        if (-not $script:config -or -not $script:config.UI.ThumbnailSize) {
            throw "Config nicht verfügbar oder UI.ThumbnailSize fehlt!"
        }
        $MaxSize = $script:config.UI.ThumbnailSize
    }
    
    if ($ThumbnailQuality -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailQuality) {
            throw "Config nicht verfügbar oder Video.ThumbnailQuality fehlt!"
        }
        $ThumbnailQuality = $script:config.Video.ThumbnailQuality
    }
    
    if ($ThumbnailCount -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailCount) {
            throw "Config nicht verfügbar oder Video.ThumbnailCount fehlt!"
        }
        $ThumbnailCount = $script:config.Video.ThumbnailCount
    }
    
    if ($ThumbnailStartPercent -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailStartPercent) {
            throw "Config nicht verfügbar oder Video.ThumbnailStartPercent fehlt!"
        }
        $ThumbnailStartPercent = $script:config.Video.ThumbnailStartPercent
    }
    
    if ($ThumbnailEndPercent -eq 0) {
        if (-not $script:config -or -not $script:config.Video.ThumbnailEndPercent) {
            throw "Config nicht verfügbar oder Video.ThumbnailEndPercent fehlt!"
        }
        $ThumbnailEndPercent = $script:config.Video.ThumbnailEndPercent
    }
    
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



#endregion