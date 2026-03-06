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
    Version: 0.10.1
    
    ÄNDERUNGEN v0.9.1:
    - Debug-Logging: Start-Transcript in debug.log
    - Verbose + Debug aktiviert (alle Details erfasst)
    - Erweiterte Error-Handling mit StackTrace
    
    ÄNDERUNGEN v0.9.0:
    - PowerShell 7.0 ONLY (Performance + Parallel)
    - System-Check beim Start (Lib_SystemCheck.ps1)
    - Long Path Support Warnung mit Admin-Anleitung
    - FFmpeg-Check in System-Check integriert
    
    ÄNDERUNGEN v0.8.2:
    - Lib_BackgroundJobs.ps1 geladen
    - Vorbereitung für Auto-Thumbnail-Generierung beim Ordner-Öffnen
    
    ÄNDERUNGEN v0.5.0:
    - Lokale .thumbs/ pro Ordner (statt zentral)
    - Get-MediaThumbnail für Fotos UND Videos
    - Cache-Validierung beim Scan (EAGER)
    - Entfernt: Zentrale $script:ThumbsDir Logik
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [int]$Port
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-Root ermitteln
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Debug-Log (wird bei jedem Start überschrieben)
$logPath = Join-Path $ScriptRoot "debug.log"
Start-Transcript -Path $logPath -Force

# Verbose + Debug aktivieren
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

Write-Host "=== PHOTO VIEWER START ===" -ForegroundColor Cyan
Write-Host "Debug-Log: $logPath" -ForegroundColor DarkGray
Write-Host ""

$libSystemCheckPath = Join-Path $ScriptRoot "Lib\System\Lib_SystemCheck.ps1"

if (Test-Path -LiteralPath $libSystemCheckPath) {
    . $libSystemCheckPath
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  SYSTEM-CHECK" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    $systemCheck = Test-SystemRequirements -ScriptRoot $ScriptRoot -ShowWarnings $false
    
    if (-not $systemCheck.AllPassed) {
        Write-Host "❌ KRITISCHE FEHLER:" -ForegroundColor Red
        foreach ($err in $systemCheck.Errors) {
            Write-Host "   • $err" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Drücke Enter zum Beenden..." -ForegroundColor Yellow
        Read-Host
        exit 1
    }
    
    if ($systemCheck.Warnings.Count -gt 0) {
        Write-Host "⚠️  WARNUNGEN:" -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $systemCheck.LongPathSupport) {
            Write-Host "📋 Long Path Support: DEAKTIVIERT" -ForegroundColor Yellow
            Write-Host "   Maximale Pfad-Länge: 260 Zeichen" -ForegroundColor Gray
            Write-Host "   Bei langen Pfaden können Fehler auftreten!" -ForegroundColor Gray
            Write-Host ""
            Write-Host "   Aktivierung (OPTIONAL - benötigt Admin-Rechte):" -ForegroundColor Cyan
            Write-Host "   1. PowerShell als Administrator starten" -ForegroundColor Gray
            Write-Host "   2. Folgenden Befehl ausführen:" -ForegroundColor Gray
            Write-Host "      Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' \" -ForegroundColor White
            Write-Host "                       -Name 'LongPathsEnabled' -Value 1" -ForegroundColor White
            Write-Host "   3. PowerShell neu starten" -ForegroundColor Gray
            Write-Host ""
        }
        
        if ($systemCheck.FFmpegAvailable -eq $false) {
            Write-Host "⚠️  FFmpeg: NICHT GEFUNDEN" -ForegroundColor Yellow
            Write-Host "   Video-Thumbnails werden nicht funktionieren!" -ForegroundColor Gray
            Write-Host ""
        }
        
        Write-Host "Trotzdem fortfahren? (J/N): " -NoNewline -ForegroundColor Yellow
        $answer = Read-Host
        
        if ($answer -ne "J" -and $answer -ne "j") {
            Write-Host ""
            Write-Host "Abgebrochen." -ForegroundColor Red
            Write-Host ""
            exit 0
        }
    }
    
    Write-Host "✅ System-Check erfolgreich!" -ForegroundColor Green
    Write-Host ""
}

# Libs laden - Core
. (Join-Path $ScriptRoot "Lib\Core\Lib_Config.ps1")
. (Join-Path $ScriptRoot "Lib\Core\Lib_State.ps1")
. (Join-Path $ScriptRoot "Lib\Core\Lib_Http.ps1")
. (Join-Path $ScriptRoot "Lib\Core\Lib_Logging.ps1")

# Libs laden - Media
. (Join-Path $ScriptRoot "Lib\Media\Lib_Scanner.ps1")
. (Join-Path $ScriptRoot "Lib\Media\Lib_Thumbnails.ps1")
. (Join-Path $ScriptRoot "Lib\Media\Lib_FileSystem.ps1")
. (Join-Path $ScriptRoot "Lib\Media\Lib_VideoThumbnails.ps1")

# Libs laden - UI
. (Join-Path $ScriptRoot "Lib\UI\Lib_Dialogs.ps1")
. (Join-Path $ScriptRoot "Lib\UI\Lib_UI_Template.ps1")

# Libs laden - Routes
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Tools.ps1")
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Settings.ps1")
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Files.ps1")
. (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Media.ps1")  # NEU - Lightbox Original-Bilder

# Libs laden - Utils
. (Join-Path $ScriptRoot "Lib\Utils\Lib_Tools.ps1")
. (Join-Path $ScriptRoot "Lib\Utils\Lib_BackgroundJobs.ps1")

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

Write-Host ""

# HttpListener starten
try {
    $listener = Start-HttpListener -Port $Port -Hostname $config.Server.Host
    Write-Host "✓ Server läuft auf: http://$($config.Server.Host):$Port" -ForegroundColor Green
} catch {
    Write-Host "FEHLER beim Server-Start: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Stop-Transcript
    return
}

# Runspace Pool für parallele Media-Requests
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $config.Performance.MaxParallelJobs)
$runspacePool.Open()
$script:ActiveRunspaces = [System.Collections.ArrayList]::new()

Write-Host "✓ Runspace Pool gestartet ($($config.Performance.MaxParallelJobs) Worker)" -ForegroundColor Green

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
            # === JOB CLEANUP ===
            # Alte abgeschlossene/fehlerhafte Jobs entfernen (verhindert File-Locks)
            Get-Job -State Completed -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
            Get-Job -State Failed -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
            
            # Route: / (Index)
            if ($path -eq "/" -and $req.HttpMethod -eq "GET") {
                
                # Ordner-Liste generieren mit JSON-Daten
                $folderListHtml = ""
                if ($script:State.Folders.Count -eq 0) {
                    $folderListHtml = "<div style='text-align:center;padding:40px;color:#718096;'>Keine Ordner mit Medien gefunden</div>"
                } else {
                    $folderRows = foreach ($folder in $script:State.Folders) {
                        $pathDisplay = if ($folder.RelativePath -eq ".") { "Root" } else { $folder.RelativePath }
                        $filesJson = (ConvertTo-Json -InputObject @($folder.Files) -Compress).Replace('"', '&quot;')
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
                if (Handle-ToolsRoute -Context $ctx -RootPath $script:State.RootPath -ScriptRoot $ScriptRoot -Config $config) {
                    continue
                }
            }
            
            # Routes: /settings/*
            if ($path -match "^/settings/") {
                if (Handle-SettingsRoute -Context $ctx -ScriptRoot $ScriptRoot) {
                    continue
                }
            }
            
            # Routes: /original, /video, /hls, /hlschunk (Media - über Runspace parallel)
            if ($path -eq '/original' -or $path -eq '/video' -or $path -eq '/hls' -or $path -eq '/hlschunk') {
                # Cleanup abgeschlossene Runspaces
                $toRemove = @()
                foreach ($rs in $script:ActiveRunspaces) {
                    if ($rs.Handle.IsCompleted) {
                        try { $rs.PowerShell.EndInvoke($rs.Handle) } catch { }
                        $rs.PowerShell.Dispose()
                        $toRemove += $rs
                    }
                }
                foreach ($rs in $toRemove) {
                    [void]$script:ActiveRunspaces.Remove($rs)
                }
                
                # Media-Request in Runspace ausführen
                $ps = [powershell]::Create()
                $ps.RunspacePool = $runspacePool
                
                [void]$ps.AddScript({
                    param($Context, $RootFull, $ScriptRoot)
                    
                    # Libs laden im Runspace
                    . (Join-Path $ScriptRoot "Lib\Core\Lib_Config.ps1")
                    . (Join-Path $ScriptRoot "Lib\Media\Lib_VideoHLS.ps1")
                    . (Join-Path $ScriptRoot "Lib\Routes\Lib_Routes_Media.ps1")
                    
                    # Route verarbeiten
                    Register-MediaRoutes -Context $Context -RootFull $RootFull
                    
                }).AddArgument($ctx).AddArgument($script:State.RootPath).AddArgument($ScriptRoot)
                
                $handle = $ps.BeginInvoke()
                [void]$script:ActiveRunspaces.Add(@{
                    PowerShell = $ps
                    Handle = $handle
                })
                
                continue
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
                    $thumbPath = Get-MediaThumbnail -Path $fullPath -ScriptRoot $ScriptRoot -MaxSize $config.UI.ThumbnailSize -Quality $config.Video.ThumbnailQuality -ThumbnailQuality $config.Video.ThumbnailQuality -ThumbnailStartPercent $config.Video.ThumbnailStartPercent
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
            
            # Route: /open-recyclebin
            if ($path -eq "/open-recyclebin" -and $req.HttpMethod -eq "POST") {
                try {
                    Start-Process "explorer.exe" -ArgumentList "shell:RecycleBinFolder"
                    Send-ResponseText -Response $res -Text '{"success":true}' -StatusCode 200 -ContentType "application/json; charset=utf-8"
                } catch {
                    Send-ResponseText -Response $res -Text '{"success":false}' -StatusCode 500 -ContentType "application/json; charset=utf-8"
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
catch {
    Write-Host "FEHLER im Server-Loop: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Red
}
finally {
    # Runspace Pool aufräumen
    if ($script:ActiveRunspaces) {
        foreach ($rs in $script:ActiveRunspaces) {
            try { $rs.PowerShell.Stop(); $rs.PowerShell.Dispose() } catch { }
        }
    }
    if ($runspacePool) {
        $runspacePool.Close()
        $runspacePool.Dispose()
        Write-Host "✓ Runspace Pool beendet" -ForegroundColor Green
    }
    
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host ""
    Write-Host "✓ Server beendet" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== PHOTO VIEWER ENDE ===" -ForegroundColor Cyan
    Stop-Transcript
    Invoke-AnonymizeLogFile -LogPath $logPath -ProjectRoot $ScriptRoot -RootPath $script:State.RootPath
}