<#
.SYNOPSIS
    FFmpeg Helper für Foto_Viewer_V2

.DESCRIPTION
    Prüft FFmpeg-Installation (Projekt-Ordner) und generiert Video-Thumbnails.
    Thumbnails werden in .thumbs/ gecacht.

.EXAMPLE
    $ffmpegPath = Test-FFmpegInstalled -ScriptRoot $PSScriptRoot
    if ($ffmpegPath) {
        $thumbPath = Get-VideoThumbnail -VideoPath "video.mp4" -CacheDir ".thumbs" -ScriptRoot $PSScriptRoot
    }

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-FFmpegInstalled {
    <#
    .SYNOPSIS
        Prüft ob FFmpeg im Projekt-Ordner existiert
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad
    
    .EXAMPLE
        $ffmpegPath = Test-FFmpegInstalled -ScriptRoot $PSScriptRoot
        if ($ffmpegPath) { Write-Host "FFmpeg OK: $ffmpegPath" }
    
    .OUTPUTS
        String - Pfad zu ffmpeg.exe oder $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    try {
        $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        
        if (Test-Path -LiteralPath $ffmpegPath -PathType Leaf) {
            Write-Verbose "FFmpeg gefunden: $ffmpegPath"
            return $ffmpegPath
        } else {
            Write-Warning "FFmpeg nicht gefunden in: $ffmpegPath"
            return $null
        }
    } catch {
        Write-Warning "Fehler beim Suchen von FFmpeg: $($_.Exception.Message)"
        return $null
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
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg)
    
    .PARAMETER TimePosition
        Position im Video (Default: 00:00:01)
    
    .EXAMPLE
        $thumb = Get-VideoThumbnail -VideoPath "C:\video.mp4" -CacheDir "C:\cache" -ScriptRoot $PSScriptRoot
    
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
        
        [Parameter(Mandatory)]
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
        $ffmpegExe = Test-FFmpegInstalled -ScriptRoot $ScriptRoot
        if (-not $ffmpegExe) {
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
        
        $process = Start-Process -FilePath $ffmpegExe -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru
        
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