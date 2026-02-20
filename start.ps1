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
    Version: 0.4.1
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
            background: #2a2a2a;
            border: 1px solid #3a3a3a;
            border-radius: 12px;
            padding: 32px;
            max-width: 700px;
            width: 90%;
            max-height: 80vh;
            overflow-y: auto;
            position: relative;
        }
        
        .overlay-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 24px;
        }
        
        .overlay-title {
            font-size: 20px;
            font-weight: 600;
            color: #ffffff;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .overlay-close {
            background: none;
            border: none;
            color: #888;
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
            background: #3a3a3a;
            color: #e0e0e0;
        }
        
        .overlay-section {
            margin-bottom: 24px;
            padding-bottom: 24px;
            border-bottom: 1px solid #3a3a3a;
        }
        
        .overlay-section:last-child {
            margin-bottom: 0;
            padding-bottom: 0;
            border-bottom: none;
        }
        
        .overlay-section-title {
            font-size: 14px;
            font-weight: 600;
            color: #ffffff;
            margin-bottom: 12px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .overlay-button {
            width: 100%;
            padding: 12px 20px;
            background: #3a3a3a;
            border: 1px solid #4a4a4a;
            border-radius: 6px;
            color: #e0e0e0;
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
            background: #454545;
            border-color: #555;
        }
        
        .overlay-button.danger {
            background: #dc2626;
            border-color: #b91c1c;
        }
        
        .overlay-button.danger:hover {
            background: #b91c1c;
        }
        
        .overlay-info {
            background: #252525;
            border: 1px solid #3a3a3a;
            border-radius: 6px;
            padding: 12px 16px;
            font-size: 13px;
            color: #888;
            margin-top: 12px;
        }
        
        .overlay-result {
            margin-top: 16px;
            padding: 12px 16px;
            background: #252525;
            border: 1px solid #3a3a3a;
            border-radius: 6px;
            font-size: 13px;
        }
        
        .overlay-result.success {
            border-color: #4ade80;
            background: rgba(74, 222, 128, 0.1);
            color: #4ade80;
        }
        
        .overlay-result.error {
            border-color: #dc2626;
            background: rgba(220, 38, 38, 0.1);
            color: #dc2626;
        }
        
        .thumbs-list {
            background: #252525;
            border: 1px solid #3a3a3a;
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
            background: #2a2a2a;
            border-radius: 6px;
            margin-bottom: 8px;
            transition: background 0.2s;
        }
        
        .thumbs-item:hover {
            background: #303030;
        }
        
        .thumbs-item:last-child {
            margin-bottom: 0;
        }
        
        .thumbs-checkbox {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }
        
        .thumbs-info {
            flex: 1;
            color: #e0e0e0;
            font-size: 13px;
        }
        
        .thumbs-path {
            font-weight: 500;
            margin-bottom: 4px;
        }
        
        .thumbs-details {
            color: #888;
            font-size: 11px;
        }
        
        .list-actions {
            display: flex;
            gap: 8px;
            margin-top: 12px;
        }
        
        .list-action-btn {
            padding: 8px 16px;
            background: #3a3a3a;
            border: 1px solid #4a4a4a;
            border-radius: 6px;
            color: #e0e0e0;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .list-action-btn:hover {
            background: #454545;
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
        
        .sidebar-row:not(:first-child) .sidebar-btn {
            font-size: 1.8em;
            width: 100%;
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
        function openSettings() {
            alert('Settings-Menü kommt in Phase 4.2! ⚙️');
        }
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