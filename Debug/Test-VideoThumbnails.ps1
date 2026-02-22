# Debug-Script: Test-VideoThumbnails.ps1
<#
.SYNOPSIS
    Debuggt Video-Thumbnail-Generierung
    
.DESCRIPTION
    Testet alle Komponenten des Video-Thumbnail-Systems:
    - FFmpeg Verfügbarkeit
    - Video-Erkennung
    - Thumbnail-Generierung
    - Cache-Validierung
    
.PARAMETER VideoPath
    Optional: Pfad zum Video (sonst wird Dialog geöffnet)
    
.EXAMPLE
    .\Debug\Test-VideoThumbnails.ps1
    # Öffnet Datei-Dialog
    
.EXAMPLE
    .\Debug\Test-VideoThumbnails.ps1 -VideoPath "D:\Videos\test.mp4"
    # Direkter Pfad

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [string]$VideoPath,
    
    [Parameter()]
    [int]$ThumbnailSize = 200,
    
    [Parameter()]
    [int]$ThumbnailQuality = 85,
    
    [Parameter()]
    [int]$ThumbnailStartPercent = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-Root ermitteln (Debug-Ordner)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Projekt-Root (eine Ebene höher)
$ScriptRoot = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VIDEO-THUMBNAIL DEBUG" -ForegroundColor White
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Libs laden
Write-Host "SCHRITT 1: Libs laden..." -ForegroundColor Yellow
try {
    . (Join-Path $ScriptRoot "Lib\Media\Lib_Thumbnails.ps1")
    Write-Host "✓ Lib_Thumbnails.ps1 geladen" -ForegroundColor Green
} catch {
    Write-Host "✗ FEHLER beim Laden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Video-Datei wählen (falls nicht angegeben)
if ([string]::IsNullOrWhiteSpace($VideoPath)) {
    Write-Host ""
    Write-Host "Bitte Video-Datei wählen..." -ForegroundColor Yellow
    
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = "Video-Datei für Thumbnail-Test wählen"
    $dialog.Filter = "Video-Dateien (*.mp4;*.avi;*.mkv;*.mov;*.wmv)|*.mp4;*.avi;*.mkv;*.mov;*.wmv;*.flv;*.webm;*.m4v;*.mpg;*.mpeg;*.3gp|Alle Dateien (*.*)|*.*"
    $dialog.Multiselect = $false
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $VideoPath = $dialog.FileName
        Write-Host "✓ Gewählt: $VideoPath" -ForegroundColor Green
    } else {
        Write-Host "✗ Keine Datei gewählt - Abbruch" -ForegroundColor Red
        exit 0
    }
}

# Video-Datei prüfen
Write-Host ""
Write-Host "SCHRITT 2: Video-Datei prüfen..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $VideoPath -PathType Leaf)) {
    Write-Host "✗ Video nicht gefunden: $VideoPath" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Video existiert: $VideoPath" -ForegroundColor Green

$ext = [System.IO.Path]::GetExtension($VideoPath).ToLowerInvariant()
Write-Host "  Extension: $ext" -ForegroundColor Gray

if (-not (Test-IsVideoFile -Path $VideoPath)) {
    Write-Host "✗ Datei wird NICHT als Video erkannt!" -ForegroundColor Red
    Write-Host "  Unterstützte Extensions: .mp4, .avi, .mkv, .mov, .wmv, .flv, .webm, .m4v, .mpg, .mpeg, .3gp" -ForegroundColor Gray
    exit 1
}
Write-Host "✓ Datei als Video erkannt" -ForegroundColor Green

# FFmpeg prüfen
Write-Host ""
Write-Host "SCHRITT 3: FFmpeg prüfen..." -ForegroundColor Yellow
$ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
if (-not (Test-Path -LiteralPath $ffmpegPath -PathType Leaf)) {
    Write-Host "✗ FFmpeg nicht gefunden: $ffmpegPath" -ForegroundColor Red
    Write-Host "  Bitte ffmpeg.exe in 'ffmpeg' Ordner ablegen!" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ FFmpeg gefunden: $ffmpegPath" -ForegroundColor Green

# FFmpeg Version
try {
    $versionOutput = & $ffmpegPath -version 2>&1 | Select-Object -First 1
    Write-Host "  Version: $versionOutput" -ForegroundColor Gray
} catch {
    Write-Host "⚠ Konnte Version nicht abrufen" -ForegroundColor Yellow
}

# Cache-Dir prüfen
Write-Host ""
Write-Host "SCHRITT 4: Cache-Verzeichnis..." -ForegroundColor Yellow
$parentFolder = Split-Path -Parent $VideoPath
$thumbsDir = Join-Path $parentFolder ".thumbs"
Write-Host "  Parent: $parentFolder" -ForegroundColor Gray
Write-Host "  .thumbs Pfad: $thumbsDir" -ForegroundColor Gray

if (Test-Path -LiteralPath $thumbsDir) {
    Write-Host "✓ .thumbs existiert bereits" -ForegroundColor Green
    
    $existingThumbs = @(Get-ChildItem -LiteralPath $thumbsDir -Filter "*.jpg" -File -ErrorAction SilentlyContinue)
    if ($existingThumbs.Count -gt 0) {
        Write-Host "  Vorhandene Thumbnails: $($existingThumbs.Count)" -ForegroundColor Gray
    }
} else {
    Write-Host "  .thumbs wird erstellt bei Thumbnail-Gen" -ForegroundColor Gray
}

# Thumbnail generieren (mit VERBOSE)
Write-Host ""
Write-Host "SCHRITT 5: Thumbnail generieren..." -ForegroundColor Yellow
Write-Host "Parameter:" -ForegroundColor Gray
Write-Host "  MaxSize: $ThumbnailSize" -ForegroundColor Gray
Write-Host "  Quality: $ThumbnailQuality" -ForegroundColor Gray
Write-Host "  StartPercent: $ThumbnailStartPercent%" -ForegroundColor Gray
Write-Host ""

try {
    $VerbosePreference = 'Continue'
    
    $thumbPath = Get-VideoThumbnail `
        -VideoPath $VideoPath `
        -CacheDir $thumbsDir `
        -ScriptRoot $ScriptRoot `
        -MaxSize $ThumbnailSize `
        -ThumbnailQuality $ThumbnailQuality `
        -ThumbnailStartPercent $ThumbnailStartPercent
    
    $VerbosePreference = 'SilentlyContinue'
    
    Write-Host ""
    if ($thumbPath) {
        Write-Host "✓ ERFOLG: Thumbnail erstellt!" -ForegroundColor Green
        Write-Host "  Pfad: $thumbPath" -ForegroundColor Gray
        
        if (Test-Path -LiteralPath $thumbPath) {
            $thumbInfo = Get-Item -LiteralPath $thumbPath
            Write-Host "  Größe: $($thumbInfo.Length) Bytes" -ForegroundColor Gray
            Write-Host "  Erstellt: $($thumbInfo.CreationTime)" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ FEHLER: Thumbnail NICHT erstellt (null zurückgegeben)" -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  StackTrace:" -ForegroundColor Gray
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

# Cache-Inhalt prüfen
Write-Host ""
Write-Host "SCHRITT 6: Cache-Inhalt..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $thumbsDir) {
    $thumbFiles = @(Get-ChildItem -LiteralPath $thumbsDir -Filter "*.jpg" -File)
    Write-Host "✓ .thumbs Ordner vorhanden" -ForegroundColor Green
    Write-Host "  Anzahl Thumbnails: $($thumbFiles.Count)" -ForegroundColor Gray
    
    if ($thumbFiles.Count -gt 0) {
        Write-Host "  Dateien:" -ForegroundColor Gray
        foreach ($file in $thumbFiles) {
            Write-Host "    - $($file.Name) ($($file.Length) Bytes)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "✗ .thumbs Ordner NICHT erstellt!" -ForegroundColor Red
}

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DEBUG ABGESCHLOSSEN" -ForegroundColor White
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""