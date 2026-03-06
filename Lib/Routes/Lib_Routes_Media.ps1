<#
ManifestHint:
  ExportFunctions = @("Register-MediaRoutes")
  Description     = "Media-Routes (Original-Bilder + Videos)"
  Category        = "Routes"
  Tags            = @("HTTP","Media","Images","Videos")
  Dependencies    = @("System.Net.HttpListener")

Zweck:
  - Route: /original?path=... (Original-Bilder senden)
  - Route: /video?path=... (Video-Streaming)
  - MIME-Type Detection (Bilder + Videos)
  - Range-Request Support (aus Config)
  - Path-Traversal Security

Funktionen:
  - Register-MediaRoutes: Registriert alle Media-Routes

Abhängigkeiten:
  - Lib_Config.ps1 (Get-Config)
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Libs laden
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

$configPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"
Write-Verbose "Lib_Routes_Media.ps1 lädt Config von: $configPath"
Write-Verbose "Config-Datei existiert: $(Test-Path -LiteralPath $configPath)"

. $configPath

# HLS-Lib laden
$hlsLibPath = Join-Path $ProjectRoot "Lib\Media\Lib_VideoHLS.ps1"
if (Test-Path -LiteralPath $hlsLibPath) {
    . $hlsLibPath
    Write-Verbose "Lib_VideoHLS.ps1 geladen"
}

function Register-MediaRoutes {
    <#
    .SYNOPSIS
        Registriert Media-Routes (Original-Bilder)
    
    .DESCRIPTION
        Registriert HTTP-Routes für Media-Operationen:
        - /original?path=... (Original-Bild senden)
        
        Features:
        - Path-Traversal Security Check
        - MIME-Type Detection
        - Range-Request Support (wenn aktiviert in Config)
        - Error-Handling
    
    .PARAMETER Context
        HttpListener Context
    
    .PARAMETER RootFull
        Root-Ordner (vollständiger Pfad)
    
    .EXAMPLE
        Register-MediaRoutes -Context $context -RootFull "C:\Photos"
    
    .NOTES
        Autor: Herbert
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootFull
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        # Config laden
        $config = Get-Config
        
        # Route: /original (Bilder)
        if ($request.Url.LocalPath -eq '/original') {
            Send-OriginalImage -Context $Context -RootFull $RootFull -Config $config
            return $true
        }
        
        # Route: /video (Videos — Direct oder HLS)
        if ($request.Url.LocalPath -eq '/video') {
            # HLS aktiviert? → Konvertieren und Playlist senden
            if ($config.Video.UseHLS) {
                Send-VideoHLS -Context $Context -RootFull $RootFull -Config $config -ScriptRoot $ProjectRoot
            }
            else {
                Send-MediaFile -Context $Context -RootFull $RootFull -Config $config -MediaType 'video'
            }
            return $true
        }
        
        # Route: /hls (HLS Playlist .m3u8)
        if ($request.Url.LocalPath -eq '/hls') {
            Send-HLSPlaylist -Context $Context -RootFull $RootFull -Config $config
            return $true
        }
        
        # Route: /hlschunk (HLS Segment .ts)
        if ($request.Url.LocalPath -eq '/hlschunk') {
            Send-HLSChunk -Context $Context -RootFull $RootFull -Config $config
            return $true
        }
        
        return $false
    }
    catch {
        Write-Error "Fehler in Register-MediaRoutes: $_"
        $response.StatusCode = 500
        $response.Close()
        return $true
    }
}

function Send-MediaFile {
    <#
    .SYNOPSIS
        Sendet Media-Datei (Video/Bild) an Client
    
    .DESCRIPTION
        Universelle Funktion für Media-Streaming.
        Unterstützt Range-Requests für Video-Seeking.
        
        Features:
        - Path-Traversal Security Check
        - MIME-Type Detection
        - Range-Request Support (aus Config)
        - Robustes Error-Handling für Client-Disconnect
    
    .PARAMETER Context
        HttpListener Context
    
    .PARAMETER RootFull
        Root-Ordner (vollständiger Pfad)
    
    .PARAMETER Config
        App-Config (für RangeRequestSupport)
    
    .PARAMETER MediaType
        'video' oder 'image' (für Logging)
    
    .EXAMPLE
        Send-MediaFile -Context $ctx -RootFull "C:\Media" -Config $config -MediaType 'video'
    
    .NOTES
        Autor: Herbert
        Version: 0.2.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [ValidateSet('video', 'image')]
        [string]$MediaType
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        # Query-Parameter: path
        $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $relPath = $query['path']
        
        if (-not $relPath) {
            Write-Warning "Kein 'path' Parameter ($MediaType)"
            $response.StatusCode = 400
            $response.Close()
            return
        }
        
        Write-Verbose "$MediaType angefordert: $relPath"
        
        # Path-Traversal Security Check
        $combined = Join-Path $RootFull $relPath
        $fullPath = [System.IO.Path]::GetFullPath($combined)
        
        if (-not $fullPath.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Path-Traversal Versuch blockiert: $relPath"
            $response.StatusCode = 403
            $response.Close()
            return
        }
        
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Write-Warning "$MediaType nicht gefunden: $fullPath"
            $response.StatusCode = 404
            $response.Close()
            return
        }
        
        # MIME-Type Detection
        $extension = [System.IO.Path]::GetExtension($fullPath).ToLower()
        $mimeType = Get-MimeType -Extension $extension -Config $Config
        
        Write-Verbose "MIME-Type: $mimeType"
        
        # Datei-Info
        $fileInfo = Get-Item -LiteralPath $fullPath
        $fileSize = $fileInfo.Length
        
        # Range-Request Support (aus Config)
        $supportsRange = $Config.FileOperations.RangeRequestSupport
        
        if ($supportsRange -and $request.Headers['Range']) {
            Write-Verbose "Range-Request erkannt ($MediaType)"
            Send-RangeResponse -Context $Context -FilePath $fullPath -FileSize $fileSize -MimeType $mimeType
        }
        else {
            Write-Verbose "Vollständige Datei senden ($MediaType)"
            Send-FullResponse -Context $Context -FilePath $fullPath -FileSize $fileSize -MimeType $mimeType
        }
    }
    catch {
        Write-Error "Fehler in Send-MediaFile ($MediaType): $_"
        try { $response.StatusCode = 500; $response.Close() } catch { }
    }
}

function Send-VideoHLS {
    <#
    .SYNOPSIS
        Konvertiert Video zu HLS und sendet Playlist-URL
    
    .DESCRIPTION
        On-Demand HLS-Konvertierung. Gibt JSON mit Playlist-URL zurück.
        Browser nutzt dann /hls und /hlschunk Endpoints zum Streamen.
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $relPath = $query['path']
        
        if (-not $relPath) {
            $response.StatusCode = 400
            $response.Close()
            return
        }
        
        # Path-Traversal Check
        $combined = Join-Path $RootFull $relPath
        $fullPath = [System.IO.Path]::GetFullPath($combined)
        
        if (-not $fullPath.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
            $response.StatusCode = 403
            $response.Close()
            return
        }
        
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $response.StatusCode = 404
            $response.Close()
            return
        }
        
        Write-Verbose "HLS angefordert: $relPath"
        
        # HLS bereits vorhanden?
        $hlsReady = Test-HLSExists -VideoPath $fullPath -RootFull $RootFull
        
        if (-not $hlsReady) {
            Write-Verbose "HLS-Konvertierung starten (Background)..."
            $playlistPath = Start-HLSConversion -VideoPath $fullPath -RootFull $RootFull -ScriptRoot $ProjectRoot
            
            if (-not $playlistPath) {
                Write-Warning "HLS-Konvertierung fehlgeschlagen: $relPath"
                Send-MediaFile -Context $Context -RootFull $RootFull -Config $Config -MediaType 'video'
                return
            }
        }
        
        # Sofort antworten — Frontend pollt /hls bis Playlist + Chunks da sind
        $hlsUrl = "/hls?path=" + [System.Web.HttpUtility]::UrlEncode($relPath)
        $json = @{ 
            status = if ($hlsReady) { "ready" } else { "converting" }
            url = $hlsUrl
            preloadSeconds = $config.Video.HLSPreloadSeconds
        } | ConvertTo-Json -Compress
        
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response.StatusCode = 200
        $response.ContentType = 'application/json'
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        try { $response.Close() } catch { }
    }
    catch {
        Write-Verbose "Fehler in Send-VideoHLS: $_"
        try { $response.StatusCode = 500; $response.Close() } catch { }
    }
}

function Send-HLSPlaylist {
    <#
    .SYNOPSIS
        Sendet HLS-Playlist (.m3u8) mit umgeschriebenen Chunk-URLs
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $relPath = $query['path']
        
        if (-not $relPath) {
            $response.StatusCode = 400
            $response.Close()
            return
        }
        
        # Path-Traversal Check
        $combined = Join-Path $RootFull $relPath
        $fullPath = [System.IO.Path]::GetFullPath($combined)
        
        if (-not $fullPath.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
            $response.StatusCode = 403
            $response.Close()
            return
        }
        
        # Playlist-Pfad berechnen
        $playlistPath = Get-HLSPlaylistPath -VideoPath $fullPath -RootFull $RootFull
        
        if (-not (Test-Path -LiteralPath $playlistPath -PathType Leaf)) {
            Write-Warning "HLS-Playlist nicht gefunden: $playlistPath"
            $response.StatusCode = 404
            $response.Close()
            return
        }
        
        # Playlist lesen und Chunk-URLs umschreiben
        $hlsDir = Split-Path -Parent $playlistPath
        $playlistContent = Get-Content -LiteralPath $playlistPath -Raw -Encoding UTF8
        
        # chunk_000.ts → /hlschunk?path=<relative-path-to-chunk>
        $rewrittenContent = $playlistContent -replace '(chunk_\d+\.ts)', {
            $chunkFile = $_.Groups[1].Value
            $chunkFullPath = Join-Path $hlsDir $chunkFile
            $chunkRelPath = $chunkFullPath.Substring($RootFull.Length).TrimStart('\', '/').Replace('\', '/')
            "/hlschunk?path=$([System.Web.HttpUtility]::UrlEncode($chunkRelPath))"
        }
        
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($rewrittenContent)
        $response.StatusCode = 200
        $response.ContentType = 'application/vnd.apple.mpegurl'
        $response.ContentLength64 = $bytes.Length
        $response.Headers.Add('Access-Control-Allow-Origin', '*')
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        try { $response.Close() } catch { }
        
        Write-Verbose "HLS-Playlist gesendet: $playlistPath"
    }
    catch {
        Write-Verbose "Fehler in Send-HLSPlaylist: $_"
        try { $response.StatusCode = 500; $response.Close() } catch { }
    }
}

function Send-HLSChunk {
    <#
    .SYNOPSIS
        Sendet HLS-Chunk (.ts Segment)
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $relPath = $query['path']
        
        if (-not $relPath) {
            $response.StatusCode = 400
            $response.Close()
            return
        }
        
        # Path-Traversal Check
        $combined = Join-Path $RootFull $relPath
        $fullPath = [System.IO.Path]::GetFullPath($combined)
        
        if (-not $fullPath.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
            $response.StatusCode = 403
            $response.Close()
            return
        }
        
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Write-Warning "HLS-Chunk nicht gefunden: $fullPath"
            $response.StatusCode = 404
            $response.Close()
            return
        }
        
        # Chunk streamen
        $fileInfo = Get-Item -LiteralPath $fullPath
        $response.StatusCode = 200
        $response.ContentType = 'video/mp2t'
        $response.ContentLength64 = $fileInfo.Length
        $response.Headers.Add('Access-Control-Allow-Origin', '*')
        
        $fileStream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $fileStream.CopyTo($response.OutputStream)
        }
        catch {
            Write-Verbose "Client disconnected während Chunk-Transfer"
        }
        finally {
            $fileStream.Close()
        }
        
        try { $response.Close() } catch { }
        Write-Verbose "HLS-Chunk gesendet: $relPath"
    }
    catch {
        Write-Verbose "Fehler in Send-HLSChunk: $_"
        try { $response.StatusCode = 500; $response.Close() } catch { }
    }
}

function Send-OriginalImage {
    <#
    .SYNOPSIS
        Sendet Original-Bild an Client
    
    .DESCRIPTION
        Lädt Original-Bild von Disk und sendet es an Client.
        
        Features:
        - Path-Traversal Security Check
        - MIME-Type Detection
        - Range-Request Support (aus Config)
        - Caching-Header
    
    .PARAMETER Context
        HttpListener Context
    
    .PARAMETER RootFull
        Root-Ordner (vollständiger Pfad)
    
    .PARAMETER Config
        App-Config (für RangeRequestSupport)
    
    .EXAMPLE
        Send-OriginalImage -Context $ctx -RootFull "C:\Photos" -Config $config
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootFull,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        # Query-Parameter: path
        $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $relPath = $query['path']
        
        if (-not $relPath) {
            Write-Warning "Kein 'path' Parameter"
            $response.StatusCode = 400
            $response.Close()
            return
        }
        
        Write-Verbose "Original-Bild angefordert: $relPath"
        
        # Path-Traversal Security Check
        $combined = Join-Path $RootFull $relPath
        $fullPath = [System.IO.Path]::GetFullPath($combined)
        
        if (-not $fullPath.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Path-Traversal Versuch blockiert: $relPath"
            $response.StatusCode = 403
            $response.Close()
            return
        }
        
        # Datei existiert?
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Write-Warning "Datei nicht gefunden: $fullPath"
            $response.StatusCode = 404
            $response.Close()
            return
        }
        
        # MIME-Type Detection
        $extension = [System.IO.Path]::GetExtension($fullPath).ToLower()
        $mimeType = Get-MimeType -Extension $extension -Config $Config        
        Write-Verbose "MIME-Type: $mimeType"
        
        # Datei-Info
        $fileInfo = Get-Item -LiteralPath $fullPath
        $fileSize = $fileInfo.Length
        
        # Range-Request Support (aus Config)
        $supportsRange = $Config.FileOperations.RangeRequestSupport
        
        if ($supportsRange -and $request.Headers['Range']) {
            Write-Verbose "Range-Request erkannt"
            Send-RangeResponse -Context $Context -FilePath $fullPath -FileSize $fileSize -MimeType $mimeType
        }
        else {
            Write-Verbose "Vollständige Datei senden"
            Send-FullResponse -Context $Context -FilePath $fullPath -FileSize $fileSize -MimeType $mimeType
        }
    }
    catch {
        Write-Error "Fehler in Send-OriginalImage: $_"
        $response.StatusCode = 500
        $response.Close()
    }
}

function Send-FullResponse {
    <#
    .SYNOPSIS
        Sendet vollständige Datei
    
    .DESCRIPTION
        Sendet komplette Datei ohne Range-Request.
    
    .PARAMETER Context
        HttpListener Context
    
    .PARAMETER FilePath
        Pfad zur Datei
    
    .PARAMETER FileSize
        Dateigröße in Bytes
    
    .PARAMETER MimeType
        MIME-Type
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [long]$FileSize,
        
        [Parameter(Mandatory)]
        [string]$MimeType
    )
    
    $response = $Context.Response
    
    try {
        $response.StatusCode = 200
        $response.ContentType = $MimeType
        $response.ContentLength64 = $FileSize
        $response.Headers.Add('Accept-Ranges', 'bytes')
        $response.Headers.Add('Cache-Control', 'public, max-age=3600')
        
        # Datei streamen
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        try {
            $fileStream.CopyTo($response.OutputStream)
        }
        catch {
            Write-Verbose "Client disconnected während Transfer"
        }
        finally {
            $fileStream.Close()
        }
        
        try { $response.Close() } catch { }
        Write-Verbose "Vollständige Datei gesendet: $FileSize Bytes"
    }
    catch {
        Write-Verbose "Fehler beim Senden (oft normal bei Video): $_"
        try { $response.Close() } catch { }
    }
}

function Send-RangeResponse {
    <#
    .SYNOPSIS
        Sendet Partial Content (HTTP 206)
    
    .DESCRIPTION
        Sendet nur angeforderten Bereich der Datei (Range-Request).
    
    .PARAMETER Context
        HttpListener Context
    
    .PARAMETER FilePath
        Pfad zur Datei
    
    .PARAMETER FileSize
        Dateigröße in Bytes
    
    .PARAMETER MimeType
        MIME-Type
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [long]$FileSize,
        
        [Parameter(Mandatory)]
        [string]$MimeType
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    try {
        # Parse Range Header: "bytes=0-1023"
        $rangeHeader = $request.Headers['Range']
        $rangeMatch = [regex]::Match($rangeHeader, 'bytes=(\d+)-(\d*)')
        
        if (-not $rangeMatch.Success) {
            Write-Warning "Ungültiger Range Header: $rangeHeader"
            Send-FullResponse -Context $Context -FilePath $FilePath -FileSize $FileSize -MimeType $MimeType
            return
        }
        
        $rangeStart = [long]$rangeMatch.Groups[1].Value
        $rangeEndStr = $rangeMatch.Groups[2].Value
        
        # Range-End bestimmen
        if ([string]::IsNullOrEmpty($rangeEndStr)) {
            $rangeEnd = $FileSize - 1
        }
        else {
            $rangeEnd = [long]$rangeEndStr
        }
        
        # Validierung
        if ($rangeStart -ge $FileSize -or $rangeEnd -ge $FileSize -or $rangeStart -gt $rangeEnd) {
            Write-Warning "Ungültiger Range: $rangeStart-$rangeEnd (FileSize: $FileSize)"
            $response.StatusCode = 416  # Range Not Satisfiable
            $response.Headers.Add('Content-Range', "bytes */$FileSize")
            $response.Close()
            return
        }
        
        $contentLength = $rangeEnd - $rangeStart + 1
        
        Write-Verbose "Range-Request: bytes $rangeStart-$rangeEnd/$FileSize ($contentLength bytes)"
        
        # Response-Header
        $response.StatusCode = 206  # Partial Content
        $response.ContentType = $MimeType
        $response.ContentLength64 = $contentLength
        $response.Headers.Add('Content-Range', "bytes $rangeStart-$rangeEnd/$FileSize")
        $response.Headers.Add('Accept-Ranges', 'bytes')
        $response.Headers.Add('Cache-Control', 'public, max-age=3600')
        
        # Datei-Teil streamen
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        try {
            $fileStream.Seek($rangeStart, [System.IO.SeekOrigin]::Begin) | Out-Null
            
            $buffer = New-Object byte[] 8192
            $remaining = $contentLength
            
            while ($remaining -gt 0) {
                $toRead = [Math]::Min($buffer.Length, $remaining)
                $read = $fileStream.Read($buffer, 0, $toRead)
                
                if ($read -le 0) { break }
                
                try {
                    $response.OutputStream.Write($buffer, 0, $read)
                    $remaining -= $read
                }
                catch {
                    # Client hat Verbindung geschlossen (normal bei Video-Seeking)
                    Write-Verbose "Client disconnected während Range-Transfer"
                    break
                }
            }
        }
        finally {
            $fileStream.Close()
        }
        
        try { $response.Close() } catch { }
        Write-Verbose "Range-Response gesendet: $contentLength Bytes"
    }
    catch {
        Write-Verbose "Range-Request abgebrochen (normal bei Video-Seeking): $_"
        try { $response.Close() } catch { }
    }
}

function Get-MimeType {
    <#
    .SYNOPSIS
        Ermittelt MIME-Type aus Config (Media.MimeTypes)
    
    .DESCRIPTION
        Gibt passenden MIME-Type für Datei-Extension zurück.
        Liest MIME-Types aus Config.Media.MimeTypes.
    
    .PARAMETER Extension
        Datei-Extension (z.B. ".jpg")
    
    .PARAMETER Config
        App-Config (mit Media.MimeTypes)
    
    .EXAMPLE
        Get-MimeType -Extension ".jpg" -Config $config
        # Returns: "image/jpeg"
    
    .NOTES
        Version: 0.2.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Extension,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    # MIME-Types aus Config
    $mimeTypes = $Config.Media.MimeTypes
    
    if ($mimeTypes) {
        $mime = $mimeTypes[$Extension.ToLower()]
        if ($mime) {
            return $mime
        }
    }
    
    Write-Verbose "Kein MIME-Type für '$Extension' in Config - nutze Fallback"
    return 'application/octet-stream'
}