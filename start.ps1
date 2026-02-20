<#
.SYNOPSIS
    Launcher für Foto_Viewer_V2

.DESCRIPTION
    Startet HTTP Server mit Hybrid PowerShell 5.1/7+ Support.
    Phase 1: Zeigt "Hello World" mit PowerShell Version.

.PARAMETER Port
    Server Port (Default aus config.json)

.EXAMPLE
    .\start.ps1
    .\start.ps1 -Port 9999

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.6
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

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Foto Viewer V2 - Phase 1" -ForegroundColor White
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
                $html = @"
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Foto Viewer V2 - Phase 1</title>
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
            text-align: center;
            max-width: 600px;
        }
        
        .success-icon {
            font-size: 80px;
            margin-bottom: 20px;
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
        
        .info-box {
            background: #f7fafc;
            border-radius: 10px;
            padding: 25px;
            margin-top: 30px;
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
        
        .ps-version {
            display: inline-block;
            background: #48bb78;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
        }
        
        .next-steps {
            margin-top: 30px;
            padding: 20px;
            background: #edf2f7;
            border-radius: 10px;
        }
        
        .next-steps h3 {
            color: #2d3748;
            margin-bottom: 15px;
            font-size: 1.2em;
        }
        
        .next-steps ul {
            list-style: none;
            text-align: left;
        }
        
        .next-steps li {
            padding: 8px 0;
            color: #4a5568;
        }
        
        .next-steps li:before {
            content: "▶";
            color: #667eea;
            font-weight: bold;
            margin-right: 10px;
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
        [data-tooltip] {
            position: relative;
        }
        
        [data-tooltip]::after {
            content: attr(data-tooltip);
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%) translateY(-10px);
            background: #2d3748;
            color: white;
            padding: 8px 16px;
            border-radius: 8px;
            font-size: 0.85em;
            white-space: nowrap;
            opacity: 0;
            pointer-events: none;
            transition: all 0.3s ease;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            z-index: 1000;
        }
        
        [data-tooltip]:hover::after {
            opacity: 1;
            transform: translateX(-50%) translateY(-5px);
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
        <h1>Phase 1 funktioniert!</h1>
        <div class="phase-badge">Minimal HTTP Server</div>
        
        <div class="info-box">
            <div class="info-row">
                <span class="info-label">PowerShell Version:</span>
                <span class="ps-version">$($psInfo.DisplayName)</span>
            </div>
            <div class="info-row">
                <span class="info-label">Server Port:</span>
                <span class="info-value">$Port</span>
            </div>
            <div class="info-row">
                <span class="info-label">Parallel-Processing:</span>
                <span class="info-value">$(if ($psInfo.IsPS7) { "✓ Verfügbar" } else { "✗ Nicht verfügbar (PS5.1)" })</span>
            </div>
        </div>
        
        <div class="next-steps">
            <h3>Nächste Schritte:</h3>
            <ul>
                <li>Phase 2: Ordner-Dialog + Scan</li>
                <li>Phase 3: Bilder Grid anzeigen</li>
                <li>Phase 4: Video-Thumbnails (FFmpeg)</li>
                <li>Phase 5: Ordner-Struktur (zuklappbar)</li>
            </ul>
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