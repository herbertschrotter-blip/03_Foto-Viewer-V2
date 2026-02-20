<#
.SYNOPSIS
    Launcher für Foto_Viewer_V2

.DESCRIPTION
    Startet HTTP Server mit Hybrid PowerShell 5.1/7+ Support.
    Phase 3: Bilder Grid + Sidebar mit fixen Tooltips.

.PARAMETER Port
    Server Port (Default aus config.json)

.EXAMPLE
    .\start.ps1
    .\start.ps1 -Port 9999

.NOTES
    Autor: Herbert Schrotter
    Version: 0.3.4
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

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Foto Viewer V2 - Phase 3" -ForegroundColor White
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
    <title>Foto Viewer V2 - Phase 3</title>
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
        
        .folder-change-btn {
            width: 100%;
            height: 46px;
            border: none;
            border-radius: 12px;
            cursor: pointer;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-weight: 600;
            font-size: 0.9em;
            transition: all 0.3s ease;
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.2);
            position: relative;
        }
        
        .folder-change-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 16px rgba(102, 126, 234, 0.3);
        }
        
        .folder-change-btn:active {
            transform: translateY(0);
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
        
        /* Tooltip Container */
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
    <!-- Tooltip Container -->
    <div class="tooltip" id="tooltip"></div>
    
    <!-- Moderne Sidebar -->
    <div class="sidebar">
        <div class="sidebar-row">
            <button class="sidebar-btn status-btn" id="statusBtn" data-tooltip="Server läuft">
                <span class="status-dot"></span>
            </button>
            <button class="sidebar-btn power-btn" onclick="shutdownServer()" data-tooltip="Server beenden">
                ⏻
            </button>
        </div>
        <button class="folder-change-btn" onclick="changeRoot()" data-tooltip="Root-Ordner wechseln">
            Ordner
        </button>
    </div>
    
    <div class="container">
        <div class="header">
            <h1>Foto Viewer V2</h1>
            <span class="phase-badge">Phase 3: Bilder Grid</span>
        </div>
        
        <div class="folder-list">
$folderListHtml
        </div>
    </div>
    
    <script>
        // Tooltip System
        const tooltip = document.getElementById('tooltip');
        
        document.querySelectorAll('[data-tooltip]').forEach(el => {
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
                // Zuklappen
                grid.style.display = 'none';
                card.classList.remove('expanded');
            } else {
                // Aufklappen
                card.classList.add('expanded');
                
                // Medien laden (lazy)
                if (grid.children.length === 0) {
                    const files = JSON.parse(card.dataset.files);
                    const folderPath = card.dataset.path;
                    
                    files.forEach(file => {
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
                
                if (result.cancelled) {
                    return;
                }
                
                if (result.ok) {
                    location.reload();
                } else {
                    alert('Fehler: ' + (result.error || 'Unbekannter Fehler'));
                }
            } catch (err) {
                console.error('Fehler beim Root-Wechsel:', err);
            }
        }
        
        async function shutdownServer() {
            if (!confirm('Server wirklich beenden?')) return;
            
            try {
                await fetch('/shutdown', { method: 'POST' });
                document.body.innerHTML = '<div style="display:flex;flex-direction:column;gap:20px;align-items:center;justify-content:center;min-height:100vh;font-size:24px;color:#2d3748;"><div style="font-size:60px;">✓</div><div>Server beendet!</div><div style="font-size:16px;opacity:0.6;">Du kannst dieses Fenster jetzt schließen.</div></div>';
            } catch (err) {
                console.log('Server beendet');
            }
        }
        
        // Server-Status Ping
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
    </script>
</body>
</html>
"@
                Send-ResponseHtml -Response $res -Html $html
                continue
            }
            
            # Route: /changeroot (Ordner wechseln)
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
                
                # Root wechseln und neu scannen
                $script:State.RootPath = $newRoot
                
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
            
            # Route: /img (Bilder ausliefern)
            if ($path -eq "/img" -and $req.HttpMethod -eq "GET") {
                $relativePath = $req.QueryString["path"]
                
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-ResponseText -Response $res -Text "Missing path parameter" -StatusCode 400
                    continue
                }
                
                $fullPath = Resolve-SafePath -RootPath $script:State.RootPath -RelativePath $relativePath
                
                if (-not $fullPath -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    Send-ResponseText -Response $res -Text "File not found" -StatusCode 404
                    continue
                }
                
                try {
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
                    Write-Error "Fehler beim Ausliefern von $fullPath : $($_.Exception.Message)"
                    Send-ResponseText -Response $res -Text "Error reading file" -StatusCode 500
                }
                
                continue
            }
            
            # Route: /ping (Server-Status)
            if ($path -eq "/ping" -and $req.HttpMethod -eq "GET") {
                Send-ResponseText -Response $res -Text "OK" -StatusCode 200
                continue
            }
            
            # Route: /shutdown
            if ($path -eq "/shutdown" -and $req.HttpMethod -eq "POST") {
                $ServerRunning = $false
                Send-ResponseText -Response $res -Text "Server wird beendet..."
                break
            }
            
            # 404 für alle anderen Routes
            Send-ResponseText -Response $res -Text "Not Found" -StatusCode 404
            
        } catch {
            Write-Error "Request-Fehler: $($_.Exception.Message)"
            Send-ResponseText -Response $res -Text "Internal Server Error" -StatusCode 500
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