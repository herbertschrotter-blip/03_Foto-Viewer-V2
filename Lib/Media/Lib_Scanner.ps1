<#
.SYNOPSIS
    Ordner-Scanner für Foto_Viewer_V2

.DESCRIPTION
    Scannt Ordner rekursiv nach Bildern und Videos.
    Gibt Liste mit Ordnern und Medien-Anzahl zurück.

.EXAMPLE
    $folders = Get-MediaFolders -RootPath "C:\Photos" -Extensions @(".jpg", ".mp4")

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
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
    
    .EXAMPLE
        $folders = Get-MediaFolders -RootPath "C:\Photos" -Extensions @(".jpg", ".png", ".mp4")
    
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
        [string[]]$Extensions
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
        
        Write-Verbose "Gefunden: $($sorted.Count) Ordner mit Medien"
        return $sorted
        
    } catch {
        Write-Error "Fehler beim Scannen: $($_.Exception.Message)"
        throw
    }
}