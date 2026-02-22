<#
ManifestHint:
  ExportFunctions = @("Start-HttpListener", "Send-ResponseHtml", "Send-ResponseText", "Get-PowerShellVersionInfo")
  Description     = "HTTP Server und Response Helpers"
  Category        = "Core"
  Tags            = @("HTTP", "Server", "HttpListener", "Response")
  Dependencies    = @("System.Net.HttpListener")

Zweck:
  - HttpListener-Wrapper für einfachen Server-Start
  - Response-Helper für HTML, Text, JSON
  - UTF8 Encoding Management
  - PowerShell Version Detection

Funktionen:
  - Start-HttpListener: Startet HTTP Server auf Port
  - Send-ResponseHtml: Sendet HTML-Response
  - Send-ResponseText: Sendet Text/JSON-Response
  - Get-PowerShellVersionInfo: PS Version Detection

Abhängigkeiten:
  - System.Net.HttpListener

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-HttpListener {
    <#
    .SYNOPSIS
        Startet HttpListener auf angegebenem Port
    
    .DESCRIPTION
        Startet HTTP Server mit Port/Hostname aus Config.
        Falls Parameter nicht übergeben, werden Config-Werte verwendet.
    
    .PARAMETER Port
        Port-Nummer (Default: aus Config.Server.Port)
    
    .PARAMETER Hostname
        Hostname (Default: aus Config.Server.Host)
    
    .EXAMPLE
        # Mit Config-Werten:
        $listener = Start-HttpListener
    
    .EXAMPLE
        # Mit expliziten Werten:
        $listener = Start-HttpListener -Port 9000 -Hostname "0.0.0.0"
    #>
    [CmdletBinding()]
    [OutputType([System.Net.HttpListener])]
    param(
        [Parameter()]
        [int]$Port,
        
        [Parameter()]
        [string]$Hostname
    )
    
    # Config laden falls Werte nicht übergeben wurden
    if (-not $Port -or -not $Hostname) {
        # Pfad zur Config ermitteln (robuster)
        $ScriptDir = if ($PSScriptRoot) { 
            $PSScriptRoot 
        } else { 
            Split-Path -Parent $MyInvocation.MyCommand.Path 
        }
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
        $libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"
        
        if (Test-Path -LiteralPath $libConfigPath) {
            . $libConfigPath
            $config = Get-Config
            
            if (-not $Port) {
                $Port = $config.Server.Port
                Write-Verbose "Port aus Config: $Port"
            }
            
            if (-not $Hostname) {
                $Hostname = $config.Server.Host
                Write-Verbose "Hostname aus Config: $Hostname"
            }
        } else {
            # Fallback zu Defaults
            if (-not $Port) { $Port = 8888 }
            if (-not $Hostname) { $Hostname = "localhost" }
            Write-Warning "Config nicht gefunden, verwende Defaults: ${Hostname}:${Port}"
        }
    }
    
    try {
        $prefix = "http://${Hostname}:${Port}/"
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add($prefix)
        $listener.Start()
        
        Write-Verbose "HttpListener gestartet: $prefix"
        return $listener
        
    } catch {
        Write-Error "HttpListener Start fehlgeschlagen: $($_.Exception.Message)"
        throw
    }
}

function Send-ResponseHtml {
    <#
    .SYNOPSIS
        Sendet HTML-Response
    
    .PARAMETER Response
        HttpListenerResponse Objekt
    
    .PARAMETER Html
        HTML-String
    
    .PARAMETER StatusCode
        HTTP Status Code (Default: 200)
    
    .EXAMPLE
        Send-ResponseHtml -Response $res -Html "<html><body>Test</body></html>"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [string]$Html,
        
        [Parameter()]
        [int]$StatusCode = 200
    )
    
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = "text/html; charset=utf-8"
        
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($Html)
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.OutputStream.Close()
        
    } catch {
        Write-Error "Fehler beim Senden der HTML-Response: $($_.Exception.Message)"
        throw
    }
}

function Send-ResponseText {
    <#
    .SYNOPSIS
        Sendet Text-Response
    
    .PARAMETER Response
        HttpListenerResponse Objekt
    
    .PARAMETER Text
        Text-String
    
    .PARAMETER StatusCode
        HTTP Status Code (Default: 200)
    
    .PARAMETER ContentType
        Content-Type (Default: text/plain)
    
    .EXAMPLE
        Send-ResponseText -Response $res -Text "OK" -StatusCode 200
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory)]
        [string]$Text,
        
        [Parameter()]
        [int]$StatusCode = 200,
        
        [Parameter()]
        [string]$ContentType = "text/plain; charset=utf-8"
    )
    
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.OutputStream.Close()
        
    } catch {
        Write-Error "Fehler beim Senden der Text-Response: $($_.Exception.Message)"
        throw
    }
}

function Get-PowerShellVersionInfo {
    <#
    .SYNOPSIS
        Gibt PowerShell Version Info zurück
    
    .DESCRIPTION
        Erkennt PS 5.1 vs 7+ und gibt formatierte Info zurück
    
    .EXAMPLE
        $psInfo = Get-PowerShellVersionInfo
        # $psInfo.Version = "7.4.1"
        # $psInfo.IsPS7 = $true
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $version = $PSVersionTable.PSVersion
    $isPS7 = $version.Major -ge 7
    
    return [PSCustomObject]@{
        Version = $version.ToString()
        Major = $version.Major
        Minor = $version.Minor
        IsPS7 = $isPS7
        DisplayName = if ($isPS7) { "PowerShell $($version.Major).$($version.Minor)" } else { "PowerShell $($version.Major).$($version.Minor) (Legacy)" }
    }
}