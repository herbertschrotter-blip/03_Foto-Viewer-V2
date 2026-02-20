<#
.SYNOPSIS
    FileSystem Helper für Foto_Viewer_V2

.DESCRIPTION
    Sichere Path-Resolution, verhindert Directory Traversal.
    Content-Type Detection für Medien.

.EXAMPLE
    $fullPath = Resolve-SafePath -RootPath "C:\Photos" -RelativePath "subfolder\image.jpg"

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

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
        $resolved = [System.IO.Path]::GetFullPath($combined)
        
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
    
    .PARAMETER Path
        Datei-Pfad
    
    .EXAMPLE
        $ct = Get-MediaContentType -Path "image.jpg"
        # Returns: "image/jpeg"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    switch ($extension) {
        ".jpg"  { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".png"  { return "image/png" }
        ".gif"  { return "image/gif" }
        ".webp" { return "image/webp" }
        ".bmp"  { return "image/bmp" }
        ".tif"  { return "image/tiff" }
        ".tiff" { return "image/tiff" }
        ".mp4"  { return "video/mp4" }
        ".mov"  { return "video/quicktime" }
        ".avi"  { return "video/x-msvideo" }
        ".mkv"  { return "video/x-matroska" }
        ".webm" { return "video/webm" }
        ".m4v"  { return "video/mp4" }
        ".wmv"  { return "video/x-ms-wmv" }
        ".flv"  { return "video/x-flv" }
        ".mpg"  { return "video/mpeg" }
        ".mpeg" { return "video/mpeg" }
        ".3gp"  { return "video/3gpp" }
        default { return "application/octet-stream" }
    }
}

function Test-IsVideoFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Video ist
    
    .PARAMETER Path
        Datei-Pfad
    
    .EXAMPLE
        if (Test-IsVideoFile -Path "video.mp4") { ... }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    
    return $extension -in @(".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".wmv", ".flv", ".mpg", ".mpeg", ".3gp")
}