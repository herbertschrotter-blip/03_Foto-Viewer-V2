<#
.SYNOPSIS
    Ordner-Scanner für Foto_Viewer_V2

.DESCRIPTION
    Scannt Ordner rekursiv nach Bildern und Videos.
    Gibt Liste mit Ordnern und Medien-Anzahl zurück.
    Validiert/Rebuilded Thumbnail-Cache automatisch (OPTION B: EAGER).

.EXAMPLE
    $folders = Get-MediaFolders -RootPath "C:\Photos" -Extensions @(".jpg", ".mp4") -ScriptRoot $PSScriptRoot

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
    
    ÄNDERUNGEN v0.2.0:
    - Integration Thumbnail-Cache Validierung
    - Auto-Rebuild bei invaliden Caches
    - Orphan-Cleanup
    - ScriptRoot Parameter für FFmpeg (Videos)
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function ConvertTo-NaturalSortKey {
    <#
    .SYNOPSIS
        Erstellt Sortier-Schlüssel für Windows Explorer Natural Sort
    
    .DESCRIPTION
        Implementiert Natural Sort wie Windows Explorer (StrCmpLogicalW):
        - Zahlen numerisch sortieren (2 < 10)
        - Führende Nullen berücksichtigen (02 < 2)
        - Bei gleichem numerischen Wert: Original-String entscheidet
        
    .EXAMPLE
        ConvertTo-NaturalSortKey "ebene2/bild10" 
        # Sortiert: ebene01, ebene02, ebene2, ebene10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )
    
    # Regex: Findet Zahlenblöcke
    $pattern = '\d+'
    
    # Phase 1: Zahlen padden für numerische Sortierung
    $paddedString = [regex]::Replace($InputString, $pattern, {
        param($match)
        # Zahlen auf 20 Stellen padden
        $match.Value.PadLeft(20, '0')
    })
    
    # Phase 2: Original als Tiebreaker anhängen
    # Damit ebene02 vor ebene2 kommt (bei gleichem Zahlenwert)
    return "$paddedString`t$InputString"
}

function Get-MediaFolders {
    <#
    .SYNOPSIS
        Scannt Ordner rekursiv nach Medien
    
    .PARAMETER RootPath
        Root-Ordner zum Scannen
    
    .PARAMETER Extensions
        Array mit Datei-Endungen (z.B. @(".jpg", ".mp4"))
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg bei Video-Thumbnails)
    
    .EXAMPLE
        $folders = Get-MediaFolders -RootPath "C:\Photos" -Extensions @(".jpg", ".png", ".mp4") -ScriptRoot $PSScriptRoot
    
    .OUTPUTS
        Array von PSCustomObjects mit:
        - Path: Ordner-Pfad
        - RelativePath: Relativer Pfad zu Root
        - MediaCount: Anzahl Medien
        - Files: Array mit Dateinamen
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        
        [Parameter(Mandatory)]
        [string[]]$Extensions,
        
        [Parameter()]
        [string]$ScriptRoot
    )
    
    try {
        if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
            throw "Root-Ordner existiert nicht: $RootPath"
        }
        
        $rootFull = [System.IO.Path]::GetFullPath($RootPath)
        
        Write-Verbose "Scanne: $rootFull"
        Write-Verbose "Extensions: $($Extensions -join ', ')"
        
        # Ordner zählen für Progress
        Write-Host "  → Zähle Ordner..." -ForegroundColor DarkGray
        $allDirs = @(Get-ChildItem -LiteralPath $rootFull -Recurse -Directory -ErrorAction SilentlyContinue)
        $totalDirs = $allDirs.Count
        Write-Host "  → Scanne $totalDirs Ordner..." -ForegroundColor DarkGray
        
        # Alle Dateien rekursiv mit Progress
        $allFiles = @()
        $currentDir = 0
        
        foreach ($dir in $allDirs) {
            $currentDir++
            
            Write-Progress -Activity "Scanne Ordner" `
                           -Status "Ordner $currentDir von $totalDirs" `
                           -PercentComplete (($currentDir / $totalDirs) * 100) `
                           -CurrentOperation $dir.Name
            
            $files = Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in $Extensions }
            
            $allFiles += $files
        }
        
        Write-Progress -Activity "Scanne Ordner" -Completed
        
        # Nach Ordner gruppieren
        $grouped = $allFiles | Group-Object -Property DirectoryName
        
        $result = foreach ($group in $grouped) {
            $folderPath = $group.Name
            $relativePath = $folderPath.Substring($rootFull.Length).TrimStart('\', '/')
            
            if ([string]::IsNullOrEmpty($relativePath)) {
                $relativePath = "."
            }
            
            [PSCustomObject]@{
                Path = $folderPath
                RelativePath = $relativePath
                MediaCount = $group.Count
                Files = @($group.Group | ForEach-Object { $_.Name })
            }
        }
        
        # Natural Sort nach RelativePath
        $sorted = $result | Sort-Object -Property @{
            Expression = { ConvertTo-NaturalSortKey -InputString $_.RelativePath }
        }
        
        # ============================================
        # THUMBNAIL-CACHE VALIDIERUNG (OPTION B: EAGER)
        # ============================================
        
        Write-Host "  → Validiere Thumbnail-Cache..." -ForegroundColor DarkGray
        
        # Lade Thumbnail-Lib (falls noch nicht geladen)
        if (-not (Get-Command Update-ThumbnailCache -ErrorAction SilentlyContinue)) {
            # Pfad zur Lib ermitteln (relativ zu diesem Script)
            $libPath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "Lib\Media\Lib_Thumbnails.ps1"
            
            if (Test-Path -LiteralPath $libPath) {
                . $libPath
                Write-Verbose "Lib_Thumbnails.ps1 geladen"
            } else {
                Write-Warning "Lib_Thumbnails.ps1 nicht gefunden: $libPath"
            }
        }
        
        # Cache validieren/rebuilden für jeden Ordner
        $cacheUpdated = 0
        $cacheValid = 0
        
        if (Get-Command Test-ThumbnailCacheValid -ErrorAction SilentlyContinue) {
            foreach ($folder in $sorted) {
                if (-not (Test-ThumbnailCacheValid -FolderPath $folder.Path)) {
                    Write-Verbose "Cache rebuild: $($folder.RelativePath)"
                    
                    $generated = Update-ThumbnailCache -FolderPath $folder.Path -ScriptRoot $ScriptRoot -MaxSize 300
                    
                    if ($generated -gt 0) {
                        Remove-OrphanedThumbnails -FolderPath $folder.Path
                        $cacheUpdated++
                    }
                } else {
                    $cacheValid++
                }
            }
            
            if ($cacheUpdated -gt 0) {
                Write-Host "  → Cache aktualisiert: $cacheUpdated Ordner" -ForegroundColor Green
            }
            if ($cacheValid -gt 0) {
                Write-Verbose "Cache valide: $cacheValid Ordner"
            }
        }
        
        Write-Verbose "Gefunden: $($sorted.Count) Ordner mit Medien"
        return $sorted
        
    } catch {
        Write-Error "Fehler beim Scannen: $($_.Exception.Message)"
        throw
    }
}