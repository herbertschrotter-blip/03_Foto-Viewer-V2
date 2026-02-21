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
    Version: 0.7.0
    
    ÄNDERUNGEN v0.7.0:
    - Background-Job für Cache-Rebuild (optional)
    - Auto-Start nach Ordner-Scan
    - ScriptRoot an Handle-ToolsRoute übergeben
    
    ÄNDERUNGEN v0.5.0:
    - Lokale .thumbs/ pro Ordner (statt zentral)
    - Get-MediaThumbnail für Fotos UND Videos
    - Cache-Validierung beim Scan (EAGER)
    - Entfernt: Zentrale $script:ThumbsDir Logik
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

# Libs laden - Core
. (Join-Path $ScriptRoot "Lib\Core\Lib_Config.ps1")
. (Join-Path $ScriptRoot "Lib\Core\Lib_State.ps1")
. (Join-Path $ScriptRoot "Lib\Core\Lib_Http.ps1")

# Libs laden - Media
. (Join-Path $ScriptRoot "Lib\Media\Lib_Scanner.ps1")
. (Join-Path $ScriptRoot "Lib\Media\Lib_Thumbnails.ps1")
. (Join-Path $ScriptRoot "Lib\Media\Lib_FileSystem.ps1")
. (Join-Path $ScriptRoot "Lib\Media\Lib_FFmpeg.ps1")

# Libs laden - UI
. (Join-Path $ScriptRoot "Lib\UI\Lib_Dialogs.ps1")
. (Join-Path $ScriptRoot "Lib\UI\Lib_UI_Template.ps1")

# Libs laden - Routes
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Tools.ps1")
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Settings.ps1")
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Files.ps1")

# Libs laden - Utils
. (Join-Path $ScriptRoot "Lib\Utils\Lib_Tools.ps1")

#region OneDrive-Schutz Check

Write-Verbose "Prüfe OneDrive-Schutz für Thumbnail-Cache..."

$hasRegistryProtection = Test-OneDriveProtection

if ($hasRegistryProtection) {
    Write-Verbose "OneDrive-Schutz: ✓ Vollständig (Hidden+System + Registry)"
}
else {
    # ... Info-Screen + Setup ...
}

#endregion

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

# Thumbnail-Cache wird lokal in jedem Ordner (.thumbs/) erstellt
# Keine zentrale ThumbsDir-Logik mehr nötig

# Medien-Extensions aus Config
$mediaExtensions = $config.Media.ImageExtensions + $config.Media.VideoExtensions

# Ordner scannen
Write-Host ""
Write-Host "Scanne Ordner..." -ForegroundColor Cyan
try {
    $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtensions -ScriptRoot $ScriptRoot)
    
    $totalMedia = ($script:State.Folders | Measure-Object -Property MediaCount -Sum).Sum
    Write-Host "✓ Gefunden: $($script:State.Folders.Count) Ordner mit $totalMedia Medien" -ForegroundColor Green
    
    # State speichern
    Save-State -State $script:State
    
} catch {
    Write-Error "Scan fehlgeschlagen: $($_.Exception.Message)"
    return
}

if ($script:State.Folders.Count -gt 0) {
    Write-Host ""
    Write-Host "Cache-Rebuild im Hintergrund?" -ForegroundColor Cyan
    Write-Host "  Validiert/Generiert Thumbnails für alle Ordner" -ForegroundColor DarkGray
    Write-Host "  Server startet sofort, Job läuft parallel" -ForegroundColor DarkGray
    Write-Host ""
    
    $response = Read-Host "Cache-Rebuild starten? (j/n) [Standard: n]"
    
    if ($response -eq 'j' -or $response -eq 'J') {
        try {
            Write-Host "Starte Background-Job..." -ForegroundColor Cyan
            
            $job = Start-CacheRebuildJob -RootPath $script:State.RootPath -Folders $script:State.Folders -ScriptRoot $ScriptRoot
            
            Write-Host "✓ Cache-Rebuild Job gestartet (ID: $($job.JobId))" -ForegroundColor Green
            Write-Host "  → Status: http://localhost:$Port/tools/cache/status" -ForegroundColor DarkGray
            Write-Host "  → Oder über Tools-Menü im Browser" -ForegroundColor DarkGray
        }
        catch {
            Write-Warning "Fehler beim Starten des Jobs: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Cache-Rebuild übersprungen" -ForegroundColor Yellow
        Write-Host "  → Kann später über Tools-Menü gestartet werden" -ForegroundColor DarkGray
    }
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
                            <div class="folder-header">
                                <input type="checkbox" class="folder-checkbox" onclick="event.stopPropagation(); toggleFolderSelection(this)">
                                <span class="folder-icon" onclick="toggleFolder(this.parentElement)">📁</span>
                                <span class="folder-name" onclick="toggleFolder(this.parentElement)">$pathDisplay</span>
                                <span class="folder-count" onclick="toggleFolder(this.parentElement)">$($folder.MediaCount) Medien</span>
                                <span class="toggle-icon" onclick="toggleFolder(this.parentElement)">▼</span>
                            </div>
                            <div class="media-grid" style="display: none;"></div>
                        </div>
"@
                    }
                    $folderListHtml = $folderRows -join "`n"
                }
                
                # HTML aus Templates generieren
                $html = Get-IndexHTML -RootPath $script:State.RootPath -FolderCards $folderListHtml -Config $config
                
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
                try {
                    $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtensions -ScriptRoot $ScriptRoot)
                    Save-State -State $script:State
                    $json = @{ ok = $true } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                }
                continue
            }
            
            # Routes: /tools/*
            if ($path -match "^/tools/") {
                if (Handle-ToolsRoute -Context $ctx -RootPath $script:State.RootPath -ScriptRoot $ScriptRoot) {
                    continue
                }
            }
            
            # Routes: /settings/*
            if ($path -match "^/settings/") {
                if (Handle-SettingsRoute -Context $ctx -ScriptRoot $ScriptRoot) {
                    continue
                }
            }
            
            # Route: /delete-files
            if ($path -eq "/delete-files") {
                if (Handle-FileOperationsRoute -Context $ctx -RootPath $script:State.RootPath -Config $config) {
                    continue
                }
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
                    # Thumbnail holen (automatisch für Fotos UND Videos)
                    $thumbPath = Get-MediaThumbnail -Path $fullPath -ScriptRoot $ScriptRoot
                    if ($thumbPath -and (Test-Path -LiteralPath $thumbPath -PathType Leaf)) {
                        $fullPath = $thumbPath
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