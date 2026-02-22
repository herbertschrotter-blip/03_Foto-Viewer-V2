<#
ManifestHint:
  ExportFunctions = @("Register-MediaRoutes")
  Description     = "Media-Routes (Original-Bilder, Videos)"
  Category        = "Routes"
  Tags            = @("HTTP","Media","Images","Videos")
  Dependencies    = @("System.Net.HttpListener")

Zweck:
  - Route: /original?path=... (Original-Bilder senden)
  - MIME-Type Detection
  - Range-Request Support (aus Config)
  - Path-Traversal Security

Funktionen:
  - Register-MediaRoutes: Registriert alle Media-Routes

Abhängigkeiten:
  - Lib_Config.ps1 (Get-AppConfig)
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
        
        # Route: /original
        if ($request.Url.LocalPath -eq '/original') {
            Send-OriginalImage -Context $Context -RootFull $RootFull -Config $config
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
        $mimeType = Get-MimeType -Extension $extension
        
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
        finally {
            $fileStream.Close()
        }
        
        $response.Close()
        Write-Verbose "Vollständige Datei gesendet: $FileSize Bytes"
    }
    catch {
        Write-Error "Fehler beim Senden: $_"
        $response.StatusCode = 500
        $response.Close()
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
                
                $response.OutputStream.Write($buffer, 0, $read)
                $remaining -= $read
            }
        }
        finally {
            $fileStream.Close()
        }
        
        $response.Close()
        Write-Verbose "Range-Response gesendet: $contentLength Bytes"
    }
    catch {
        Write-Error "Fehler bei Range-Request: $_"
        $response.StatusCode = 500
        $response.Close()
    }
}

function Get-MimeType {
    <#
    .SYNOPSIS
        Ermittelt MIME-Type anhand Extension
    
    .DESCRIPTION
        Gibt passenden MIME-Type für Datei-Extension zurück.
    
    .PARAMETER Extension
        Datei-Extension (z.B. ".jpg")
    
    .EXAMPLE
        Get-MimeType -Extension ".jpg"
        # Returns: "image/jpeg"
    
    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Extension
    )
    
    # MIME-Type Mapping
    $mimeTypes = @{
        '.jpg'  = 'image/jpeg'
        '.jpeg' = 'image/jpeg'
        '.png'  = 'image/png'
        '.gif'  = 'image/gif'
        '.webp' = 'image/webp'
        '.bmp'  = 'image/bmp'
        '.tif'  = 'image/tiff'
        '.tiff' = 'image/tiff'
        '.svg'  = 'image/svg+xml'
        '.ico'  = 'image/x-icon'
    }
    
    $mime = $mimeTypes[$Extension.ToLower()]
    
    if ($mime) {
        return $mime
    }
    
    # Fallback
    return 'application/octet-stream'
}