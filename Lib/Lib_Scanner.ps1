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
        Erstellt Sortier-Schlüssel für natürliche Sortierung
    
    .DESCRIPTION
        Zerlegt String in Text- und Zahlen-Teile.
        Zahlen werden auf 20 Stellen gepaddet für korrekte Sortierung.
        
    .EXAMPLE
        ConvertTo-NaturalSortKey "ebene2/bild10" 
        # → "ebene00000000000000000002/bild00000000000000000010"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )
    
    # Regex: Findet Zahlenblöcke
    $pattern = '\d+'
    
    $result = [regex]::Replace($InputString, $pattern, {
        param($match)
        # Zahlen auf 20 Stellen padden (funktioniert bis zu sehr großen Zahlen)
        $match.Value.PadLeft(20, '0')
    })
    
    return $result
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
        
        # Alle Dateien rekursiv
        $allFiles = Get-ChildItem -LiteralPath $rootFull -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in $Extensions }
        
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