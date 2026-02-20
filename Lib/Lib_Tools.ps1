<#
.SYNOPSIS
    Tools & Maintenance für Foto_Viewer_V2

.DESCRIPTION
    Cleanup-Funktionen für .thumbs Cache und andere Wartungsaufgaben.

.EXAMPLE
    Clean-ThumbsDirectory -RootPath "C:\Photos"

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Clean-ThumbsDirectory {
    <#
    .SYNOPSIS
        Bereinigt .thumbs Ordner (entfernt verschachtelte/alte Thumbnails)
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .EXAMPLE
        $result = Clean-ThumbsDirectory -RootPath "C:\Photos"
    
    .OUTPUTS
        PSCustomObject mit DeletedCount, DeletedSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    try {
        $thumbsDir = Join-Path $RootPath ".thumbs"
        
        if (-not (Test-Path -LiteralPath $thumbsDir -PathType Container)) {
            Write-Verbose "Kein .thumbs Ordner gefunden"
            return [PSCustomObject]@{
                DeletedCount = 0
                DeletedSize = 0
            }
        }
        
        $deletedCount = 0
        $deletedSize = 0
        
        # Verschachtelte .thumbs Ordner finden und löschen
        $nestedThumbs = Get-ChildItem -LiteralPath $thumbsDir -Recurse -Directory -Filter ".thumbs" -ErrorAction SilentlyContinue
        
        foreach ($nested in $nestedThumbs) {
            Write-Verbose "Lösche verschachtelten .thumbs: $($nested.FullName)"
            
            # Größe berechnen
            $size = (Get-ChildItem -LiteralPath $nested.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            
            Remove-Item -LiteralPath $nested.FullName -Recurse -Force -ErrorAction SilentlyContinue
            
            $deletedCount++
            $deletedSize += $size
        }
        
        # Alte/ungültige Thumbnails löschen (optional: älter als X Tage)
        # Hier können später weitere Cleanup-Regeln hinzugefügt werden
        
        Write-Verbose "Cleanup abgeschlossen: $deletedCount Ordner, $([Math]::Round($deletedSize / 1MB, 2)) MB"
        
        return [PSCustomObject]@{
            DeletedCount = $deletedCount
            DeletedSize = $deletedSize
        }
        
    } catch {
        Write-Error "Fehler beim Cleanup: $($_.Exception.Message)"
        throw
    }
}

function Get-ThumbsStatistics {
    <#
    .SYNOPSIS
        Gibt Statistiken über .thumbs Cache zurück
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .EXAMPLE
        $stats = Get-ThumbsStatistics -RootPath "C:\Photos"
    
    .OUTPUTS
        PSCustomObject mit Count, TotalSize, Path
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    try {
        $thumbsDir = Join-Path $RootPath ".thumbs"
        
        if (-not (Test-Path -LiteralPath $thumbsDir -PathType Container)) {
            return [PSCustomObject]@{
                Count = 0
                TotalSize = 0
                Path = $thumbsDir
            }
        }
        
        $files = Get-ChildItem -LiteralPath $thumbsDir -File -Recurse -ErrorAction SilentlyContinue
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        
        return [PSCustomObject]@{
            Count = $files.Count
            TotalSize = $totalSize
            Path = $thumbsDir
        }
        
    } catch {
        Write-Error "Fehler beim Abrufen der Statistiken: $($_.Exception.Message)"
        throw
    }
}

function Clear-AllThumbnails {
    <#
    .SYNOPSIS
        Löscht alle Thumbnails (kompletter .thumbs Ordner)
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .EXAMPLE
        Clear-AllThumbnails -RootPath "C:\Photos"
    
    .OUTPUTS
        PSCustomObject mit Success, DeletedSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    try {
        $thumbsDir = Join-Path $RootPath ".thumbs"
        
        if (-not (Test-Path -LiteralPath $thumbsDir -PathType Container)) {
            return [PSCustomObject]@{
                Success = $true
                DeletedSize = 0
            }
        }
        
        # Größe berechnen
        $files = Get-ChildItem -LiteralPath $thumbsDir -File -Recurse -ErrorAction SilentlyContinue
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        
        # Löschen
        Remove-Item -LiteralPath $thumbsDir -Recurse -Force -ErrorAction Stop
        
        Write-Verbose "Alle Thumbnails gelöscht: $([Math]::Round($totalSize / 1MB, 2)) MB"
        
        return [PSCustomObject]@{
            Success = $true
            DeletedSize = $totalSize
        }
        
    } catch {
        Write-Error "Fehler beim Löschen: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            DeletedSize = 0
        }
    }
}