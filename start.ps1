<#
.SYNOPSIS
    Launcher für Foto_Viewer_V2

.DESCRIPTION
    Startet HTTP Server mit Hybrid PowerShell 5.1/7+ Support.
    Phase 2: Ordner-Dialog + Scan + Liste anzeigen.

.PARAMETER Port
    Server Port (Default aus config.json)

.EXAMPLE
    .\start.ps1
    .\start.ps1 -Port 9999

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
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

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Foto Viewer V2 - Phase 2" -ForegroundColor White
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
    
    $rootPath = Show-FolderDialog -Title "Root-Ordner für Foto-Gallery wählen"
    
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
                
                # Ordner-Liste generieren
                $folderListHtml = ""
                if ($script:State.Folders.Count -eq 0) {
                    $folderListHtml = "<div style='text-align:center;padding:40px;color:#718096;'>Keine Ordner mit Medien gefunden</div>"
                } else {
                    $folderRows = foreach ($folder in $script:State.Folders) {
                        $pathDisplay = if ($folder.RelativePath -eq ".") { "📁 Root" } else { "📁 $($folder.RelativePath)" }
                        @"
                        <div class="folder-row">
                            <span class="folder-path">$pathDisplay</span>
                            <span class="folder-count">$($folder.MediaCount) Medien</span>
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
    <title>Foto Viewer V2 - Phase 2</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            padding: 60px 80px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            max-width: 900px;
            width: 100%;
        }
        
        .success-icon {
            font-size: 80px;
            margin-bottom: 20px;
            text-align: center;
            animation: bounce 1s ease-in-out;
        }
        
        @keyframes bounce {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-20px); }
        }
        
        h1 {
            color: #2d3748;
            font-size: 2.5em;
            margin-bottom: 20px;
            font-weight: 700;
            text-align: center;
        }
        
        .phase-badge {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 10px 30px;
            border-radius: 50px;
            font-weight: 600;
            margin-bottom: 30px;
            font-size: 1.1em;
        }
        
        .badge-container {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .info-box {
            background: #f7fafc;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 30px;
            border-left: 4px solid #667eea;
        }
        
        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 0;
            border-bottom: 1px solid #e2e8f0;
        }
        
        .info-row:last-child {
            border-bottom: none;
        }
        
        .info-label {
            font-weight: 600;
            color: #4a5568;
        }
        
        .info-value {
            color: #2d3748;
            font-family: 'Courier New', monospace;
        }
        
        .folder-list {
            max-height: 400px;
            overflow-y: auto;
            background: #f7fafc;
            border-radius: 10px;
            padding: 20px;
        }
        
        .folder-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            margin-bottom: 8px;
            background: white;
            border-radius: 8px;
            transition: all 0.2s ease;
        }
        
        .folder-row:hover {
            background: #edf2f7;
            transform: translateX(4px);
        }
        
        .folder-path {
            font-weight: 500;
            color: #2d3748;
        }
        
        .folder-count {
            color: #667eea;
            font-weight: 600;
            font-size: 0.9em;
        }
        
        .server-status {
            position: fixed;
            top: 20px;
            left: 20px;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 12px;
            padding: 12px 20px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 1.2em;
            cursor: default;
        }
        
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #48bb78;
            animation: pulse 2s ease-in-out infinite;
        }
        
        .status-dot.offline {
            background: #f56565;
            animation: none;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .shutdown-btn {
            position: fixed;
            top: 20px;
            right: 20px;
            background: linear-gradient(135deg, #f56565 0%, #e53e3e 100%);
            color: white;
            border: none;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            font-weight: 600;
            cursor: pointer;
            box-shadow: 0 4px 12px rgba(245, 101, 101, 0.3);
            transition: all 0.3s ease;
            font-size: 1.8em;
            display: flex;
            align-items: center;
            justify-content: center;
            line-height: 1;
            padding: 0;
        }
        
        .shutdown-btn:hover {
            background: linear-gradient(135deg, #e53e3e 0%, #c53030 100%);
            transform: translateY(-2px) scale(1.1);
            box-shadow: 0 6px 20px rgba(245, 101, 101, 0.6);
        }
        
        .shutdown-btn:active {
            transform: translateY(0) scale(1.05);
        }
        
        /* Globaler Custom Tooltip */
        [data-tooltip]::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            z-index: -1;
        }
        
        [data-tooltip]::after {
            content: attr(data-tooltip);
            position: fixed;
            transform: translate(-50%, 10px);
            background: #2d3748;
            color: white;
            padding: 10px 18px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            white-space: nowrap;
            opacity: 0;
            pointer-events: none;
            transition: all 0.3s ease;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            z-index: 1000;
            min-width: 140px;
            text-align: center;
        }
        
        .server-status:hover::after {
            opacity: 1;
            left: 20px;
            top: 80px;
            transform: translate(0, 0);
        }
        
        .shutdown-btn:hover::after {
            opacity: 1;
            right: 20px;
            left: auto;
            top: 80px;
            transform: translate(0, 0);
        }
    </style>
</head>
<body>
    <div class="server-status" id="serverStatus" data-tooltip="Server läuft">
        <span>🖥️</span>
        <span class="status-dot" id="statusDot"></span>
    </div>
    
    <button class="shutdown-btn" onclick="shutdownServer()" data-tooltip="Server beenden">⏻</button>
    
    <div class="container">
        <div class="success-icon">✓</div>
        <h1>Phase 2 funktioniert!</h1>
        <div class="badge-container">
            <span class="phase-badge">Ordner-Dialog + Scan</span>
        </div>
        
        <div class="info-box">
            <div class="info-row">
                <span class="info-label">Root-Ordner:</span>
                <span class="info-value">$($script:State.RootPath)</span>
            </div>
            <div class="info-row">
                <span class="info-label">Ordner gefunden:</span>
                <span class="info-value">$($script:State.Folders.Count)</span>
            </div>
            <div class="info-row">
                <span class="info-label">Gesamt-Medien:</span>
                <span class="info-value">$(($script:State.Folders | Measure-Object -Property MediaCount -Sum).Sum)</span>
            </div>
        </div>
        
        <div class="folder-list">
$folderListHtml
        </div>
    </div>
    
    <script>
        async function shutdownServer() {
            if (!confirm('Server wirklich beenden?')) return;
            
            try {
                await fetch('/shutdown', { method: 'POST' });
                document.body.innerHTML = '<div style="display:flex;flex-direction:column;gap:20px;align-items:center;justify-content:center;min-height:100vh;font-size:24px;color:white;"><div style="font-size:60px;">✓</div><div>Server beendet!</div><div style="font-size:16px;opacity:0.8;">Du kannst dieses Fenster jetzt schließen.</div></div>';
            } catch (err) {
                console.log('Server beendet');
            }
        }
        
        // Server-Status Ping
        async function checkServerStatus() {
            const dot = document.getElementById('statusDot');
            const status = document.getElementById('serverStatus');
            
            try {
                await fetch('/ping');
                dot.classList.remove('offline');
                status.setAttribute('data-tooltip', 'Server läuft');
            } catch {
                dot.classList.add('offline');
                status.setAttribute('data-tooltip', 'Server offline');
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