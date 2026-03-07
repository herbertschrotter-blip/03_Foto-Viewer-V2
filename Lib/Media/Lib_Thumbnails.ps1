<#
ManifestHint:
  ExportFunctions = @(
    "Get-MediaThumbnail", "Get-MediaThumbnails",
    "Get-ImageThumbnail", "Get-VideoThumbnail", "Get-VideoThumbnails",
    "Test-IsImageFile", "Test-IsVideoFile", "Get-ThumbnailCachePath",
    "Test-ThumbnailExists", "New-ThumbnailCacheFolder",
    "Test-OneDriveProtection", "Enable-OneDriveProtection"
  )
  Description     = "Thumbnail-Generierung fuer Bilder (System.Drawing) und Videos (FFmpeg)"
  Category        = "Media"
  Tags            = @("Thumbnails","Images","Videos","FFmpeg","Cache","OneDrive")
  Dependencies    = @("System.Drawing","FFmpeg","Lib_Config.ps1","Lib_Logging.ps1")

Zweck:
  - Universelle Thumbnail-Generierung (Bilder + Videos)
  - Hash-basierter Cache (.thumbs pro Ordner)
  - OneDrive-Schutz (Hidden+System + Registry)
  - Multi-Thumbnail Support fuer Videos
  - Parallel-Processing (PowerShell 7)

Funktionen:
  HELPER:
  - Test-IsImageFile: Prueft Extension gegen Config
  - Test-IsVideoFile: Prueft Extension gegen Config
  - Get-ThumbnailCachePath: MD5-Hash-basierter Cache-Pfad

  CACHE:
  - Test-ThumbnailExists: Schnelle Cache-Pruefung (<1ms)
  - New-ThumbnailCacheFolder: .thumbs Ordner mit OneDrive-Schutz

  ONEDRIVE:
  - Test-OneDriveProtection: Registry-Schutz pruefen
  - Enable-OneDriveProtection: Registry-Schutz aktivieren

  BILD:
  - Get-ImageThumbnail: System.Drawing Resize + JPEG Encoding

  VIDEO:
  - Get-VideoThumbnail: Einzelnes Thumbnail (FFmpeg)
  - Get-VideoThumbnails: Mehrere Thumbnails (Parallel)

  DISPATCHER:
  - Get-MediaThumbnail: Routet zu Image oder Video
  - Get-MediaThumbnails: Multi-Thumbnails (nur Video)

REFACTORING v1.0.0:
  - 3 Libs zusammengefuehrt (Lib_Thumbnails + Lib_ImageThumbnails + Lib_VideoThumbnails)
  - Config wird NICHT mehr selbst geladen (Voraussetzung: start.ps1 laedt Config)
  - Keine gegenseitigen Lib-Abhaengigkeiten mehr
  - Doppelte Test-ThumbnailExists Funktion entfernt
  - Lib_Logging.ps1 wird NICHT mehr selbst geladen

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.0

.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# VORAUSSETZUNGEN (werden von start.ps1 geladen, NICHT hier!)
# - Lib_Config.ps1 muss geladen sein (Get-Config verfuegbar)
# - Lib_Logging.ps1 muss geladen sein (Get-AnonymizedLogPath verfuegbar)
# ============================================================================

# Config einmalig holen (aus bereits geladenem Lib_Config.ps1)
$script:thumbConfig = Get-Config


#region ========== HELPER FUNCTIONS ==========

function Test-IsImageFile {
    <#
    .SYNOPSIS
        Prueft ob Datei ein Bild ist

    .DESCRIPTION
        Prueft Extension gegen Config.Media.ImageExtensions.

    .PARAMETER Path
        Pfad zur Datei

    .EXAMPLE
        Test-IsImageFile -Path "C:\foto.jpg"

    .EXAMPLE
        if (Test-IsImageFile -Path $file) { "Bild!" }

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
    return $ext -in $script:thumbConfig.Media.ImageExtensions
}

function Test-IsVideoFile {
    <#
    .SYNOPSIS
        Prueft ob Datei ein Video ist

    .DESCRIPTION
        Prueft Extension gegen Config.Media.VideoExtensions.

    .PARAMETER Path
        Pfad zur Datei

    .EXAMPLE
        Test-IsVideoFile -Path "C:\video.mp4"

    .EXAMPLE
        if (Test-IsVideoFile -Path $file) { "Video!" }

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
    return $ext -in $script:thumbConfig.Media.VideoExtensions
}

function Get-ThumbnailCachePath {
    <#
    .SYNOPSIS
        Generiert Cache-Pfad fuer Thumbnail (Hash-basiert)

    .DESCRIPTION
        Erstellt MD5-Hash aus: FullPath + LastWriteTimeUtc
        Format: {CacheDir}/{Hash}.jpg
        Optionaler Index fuer Multi-Thumbnails (Videos).

    .PARAMETER MediaPath
        Pfad zur Medien-Datei

    .PARAMETER CacheDir
        Cache-Verzeichnis (.thumbs)

    .PARAMETER Index
        Optional: Index fuer Multi-Thumbnails (z.B. Video Frame 3)

    .EXAMPLE
        $path = Get-ThumbnailCachePath -MediaPath "C:\foto.jpg" -CacheDir "C:\photos\.thumbs"

    .EXAMPLE
        $path = Get-ThumbnailCachePath -MediaPath "C:\video.mp4" -CacheDir "C:\videos\.thumbs" -Index 3

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

        return (Join-Path $CacheDir $fileName)
    }
    catch {
        Write-Error "Fehler beim Generieren des Cache-Pfads: $($_.Exception.Message)"
        throw
    }
}

#endregion


#region ========== CACHE CHECK ==========

function Test-ThumbnailExists {
    <#
    .SYNOPSIS
        Schnelle Pruefung ob Thumbnail im Cache existiert (<1ms)

    .DESCRIPTION
        Prueft NUR ob der hash-basierte Cache-Pfad existiert.
        Keine Thumbnail-Generierung, kein FFmpeg, kein System.Drawing.

    .PARAMETER Path
        Pfad zur Medien-Datei

    .EXAMPLE
        $result = Test-ThumbnailExists -Path "C:\Photos\foto.jpg"
        if ($result.Exists) { # Thumbnail aus $result.ThumbnailPath liefern }

    .OUTPUTS
        PSCustomObject mit Exists (bool) und ThumbnailPath (string oder $null)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return [PSCustomObject]@{ Exists = $false; ThumbnailPath = $null }
        }

        $parentFolder = Split-Path -Parent $Path
        $cacheDir = Join-Path $parentFolder ".thumbs"

        if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
            return [PSCustomObject]@{ Exists = $false; ThumbnailPath = $null }
        }

        $thumbPath = Get-ThumbnailCachePath -MediaPath $Path -CacheDir $cacheDir

        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            return [PSCustomObject]@{ Exists = $true; ThumbnailPath = $thumbPath }
        }

        return [PSCustomObject]@{ Exists = $false; ThumbnailPath = $null }
    }
    catch {
        Write-Verbose "Test-ThumbnailExists Fehler: $($_.Exception.Message)"
        return [PSCustomObject]@{ Exists = $false; ThumbnailPath = $null }
    }
}

#endregion


#region ========== ONEDRIVE PROTECTION ==========

function New-ThumbnailCacheFolder {
    <#
    .SYNOPSIS
        Erstellt .thumbs Ordner mit OneDrive-Schutz

    .DESCRIPTION
        Erstellt lokalen Thumbnail-Cache Ordner mit Hidden + System Attributen.
        OneDrive/Windows ignoriert System-Ordner standardmaessig.

    .PARAMETER FolderPath
        Uebergeordneter Ordner (nicht der .thumbs Ordner selbst!)

    .EXAMPLE
        $cacheDir = New-ThumbnailCacheFolder -FolderPath "C:\Photos\Urlaub"

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

        if (-not (Test-Path -LiteralPath $thumbsDir)) {
            New-Item -Path $thumbsDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Cache-Ordner erstellt: $thumbsDir"
        }

        # Hidden + System Attribute setzen
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
        Prueft ob OneDrive-Schutz via Registry konfiguriert ist

    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO"

        if (-not (Test-Path $regPath)) {
            return $false
        }

        $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) { return $false }

        foreach ($prop in $properties.PSObject.Properties) {
            if ($prop.Value -eq ".thumbs\*") {
                Write-Verbose "Registry-Schutz gefunden: $($prop.Name) = .thumbs\*"
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Verbose "Fehler beim Pruefen der Registry: $($_.Exception.Message)"
        return $false
    }
}

function Enable-OneDriveProtection {
    <#
    .SYNOPSIS
        Aktiviert OneDrive-Schutz via Registry (benoetigt Admin!)

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
                    if ($num -ge $nextNumber) { $nextNumber = $num + 1 }
                }
            }
        }

        New-ItemProperty -Path $regPath -Name "$nextNumber" -Value ".thumbs\*" -PropertyType String -Force -ErrorAction Stop | Out-Null
        Write-Verbose "OneDrive-Schutz erfolgreich aktiviert"
        return $true
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "Admin-Rechte benoetigt!"
        return $false
    }
    catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return $false
    }
}

#endregion


#region ========== IMAGE THUMBNAIL ==========

function Get-ImageThumbnail {
    <#
    .SYNOPSIS
        Generiert Thumbnail fuer Foto (System.Drawing)

    .DESCRIPTION
        Erstellt optimiertes JPEG-Thumbnail mit High-Quality Settings.
        Verwendet Hash-basierten Cache. Bei Cache-Hit wird sofort zurueckgegeben.

    .PARAMETER ImagePath
        Vollstaendiger Pfad zum Bild

    .PARAMETER CacheDir
        Cache-Verzeichnis fuer Thumbnails (.thumbs)

    .PARAMETER MaxSize
        Maximale Breite/Hoehe in Pixel (Default aus Config: UI.ThumbnailSize)

    .PARAMETER Quality
        JPEG Quality 0-100 (Default aus Config: Video.ThumbnailQuality)

    .EXAMPLE
        $thumb = Get-ImageThumbnail -ImagePath "C:\foto.jpg" -CacheDir "C:\photos\.thumbs"

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

    # Defaults aus Config
    if ($MaxSize -eq 0) { $MaxSize = $script:thumbConfig.UI.ThumbnailSize }
    if ($Quality -eq 0) { $Quality = $script:thumbConfig.Video.ThumbnailQuality }

    try {
        if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
            Write-Warning "Bild nicht gefunden: $(Get-AnonymizedLogPath -FullPath $ImagePath -ProjectRoot $ProjectRoot)"
            return $null
        }

        # Cache-Pfad
        $thumbPath = Get-ThumbnailCachePath -MediaPath $ImagePath -CacheDir $CacheDir

        # Cache-Hit?
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Thumbnail aus Cache: $thumbPath"
            return $thumbPath
        }

        Write-Verbose "DEBUG: Cache-Miss - Generiere Thumbnail fuer: $ImagePath"

        # System.Drawing laden
        Add-Type -AssemblyName System.Drawing

        $fileStream = $null
        $originalImage = $null
        $thumbnail = $null
        $graphics = $null
        $memoryStream = $null

        try {
            # Bild laden
            $fileStream = [System.IO.File]::OpenRead($ImagePath)
            $originalImage = [System.Drawing.Image]::FromStream($fileStream)

            # Aspect Ratio beibehalten
            $ratio = [Math]::Min(
                ($MaxSize / $originalImage.Width),
                ($MaxSize / $originalImage.Height)
            )
            $newWidth = [int]($originalImage.Width * $ratio)
            $newHeight = [int]($originalImage.Height * $ratio)

            Write-Verbose "Original: $($originalImage.Width)x$($originalImage.Height) -> Thumbnail: ${newWidth}x${newHeight}"

            # High-Quality Resize
            $thumbnail = [System.Drawing.Bitmap]::new($newWidth, $newHeight)
            $graphics = [System.Drawing.Graphics]::FromImage($thumbnail)
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.DrawImage($originalImage, 0, 0, $newWidth, $newHeight)

            # Ressourcen freigeben VOR Save
            $graphics.Dispose(); $graphics = $null
            $originalImage.Dispose(); $originalImage = $null
            $fileStream.Close(); $fileStream.Dispose(); $fileStream = $null

            # JPEG Encoder
            $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                Where-Object { $_.MimeType -eq 'image/jpeg' } |
                Select-Object -First 1
            $encoderParams = [System.Drawing.Imaging.EncoderParameters]::new(1)
            $encoderParams.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
                [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality
            )

            # In MemoryStream speichern
            $memoryStream = [System.IO.MemoryStream]::new()
            $thumbnail.Save($memoryStream, $jpegCodec, $encoderParams)
            $fileBytes = $memoryStream.ToArray()

            # Alles freigeben
            $memoryStream.Dispose(); $memoryStream = $null
            $thumbnail.Dispose(); $thumbnail = $null

            # GC vor File-Write (verhindert File-Lock bei GDI+)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()

            # Datei schreiben
            [System.IO.File]::WriteAllBytes($thumbPath, $fileBytes)
            Write-Verbose "Thumbnail gespeichert: $thumbPath"

        } finally {
            if ($memoryStream) { $memoryStream.Dispose() }
            if ($graphics) { $graphics.Dispose() }
            if ($thumbnail) { $thumbnail.Dispose() }
            if ($originalImage) { $originalImage.Dispose() }
            if ($fileStream) { $fileStream.Close(); $fileStream.Dispose() }
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()
        }

        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            return $thumbPath
        }

        Write-Warning "Thumbnail wurde nicht erstellt: $thumbPath"
        return $null
    }
    catch {
        Write-Error "Fehler beim Bild-Thumbnail: $($_.Exception.Message)"
        return $null
    }
}

#endregion


#region ========== VIDEO THUMBNAILS ==========

function Get-VideoThumbnail {
    <#
    .SYNOPSIS
        Generiert EINZELNES Thumbnail fuer Video (Legacy-Kompatibilitaet)

    .DESCRIPTION
        Erstellt ein Thumbnail an ThumbnailStartPercent Position.
        Wrapper um Get-VideoThumbnails mit Count=1.

    .PARAMETER VideoPath
        Vollstaendiger Pfad zum Video

    .PARAMETER CacheDir
        Cache-Verzeichnis (.thumbs)

    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (fuer FFmpeg)

    .PARAMETER MaxSize
        Maximale Breite/Hoehe (Default aus Config)

    .PARAMETER ThumbnailQuality
        JPEG Quality 0-100 (Default aus Config)

    .PARAMETER ThumbnailStartPercent
        Position im Video in Prozent (Default aus Config)

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

    # Defaults aus Config
    if ($MaxSize -eq 0) { $MaxSize = $script:thumbConfig.UI.ThumbnailSize }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = $script:thumbConfig.Video.ThumbnailQuality }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = $script:thumbConfig.Video.ThumbnailStartPercent }

    $thumbs = Get-VideoThumbnails `
        -VideoPath $VideoPath `
        -CacheDir $CacheDir `
        -ScriptRoot $ScriptRoot `
        -MaxSize $MaxSize `
        -ThumbnailQuality $ThumbnailQuality `
        -ThumbnailCount 1 `
        -ThumbnailStartPercent $ThumbnailStartPercent `
        -ThumbnailEndPercent $ThumbnailStartPercent

    if ($thumbs -and $thumbs.Count -gt 0) {
        return $thumbs[0].Path
    }
    return $null
}

function Get-VideoThumbnails {
    <#
    .SYNOPSIS
        Generiert MEHRERE Thumbnails fuer Video (mit Parallel-Processing)

    .DESCRIPTION
        Erstellt mehrere Thumbnails an zufaelligen, sortierten Positionen.
        Nutzt PowerShell 7 Parallel-Processing wenn UseParallelProcessing=true.

    .PARAMETER VideoPath
        Vollstaendiger Pfad zum Video

    .PARAMETER CacheDir
        Cache-Verzeichnis (.thumbs)

    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (fuer FFmpeg)

    .PARAMETER MaxSize
        Maximale Breite/Hoehe (Default aus Config)

    .PARAMETER ThumbnailQuality
        JPEG Quality 0-100 (Default aus Config)

    .PARAMETER ThumbnailCount
        Anzahl Thumbnails (Default aus Config)

    .PARAMETER ThumbnailStartPercent
        Start-Position in Prozent (Default aus Config)

    .PARAMETER ThumbnailEndPercent
        End-Position in Prozent (Default aus Config)

    .EXAMPLE
        $thumbs = Get-VideoThumbnails -VideoPath "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot

    .EXAMPLE
        $thumbs = Get-VideoThumbnails -VideoPath "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot -ThumbnailCount 5

    .OUTPUTS
        Array of PSCustomObject - Properties: Path, Position, Index
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

    # Defaults aus Config
    if ($MaxSize -eq 0) { $MaxSize = $script:thumbConfig.UI.ThumbnailSize }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = $script:thumbConfig.Video.ThumbnailQuality }
    if ($ThumbnailCount -eq 0) { $ThumbnailCount = $script:thumbConfig.Video.ThumbnailCount }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = $script:thumbConfig.Video.ThumbnailStartPercent }
    if ($ThumbnailEndPercent -eq 0) { $ThumbnailEndPercent = $script:thumbConfig.Video.ThumbnailEndPercent }

    $useParallel = $ThumbnailCount -gt 1 -and $script:thumbConfig.Performance.UseParallelProcessing
    $maxParallelJobs = $script:thumbConfig.Performance.MaxParallelJobs

    try {
        if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
            Write-Warning "Video nicht gefunden: $(Get-AnonymizedLogPath -FullPath $VideoPath -ProjectRoot $ProjectRoot)"
            return @()
        }

        # CacheDir sicherstellen
        if (-not (Test-Path -LiteralPath $CacheDir -PathType Container)) {
            New-Item -Path $CacheDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        # FFmpeg-Pfad
        $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        if (-not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf)) {
            Write-Warning "FFmpeg nicht gefunden: $ffmpegPath"
            return @()
        }

        $mode = if ($useParallel) { "PARALLEL ($maxParallelJobs threads)" } else { "SEQUENTIAL" }
        Write-Verbose "Generiere $ThumbnailCount Video-Thumbnails ($mode) fuer: $VideoPath"

        # Video-Dauer ermitteln
        $durationArgs = @("-i", $VideoPath, "-hide_banner")
        $durationOutput = & $ffmpegPath $durationArgs 2>&1 | Out-String

        $totalSeconds = 0
        if ($durationOutput -match 'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})') {
            $totalSeconds = ([int]$matches[1] * 3600) + ([int]$matches[2] * 60) + [int]$matches[3]
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

        # Zufaellige Positionen generieren + sortieren
        $random = [System.Random]::new()
        $positions = @()
        for ($i = 0; $i -lt $ThumbnailCount; $i++) {
            $positions += $random.Next($startSeconds, $endSeconds + 1)
        }
        $positions = $positions | Sort-Object

        Write-Verbose "Positionen (s): $($positions -join ', ')"

        # FFmpeg Quality-Mapping (0-100 → 2-31)
        $qValue = [Math]::Max(2, [Math]::Min(31, 31 - [int](($ThumbnailQuality / 100.0) * 29)))

        # === PARALLEL MODE ===
        if ($useParallel) {
            Write-Verbose "Parallel-Processing mit $maxParallelJobs Threads"

            $indexMap = @{}
            for ($i = 0; $i -lt $positions.Count; $i++) {
                $indexMap[$positions[$i]] = $i + 1
            }

            $results = $positions | ForEach-Object -ThrottleLimit $maxParallelJobs -Parallel {
                $posSeconds = $_
                $index = ($using:indexMap)[$posSeconds]

                $VideoPath = $using:VideoPath
                $CacheDir = $using:CacheDir
                $ffmpegPath = $using:ffmpegPath
                $MaxSize = $using:MaxSize
                $qValue = $using:qValue

                try {
                    $seekTime = [TimeSpan]::FromSeconds($posSeconds).ToString('hh\:mm\:ss')

                    # Cache-Pfad mit Index (inline statt Lib-Aufruf im Runspace)
                    $fileInfo = [System.IO.FileInfo]::new($VideoPath)
                    $hashInput = "$($fileInfo.FullName)-$($fileInfo.LastWriteTimeUtc.Ticks)"
                    $hash = [System.BitConverter]::ToString(
                        [System.Security.Cryptography.MD5]::Create().ComputeHash(
                            [System.Text.Encoding]::UTF8.GetBytes($hashInput)
                        )
                    ).Replace('-', '').ToLowerInvariant()
                    $thumbPath = Join-Path $CacheDir "${hash}_${index}.jpg"

                    # Cache-Hit?
                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        return [PSCustomObject]@{ Path = $thumbPath; Position = $posSeconds; Index = $index }
                    }

                    # FFmpeg
                    $ffmpegArgs = @(
                        "-ss", $seekTime, "-i", $VideoPath,
                        "-frames:v", "1", "-update", "1",
                        "-vf", "scale=${MaxSize}:${MaxSize}:force_original_aspect_ratio=decrease",
                        "-q:v", "$qValue", "-y", $thumbPath
                    )

                    $process = Start-Process -FilePath $ffmpegPath -ArgumentList $ffmpegArgs -Wait -NoNewWindow -PassThru

                    if ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $thumbPath -PathType Leaf)) {
                        return [PSCustomObject]@{ Path = $thumbPath; Position = $posSeconds; Index = $index }
                    }
                    return $null
                }
                catch {
                    return $null
                }
            }

            $results = @($results | Where-Object { $_ -ne $null } | Sort-Object Index)
        }
        # === SEQUENTIAL MODE ===
        else {
            Write-Verbose "Sequential Processing"

            $results = @()
            $index = 1

            foreach ($posSeconds in $positions) {
                try {
                    $seekTime = [TimeSpan]::FromSeconds($posSeconds).ToString('hh\:mm\:ss')
                    $thumbPath = Get-ThumbnailCachePath -MediaPath $VideoPath -CacheDir $CacheDir -Index $index

                    # Cache-Hit?
                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        Write-Verbose "Thumbnail $index aus Cache"
                        $results += [PSCustomObject]@{ Path = $thumbPath; Position = $posSeconds; Index = $index }
                        $index++
                        continue
                    }

                    Write-Verbose "Erstelle Thumbnail $index bei $seekTime"

                    $ffmpegArgs = @(
                        "-ss", $seekTime, "-i", $VideoPath,
                        "-frames:v", "1", "-update", "1",
                        "-vf", "scale=${MaxSize}:${MaxSize}:force_original_aspect_ratio=decrease",
                        "-q:v", "$qValue", "-y", $thumbPath
                    )

                    $ffmpegOutput = & $ffmpegPath $ffmpegArgs 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "FFmpeg Fehler bei Thumbnail $index (Exit: $LASTEXITCODE)"
                        $index++
                        continue
                    }

                    if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
                        $results += [PSCustomObject]@{ Path = $thumbPath; Position = $posSeconds; Index = $index }
                    }
                    $index++
                }
                catch {
                    Write-Warning "Fehler bei Thumbnail ${index}: $($_.Exception.Message)"
                    $index++
                }
            }
        }

        Write-Verbose "Erfolgreich: $($results.Count) von $ThumbnailCount Thumbnails"
        return $results
    }
    catch {
        Write-Error "Video-Thumbnails Fehler: $($_.Exception.Message)"
        return @()
    }
}

#endregion


#region ========== DISPATCHER (Universal) ==========

function Get-MediaThumbnail {
    <#
    .SYNOPSIS
        Universelle Thumbnail-Generierung fuer Fotos UND Videos

    .DESCRIPTION
        Routet automatisch zu Image oder Video Thumbnail-Generierung.
        Fuer Multi-Thumbnails (Videos): Verwende Get-MediaThumbnails!

    .PARAMETER Path
        Pfad zur Medien-Datei

    .PARAMETER ScriptRoot
        Projekt-Root (fuer FFmpeg bei Videos)

    .PARAMETER MaxSize
        Maximale Groesse (Default aus Config)

    .PARAMETER Quality
        JPEG-Qualitaet (Default aus Config)

    .PARAMETER ThumbnailQuality
        Video: JPEG-Qualitaet (Default aus Config)

    .PARAMETER ThumbnailStartPercent
        Video: Position in Prozent (Default aus Config)

    .EXAMPLE
        $thumb = Get-MediaThumbnail -Path "C:\foto.jpg" -ScriptRoot $PSScriptRoot

    .EXAMPLE
        $thumb = Get-MediaThumbnail -Path "C:\video.mp4" -ScriptRoot $PSScriptRoot

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

    # Defaults aus Config
    if ($MaxSize -eq 0) { $MaxSize = $script:thumbConfig.UI.ThumbnailSize }
    if ($Quality -eq 0) { $Quality = $script:thumbConfig.Video.ThumbnailQuality }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = $script:thumbConfig.Video.ThumbnailQuality }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = $script:thumbConfig.Video.ThumbnailStartPercent }

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
                Write-Warning "ScriptRoot benoetigt fuer Video-Thumbnails"
                return $null
            }
            return Get-VideoThumbnail -VideoPath $Path -CacheDir $cacheDir -ScriptRoot $ScriptRoot -MaxSize $MaxSize -ThumbnailQuality $ThumbnailQuality -ThumbnailStartPercent $ThumbnailStartPercent
        }
        else {
            Write-Warning "Unbekannter Dateityp: $Path"
            return $null
        }
    }
    catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return $null
    }
}

function Get-MediaThumbnails {
    <#
    .SYNOPSIS
        Multi-Thumbnail Generierung (nur Videos)

    .DESCRIPTION
        Erstellt mehrere Thumbnails fuer Videos.
        Fuer Bilder: Verwende Get-MediaThumbnail (nur 1 Thumbnail)!

    .PARAMETER Path
        Pfad zum Video

    .PARAMETER ScriptRoot
        Projekt-Root (fuer FFmpeg)

    .PARAMETER MaxSize
        Maximale Groesse (Default aus Config)

    .PARAMETER ThumbnailQuality
        JPEG Quality (Default aus Config)

    .PARAMETER ThumbnailCount
        Anzahl Thumbnails (Default aus Config)

    .PARAMETER ThumbnailStartPercent
        Start-Position (Default aus Config)

    .PARAMETER ThumbnailEndPercent
        End-Position (Default aus Config)

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

    # Defaults aus Config
    if ($MaxSize -eq 0) { $MaxSize = $script:thumbConfig.UI.ThumbnailSize }
    if ($ThumbnailQuality -eq 0) { $ThumbnailQuality = $script:thumbConfig.Video.ThumbnailQuality }
    if ($ThumbnailCount -eq 0) { $ThumbnailCount = $script:thumbConfig.Video.ThumbnailCount }
    if ($ThumbnailStartPercent -eq 0) { $ThumbnailStartPercent = $script:thumbConfig.Video.ThumbnailStartPercent }
    if ($ThumbnailEndPercent -eq 0) { $ThumbnailEndPercent = $script:thumbConfig.Video.ThumbnailEndPercent }

    try {
        if (-not (Test-IsVideoFile -Path $Path)) {
            Write-Warning "Multi-Thumbnails nur fuer Videos: $Path"
            return @()
        }

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
    }
    catch {
        Write-Error "Fehler: $($_.Exception.Message)"
        return @()
    }
}

#endregion