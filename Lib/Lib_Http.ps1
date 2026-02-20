<#
.SYNOPSIS
    HTTP Server und Response Helpers für Foto_Viewer_V2

.DESCRIPTION
    HttpListener-Wrapper mit Response-Helper-Funktionen.
    Unterstützt HTML, Text, JSON und Streaming.

.EXAMPLE
    $listener = Start-HttpListener -Port 8888
    Send-ResponseHtml -Response $res -Html "<html>...</html>"

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Start-HttpListener {
    <#
    .SYNOPSIS
        Startet HttpListener auf angegebenem Port
    
    .PARAMETER Port
        Port-Nummer (Default: 8888)
    
    .PARAMETER Host
        Hostname (Default: localhost)
    
    .EXAMPLE
        $listener = Start-HttpListener -Port 8888
    #>
    [CmdletBinding()]
    [OutputType([System.Net.HttpListener])]
    param(
        [Parameter()]
        [int]$Port = 8888,
        
        [Parameter()]
        [string]$Host = "localhost"
    )
    
    try {
        $prefix = "http://${Host}:${Port}/"
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