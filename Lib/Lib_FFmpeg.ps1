<#
.SYNOPSIS
    FFmpeg Helper für Foto_Viewer_V2

.DESCRIPTION
    Prüft FFmpeg-Installation und generiert Video-Thumbnails.
    Thumbnails werden in .thumbs/ gecacht.

.EXAMPLE
    if (Test-FFmpegInstalled) {
        $thumbPath = Get-VideoThumbnail -VideoPath "video.mp4" -CacheDir ".thumbs"
    }

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-FFmpegInstalled {
    <#
    .SYNOPSIS
        Prüft ob FFmpeg installiert ist
    
    .EXAMPLE
        if (Test-FFmpegInstalled) { Write-Host "FFmpeg OK" }
    
    .OUTPUTS
        Boolean - True wenn FFmpeg verfügbar
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $null = Get-Command ffmpeg -ErrorAction Stop
        Write-Verbose "FFmpeg gefunden"
        return $true
    } catch {
        Write-Verbose "FFmpeg nicht gefunden"
        return $false
    }
}

function Get-VideoThumbnail {
    <#
    .SYNOPSIS
        Generiert Thumbnail aus Video (oder holt aus Cache)
    
    .PARAMETER VideoPath
        Vollständiger Pfad zur Video-Datei
    
    .PARAMETER CacheDir
        Cache-Verzeichnis für Thumbnails
    
    .PARAMETER TimePosition
        Position im Video (Default: 00:00:01)
    
    .EXAMPLE
        $thumb = Get-VideoThumbnail -VideoPath "C:\video.mp4" -CacheDir "C:\cache"
    
    .OUTPUTS
        String - Pfad zum Thumbnail oder $null bei Fehler
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$CacheDir,
        
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
        
        # Thumbnail-Name (Hash aus Pfad + ModifiedDate)
        $fileInfo = [System.IO.FileInfo]::new($VideoPath)
        $hashInput = "$VideoPath-$($fileInfo.LastWriteTimeUtc.Ticks)"
        $hash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($hashInput)
            )
        ).Replace('-', '').ToLowerInvariant()
        
        $thumbPath = Join-Path $CacheDir "$hash.jpg"
        
        # Cache-Hit?
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Thumbnail aus Cache: $thumbPath"
            return $thumbPath
        }
        
        # FFmpeg verfügbar?
        if (-not (Test-FFmpegInstalled)) {
            Write-Warning "FFmpeg nicht installiert - kann kein Thumbnail generieren"
            return $null
        }
        
        # Thumbnail generieren
        Write-Verbose "Generiere Thumbnail für: $VideoPath"
        
        $ffmpegArgs = @(
            '-ss', $TimePosition
            '-i', $VideoPath
            '-vframes', '1'
            '-q:v', '2'
            '-y'
            $thumbPath
        )
        
        $process = Start-Process -FilePath 'ffmpeg' -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Warning "FFmpeg Fehler (Exit: $($process.ExitCode)) für: $VideoPath"
            return $null
        }
        
        if (Test-Path -LiteralPath $thumbPath -PathType Leaf) {
            Write-Verbose "Thumbnail generiert: $thumbPath"
            return $thumbPath
        } else {
            Write-Warning "Thumbnail nicht erstellt: $thumbPath"
            return $null
        }
        
    } catch {
        Write-Error "Fehler beim Generieren von Thumbnail: $($_.Exception.Message)"
        return $null
    }
}