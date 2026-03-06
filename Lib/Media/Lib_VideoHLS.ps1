<#
ManifestHint:
  ExportFunctions = @("Convert-VideoToHLS", "Get-HLSPlaylistPath", "Test-HLSExists")
  Description     = "HLS Video-Konvertierung mit FFmpeg"
  Category        = "Media"
  Tags            = @("HLS","FFmpeg","Video","Streaming")
  Dependencies    = @("FFmpeg","Lib_Config.ps1")

Zweck:
  - On-Demand HLS-Konvertierung (Video → .m3u8 + .ts Chunks)
  - Config-basiert (Video.UseHLS, HLSSegmentDuration, ConversionPreset)
  - FFmpeg-Pfad aus Projekt-Root (ffmpeg\ffmpeg.exe)
  - Temp-Ordner aus Config (Paths.TempFolder)

Funktionen:
  - Convert-VideoToHLS: Konvertiert Video zu HLS-Segmenten
  - Get-HLSPlaylistPath: Gibt Pfad zur .m3u8 Playlist zurück
  - Test-HLSExists: Prüft ob HLS-Version bereits existiert

Abhängigkeiten:
  - FFmpeg (ffmpeg\ffmpeg.exe)
  - Lib_Config.ps1 (Get-Config)

.NOTES
    Autor: Herbert
    Version: 0.1.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config laden
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

$configPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"
if (Test-Path -LiteralPath $configPath) {
    . $configPath
} else {
    throw "FEHLER: Lib_Config.ps1 nicht gefunden: $configPath"
}

function Test-HLSExists {
    <#
    .SYNOPSIS
        Prüft ob HLS-Version eines Videos bereits existiert
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER RootFull
        Root-Ordner der Mediathek
    
    .EXAMPLE
        Test-HLSExists -VideoPath "C:\Media\video.mkv" -RootFull "C:\Media"
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$RootFull
    )
    
    $playlistPath = Get-HLSPlaylistPath -VideoPath $VideoPath -RootFull $RootFull
    return (Test-Path -LiteralPath $playlistPath -PathType Leaf)
}

function Get-HLSPlaylistPath {
    <#
    .SYNOPSIS
        Gibt den Pfad zur HLS-Playlist (.m3u8) zurück
    
    .DESCRIPTION
        Berechnet den Pfad wo die HLS-Playlist gespeichert wird.
        Struktur: RootFull\.temp\<hash>\playlist.m3u8
        Hash basiert auf relativem Pfad des Videos.
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER RootFull
        Root-Ordner der Mediathek
    
    .EXAMPLE
        Get-HLSPlaylistPath -VideoPath "C:\Media\sub\video.mkv" -RootFull "C:\Media"
        # Returns: "C:\Media\.temp\a1b2c3d4\playlist.m3u8"
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$RootFull
    )
    
    $config = Get-Config
    $tempFolder = $config.Paths.TempFolder
    
    # Hash aus Dateiname (eindeutig pro Video)
    $fileName = [System.IO.Path]::GetFileName($VideoPath)
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($fileName.ToLower())
    )
    $hash = [BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
    
    # .temp im gleichen Ordner wie das Video (wie .thumbs)
    $videoDir = Split-Path -Parent $VideoPath
    $hlsDir = Join-Path $videoDir (Join-Path $tempFolder $hash)
    return (Join-Path $hlsDir "playlist.m3u8")
}

function Start-HLSConversion {
    <#
    .SYNOPSIS
        Startet HLS-Konvertierung im Hintergrund (non-blocking)
    
    .DESCRIPTION
        Startet FFmpeg als separaten Prozess und gibt sofort zurück.
        FFmpeg schreibt Chunks progressiv — Browser kann schon abspielen
        während Konvertierung noch läuft.
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER RootFull
        Root-Ordner der Mediathek
    
    .PARAMETER ScriptRoot
        Projekt-Root (für FFmpeg-Pfad)
    
    .OUTPUTS
        [string] Pfad zur .m3u8 Playlist (wird von FFmpeg erstellt)
        $null bei Fehler
    
    .NOTES
        Autor: Herbert
        Version: 0.2.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    try {
        $config = Get-Config
        
        # FFmpeg-Pfad
        $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        
        if (-not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf)) {
            Write-Error "FFmpeg nicht gefunden: $ffmpegPath"
            return $null
        }
        
        # Playlist-Pfad berechnen
        $playlistPath = Get-HLSPlaylistPath -VideoPath $VideoPath -RootFull $RootFull
        $hlsDir = Split-Path -Parent $playlistPath
        
        # Bereits konvertiert?
        if (Test-Path -LiteralPath $playlistPath -PathType Leaf) {
            Write-Verbose "HLS bereits vorhanden: $playlistPath"
            return $playlistPath
        }
        
        # HLS-Ordner erstellen (mit verstecktem .temp)
        $tempRoot = Join-Path (Split-Path -Parent $VideoPath) $config.Paths.TempFolder
        if (-not (Test-Path -LiteralPath $hlsDir)) {
            New-Item -ItemType Directory -Path $hlsDir -Force | Out-Null
            Write-Verbose "HLS-Ordner erstellt: $hlsDir"
        }
        if (Test-Path -LiteralPath $tempRoot) {
            $tempDirInfo = Get-Item -LiteralPath $tempRoot -Force
            if (-not ($tempDirInfo.Attributes -band [System.IO.FileAttributes]::Hidden)) {
                $tempDirInfo.Attributes = $tempDirInfo.Attributes -bor [System.IO.FileAttributes]::Hidden
                Write-Verbose ".temp versteckt: $tempRoot"
            }
        }
        
        # Config-Werte
        $segmentDuration = $config.Video.HLSSegmentDuration
        $preset = $config.Video.ConversionPreset
        $segmentPattern = Join-Path $hlsDir "chunk_%03d.ts"
        
        Write-Verbose "HLS-Konvertierung (Background): $VideoPath"
        Write-Verbose "  Segment: ${segmentDuration}s, Preset: $preset"
        
        # FFmpeg als separaten Prozess starten (NICHT warten!)
        # ArgumentList als einzelner String mit korrektem Quoting
        $argString = "-i `"$VideoPath`" -c:v libx264 -preset $preset -c:a aac -b:a 128k -f hls -hls_time $segmentDuration -hls_list_size 0 -hls_segment_filename `"$segmentPattern`" -y `"$playlistPath`""
        
        Start-Process -FilePath $ffmpegPath -ArgumentList $argString -WindowStyle Hidden -PassThru | Out-Null
        
        Write-Host "  → HLS-Konvertierung gestartet (Background)" -ForegroundColor Yellow
        
        return $playlistPath
    }
    catch {
        Write-Error "Fehler bei Start-HLSConversion: $_"
        return $null
    }
}
function Convert-VideoToHLS {
    <#
    .SYNOPSIS
        Konvertiert Video zu HLS-Segmenten mit FFmpeg
    
    .DESCRIPTION
        Konvertiert ein Video zu HLS-Format (.m3u8 + .ts Chunks).
        Alle Settings aus Config:
        - Video.HLSSegmentDuration (Chunk-Länge)
        - Video.ConversionPreset (FFmpeg Preset)
        - Paths.TempFolder (Ausgabe-Ordner)
    
    .PARAMETER VideoPath
        Vollständiger Pfad zum Video
    
    .PARAMETER RootFull
        Root-Ordner der Mediathek
    
    .PARAMETER ScriptRoot
        Projekt-Root (für FFmpeg-Pfad)
    
    .EXAMPLE
        $playlist = Convert-VideoToHLS -VideoPath "C:\Media\video.mkv" -RootFull "C:\Media" -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        [string] Pfad zur .m3u8 Playlist oder $null bei Fehler
    
    .NOTES
        Autor: Herbert
        Version: 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    try {
        $config = Get-Config
        
        # FFmpeg-Pfad
        $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
        
        if (-not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf)) {
            Write-Error "FFmpeg nicht gefunden: $ffmpegPath"
            return $null
        }
        
        # Playlist-Pfad berechnen
        $playlistPath = Get-HLSPlaylistPath -VideoPath $VideoPath -RootFull $RootFull
        $hlsDir = Split-Path -Parent $playlistPath
        
        # Bereits konvertiert?
        if (Test-Path -LiteralPath $playlistPath -PathType Leaf) {
            Write-Verbose "HLS bereits vorhanden: $playlistPath"
            return $playlistPath
        }
        
        # HLS-Ordner erstellen
        if (-not (Test-Path -LiteralPath $hlsDir)) {
            New-Item -ItemType Directory -Path $hlsDir -Force | Out-Null
            Write-Verbose "HLS-Ordner erstellt: $hlsDir"
            
            # .temp Ordner verstecken (wie .thumbs)
            $tempDir = Join-Path (Split-Path -Parent $hlsDir) ""
            $tempParent = Split-Path -Parent $hlsDir
            # Den .temp Ordner selbst verstecken (eine Ebene über dem Hash)
            $tempRoot = Join-Path (Split-Path -Parent $VideoPath) $config.Paths.TempFolder
            if (Test-Path -LiteralPath $tempRoot) {
                $dirInfo = Get-Item -LiteralPath $tempRoot -Force
                if (-not ($dirInfo.Attributes -band [System.IO.FileAttributes]::Hidden)) {
                    $dirInfo.Attributes = $dirInfo.Attributes -bor [System.IO.FileAttributes]::Hidden
                    Write-Verbose ".temp Ordner versteckt: $tempRoot"
                }
            }
        }
        
        # Config-Werte
        $segmentDuration = $config.Video.HLSSegmentDuration
        $preset = $config.Video.ConversionPreset
        
        Write-Verbose "HLS-Konvertierung: $VideoPath"
        Write-Verbose "  Segment: ${segmentDuration}s, Preset: $preset"
        Write-Verbose "  Output: $hlsDir"
        
        # Segment-Pattern
        $segmentPattern = Join-Path $hlsDir "chunk_%03d.ts"
        
        # FFmpeg Args
        $ffmpegArgs = @(
            '-i', $VideoPath
            '-c:v', 'libx264'
            '-preset', $preset
            '-c:a', 'aac'
            '-b:a', '128k'
            '-f', 'hls'
            '-hls_time', $segmentDuration
            '-hls_list_size', '0'
            '-hls_segment_filename', $segmentPattern
            '-y'
            $playlistPath
        )
        
        Write-Host "  → HLS-Konvertierung gestartet..." -ForegroundColor Yellow
        
        # FFmpeg synchron (& Operator = sicher mit Leerzeichen)
        & $ffmpegPath @ffmpegArgs 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -ne 0) {
            Write-Warning "FFmpeg HLS beendet mit Exit Code: $exitCode"
        }
        
        if (-not (Test-Path -LiteralPath $playlistPath -PathType Leaf)) {
            Write-Error "Playlist nicht erstellt: $playlistPath"
            return $null
        }
        
        Write-Host "  → HLS-Konvertierung abgeschlossen" -ForegroundColor Green
        
        return $playlistPath
    }
    catch {
        Write-Error "Fehler bei HLS-Konvertierung: $_"
        return $null
    }
}