<#
.SYNOPSIS
    Launcher für Foto_Viewer_V2

.DESCRIPTION
    Startet HTTP Server mit Hybrid PowerShell 5.1/7+ Support.
    Phase 4.1: Tools-Menü für .thumbs Verwaltung.

.PARAMETER Port
    Server Port (Default aus config.json)

.EXAMPLE
    .\start.ps1
    .\start.ps1 -Port 9999

.NOTES
    Autor: Herbert Schrotter
    Version: 0.4.7
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [int]$Port
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-Root ermitteln
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Libs laden
. (Join-Path $ScriptRoot "Lib\Lib_Config.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Http.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Dialogs.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Scanner.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_State.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_FileSystem.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_FFmpeg.ps1")
. (Join-Path $ScriptRoot "Lib\Lib_Tools.ps1")

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Foto Viewer V2 - Phase 4.1" -ForegroundColor White
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Config laden
try {
    $config = Get-Config
    Write-Host "✓ Config geladen" -ForegroundColor Green
} catch {
    Write-Error "Config konnte nicht geladen werden: $($_.Exception.Message)"
    return
}

# Port aus Config oder Parameter
if (-not $Port) {
    $Port = $config.Server.Port
}

# PowerShell Version Info
$psInfo = Get-PowerShellVersionInfo
Write-Host "✓ PowerShell: $($psInfo.DisplayName)" -ForegroundColor Green

if ($psInfo.IsPS7) {
    Write-Host "  → Parallel-Processing verfügbar" -ForegroundColor DarkGray
} else {
    Write-Host "  → Sequenziell (für Parallel: PS7+ installieren)" -ForegroundColor DarkGray
}

Write-Host ""

# FFmpeg Check
$script:FFmpegPath = Test-FFmpegInstalled -ScriptRoot $ScriptRoot
if ($script:FFmpegPath) {
    Write-Host "✓ FFmpeg gefunden: $script:FFmpegPath" -ForegroundColor Green
} else {
    Write-Warning "FFmpeg nicht gefunden - Video-Thumbnails deaktiviert"
}

Write-Host ""

# State laden
$script:State = Get-State
Write-Host "✓ State geladen" -ForegroundColor Green

# Root-Ordner wählen (wenn nicht im State)
if ([string]::IsNullOrWhiteSpace($script:State.RootPath) -or 
    -not (Test-Path -LiteralPath $script:State.RootPath)) {
    
    Write-Host ""
    Write-Host "Bitte wähle einen Root-Ordner..." -ForegroundColor Yellow
    
    $rootPath = Show-FolderDialog -Title "Root-Ordner für Foto-Gallery wählen" -InitialDirectory $script:State.RootPath
    
    if (-not $rootPath) {
        Write-Warning "Kein Ordner gewählt. Beende."
        return
    }
    
    $script:State.RootPath = $rootPath
    Write-Host "✓ Root gewählt: $rootPath" -ForegroundColor Green
} else {
    Write-Host "✓ Root aus State: $($script:State.RootPath)" -ForegroundColor Green
}

# Thumbnail-Cache Verzeichnis
$script:ThumbsDir = Join-Path $script:State.RootPath ".thumbs"
if (-not (Test-Path -LiteralPath $script:ThumbsDir)) {
    New-Item -Path $script:ThumbsDir -ItemType Directory -Force | Out-Null
    Write-Host "✓ Thumbnail-Cache erstellt: $script:ThumbsDir" -ForegroundColor Green
}

# Medien-Extensions aus Config
$mediaExtensions = $config.Media.ImageExtensions + $config.Media.VideoExtensions

# Ordner scannen
Write-Host ""
Write-Host "Scanne Ordner..." -ForegroundColor Cyan
try {
    $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtensions)
    
    $totalMedia = ($script:State.Folders | Measure-Object -Property MediaCount -Sum).Sum
    Write-Host "✓ Gefunden: $($script:State.Folders.Count) Ordner mit $totalMedia Medien" -ForegroundColor Green
    
    # State speichern
    Save-State -State $script:State
    
} catch {
    Write-Error "Scan fehlgeschlagen: $($_.Exception.Message)"
    return
}

Write-Host ""

# HttpListener starten
try {
    $listener = Start-HttpListener -Port $Port -Hostname $config.Server.Host
    Write-Host "✓ Server läuft auf: http://$($config.Server.Host):$Port" -ForegroundColor Green
} catch {
    Write-Error "Server-Start fehlgeschlagen: $($_.Exception.Message)"
    return
}

# Browser öffnen (wenn aktiviert)
if ($config.Server.AutoOpenBrowser) {
    try {
        Start-Process "http://$($config.Server.Host):$Port"
        Write-Host "✓ Browser geöffnet" -ForegroundColor Green
    } catch {
        Write-Warning "Browser konnte nicht automatisch geöffnet werden"
    }
}

Write-Host ""
Write-Host "Drücke Ctrl+C zum Beenden" -ForegroundColor Yellow
Write-Host ""

# Server-Loop
$ServerRunning = $true

try {
    while ($listener.IsListening -and $ServerRunning) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $path = $req.Url.AbsolutePath.ToLowerInvariant()
        
        try {
            # Route: / (Index)
            if ($path -eq "/" -and $req.HttpMethod -eq "GET") {
                
                # Ordner-Liste generieren mit JSON-Daten
                $folderListHtml = ""
                if ($script:State.Folders.Count -eq 0) {
                    $folderListHtml = "<div style='text-align:center;padding:40px;color:#718096;'>Keine Ordner mit Medien gefunden</div>"
                } else {
                    $folderRows = foreach ($folder in $script:State.Folders) {
                        $pathDisplay = if ($folder.RelativePath -eq ".") { "Root" } else { $folder.RelativePath }
                        $filesJson = ($folder.Files | ConvertTo-Json -Compress).Replace('"', '&quot;')
                        $relativePath = $folder.RelativePath.Replace('\', '/').Replace('"', '&quot;')
                        
                        @"
                        <div class="folder-card" data-path="$relativePath" data-files="$filesJson">
                            <div class="folder-header" onclick="toggleFolder(this)">
                                <span class="folder-icon">📁</span>
                                <span class="folder-name">$pathDisplay</span>
                                <span class="folder-count">$($folder.MediaCount) Medien</span>
                                <span class="toggle-icon">▼</span>
                            </div>
                            <div class="media-grid" style="display: none;"></div>
                        </div>
"@
                    }
                    $folderListHtml = $folderRows -join "`n"
                }
                
                $html = @"
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Foto Viewer V2 - Phase 4.1</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: #f7fafc;
            min-height: 100vh;
            padding: 20px 20px 20px 140px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        
        h1 {
            color: #2d3748;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .phase-badge {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 8px 24px;
            border-radius: 50px;
            font-weight: 600;
            font-size: 0.9em;
        }

        .folder-btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        
        .tools-btn {
            background: linear-gradient(135deg, #ed8936 0%, #dd6b20 100%);
            color: white;
        }
        
        .settings-btn {
            background: linear-gradient(135deg, #4299e1 0%, #3182ce 100%);
            color: white;
        }
        
        /* Tools Overlay */
        .overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.8);
            z-index: 2000;
            align-items: center;
            justify-content: center;
        }
        
        .overlay.show {
            display: flex;
        }
        
        .overlay-content {
            background: white;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            max-width: 700px;
            width: 90%;
            max-height: 80vh;
            position: relative;
            display: flex;
            flex-direction: column;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
        }
        
        .overlay-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 32px 32px 24px 32px;
            background: white;
            border-bottom: 1px solid #e2e8f0;
            flex-shrink: 0;
        }
        
        .overlay-body {
            flex: 1;
            overflow-y: auto;
            padding: 24px 32px;
        }
        
        .overlay-title {
            font-size: 20px;
            font-weight: 600;
            color: #2d3748;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .overlay-close {
            background: none;
            border: none;
            color: #718096;
            font-size: 24px;
            cursor: pointer;
            padding: 0;
            width: 32px;
            height: 32px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 4px;
            transition: all 0.2s;
        }
        
        .overlay-close:hover {
            background: #f7fafc;
            color: #2d3748;
        }
        
        .overlay-section {
            margin-bottom: 24px;
            padding-bottom: 24px;
            border-bottom: 1px solid #e2e8f0;
        }
        
        .overlay-section:last-child {
            margin-bottom: 0;
            padding-bottom: 0;
            border-bottom: none;
        }
        
        .overlay-section-title {
            font-size: 14px;
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 12px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .overlay-button {
            width: 100%;
            padding: 12px 20px;
            background: white;
            border: 1px solid #cbd5e0;
            border-radius: 6px;
            color: #2d3748;
            font-size: 14px;
            cursor: pointer;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin-bottom: 12px;
        }
        
        .overlay-button:hover {
            background: #f7fafc;
            border-color: #a0aec0;
        }
        
        .overlay-button.danger {
            background: #dc2626;
            border-color: #b91c1c;
            color: white;
        }
        
        .overlay-button.danger:hover {
            background: #b91c1c;
        }
        
        .overlay-info {
            background: #f7fafc;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            padding: 12px 16px;
            font-size: 13px;
            color: #718096;
            margin-top: 12px;
        }
        
        .overlay-result {
            margin-top: 16px;
            padding: 12px 16px;
            background: #f7fafc;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            font-size: 13px;
            color: #2d3748;
        }
        
        .overlay-result.success {
            border-color: #4ade80;
            background: rgba(74, 222, 128, 0.1);
            color: #16a34a;
        }
        
        .overlay-result.error {
            border-color: #dc2626;
            background: rgba(220, 38, 38, 0.1);
            color: #dc2626;
        }
        
        .thumbs-list {
            background: #f7fafc;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            padding: 12px;
            max-height: 300px;
            overflow-y: auto;
            margin-top: 12px;
        }
        
        .thumbs-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 10px 12px;
            background: white;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            margin-bottom: 8px;
            transition: all 0.2s;
        }
        
        .thumbs-item:hover {
            border-color: #cbd5e0;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
        }
        
        .thumbs-item:last-child {
            margin-bottom: 0;
        }
        
        .thumbs-checkbox {
            width: 18px;
            height: 18px;
            cursor: pointer;
            accent-color: #667eea;
        }
        
        .thumbs-info {
            flex: 1;
            color: #2d3748;
            font-size: 13px;
        }
        
        .thumbs-path {
            font-weight: 500;
            margin-bottom: 4px;
        }
        
        .thumbs-details {
            color: #718096;
            font-size: 11px;
        }
        
        .list-actions {
            display: flex;
            gap: 8px;
            margin-top: 12px;
        }
        
        .list-action-btn {
            padding: 8px 16px;
            background: white;
            border: 1px solid #cbd5e0;
            border-radius: 6px;
            color: #2d3748;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .list-action-btn:hover {
            background: #f7fafc;
            border-color: #a0aec0;
        }
        
        .list-action-btn.danger {
            background: #dc2626;
            border-color: #b91c1c;
            color: white;
        }
        
        .list-action-btn.danger:hover {
            background: #b91c1c;
        }
        
        .settings-category {
            margin-bottom: 16px;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            overflow: hidden;
        }
        
        .settings-category-header {
            padding: 14px 16px;
            background: #f7fafc;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: space-between;
            transition: background 0.2s;
        }
        
        .settings-category-header:hover {
            background: #edf2f7;
        }
        
        .settings-category-title {
            font-size: 14px;
            font-weight: 600;
            color: #2d3748;
        }
        
        .settings-category-toggle {
            color: #718096;
            transition: transform 0.3s;
        }
        
        .settings-category.expanded .settings-category-toggle {
            transform: rotate(180deg);
        }
        
        .settings-category-content {
            display: none;
            padding: 16px;
            background: white;
        }
        
        .settings-category.expanded .settings-category-content {
            display: block;
        }
        
        .settings-group {
            margin-bottom: 16px;
        }
        
        .settings-group:last-child {
            margin-bottom: 0;
        }
        
        .settings-label {
            display: block;
            font-size: 13px;
            font-weight: 500;
            color: #2d3748;
            margin-bottom: 6px;
        }
        
        .settings-input {
            width: 100%;
            padding: 8px 12px;
            background: white;
            border: 1px solid #cbd5e0;
            border-radius: 6px;
            color: #2d3748;
            font-size: 13px;
            font-family: inherit;
        }
        
        .settings-input:focus {
            outline: none;
            border-color: #667eea;
            background: white;
        }
        
        .settings-input:disabled {
            background: #f7fafc;
            color: #a0aec0;
            cursor: not-allowed;
        }
        
        .settings-input[type="number"] {
            width: 120px;
        }
        
        .settings-row {
            display: flex;
            gap: 12px;
            align-items: flex-start;
        }
        
        .settings-row .settings-group {
            flex: 1;
            margin-bottom: 0;
        }
        
        .settings-checkbox-wrapper {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px 0;
        }
        
        .settings-checkbox {
            width: 18px;
            height: 18px;
            cursor: pointer;
            accent-color: #667eea;
        }
        
        .settings-checkbox-label {
            font-size: 13px;
            color: #2d3748;
            cursor: pointer;
        }
        
        .settings-actions {
            display: flex;
            gap: 12px;
            padding: 20px 32px 32px 32px;
            border-top: 1px solid #e2e8f0;
            background: white;
            flex-shrink: 0;
        }
        
        .settings-btn {
            flex: 1;
            padding: 12px 20px;
            border: none;
            border-radius: 6px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .settings-btn-primary {
            background: #667eea;
            color: white;
        }
        
        .settings-btn-primary:hover {
            background: #5568d3;
        }
        
        .settings-btn-secondary {
            background: white;
            border: 1px solid #cbd5e0;
            color: #2d3748;
        }
        
        .settings-btn-secondary:hover {
            background: #f7fafc;
            border-color: #a0aec0;
        }
        
/* Moderne Sidebar */
        .sidebar {
            position: fixed;
            top: 20px;
            left: 20px;
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 16px;
            padding: 12px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
            z-index: 1000;
            display: flex;
            flex-direction: column;
            gap: 8px;
            min-width: 100px;
        }
        
        .sidebar-row {
            display: flex;
            gap: 8px;
            align-items: center;
            justify-content: center;
        }
        
        .sidebar-btn {
            width: 46px;
            height: 46px;
            border: none;
            border-radius: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.3em;
            transition: all 0.3s ease;
            background: #f7fafc;
            position: relative;
            font-weight: 600;
            color: white;
        }
        
        .sidebar-row:not(:first-child):not(.sidebar-row-triple) .sidebar-btn {
            font-size: 1.8em;
            width: 100%;
        }
        
        .sidebar-row-triple {
            gap: 4px;
        }
        
        .sidebar-row-triple {
            width: 100%;
        }
        
        .sidebar-row-triple .sidebar-btn {
            width: 28px;
            height: 28px;
            font-size: 1em;
            border-radius: 6px;
            flex-shrink: 0;
        }
        
        .size-btn {
            background: #e2e8f0;
        }
        
        .size-btn.active {
            background: #cbd5e0;
        }
        
        .size-dots {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: flex-end;
            height: 20px;
            gap: 3px;
        }
        
        .dot {
            width: 4px;
            height: 4px;
            background: #2d3748;
            border-radius: 50%;
        }
        
        .size-btn.active .dot {
            background: white;
        }
        
        .sidebar-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
        }
        
        .sidebar-btn:active {
            transform: translateY(0);
        }
        
        .status-btn {
            background: linear-gradient(135deg, #48bb78 0%, #38a169 100%);
        }
        
        .status-btn.offline {
            background: linear-gradient(135deg, #f56565 0%, #e53e3e 100%);
        }
        
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: white;
            box-shadow: 0 0 8px rgba(255, 255, 255, 0.6);
            animation: pulse 2s ease-in-out infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.7; transform: scale(0.9); }
        }
        
        .power-btn {
            background: linear-gradient(135deg, #f56565 0%, #e53e3e 100%);
            color: white;
        }
        
    
        
        .folder-card {
            background: white;
            border-radius: 12px;
            margin-bottom: 16px;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
            overflow: hidden;
            transition: all 0.3s ease;
        }
        
        .folder-card:hover {
            box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
        }
        
        .folder-header {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 20px;
            cursor: pointer;
            user-select: none;
            transition: background 0.2s ease;
        }
        
        .folder-header:hover {
            background: #f7fafc;
        }
        
        .folder-icon {
            font-size: 1.5em;
        }
        
        .folder-name {
            flex: 1;
            font-weight: 600;
            color: #2d3748;
            font-size: 1.1em;
        }
        
        .folder-count {
            color: #667eea;
            font-weight: 600;
            font-size: 0.9em;
        }
        
        .toggle-icon {
            color: #718096;
            transition: transform 0.3s ease;
        }
        
        .folder-card.expanded .toggle-icon {
            transform: rotate(180deg);
        }
        
        .media-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 16px;
            padding: 20px;
            background: #f7fafc;
        }
        
        .media-item {
            position: relative;
            aspect-ratio: 1;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        
        .media-item:hover {
            transform: translateY(-4px);
            box-shadow: 0 8px 16px rgba(0, 0, 0, 0.2);
        }
        
        .media-item img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        
        .video-badge {
            position: absolute;
            top: 8px;
            right: 8px;
            background: rgba(0, 0, 0, 0.7);
            color: white;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.8em;
            font-weight: 600;
        }
        
        .tooltip {
            position: fixed;
            background: #2d3748;
            color: white;
            padding: 8px 12px;
            border-radius: 8px;
            font-size: 13px;
            font-weight: 500;
            white-space: nowrap;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.3s ease;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            z-index: 10000;
        }
        
        .tooltip.show {
            opacity: 1;
        }
    </style>
</head>
<body>
    <div class="tooltip" id="tooltip"></div>
    
    <div class="sidebar">
        <div class="sidebar-row">
            <button class="sidebar-btn status-btn" id="statusBtn" data-tooltip="Server läuft">
                <span class="status-dot"></span>
            </button>
            <button class="sidebar-btn power-btn" onclick="shutdownServer()" data-tooltip="Server beenden">
                ⏻
            </button>
        </div>
        <div class="sidebar-row sidebar-row-triple">
            <button class="sidebar-btn size-btn size-small active" onclick="setThumbSize('small')" data-tooltip="Klein (150px)">
                <span class="size-dots one-dot"><span class="dot"></span></span>
            </button>
            <button class="sidebar-btn size-btn size-medium" onclick="setThumbSize('medium')" data-tooltip="Mittel (200px)">
                <span class="size-dots two-dots"><span class="dot"></span><span class="dot"></span></span>
            </button>
            <button class="sidebar-btn size-btn size-large" onclick="setThumbSize('large')" data-tooltip="Groß (300px)">
                <span class="size-dots three-dots"><span class="dot"></span><span class="dot"></span><span class="dot"></span></span>
            </button>
        </div>
        <div class="sidebar-row">
            <button class="sidebar-btn folder-btn" onclick="changeRoot()" data-tooltip="Ordner wechseln">
                📂
            </button>
        </div>
        <div class="sidebar-row">
            <button class="sidebar-btn tools-btn" onclick="openTools()" data-tooltip="Tools">
                🛠️
            </button>
        </div>
        <div class="sidebar-row">
            <button class="sidebar-btn settings-btn" onclick="openSettings()" data-tooltip="Einstellungen">
                ⚙️
            </button>
        </div>
    </div>
    
    <div class="container">
        <div class="header">
            <h1>Foto Viewer V2</h1>
            <span class="phase-badge">Phase 4.1: Tools-Menü</span>
        </div>
        
        <div class="folder-list">
$folderListHtml
        </div>
    </div>
    
    <div class="overlay" id="toolsOverlay">
        <div class="overlay-content">
            <div class="overlay-header">
                <div class="overlay-title">
                    <span>🧰</span>
                    <span>Tools</span>
                </div>
                <button class="overlay-close" onclick="closeTools()">×</button>
            </div>
            
            <div class="overlay-section">
                <div class="overlay-section-title">📊 Cache-Statistik</div>
                <button class="overlay-button" onclick="getCacheStats()">
                    <span>📈</span>
                    <span>Statistik anzeigen</span>
                </button>
                <div id="statsResult"></div>
            </div>
            
            <div class="overlay-section">
                <div class="overlay-section-title">📂 .thumbs Ordner verwalten</div>
                <button class="overlay-button" onclick="listThumbs()">
                    <span>📋</span>
                    <span>Liste laden</span>
                </button>
                <div id="thumbsList"></div>
            </div>
            
            <div class="overlay-section">
                <div class="overlay-section-title">🗑️ Alle löschen</div>
                <button class="overlay-button danger" onclick="deleteAllThumbs()">
                    <span>🗑️</span>
                    <span>ALLE .thumbs löschen</span>
                </button>
                <div class="overlay-info">
                    ⚠️ Löscht alle .thumbs Ordner im gesamten Root rekursiv!
                </div>
            </div>
        </div>
    </div>
    
    <div class="overlay" id="settingsOverlay">
        <div class="overlay-content">
            <div class="overlay-header">
                <div class="overlay-title">
                    <span>⚙️</span>
                    <span>Einstellungen</span>
                </div>
                <button class="overlay-close" onclick="closeSettings()">×</button>
            </div>
            
            <div class="overlay-body">
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">🌐 Server</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <label class="settings-label">Port</label>
                        <input type="number" class="settings-input" id="setting-server-port" min="1000" max="65535">
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Host</label>
                        <input type="text" class="settings-input" id="setting-server-host">
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-server-autoopen">
                            <label class="settings-checkbox-label" for="setting-server-autoopen">Browser automatisch öffnen</label>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">📁 Medien</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <label class="settings-label">Bild-Dateitypen (mit ; trennen)</label>
                        <input type="text" class="settings-input" id="setting-media-images" placeholder=".jpg;.png;.gif">
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Video-Dateitypen (mit ; trennen)</label>
                        <input type="text" class="settings-input" id="setting-media-videos" placeholder=".mp4;.mov;.avi">
                    </div>
                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">🎬 Video</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <label class="settings-label">Thumbnail-Qualität</label>
                        <input type="number" class="settings-input" id="setting-video-quality" min="1" max="100">
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-video-autoconvert">
                            <label class="settings-checkbox-label" for="setting-video-autoconvert">Auto-Konvertierung aktivieren</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Bevorzugter Video-Codec</label>
                        <select class="settings-input" id="setting-video-codec">
                            <option value="h264">H.264</option>
                            <option value="h265">H.265 (HEVC)</option>
                            <option value="vp9">VP9</option>
                        </select>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Konvertierungs-Preset</label>
                        <select class="settings-input" id="setting-video-preset">
                            <option value="fast">Schnell</option>
                            <option value="medium">Mittel</option>
                            <option value="slow">Langsam (beste Qualität)</option>
                        </select>
                    </div>
                    <div style="height: 12px;"></div>
                    <div class="settings-group">
                        <label class="settings-label">Anzahl Thumbnails pro Video</label>
                        <input type="number" class="settings-input" id="setting-video-thumbcount" min="1" max="20">
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Thumbnails pro Sekunde (FPS)</label>
                        <input type="number" class="settings-input" id="setting-video-thumbfps" min="1" max="10">
                    </div>
                    <div class="settings-group">
                        <label class="settings-label" style="margin-bottom: 8px;">Zeitbereich (% der Video-Dauer)</label>
                        <div class="settings-row">
                            <div class="settings-group">
                                <label class="settings-label" style="font-size: 12px; color: #aaa;">Von</label>
                                <input type="number" class="settings-input" id="setting-video-thumbstart" min="0" max="100">
                            </div>
                            <div class="settings-group">
                                <label class="settings-label" style="font-size: 12px; color: #aaa;">Bis</label>
                                <input type="number" class="settings-input" id="setting-video-thumbend" min="0" max="100">
                            </div>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-video-hls">
                            <label class="settings-checkbox-label" for="setting-video-hls">HLS Streaming aktivieren</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">HLS Segment-Länge (Sekunden)</label>
                        <input type="number" class="settings-input" id="setting-video-hlssegment" min="5" max="30">
                    </div>
                    <div style="height: 12px;"></div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-video-gifpreview">
                            <label class="settings-checkbox-label" for="setting-video-gifpreview">Video-Vorschau als animiertes GIF</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">GIF-Länge (Sekunden)</label>
                        <input type="number" class="settings-input" id="setting-video-gifduration" min="1" max="10">
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">GIF Bilder pro Sekunde (FPS)</label>
                        <input type="number" class="settings-input" id="setting-video-gifframerate" min="5" max="30">
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-video-gifloop">
                            <label class="settings-checkbox-label" for="setting-video-gifloop">GIF endlos wiederholen</label>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">🎨 Oberfläche</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <label class="settings-label">Farbschema</label>
                        <select class="settings-input" id="setting-ui-theme" disabled>
                            <option value="light">Hell (Standard)</option>
                            <option value="dark">Dunkel (in Entwicklung)</option>
                        </select>
                        <div style="font-size: 11px; color: #888; margin-top: 4px;">Momentan nur helles Design verfügbar</div>
                    </div>
                    <div style="height: 12px;"></div>
                    <div class="settings-group">
                        <label class="settings-label">Standard Thumbnail-Größe beim Start</label>
                        <select class="settings-input" id="setting-ui-defaultsize">
                            <option value="small">Klein</option>
                            <option value="medium">Mittel</option>
                            <option value="large">Groß</option>
                        </select>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Thumbnail-Größe Mittel (px)</label>
                        <input type="number" class="settings-input" id="setting-ui-thumbsize" min="100" max="400">
                        <div style="font-size: 11px; color: #888; margin-top: 4px;">Klein = 75%, Groß = 150%</div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Grid-Spalten</label>
                        <input type="number" class="settings-input" id="setting-ui-columns" min="2" max="12">
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Anzahl Vorschau-Thumbnails</label>
                        <input type="number" class="settings-input" id="setting-ui-previewcount" min="1" max="20">
                    </div>
                    <div style="height: 12px;"></div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-ui-showmetadata">
                            <label class="settings-checkbox-label" for="setting-ui-showmetadata">Video-Metadaten anzeigen</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-ui-showcodec">
                            <label class="settings-checkbox-label" for="setting-ui-showcodec">Video-Codec anzeigen</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-ui-showduration">
                            <label class="settings-checkbox-label" for="setting-ui-showduration">Video-Dauer anzeigen</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-ui-showcompat">
                            <label class="settings-checkbox-label" for="setting-ui-showcompat">Browser-Kompatibilität anzeigen</label>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">⚡ Performance</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-perf-parallel">
                            <label class="settings-checkbox-label" for="setting-perf-parallel">Parallel-Processing (PS7+)</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Max. Parallele Jobs</label>
                        <input type="number" class="settings-input" id="setting-perf-maxjobs" min="1" max="32">
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-perf-cache">
                            <label class="settings-checkbox-label" for="setting-perf-cache">Thumbnails cachen</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-perf-lazy">
                            <label class="settings-checkbox-label" for="setting-perf-lazy">Lazy Loading</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Lösch-Job Timeout (Sekunden)</label>
                        <input type="number" class="settings-input" id="setting-perf-timeout" min="1" max="60">
                    </div>
                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">🗑️ Datei-Operationen</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-file-recycle">
                            <label class="settings-checkbox-label" for="setting-file-recycle">Papierkorb verwenden</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-file-confirm">
                            <label class="settings-checkbox-label" for="setting-file-confirm">Löschen bestätigen</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-file-move">
                            <label class="settings-checkbox-label" for="setting-file-move">Dateien verschieben aktivieren</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-file-flatten">
                            <label class="settings-checkbox-label" for="setting-file-flatten">Flatten & Move aktivieren</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-file-range">
                            <label class="settings-checkbox-label" for="setting-file-range">Range-Request Unterstützung (Video-Streaming)</label>
                        </div>
                    </div>
                                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">💾 Cache</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-cache-scan">
                            <label class="settings-checkbox-label" for="setting-cache-scan">Scan-Cache verwenden</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Cache-Ordner</label>
                        <input type="text" class="settings-input" id="setting-cache-folder" placeholder=".cache">
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-cache-videometa">
                            <label class="settings-checkbox-label" for="setting-cache-videometa">Video-Metadaten cachen</label>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="settings-category">
                <div class="settings-category-header" onclick="toggleCategory(this)">
                    <span class="settings-category-title">✨ Features</span>
                    <span class="settings-category-toggle">▼</span>
                </div>
                <div class="settings-category-content">
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-archive">
                            <label class="settings-checkbox-label" for="setting-feat-archive">Archiv-Extraktion aktivieren</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <label class="settings-label">Archiv-Dateitypen (mit ; trennen)</label>
                        <input type="text" class="settings-input" id="setting-feat-archiveext" placeholder=".zip;.rar;.7z">
                    </div>
                    <div style="height: 12px;"></div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-thumbpre">
                            <label class="settings-checkbox-label" for="setting-feat-thumbpre">Video-Thumbnails vorab generieren</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-lazyconv">
                            <label class="settings-checkbox-label" for="setting-feat-lazyconv">Lazy Video-Konvertierung</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-vlc">
                            <label class="settings-checkbox-label" for="setting-feat-vlc">In VLC öffnen</label>
                        </div>
                    </div>
                    <div style="height: 12px;"></div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-collapse">
                            <label class="settings-checkbox-label" for="setting-feat-collapse">Ordner einklappbar</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-lightbox">
                            <label class="settings-checkbox-label" for="setting-feat-lightbox">Lightbox-Viewer</label>
                        </div>
                    </div>
                    <div class="settings-group">
                        <div class="settings-checkbox-wrapper">
                            <input type="checkbox" class="settings-checkbox" id="setting-feat-keyboard">
                            <label class="settings-checkbox-label" for="setting-feat-keyboard">Tastatur-Navigation</label>
                        </div>
                    </div>
                </div>
            </div>
            </div>
            
            <div class="settings-actions">
                <button class="settings-btn settings-btn-secondary" onclick="closeSettings()">Abbrechen</button>
                <button class="settings-btn settings-btn-secondary" onclick="resetSettings()">Zurücksetzen</button>
                <button class="settings-btn settings-btn-primary" onclick="saveSettings()">Speichern</button>
            </div>
        </div>
    </div>
    
    <script>
        const tooltip = document.getElementById('tooltip');
        
        document.querySelectorAll('[data-tooltip]').forEach(function(el) {
            el.addEventListener('mouseenter', function(e) {
                const text = this.getAttribute('data-tooltip');
                const rect = this.getBoundingClientRect();
                tooltip.textContent = text;
                tooltip.style.left = (rect.right + 10) + 'px';
                tooltip.style.top = (rect.top + rect.height / 2) + 'px';
                tooltip.style.transform = 'translateY(-50%)';
                tooltip.classList.add('show');
            });
            el.addEventListener('mouseleave', function() {
                tooltip.classList.remove('show');
            });
        });
        
        function toggleFolder(header) {
            const card = header.closest('.folder-card');
            const grid = card.querySelector('.media-grid');
            const isExpanded = card.classList.contains('expanded');
            
            if (isExpanded) {
                grid.style.display = 'none';
                card.classList.remove('expanded');
            } else {
                card.classList.add('expanded');
                if (grid.children.length === 0) {
                    const files = JSON.parse(card.dataset.files);
                    const folderPath = card.dataset.path;
                    files.forEach(function(file) {
                        const isVideo = /\.(mp4|mov|avi|mkv|webm|m4v|wmv|flv|mpg|mpeg|3gp)$/i.test(file);
                        const filePath = folderPath === '.' ? file : folderPath + '/' + file;
                        const imgUrl = '/img?path=' + encodeURIComponent(filePath);
                        const item = document.createElement('div');
                        item.className = 'media-item';
                        item.innerHTML = '<img src="' + imgUrl + '" alt="' + file + '" loading="lazy">' +
                                        (isVideo ? '<span class="video-badge">▶ VIDEO</span>' : '');
                        grid.appendChild(item);
                    });
                }
                grid.style.display = 'grid';
            }
        }
        
        async function changeRoot() {
            try {
                const response = await fetch('/changeroot', { method: 'POST' });
                const result = await response.json();
                if (result.cancelled) return;
                if (result.ok) {
                    location.reload();
                } else {
                    alert('Fehler: ' + (result.error || 'Unbekannter Fehler'));
                }
            } catch (err) {
                console.error('Fehler:', err);
            }
        }
        
        async function shutdownServer() {
            if (!confirm('Server wirklich beenden?')) return;
            try {
                await fetch('/shutdown', { method: 'POST' });
                document.body.innerHTML = '<div style="display:flex;flex-direction:column;gap:20px;align-items:center;justify-content:center;min-height:100vh;font-size:24px;color:#2d3748;"><div style="font-size:60px;">✓</div><div>Server beendet!</div></div>';
            } catch (err) {
                console.log('Server beendet');
            }
        }
        
        async function checkServerStatus() {
            const btn = document.getElementById('statusBtn');
            try {
                await fetch('/ping');
                btn.classList.remove('offline');
                btn.setAttribute('data-tooltip', 'Server läuft');
            } catch {
                btn.classList.add('offline');
                btn.setAttribute('data-tooltip', 'Server offline');
            }
        }
        
        setInterval(checkServerStatus, 2000);
        checkServerStatus();
        
        function openTools() {
            document.getElementById('toolsOverlay').classList.add('show');
        }
        
        function closeTools() {
            document.getElementById('toolsOverlay').classList.remove('show');
            document.getElementById('statsResult').innerHTML = '';
            document.getElementById('thumbsList').innerHTML = '';
        }
        
        async function getCacheStats() {
            var resultDiv = document.getElementById('statsResult');
            resultDiv.innerHTML = '<div class="overlay-result">⏳ Berechne Statistik...</div>';
            
            try {
                var response = await fetch('/tools/cache-stats');
                var result = await response.json();
                
                if (result.success) {
                    resultDiv.innerHTML = '<div class="overlay-result success">' +
                        '<div style="font-weight: 600; margin-bottom: 8px;">📊 Cache-Statistik</div>' +
                        '<div>📁 .thumbs Ordner: ' + result.data.ThumbsDirectories + '</div>' +
                        '<div>🖼️ Thumbnail-Dateien: ' + result.data.ThumbnailFiles + '</div>' +
                        '<div>💾 Gesamtgröße: ' + result.data.TotalSizeFormatted + '</div>' +
                        '</div>';
                } else {
                    resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + (result.error || 'Fehler') + '</div>';
                }
            } catch (err) {
                resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
            }
        }
        
        async function listThumbs() {
            var listDiv = document.getElementById('thumbsList');
            listDiv.innerHTML = '<div class="overlay-result">⏳ Lade Liste...</div>';
            
            try {
                var response = await fetch('/tools/list-thumbs');
                var result = await response.json();
                
                if (!result.success) {
                    listDiv.innerHTML = '<div class="overlay-result error">❌ ' + (result.error || 'Fehler') + '</div>';
                    return;
                }
                
                if (result.data.length === 0) {
                    listDiv.innerHTML = '<div class="overlay-result">Keine .thumbs Ordner gefunden</div>';
                    return;
                }
                
                var itemsHtml = result.data.map(function(item) {
                    return '<div class="thumbs-item">' +
                        '<input type="checkbox" class="thumbs-checkbox" data-path="' + item.Path + '">' +
                        '<div class="thumbs-info">' +
                        '<div class="thumbs-path">📁 ' + item.RelativePath + '</div>' +
                        '<div class="thumbs-details">' + item.FileCount + ' Dateien, ' + item.SizeFormatted + '</div>' +
                        '</div></div>';
                }).join('');
                
                listDiv.innerHTML = '<div class="thumbs-list">' + itemsHtml + '</div>' +
                    '<div class="list-actions">' +
                    '<button class="list-action-btn" onclick="selectAllThumbs()">☑ Alle auswählen</button>' +
                    '<button class="list-action-btn" onclick="deselectAllThumbs()">☐ Alle abwählen</button>' +
                    '<button class="list-action-btn danger" onclick="deleteSelectedThumbs()">🗑️ Ausgewählte löschen</button>' +
                    '</div><div id="deleteSelectedResult"></div>';
            } catch (err) {
                listDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
            }
        }
        
        function selectAllThumbs() {
            document.querySelectorAll('.thumbs-checkbox').forEach(function(cb) { cb.checked = true; });
        }
        
        function deselectAllThumbs() {
            document.querySelectorAll('.thumbs-checkbox').forEach(function(cb) { cb.checked = false; });
        }
        
        async function deleteSelectedThumbs() {
            var checkboxes = document.querySelectorAll('.thumbs-checkbox:checked');
            if (checkboxes.length === 0) {
                alert('Keine Ordner ausgewählt!');
                return;
            }
            
            var paths = Array.from(checkboxes).map(function(cb) { return cb.dataset.path; });
            if (!confirm(paths.length + ' Ordner wirklich löschen?')) return;
            
            var resultDiv = document.getElementById('deleteSelectedResult');
            resultDiv.innerHTML = '<div class="overlay-result">⏳ Lösche...</div>';
            
            try {
                var response = await fetch('/tools/delete-selected', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ paths: paths })
                });
                var result = await response.json();
                
                if (result.success) {
                    resultDiv.innerHTML = '<div class="overlay-result success">✓ ' + 
                        result.data.DeletedCount + ' Ordner gelöscht (' + 
                        (result.data.DeletedSize / 1024 / 1024).toFixed(2) + ' MB)</div>';
                    setTimeout(function() { listThumbs(); }, 1000);
                } else {
                    resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + result.error + '</div>';
                }
            } catch (err) {
                resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
            }
        }
        
        async function deleteAllThumbs() {
            if (!confirm('ALLE .thumbs Ordner wirklich löschen?\n\nDies kann nicht rückgängig gemacht werden!')) return;
            if (!confirm('Bist du sicher? Dies löscht ALLE Thumbnails im gesamten Root!')) return;
            
            try {
                var response = await fetch('/tools/delete-all-thumbs', { method: 'POST' });
                var result = await response.json();
                
                if (result.success) {
                    alert('✓ ' + result.data.DeletedCount + ' Ordner gelöscht\n' + 
                        (result.data.DeletedSize / 1024 / 1024).toFixed(2) + ' MB freigegeben');
                    closeTools();
                } else {
                    alert('❌ Fehler: ' + (result.error || 'Unbekannter Fehler'));
                }
            } catch (err) {
                alert('❌ Fehler: ' + err.message);
            }
        }
        
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') closeTools();
        });
        
        document.getElementById('toolsOverlay').addEventListener('click', function(e) {
            if (e.target === this) closeTools();
        });
        function toggleCategory(header) {
            var category = header.closest('.settings-category');
            category.classList.toggle('expanded');
        }
        
        function openSettings() {
            loadSettings();
            document.getElementById('settingsOverlay').classList.add('show');
        }
        
        function closeSettings() {
            document.getElementById('settingsOverlay').classList.remove('show');
        }
        
        async function loadSettings() {
            try {
                var response = await fetch('/settings/get');
                var config = await response.json();
                
                document.getElementById('setting-server-port').value = config.Server.Port;
                document.getElementById('setting-server-host').value = config.Server.Host;
                document.getElementById('setting-server-autoopen').checked = config.Server.AutoOpenBrowser;
                
                document.getElementById('setting-media-images').value = config.Media.ImageExtensions.join(';');
                document.getElementById('setting-media-videos').value = config.Media.VideoExtensions.join(';');
                
                document.getElementById('setting-video-quality').value = config.Video.ThumbnailQuality;
                document.getElementById('setting-video-autoconvert').checked = config.Video.EnableAutoConversion;
                document.getElementById('setting-video-hls').checked = config.Video.UseHLS;
                document.getElementById('setting-video-hlssegment').value = config.Video.HLSSegmentDuration;
                document.getElementById('setting-video-codec').value = config.Video.PreferredCodec;
                document.getElementById('setting-video-preset').value = config.Video.ConversionPreset;
                document.getElementById('setting-video-thumbcount').value = config.Video.ThumbnailCount;
                document.getElementById('setting-video-thumbfps').value = config.Video.ThumbnailFPS;
                document.getElementById('setting-video-gifpreview').checked = config.Video.PreviewAsGIF;
                document.getElementById('setting-video-gifduration').value = config.Video.GIFDuration;
                document.getElementById('setting-video-gifframerate').value = config.Video.GIFFrameRate;
                document.getElementById('setting-video-gifloop').checked = config.Video.GIFLoop;
                document.getElementById('setting-video-thumbstart').value = config.Video.ThumbnailStartPercent;
                document.getElementById('setting-video-thumbend').value = config.Video.ThumbnailEndPercent;
                
                document.getElementById('setting-ui-theme').value = config.UI.Theme;
                document.getElementById('setting-ui-defaultsize').value = config.UI.DefaultThumbSize || 'medium';
                document.getElementById('setting-ui-thumbsize').value = config.UI.ThumbnailSize;
                document.getElementById('setting-ui-columns').value = config.UI.GridColumns;
                document.getElementById('setting-ui-previewcount').value = config.UI.PreviewThumbnailCount;
                document.getElementById('setting-ui-showmetadata').checked = config.UI.ShowVideoMetadata;
                document.getElementById('setting-ui-showcodec').checked = config.UI.ShowVideoCodec;
                document.getElementById('setting-ui-showduration').checked = config.UI.ShowVideoDuration;
                document.getElementById('setting-ui-showcompat').checked = config.UI.ShowBrowserCompatibility;
                
                document.getElementById('setting-perf-parallel').checked = config.Performance.UseParallelProcessing;
                document.getElementById('setting-perf-maxjobs').value = config.Performance.MaxParallelJobs;
                document.getElementById('setting-perf-cache').checked = config.Performance.CacheThumbnails;
                document.getElementById('setting-perf-lazy').checked = config.Performance.LazyLoading;
                document.getElementById('setting-perf-timeout').value = config.Performance.DeleteJobTimeout;
                
                document.getElementById('setting-file-recycle').checked = config.FileOperations.UseRecycleBin;
                document.getElementById('setting-file-confirm').checked = config.FileOperations.ConfirmDelete;
                document.getElementById('setting-file-move').checked = config.FileOperations.EnableMove;
                document.getElementById('setting-file-flatten').checked = config.FileOperations.EnableFlattenAndMove;
                document.getElementById('setting-file-range').checked = config.FileOperations.RangeRequestSupport;
                
                document.getElementById('setting-cache-scan').checked = config.Cache.UseScanCache;
                document.getElementById('setting-cache-folder').value = config.Cache.CacheFolder;
                document.getElementById('setting-cache-videometa').checked = config.Cache.VideoMetadataCache;
                
                document.getElementById('setting-feat-archive').checked = config.Features.ArchiveExtraction;
                document.getElementById('setting-feat-archiveext').value = config.Features.ArchiveExtensions.join(';');
                document.getElementById('setting-feat-thumbpre').checked = config.Features.VideoThumbnailPreGeneration;
                document.getElementById('setting-feat-lazyconv').checked = config.Features.LazyVideoConversion;
                document.getElementById('setting-feat-vlc').checked = config.Features.OpenInVLC;
                document.getElementById('setting-feat-collapse').checked = config.Features.CollapsibleFolders;
                document.getElementById('setting-feat-lightbox').checked = config.Features.LightboxViewer;
                document.getElementById('setting-feat-keyboard').checked = config.Features.KeyboardNavigation;
            } catch (err) {
                alert('Fehler beim Laden der Einstellungen: ' + err.message);
            }
        }
        
        async function saveSettings() {
            try {
                var settings = {
                    Server: {
                        Port: parseInt(document.getElementById('setting-server-port').value),
                        Host: document.getElementById('setting-server-host').value,
                        AutoOpenBrowser: document.getElementById('setting-server-autoopen').checked
                    },
                    Media: {
                        ImageExtensions: document.getElementById('setting-media-images').value.split(';').map(function(s) { return s.trim(); }).filter(Boolean),
                        VideoExtensions: document.getElementById('setting-media-videos').value.split(';').map(function(s) { return s.trim(); }).filter(Boolean)
                    },
                    Video: {
                        ThumbnailQuality: parseInt(document.getElementById('setting-video-quality').value),
                        EnableAutoConversion: document.getElementById('setting-video-autoconvert').checked,
                        UseHLS: document.getElementById('setting-video-hls').checked,
                        HLSSegmentDuration: parseInt(document.getElementById('setting-video-hlssegment').value),
                        PreferredCodec: document.getElementById('setting-video-codec').value,
                        ConversionPreset: document.getElementById('setting-video-preset').value,
                        ThumbnailCount: parseInt(document.getElementById('setting-video-thumbcount').value),
                        ThumbnailFPS: parseInt(document.getElementById('setting-video-thumbfps').value),
                        PreviewAsGIF: document.getElementById('setting-video-gifpreview').checked,
                        GIFDuration: parseInt(document.getElementById('setting-video-gifduration').value),
                        GIFFrameRate: parseInt(document.getElementById('setting-video-gifframerate').value),
                        GIFLoop: document.getElementById('setting-video-gifloop').checked,
                        ThumbnailStartPercent: parseInt(document.getElementById('setting-video-thumbstart').value),
                        ThumbnailEndPercent: parseInt(document.getElementById('setting-video-thumbend').value)
                    },
                    UI: {
                        Theme: document.getElementById('setting-ui-theme').value,
                        DefaultThumbSize: document.getElementById('setting-ui-defaultsize').value,
                        ThumbnailSize: parseInt(document.getElementById('setting-ui-thumbsize').value),
                        GridColumns: parseInt(document.getElementById('setting-ui-columns').value),
                        PreviewThumbnailCount: parseInt(document.getElementById('setting-ui-previewcount').value),
                        ShowVideoMetadata: document.getElementById('setting-ui-showmetadata').checked,
                        ShowVideoCodec: document.getElementById('setting-ui-showcodec').checked,
                        ShowVideoDuration: document.getElementById('setting-ui-showduration').checked,
                        ShowBrowserCompatibility: document.getElementById('setting-ui-showcompat').checked
                    },
                    Performance: {
                        UseParallelProcessing: document.getElementById('setting-perf-parallel').checked,
                        MaxParallelJobs: parseInt(document.getElementById('setting-perf-maxjobs').value),
                        CacheThumbnails: document.getElementById('setting-perf-cache').checked,
                        LazyLoading: document.getElementById('setting-perf-lazy').checked,
                        DeleteJobTimeout: parseInt(document.getElementById('setting-perf-timeout').value)
                    },
                    FileOperations: {
                        UseRecycleBin: document.getElementById('setting-file-recycle').checked,
                        ConfirmDelete: document.getElementById('setting-file-confirm').checked,
                        EnableMove: document.getElementById('setting-file-move').checked,
                        EnableFlattenAndMove: document.getElementById('setting-file-flatten').checked,
                        RangeRequestSupport: document.getElementById('setting-file-range').checked
                    },
                    Cache: {
                        UseScanCache: document.getElementById('setting-cache-scan').checked,
                        CacheFolder: document.getElementById('setting-cache-folder').value,
                        VideoMetadataCache: document.getElementById('setting-cache-videometa').checked
                    },
                    Features: {
                        ArchiveExtraction: document.getElementById('setting-feat-archive').checked,
                        ArchiveExtensions: document.getElementById('setting-feat-archiveext').value.split(';').map(function(s) { return s.trim(); }).filter(Boolean),
                        VideoThumbnailPreGeneration: document.getElementById('setting-feat-thumbpre').checked,
                        LazyVideoConversion: document.getElementById('setting-feat-lazyconv').checked,
                        OpenInVLC: document.getElementById('setting-feat-vlc').checked,
                        CollapsibleFolders: document.getElementById('setting-feat-collapse').checked,
                        LightboxViewer: document.getElementById('setting-feat-lightbox').checked,
                        KeyboardNavigation: document.getElementById('setting-feat-keyboard').checked
                    }
                };
                
                var response = await fetch('/settings/save', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(settings)
                });
                
                var result = await response.json();
                
                if (result.success) {
                    alert('✓ Einstellungen gespeichert!\n\nServer wird neu gestartet...');
                    location.reload();
                } else {
                    alert('❌ Fehler beim Speichern: ' + (result.error || 'Unbekannt'));
                }
            } catch (err) {
                alert('❌ Fehler: ' + err.message);
            }
        }
        
        async function resetSettings() {
            if (!confirm('Einstellungen auf Standard zurücksetzen?')) return;
            
            try {
                var response = await fetch('/settings/reset', { method: 'POST' });
                var result = await response.json();
                
                if (result.success) {
                    alert('✓ Einstellungen zurückgesetzt!');
                    loadSettings();
                } else {
                    alert('❌ Fehler: ' + (result.error || 'Unbekannt'));
                }
            } catch (err) {
                alert('❌ Fehler: ' + err.message);
            }
        }
        
        document.getElementById('settingsOverlay').addEventListener('click', function(e) {
            if (e.target === this) closeSettings();
        });
        
        var baseThumbnailSize = 200;
        
        function setThumbSize(size) {
            document.querySelectorAll('.size-btn').forEach(function(btn) {
                btn.classList.remove('active');
            });
            
            var sizeMultiplier = {
                'small': 0.75,
                'medium': 1,
                'large': 1.5
            };
            
            var pixelSize = Math.round(baseThumbnailSize * sizeMultiplier[size]);
            
            document.querySelector('.size-' + size).classList.add('active');
            
            var style = document.querySelector('style.dynamic-thumb-size');
            if (!style) {
                style = document.createElement('style');
                style.className = 'dynamic-thumb-size';
                document.head.appendChild(style);
            }
            
            style.textContent = '.media-grid { grid-template-columns: repeat(auto-fill, minmax(' + pixelSize + 'px, 1fr)); }';
        }
        
        async function initThumbSize() {
            try {
                var response = await fetch('/settings/get');
                var config = await response.json();
                baseThumbnailSize = config.UI.ThumbnailSize || 200;
                var defaultSize = config.UI.DefaultThumbSize || 'medium';
                setThumbSize(defaultSize);
            } catch (err) {
                console.error('Fehler beim Laden der Thumbnail-Größe:', err);
                setThumbSize('medium');
            }
        }
        
        initThumbSize();
    </script>
</body>
</html>
"@
                Send-ResponseHtml -Response $res -Html $html
                continue
            }
            
            # Route: /changeroot
            if ($path -eq "/changeroot" -and $req.HttpMethod -eq "POST") {
                $newRoot = Show-FolderDialog -Title "Neuen Root-Ordner wählen" -InitialDirectory $script:State.RootPath
                if (-not $newRoot) {
                    $json = @{ cancelled = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                    continue
                }
                if (-not (Test-Path -LiteralPath $newRoot -PathType Container)) {
                    $json = @{ error = "Ordner existiert nicht" } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                    continue
                }
                $script:State.RootPath = $newRoot
                $script:ThumbsDir = Join-Path $script:State.RootPath ".thumbs"
                if (-not (Test-Path -LiteralPath $script:ThumbsDir)) {
                    New-Item -Path $script:ThumbsDir -ItemType Directory -Force | Out-Null
                }
                try {
                    $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtensions)
                    Save-State -State $script:State
                    $json = @{ ok = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/cache-stats
            if ($path -eq "/tools/cache-stats" -and $req.HttpMethod -eq "GET") {
                try {
                    $stats = Get-ThumbsCacheStats -RootPath $script:State.RootPath
                    $json = @{
                        success = $true
                        data = @{
                            ThumbsDirectories = $stats.ThumbsDirectories
                            ThumbnailFiles = $stats.ThumbnailFiles
                            TotalSize = $stats.TotalSize
                            TotalSizeFormatted = $stats.TotalSizeFormatted
                        }
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/list-thumbs
            if ($path -eq "/tools/list-thumbs" -and $req.HttpMethod -eq "GET") {
                try {
                    $list = Get-ThumbsDirectoriesList -RootPath $script:State.RootPath
                    $json = @{
                        success = $true
                        data = @($list | ForEach-Object {
                            @{
                                Path = $_.Path
                                RelativePath = $_.RelativePath
                                FileCount = $_.FileCount
                                Size = $_.Size
                                SizeFormatted = $_.SizeFormatted
                            }
                        })
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/delete-selected
            if ($path -eq "/tools/delete-selected" -and $req.HttpMethod -eq "POST") {
                try {
                    $reader = [System.IO.StreamReader]::new($req.InputStream)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    $data = $body | ConvertFrom-Json
                    $paths = $data.paths
                    if (-not $paths -or $paths.Count -eq 0) {
                        $json = @{ success = $false; error = "Keine Pfade" } | ConvertTo-Json -Compress
                        Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                        continue
                    }
                    $result = Remove-SelectedThumbsDirectories -Paths $paths
                    $json = @{
                        success = $true
                        data = @{
                            DeletedCount = $result.DeletedCount
                            DeletedSize = $result.DeletedSize
                        }
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /tools/delete-all-thumbs
            if ($path -eq "/tools/delete-all-thumbs" -and $req.HttpMethod -eq "POST") {
                try {
                    $result = Remove-AllThumbsDirectories -RootPath $script:State.RootPath
                    $json = @{
                        success = $true
                        data = @{
                            DeletedCount = $result.DeletedCount
                            DeletedSize = $result.DeletedSize
                        }
                    } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /settings/get
            if ($path -eq "/settings/get" -and $req.HttpMethod -eq "GET") {
                try {
                    $configPath = Join-Path $ScriptRoot "config.json"
                    $configJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                    Send-ResponseText -Response $res -Text $configJson -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /settings/save
            if ($path -eq "/settings/save" -and $req.HttpMethod -eq "POST") {
                try {
                    $reader = [System.IO.StreamReader]::new($req.InputStream)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $newSettings = $body | ConvertFrom-Json
                    $configPath = Join-Path $ScriptRoot "config.json"
                    $currentConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                    
                    $currentConfig.Server.Port = $newSettings.Server.Port
                    $currentConfig.Server.Host = $newSettings.Server.Host
                    $currentConfig.Server.AutoOpenBrowser = $newSettings.Server.AutoOpenBrowser
                    
                    $currentConfig.Media.ImageExtensions = $newSettings.Media.ImageExtensions
                    $currentConfig.Media.VideoExtensions = $newSettings.Media.VideoExtensions
                    
                    $currentConfig.Video.ThumbnailQuality = $newSettings.Video.ThumbnailQuality
                    $currentConfig.Video.EnableAutoConversion = $newSettings.Video.EnableAutoConversion
                    $currentConfig.Video.UseHLS = $newSettings.Video.UseHLS
                    $currentConfig.Video.HLSSegmentDuration = $newSettings.Video.HLSSegmentDuration
                    $currentConfig.Video.PreferredCodec = $newSettings.Video.PreferredCodec
                    $currentConfig.Video.ConversionPreset = $newSettings.Video.ConversionPreset
                    $currentConfig.Video.ThumbnailCount = $newSettings.Video.ThumbnailCount
                    $currentConfig.Video.ThumbnailFPS = $newSettings.Video.ThumbnailFPS
                    $currentConfig.Video.PreviewAsGIF = $newSettings.Video.PreviewAsGIF
                    $currentConfig.Video.GIFDuration = $newSettings.Video.GIFDuration
                    $currentConfig.Video.GIFFrameRate = $newSettings.Video.GIFFrameRate
                    $currentConfig.Video.GIFLoop = $newSettings.Video.GIFLoop
                    $currentConfig.Video.ThumbnailStartPercent = $newSettings.Video.ThumbnailStartPercent
                    $currentConfig.Video.ThumbnailEndPercent = $newSettings.Video.ThumbnailEndPercent
                    
                    $currentConfig.UI.Theme = $newSettings.UI.Theme
                    $currentConfig.UI.DefaultThumbSize = $newSettings.UI.DefaultThumbSize
                    $currentConfig.UI.ThumbnailSize = $newSettings.UI.ThumbnailSize
                    $currentConfig.UI.GridColumns = $newSettings.UI.GridColumns
                    $currentConfig.UI.PreviewThumbnailCount = $newSettings.UI.PreviewThumbnailCount
                    $currentConfig.UI.ShowVideoMetadata = $newSettings.UI.ShowVideoMetadata
                    $currentConfig.UI.ShowVideoCodec = $newSettings.UI.ShowVideoCodec
                    $currentConfig.UI.ShowVideoDuration = $newSettings.UI.ShowVideoDuration
                    $currentConfig.UI.ShowBrowserCompatibility = $newSettings.UI.ShowBrowserCompatibility
                    
                    $currentConfig.Performance.UseParallelProcessing = $newSettings.Performance.UseParallelProcessing
                    $currentConfig.Performance.MaxParallelJobs = $newSettings.Performance.MaxParallelJobs
                    $currentConfig.Performance.CacheThumbnails = $newSettings.Performance.CacheThumbnails
                    $currentConfig.Performance.LazyLoading = $newSettings.Performance.LazyLoading
                    $currentConfig.Performance.DeleteJobTimeout = $newSettings.Performance.DeleteJobTimeout
                    
                    $currentConfig.FileOperations.UseRecycleBin = $newSettings.FileOperations.UseRecycleBin
                    $currentConfig.FileOperations.ConfirmDelete = $newSettings.FileOperations.ConfirmDelete
                    $currentConfig.FileOperations.EnableMove = $newSettings.FileOperations.EnableMove
                    $currentConfig.FileOperations.EnableFlattenAndMove = $newSettings.FileOperations.EnableFlattenAndMove
                    $currentConfig.FileOperations.RangeRequestSupport = $newSettings.FileOperations.RangeRequestSupport
                    
                    $currentConfig.Cache.UseScanCache = $newSettings.Cache.UseScanCache
                    $currentConfig.Cache.CacheFolder = $newSettings.Cache.CacheFolder
                    $currentConfig.Cache.VideoMetadataCache = $newSettings.Cache.VideoMetadataCache
                    
                    $currentConfig.Features.ArchiveExtraction = $newSettings.Features.ArchiveExtraction
                    $currentConfig.Features.ArchiveExtensions = $newSettings.Features.ArchiveExtensions
                    $currentConfig.Features.VideoThumbnailPreGeneration = $newSettings.Features.VideoThumbnailPreGeneration
                    $currentConfig.Features.LazyVideoConversion = $newSettings.Features.LazyVideoConversion
                    $currentConfig.Features.OpenInVLC = $newSettings.Features.OpenInVLC
                    $currentConfig.Features.CollapsibleFolders = $newSettings.Features.CollapsibleFolders
                    $currentConfig.Features.LightboxViewer = $newSettings.Features.LightboxViewer
                    $currentConfig.Features.KeyboardNavigation = $newSettings.Features.KeyboardNavigation
                    
                    $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                    
                    $json = @{ success = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /settings/reset
            if ($path -eq "/settings/reset" -and $req.HttpMethod -eq "POST") {
                try {
                    $configPath = Join-Path $ScriptRoot "config.json"
                    $backupPath = Join-Path $ScriptRoot "config.json.backup"
                    
                    if (Test-Path -LiteralPath $backupPath) {
                        Copy-Item -LiteralPath $backupPath -Destination $configPath -Force
                        $json = @{ success = $true } | ConvertTo-Json -Compress
                    } else {
                        $json = @{ success = $false; error = "Keine Backup-Datei gefunden" } | ConvertTo-Json -Compress
                    }
                    
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Route: /img
            if ($path -eq "/img" -and $req.HttpMethod -eq "GET") {
                $relativePath = $req.QueryString["path"]
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-ResponseText -Response $res -Text "Missing path" -StatusCode 400
                    continue
                }
                $fullPath = Resolve-SafePath -RootPath $script:State.RootPath -RelativePath $relativePath
                if (-not $fullPath -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    Send-ResponseText -Response $res -Text "Not found" -StatusCode 404
                    continue
                }
                try {
                    if (Test-IsVideoFile -Path $fullPath) {
                        if ($script:FFmpegPath) {
                            $thumbPath = Get-VideoThumbnail -VideoPath $fullPath -CacheDir $script:ThumbsDir -ScriptRoot $ScriptRoot
                            if ($thumbPath -and (Test-Path -LiteralPath $thumbPath -PathType Leaf)) {
                                $fullPath = $thumbPath
                            }
                        }
                    }
                    $contentType = Get-MediaContentType -Path $fullPath
                    $fileInfo = [System.IO.FileInfo]::new($fullPath)
                    $res.StatusCode = 200
                    $res.ContentType = $contentType
                    $res.ContentLength64 = $fileInfo.Length
                    $fs = [System.IO.File]::OpenRead($fullPath)
                    try {
                        $fs.CopyTo($res.OutputStream)
                    }
                    finally {
                        $fs.Close()
                        $res.OutputStream.Close()
                    }
                } catch {
                    Write-Error "Fehler: $($_.Exception.Message)"
                    Send-ResponseText -Response $res -Text "Error" -StatusCode 500
                }
                continue
            }
            
            # Route: /ping
            if ($path -eq "/ping" -and $req.HttpMethod -eq "GET") {
                Send-ResponseText -Response $res -Text "OK" -StatusCode 200
                continue
            }
            
            # Route: /shutdown
            if ($path -eq "/shutdown" -and $req.HttpMethod -eq "POST") {
                $ServerRunning = $false
                Send-ResponseText -Response $res -Text "Beende..."
                break
            }
            
            Send-ResponseText -Response $res -Text "Not Found" -StatusCode 404
            
        } catch {
            Write-Error "Request-Fehler: $($_.Exception.Message)"
            Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host ""
    Write-Host "✓ Server beendet" -ForegroundColor Green
    Write-Host ""
}            