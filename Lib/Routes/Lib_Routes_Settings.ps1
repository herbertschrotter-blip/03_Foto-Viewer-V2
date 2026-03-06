<#
.SYNOPSIS
    Routes Handler für Settings-Menü

.DESCRIPTION
    Behandelt alle /settings/* Routes:
    - /settings/get - Config laden
    - /settings/save - Config speichern
    - /settings/reset - Config auf Standard zurücksetzen

.NOTES
    Autor: Herbert Schrotter
    Version: 0.3.0

    ÄNDERUNGEN v0.2.0:
    - Lib_Config.ps1 dot-source hinzugefügt (war fehlend)
    - /settings/reset nutzt Get-DefaultConfig statt hardcoded Werte
    - #Requires auf 7.0 korrigiert
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest

# Libs laden
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

. (Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1")

function Handle-SettingsRoute {
    <#
    .SYNOPSIS
        Behandelt alle /settings/* Routes

    .PARAMETER Context
        HttpListenerContext

    .PARAMETER ScriptRoot
        Script-Root Pfad für config.json

    .EXAMPLE
        Handle-SettingsRoute -Context $ctx -ScriptRoot $root

    .EXAMPLE
        Handle-SettingsRoute -Context $ctx -ScriptRoot "C:\PhotoFolder"
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    $req  = $Context.Request
    $res  = $Context.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()

    try {
        # Route: /settings/get
        if ($path -eq "/settings/get" -and $req.HttpMethod -eq "GET") {
            try {
                $configPath = Join-Path $ScriptRoot "config.json"
                $configJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                Send-ResponseText -Response $res -Text $configJson -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            }
            catch {
                $json = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route: /settings/save
        if ($path -eq "/settings/save" -and $req.HttpMethod -eq "POST") {
            try {
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $body   = $reader.ReadToEnd()
                $reader.Close()

                $newSettings  = $body | ConvertFrom-Json -AsHashtable
                $configPath   = Join-Path $ScriptRoot "config.json"
                $currentConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable

                # Deep-Merge: Frontend-Settings in bestehende Config
                foreach ($section in $newSettings.Keys) {
                    if (-not $currentConfig.ContainsKey($section)) {
                        $currentConfig[$section] = @{}
                    }
                    if ($newSettings[$section] -is [hashtable] -and $currentConfig[$section] -is [hashtable]) {
                        foreach ($key in $newSettings[$section].Keys) {
                            $currentConfig[$section][$key] = $newSettings[$section][$key]
                        }
                    } else {
                        $currentConfig[$section] = $newSettings[$section]
                    }
                }

                # Speichern
                $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

                $json = @{ success = $true } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            }
            catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route: /settings/reset
        if ($path -eq "/settings/reset" -and $req.HttpMethod -eq "POST") {
            try {
                $configPath    = Join-Path $ScriptRoot "config.json"

                # Defaults aus zentraler Quelle - KEINE hardcoded Werte hier!
                $defaultConfig = Get-DefaultConfig

                # Als JSON speichern
                $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

                # Config-Cache invalidieren damit nächster Get-Config neu lädt
                Clear-ConfigCache

                $json = @{ success = $true } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            }
            catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route nicht gefunden in Settings
        return $false

    }
    catch {
        Write-Error "Settings Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}
