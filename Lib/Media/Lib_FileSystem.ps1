<#
ManifestHint:
  ExportFunctions = @("Resolve-SafePath", "Get-MediaContentType", "Test-IsVideoFile")
  Description     = "FileSystem Security & MIME Detection"
  Category        = "Core"
  Tags            = @("Security", "Path-Traversal", "MIME", "Content-Type")
  Dependencies    = @("Lib_Config.ps1")

Zweck:
  - Sichere Path-Resolution (verhindert Directory Traversal)
  - Content-Type Detection für HTTP Responses
  - Video-Datei Erkennung

Funktionen:
  - Resolve-SafePath: Sicherer Pfad-Resolver (Path-Traversal Schutz)
  - Get-MediaContentType: Extension → MIME-Type Mapping
  - Test-IsVideoFile: Prüft ob Datei ein Video ist

Sicherheit:
  - KRITISCH: Resolve-SafePath verhindert Zugriff außerhalb Root
  - Validiert dass resolved Path innerhalb RootPath liegt
  - Blockiert ..\..\.. Angriffe

Abhängigkeiten:
  - Keine

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config laden (optional, für Test-IsVideoFile)
$ScriptDir = if ($PSScriptRoot) { 
    $PSScriptRoot 
} else { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
}
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"

if (Test-Path -LiteralPath $libConfigPath) {
    . $libConfigPath
    $script:config = Get-Config
} else {
    throw "FEHLER: Lib_Config.ps1 nicht gefunden! Lib_FileSystem benötigt Config."
}

function Resolve-SafePath {
    <#
    .SYNOPSIS
        Löst relativen Pfad sicher auf (verhindert Directory Traversal)
    
    .PARAMETER RootPath
        Root-Ordner (Basis)
    
    .PARAMETER RelativePath
        Relativer Pfad (z.B. "subfolder\image.jpg")
    
    .EXAMPLE
        $full = Resolve-SafePath -RootPath "C:\Photos" -RelativePath "test.jpg"
    
    .OUTPUTS
        String - Vollständiger sicherer Pfad oder $null bei Fehler
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        
        [Parameter(Mandatory)]
        [string]$RelativePath
    )
    
    try {
        # Root normalisieren
        $rootFull = [System.IO.Path]::GetFullPath($RootPath)
        
        # Relativen Pfad kombinieren
        $combined = Join-Path $rootFull $RelativePath
        
        # Zu vollem Pfad auflösen
        try {
            $resolved = [System.IO.Path]::GetFullPath($combined)
        }
        catch [System.IO.PathTooLongException] {
            Write-Warning "Pfad zu lang (>260 Zeichen): $RelativePath"
            return $null
        }
        
        # Sicherheits-Check: Muss innerhalb Root sein
        if (-not $resolved.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Path Traversal Versuch blockiert: $RelativePath"
            return $null
        }
        
        return $resolved
        
    } catch {
        Write-Warning "Fehler beim Auflösen von Pfad: $($_.Exception.Message)"
        return $null
    }
}

function Get-MediaContentType {
    <#
    .SYNOPSIS
        Gibt Content-Type basierend auf Datei-Extension zurück
    
    .DESCRIPTION
        Nutzt Config.Media.MimeTypes für Mapping.
        Config wird von Lib_Config.ps1 bereitgestellt (automatisch geladen).
        Fallback zu "application/octet-stream" wenn Extension unbekannt.
    
    .PARAMETER Path
        Datei-Pfad
    
    .EXAMPLE
        $ct = Get-MediaContentType -Path "image.jpg"
        # Returns: "image/jpeg"
    
    .OUTPUTS
        String - MIME-Type
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    # MIME-Type aus Config
    if ($script:config -and 
        $script:config.Media.MimeTypes -and 
        $script:config.Media.MimeTypes.ContainsKey($extension)) {
        
        return $script:config.Media.MimeTypes[$extension]
    }
    
    # Unbekannte Extension → Fallback
    Write-Verbose "Unbekannte Extension '$extension' → application/octet-stream"
    return "application/octet-stream"
}

function Test-IsVideoFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Video ist
    
    .DESCRIPTION
        Prüft Extension gegen Config.Media.VideoExtensions.
        Config wird von Lib_Config.ps1 bereitgestellt (automatisch geladen).
    
    .PARAMETER Path
        Datei-Pfad
    
    .EXAMPLE
        if (Test-IsVideoFile -Path "video.mp4") { ... }
    
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    # Video-Extensions aus Config (PFLICHT!)
    if (-not $script:config -or -not $script:config.Media.VideoExtensions) {
        throw "Config nicht verfügbar oder Media.VideoExtensions fehlt!"
    }
    
    return $extension -in $script:config.Media.VideoExtensions
}