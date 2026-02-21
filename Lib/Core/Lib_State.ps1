<#
.SYNOPSIS
    State Management für Foto_Viewer_V2

.DESCRIPTION
    Lädt und speichert Runtime-State in state.json.
    State enthält aktuellen Root-Pfad und gescannte Ordner.

.EXAMPLE
    $state = Get-State
    $state.RootPath = "C:\Photos"
    Save-State -State $state

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-State {
    <#
    .SYNOPSIS
        Lädt state.json oder gibt leeren State zurück
    
    .EXAMPLE
        $state = Get-State
    
    .OUTPUTS
        PSCustomObject mit:
        - RootPath: Aktueller Root-Ordner
        - Folders: Array mit gescannten Ordnern
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $statePath = Join-Path $scriptRoot "state.json"
        
        if (Test-Path -LiteralPath $statePath) {
            $json = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 -ErrorAction Stop
            $state = $json | ConvertFrom-Json -ErrorAction Stop
            
            Write-Verbose "State geladen: $statePath"
            return $state
        } else {
            Write-Verbose "Keine state.json gefunden, erstelle leeren State"
            return Get-EmptyState
        }
        
    } catch {
        Write-Warning "Fehler beim Laden von state.json: $($_.Exception.Message)"
        return Get-EmptyState
    }
}

function Get-EmptyState {
    <#
    .SYNOPSIS
        Gibt leeren State zurück
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    return [PSCustomObject]@{
        RootPath = ""
        Folders = @()
    }
}

function Save-State {
    <#
    .SYNOPSIS
        Speichert State in state.json
    
    .PARAMETER State
        State-Objekt zum Speichern
    
    .EXAMPLE
        $state.RootPath = "C:\Photos"
        Save-State -State $state
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State
    )
    
    try {
        $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $statePath = Join-Path $scriptRoot "state.json"
        
        $json = $State | ConvertTo-Json -Depth 10
        $json | Out-File -LiteralPath $statePath -Encoding UTF8 -Force
        
        Write-Verbose "State gespeichert: $statePath"
        
    } catch {
        Write-Error "Fehler beim Speichern von state.json: $($_.Exception.Message)"
        throw
    }
}