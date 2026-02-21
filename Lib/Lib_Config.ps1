<#
.SYNOPSIS
    Konfigurationsverwaltung für Foto_Viewer_V2

.DESCRIPTION
    Lädt und speichert config.json mit Validierung.
    Unterstützt Standard-Werte bei fehlenden Einträgen.

.EXAMPLE
    $config = Get-Config
    $port = $config.Server.Port

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-Config {
    <#
    .SYNOPSIS
        Lädt config.json aus Projekt-Root
    
    .DESCRIPTION
        Lädt Konfiguration, validiert JSON, gibt PSCustomObject zurück.
        Bei Fehler: Gibt Standard-Config zurück.
    
    .EXAMPLE
        $config = Get-Config
        $port = $config.Server.Port
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $configPath = Join-Path $scriptRoot "config.json"
        
        if (-not (Test-Path -LiteralPath $configPath)) {
            Write-Warning "config.json nicht gefunden: $configPath"
            return Get-DefaultConfig
        }
        
        $json = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        
        Write-Verbose "Config geladen: $configPath"
        return $config
        
    } catch {
        Write-Error "Fehler beim Laden der Config: $($_.Exception.Message)"
        return Get-DefaultConfig
    }
}

function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Gibt Standard-Konfiguration zurück
    
    .DESCRIPTION
        Fallback wenn config.json nicht geladen werden kann.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
        return @{
        Server = @{
            Port = 8888
            AutoOpenBrowser = $true
            Host = "localhost"
        }
        Paths = @{
            RootFolder = ""
            ThumbsFolder = ".thumbs"
            TempFolder = ".temp"
            ConvertedFolder = ".converted"
        }
        Performance = @{
            UseParallelProcessing = $true
            MaxParallelJobs = 8
        }
    }
}

function Save-Config {
    <#
    .SYNOPSIS
        Speichert Konfiguration in config.json
    
    .DESCRIPTION
        Konvertiert PSCustomObject zu JSON und speichert formatiert.
    
    .PARAMETER Config
        Konfigurations-Objekt zum Speichern
    
    .EXAMPLE
        $config.Server.Port = 9999
        Save-Config -Config $config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $configPath = Join-Path $scriptRoot "config.json"
        
        $json = $Config | ConvertTo-Json -Depth 10
        $json | Out-File -LiteralPath $configPath -Encoding UTF8 -Force
        
        Write-Verbose "Config gespeichert: $configPath"
        
    } catch {
        Write-Error "Fehler beim Speichern der Config: $($_.Exception.Message)"
        throw
    }
}