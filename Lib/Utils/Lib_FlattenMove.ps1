<#
ManifestHint:
  ExportFunctions = @("Get-FlattenPreview")
  Description     = "Flatten & Move - Ordnerstrukturen flach machen mit intelligenter Benennung"
  Category        = "Utils"
  Tags            = @("Flatten", "Move", "Reorganize", "FolderStructure")
  Dependencies    = @()

Zweck:
  - Ordnerstrukturen analysieren und flach machen
  - Intelligente Ziel-Ordner-Benennung aus Pfad-Ebenen
  - Duplikate in Pfad-Ebenen entfernen (test01/test01/raw -> test01_raw)
  - Preview vor dem Verschieben (keine Dateisystem-Aenderung)

Funktionen:
  - Get-FlattenPreview: Analyse + Preview (read-only)

Interne Helper:
  - Get-DeduplicatedName: Pfad-Ebenen deduplizieren + zusammenfuegen
  - Format-FlattenSize:   Bytes in menschenlesbare Groesse

Abhaengigkeiten:
  - Keine (eigenstaendig)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0

.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# ============================================================================
# INTERNE HELPER
# ============================================================================

function Get-DeduplicatedName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Levels,

        [Parameter()]
        [string]$Separator = "_",

        [Parameter()]
        [bool[]]$SelectedLevels = @()
    )

    $levelCount = @($Levels).Count
    if ($levelCount -eq 0) { return "" }

    # Ebenen filtern wenn SelectedLevels angegeben
    $activeLevels = @($Levels)
    $selCount = @($SelectedLevels).Count
    if ($selCount -gt 0 -and $selCount -eq $levelCount) {
        $filtered = [System.Collections.ArrayList]::new()
        for ($i = 0; $i -lt $levelCount; $i++) {
            if ($SelectedLevels[$i]) {
                [void]$filtered.Add($Levels[$i])
            }
        }
        $activeLevels = @($filtered)
    }

    $activeCount = @($activeLevels).Count
    if ($activeCount -eq 0) { return "" }
    if ($activeCount -eq 1) { return $activeLevels[0] }

    # Alle Duplikate entfernen: Erstes Vorkommen bleibt
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $unique = [System.Collections.ArrayList]::new()

    foreach ($level in $activeLevels) {
        if ($seen.Add($level)) {
            [void]$unique.Add($level)
        }
    }

    return ($unique -join $Separator)
}


function Format-FlattenSize {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}


# ============================================================================
# HAUPTFUNKTION: PREVIEW
# ============================================================================

function Get-FlattenPreview {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string[]]$Extensions,

        [Parameter()]
        [string]$Separator = "_"
    )

    $rootFull = [System.IO.Path]::GetFullPath($RootPath)
    Write-Verbose "Flatten-Preview: $rootFull"

    # Ignorierte Ordner
    $ignoreDirs = @('.thumbs', '.cache', '.temp', '.converted')
    $lowerExts = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($ext in $Extensions) {
        [void]$lowerExts.Add($ext.ToLowerInvariant())
    }

    # Alle Unterordner rekursiv holen
    $childDirs = Get-ChildItem -LiteralPath $rootFull -Directory -Recurse -Force -ErrorAction SilentlyContinue
    $allDirs = [System.Collections.ArrayList]::new()

    if ($null -ne $childDirs) {
        foreach ($d in @($childDirs)) {
            $dirNameLower = $d.Name.ToLowerInvariant()
            if ($dirNameLower -in $ignoreDirs) { continue }
            # Ignorierter Ordner im Pfad?
            $relToRoot = $d.FullName.Substring($rootFull.Length)
            $skip = $false
            foreach ($ig in $ignoreDirs) {
                $igEscaped = [regex]::Escape($ig)
                if ($relToRoot -match "[\\/]${igEscaped}([\\/]|$)") {
                    $skip = $true
                    break
                }
            }
            if (-not $skip) {
                [void]$allDirs.Add($d)
            }
        }
    }

    # Root selbst + alle gefundenen Unterordner
    $dirsToScan = [System.Collections.ArrayList]::new()
    [void]$dirsToScan.Add([System.IO.DirectoryInfo]::new($rootFull))
    foreach ($d in $allDirs) {
        [void]$dirsToScan.Add($d)
    }

    $folders = [System.Collections.ArrayList]::new()
    $allLevelNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $maxDepth = 0

    foreach ($dir in $dirsToScan) {
        # Nur Dateien in DIESEM Ordner (nicht rekursiv)
        $dirFiles = Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue
        if ($null -eq $dirFiles) { continue }

        # Medien-Dateien filtern
        $files = [System.Collections.ArrayList]::new()
        foreach ($f in @($dirFiles)) {
            if ($lowerExts.Contains($f.Extension.ToLowerInvariant())) {
                [void]$files.Add($f)
            }
        }

        $fileCount = @($files).Count
        if ($fileCount -eq 0) { continue }

        # Relativer Pfad
        $relPath = $dir.FullName.Substring($rootFull.Length).TrimStart('\', '/')

        # Ebenen extrahieren
        $levels = @()
        if (-not [string]::IsNullOrWhiteSpace($relPath)) {
            $splitResult = $relPath -split '[/\\]'
            $levelsArr = [System.Collections.ArrayList]::new()
            foreach ($part in $splitResult) {
                if ($part -ne '') {
                    [void]$levelsArr.Add($part)
                }
            }
            $levels = @($levelsArr)
        }

        $levelCount = @($levels).Count

        # MaxDepth tracken
        if ($levelCount -gt $maxDepth) { $maxDepth = $levelCount }

        # Ebenennamen sammeln (fuer UI)
        foreach ($lvl in $levels) { [void]$allLevelNames.Add($lvl) }

        # Deduplizierten Namen berechnen
        $suggestedName = "_root"
        if ($levelCount -gt 0) {
            $suggestedName = Get-DeduplicatedName -Levels $levels -Separator $Separator
        }

        # Groesse berechnen
        $totalSize = [long]0
        foreach ($f in $files) {
            $totalSize += $f.Length
        }

        # Dateinamen sammeln (sortiert)
        $sortedFiles = @($files | Sort-Object Name)
        $fileNames = [System.Collections.ArrayList]::new()
        foreach ($f in $sortedFiles) {
            [void]$fileNames.Add($f.Name)
        }

        [void]$folders.Add([PSCustomObject]@{
            AbsolutePath       = $dir.FullName
            RelativePath       = if ([string]::IsNullOrWhiteSpace($relPath)) { "." } else { $relPath }
            Levels             = $levels
            LevelCount         = $levelCount
            SuggestedName      = $suggestedName
            FileCount          = $fileCount
            Files              = @($fileNames)
            TotalSize          = $totalSize
            TotalSizeFormatted = Format-FlattenSize -Bytes $totalSize
            IsRoot             = ($levelCount -eq 0)
        })
    }

    # Sortieren nach relativem Pfad
    $sortedFolders = @($folders | Sort-Object RelativePath)

    # Gesamtstatistik (explizite Schleife statt Measure-Object)
    $totalFiles = [int]0
    $totalSizeAll = [long]0
    foreach ($f in $sortedFolders) {
        $totalFiles += $f.FileCount
        $totalSizeAll += $f.TotalSize
    }

    $folderCount = @($sortedFolders).Count

    Write-Verbose "Preview: $folderCount Ordner, $totalFiles Dateien, $(Format-FlattenSize -Bytes $totalSizeAll)"

    return [PSCustomObject]@{
        RootPath           = $rootFull
        TotalFolders       = $folderCount
        TotalFiles         = $totalFiles
        TotalSize          = $totalSizeAll
        TotalSizeFormatted = Format-FlattenSize -Bytes $totalSizeAll
        MaxDepth           = $maxDepth
        LevelNames         = @($allLevelNames | Sort-Object)
        Separator          = $Separator
        Folders            = $sortedFolders
    }
}