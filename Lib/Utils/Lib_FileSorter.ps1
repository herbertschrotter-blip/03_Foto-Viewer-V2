<#
ManifestHint:
  ExportFunctions = @("Get-FileGroups", "Invoke-FileSorting", "Export-FileNames",
                       "Get-SorterPatterns", "Save-SorterPatterns",
                       "Add-SorterPattern", "Remove-SorterPattern",
                       "Move-FileBetweenGroups", "Merge-FileGroups", "Split-FileGroup",
                       "Undo-FileSorting")
  Description     = "Dateinamen-Analyse, Multi-Pattern-Gruppierung und Auto-Sortierung"
  Category        = "Utils"
  Tags            = @("FileSorter", "Grouping", "Organize", "Pattern", "Undo")
  Dependencies    = @()

Zweck:
  - Multi-Pattern-Engine: Prefix, Datum, Custom-Regex (erweiterbar)
  - Pattern-Profile als JSON gespeichert (file-sorter-patterns.json)
  - Dateinamen-Export in _filenames.log (manuelle Analyse)
  - Preview-Gruppierung VOR dem Sortieren
  - Gruppen-Manipulation: Umgruppieren, Mergen, Splitten
  - Sortierung mit Undo-Log (_undo-sort.json)

Funktionen:
  - Get-SorterPatterns:     Pattern-Profile laden (JSON oder Defaults)
  - Save-SorterPatterns:    Pattern-Profile speichern
  - Add-SorterPattern:      Neues Custom-Pattern hinzufügen
  - Remove-SorterPattern:   Pattern entfernen / deaktivieren
  - Export-FileNames:       Dateinamen + Statistik in Log-Datei
  - Get-FileGroups:         Multi-Pattern Analyse + Gruppierung
  - Move-FileBetweenGroups: Datei zwischen Gruppen verschieben (in-memory)
  - Merge-FileGroups:       Zwei Gruppen zusammenführen (in-memory)
  - Split-FileGroup:        Gruppe aufteilen (in-memory)
  - Invoke-FileSorting:     Dateien verschieben mit Undo-Log
  - Undo-FileSorting:       Letzte Sortierung rückgängig machen

Abhängigkeiten:
  - Keine (eigenständig)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# ============================================================================
# INTERNE HELPER
# ============================================================================

function Format-FileSize {
    <# Interner Helper: Bytes in menschenlesbare Größe #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}


# ============================================================================
# PATTERN PROFILE MANAGEMENT
# ============================================================================

function Get-SorterPatterns {
    <#
    .SYNOPSIS
        Lädt Pattern-Profile aus file-sorter-patterns.json

    .DESCRIPTION
        Liest gespeicherte Pattern-Definitionen. Falls Datei nicht existiert,
        werden Built-in Defaults zurückgegeben. Jedes Pattern hat: Name,
        Regex, GroupCapture, Priority, Enabled, BuiltIn, Description.

    .PARAMETER ScriptRoot
        Projekt-Root Pfad (wo file-sorter-patterns.json liegt)

    .EXAMPLE
        $patterns = Get-SorterPatterns -ScriptRoot $ScriptRoot

    .EXAMPLE
        $active = Get-SorterPatterns -ScriptRoot $root | Where-Object Enabled

    .OUTPUTS
        [PSCustomObject[]]
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptRoot
    )

    $jsonPath = Join-Path $ScriptRoot "file-sorter-patterns.json"

    $defaults = @(
        [PSCustomObject]@{
            Name = "Prefix"; Regex = '^([a-zA-Z]{1,2}\d{2,3})'; GroupCapture = 1
            Priority = 10; Enabled = $true; BuiltIn = $true
            Description = "1-2 Buchstaben + 2-3 Ziffern (z.B. p006, pa09, pa170)"
        }
        [PSCustomObject]@{
            Name = "Datum_YYYY-MM-DD"; Regex = '(\d{4}-\d{2}-\d{2})'; GroupCapture = 1
            Priority = 20; Enabled = $false; BuiltIn = $true
            Description = "Datum im Format YYYY-MM-DD (z.B. 2024-01-15)"
        }
        [PSCustomObject]@{
            Name = "Datum_YYYYMMDD"; Regex = '(\d{4}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01]))'; GroupCapture = 1
            Priority = 30; Enabled = $false; BuiltIn = $true
            Description = "Datum im Format YYYYMMDD (z.B. 20240115)"
        }
    )

    if (-not (Test-Path -LiteralPath $jsonPath)) {
        Write-Verbose "Keine Pattern-Datei gefunden, verwende Defaults"
        return $defaults
    }

    try {
        $json = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 -ErrorAction Stop
        $loaded = $json | ConvertFrom-Json -ErrorAction Stop

        $patterns = [System.Collections.ArrayList]::new()
        foreach ($item in $loaded) {
            [void]$patterns.Add([PSCustomObject]@{
                Name         = [string]$item.Name
                Regex        = [string]$item.Regex
                GroupCapture = [int]($item.GroupCapture ?? 1)
                Priority     = [int]($item.Priority ?? 50)
                Enabled      = [bool]($item.Enabled ?? $true)
                BuiltIn      = [bool]($item.BuiltIn ?? $false)
                Description  = [string]($item.Description ?? "")
            })
        }

        Write-Verbose "Pattern-Profile geladen: $($patterns.Count) Pattern"
        return @($patterns)
    }
    catch {
        Write-Warning "Pattern-Datei fehlerhaft: $($_.Exception.Message). Verwende Defaults."
        return $defaults
    }
}


function Save-SorterPatterns {
    <#
    .SYNOPSIS
        Speichert Pattern-Profile nach file-sorter-patterns.json

    .DESCRIPTION
        Schreibt Pattern-Array als JSON. Erstellt Backup falls vorhanden.

    .PARAMETER Patterns
        Array von Pattern-Objekten

    .PARAMETER ScriptRoot
        Projekt-Root Pfad

    .EXAMPLE
        Save-SorterPatterns -Patterns $patterns -ScriptRoot $ScriptRoot

    .EXAMPLE
        $p = Get-SorterPatterns -ScriptRoot $root; $p[0].Enabled = $false
        Save-SorterPatterns -Patterns $p -ScriptRoot $root
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Patterns,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptRoot
    )

    $jsonPath = Join-Path $ScriptRoot "file-sorter-patterns.json"

    try {
        if (Test-Path -LiteralPath $jsonPath) {
            Copy-Item -LiteralPath $jsonPath -Destination "$jsonPath.backup" -Force
        }

        $Patterns | ConvertTo-Json -Depth 5 |
            Out-File -FilePath $jsonPath -Encoding UTF8 -Force

        Write-Verbose "Pattern gespeichert: $($Patterns.Count) Einträge"
    }
    catch {
        Write-Error "Fehler beim Speichern: $($_.Exception.Message)"
        throw
    }
}


function Add-SorterPattern {
    <#
    .SYNOPSIS
        Fügt ein neues Custom-Pattern hinzu

    .DESCRIPTION
        Validiert Regex, prüft auf Name-Duplikate, speichert.

    .PARAMETER Name
        Eindeutiger Name

    .PARAMETER Regex
        Regulärer Ausdruck mit Capture-Group(s)

    .PARAMETER GroupCapture
        Welche Capture-Group als Key (0 = gesamter Match, Default: 1)

    .PARAMETER Priority
        Reihenfolge (niedriger = früher, Default: 50)

    .PARAMETER Description
        Optionale Beschreibung

    .PARAMETER ScriptRoot
        Projekt-Root Pfad

    .EXAMPLE
        Add-SorterPattern -Name "IMG_Datum" -Regex 'IMG_(\d{8})' -GroupCapture 1 -ScriptRoot $root

    .EXAMPLE
        Add-SorterPattern -Name "SetNr" -Regex '^set(\d+)' -Priority 15 -ScriptRoot $root

    .OUTPUTS
        [PSCustomObject] Das erstellte Pattern
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Regex,
        [Parameter()][int]$GroupCapture = 1,
        [Parameter()][int]$Priority = 50,
        [Parameter()][string]$Description = "",
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScriptRoot
    )

    try { [void][regex]::new($Regex) }
    catch { throw "Ungültiger Regex '$Regex': $($_.Exception.Message)" }

    $patterns = @(Get-SorterPatterns -ScriptRoot $ScriptRoot)

    if ($patterns | Where-Object { $_.Name -eq $Name }) {
        throw "Pattern '$Name' existiert bereits"
    }

    $newPattern = [PSCustomObject]@{
        Name = $Name; Regex = $Regex; GroupCapture = $GroupCapture
        Priority = $Priority; Enabled = $true; BuiltIn = $false
        Description = $Description
    }

    Save-SorterPatterns -Patterns (@($patterns) + @($newPattern)) -ScriptRoot $ScriptRoot
    Write-Verbose "Pattern '$Name' hinzugefügt"
    return $newPattern
}


function Remove-SorterPattern {
    <#
    .SYNOPSIS
        Entfernt Custom-Pattern oder deaktiviert Built-in Pattern

    .DESCRIPTION
        Custom = gelöscht. Built-in = Enabled auf false gesetzt.

    .PARAMETER Name
        Name des Patterns

    .PARAMETER ScriptRoot
        Projekt-Root Pfad

    .EXAMPLE
        Remove-SorterPattern -Name "MeinPattern" -ScriptRoot $root

    .EXAMPLE
        Remove-SorterPattern -Name "Prefix" -ScriptRoot $root  # nur deaktiviert

    .OUTPUTS
        [bool] True wenn erfolgreich
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScriptRoot
    )

    $patterns = @(Get-SorterPatterns -ScriptRoot $ScriptRoot)
    $target = $patterns | Where-Object { $_.Name -eq $Name }

    if (-not $target) {
        Write-Warning "Pattern '$Name' nicht gefunden"
        return $false
    }

    if ($target.BuiltIn) {
        $target.Enabled = $false
        Save-SorterPatterns -Patterns $patterns -ScriptRoot $ScriptRoot
        Write-Verbose "Built-in '$Name' deaktiviert"
    }
    else {
        Save-SorterPatterns -Patterns @($patterns | Where-Object { $_.Name -ne $Name }) -ScriptRoot $ScriptRoot
        Write-Verbose "Custom '$Name' entfernt"
    }
    return $true
}


# ============================================================================
# DATEINAMEN-EXPORT
# ============================================================================

function Export-FileNames {
    <#
    .SYNOPSIS
        Exportiert Dateinamen + Statistik in _filenames.log

    .DESCRIPTION
        Schreibt sortierte Dateiliste mit Extension-Statistik und
        Prefix-Voranalyse in den analysierten Ordner.

    .PARAMETER FolderPath
        Absoluter Pfad zum Ordner

    .PARAMETER Extensions
        Optionale Einschränkung auf bestimmte Extensions

    .EXAMPLE
        $log = Export-FileNames -FolderPath "D:\Fotos\Unsortiert"

    .EXAMPLE
        $log = Export-FileNames -FolderPath "D:\Fotos" -Extensions @(".jpg",".png")

    .OUTPUTS
        [string] Pfad zur Log-Datei
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$FolderPath,

        [Parameter()]
        [string[]]$Extensions
    )

    $allFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction Stop)

    if ($Extensions -and $Extensions.Count -gt 0) {
        $lowerExts = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
        $allFiles = @($allFiles | Where-Object { $_.Extension.ToLowerInvariant() -in $lowerExts })
    }

    $allFiles = @($allFiles | Sort-Object Name)
    $logPath = Join-Path $FolderPath "_filenames.log"

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("=" * 70)
    [void]$sb.AppendLine("DATEINAMEN-EXPORT")
    [void]$sb.AppendLine("=" * 70)
    [void]$sb.AppendLine("Zeitpunkt:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("Ordner:     $FolderPath")
    [void]$sb.AppendLine("Dateien:    $($allFiles.Count)")
    if ($Extensions) { [void]$sb.AppendLine("Filter:     $($Extensions -join ', ')") }
    [void]$sb.AppendLine("=" * 70)
    [void]$sb.AppendLine("")

    # Extension-Statistik
    $extGroups = $allFiles | Group-Object { $_.Extension.ToLowerInvariant() } | Sort-Object Count -Descending
    [void]$sb.AppendLine("EXTENSIONS:")
    foreach ($eg in $extGroups) { [void]$sb.AppendLine("  $($eg.Name): $($eg.Count)") }
    [void]$sb.AppendLine("")

    # Prefix-Voranalyse
    $prefixGroups = $allFiles | Group-Object {
                if ($_.BaseName -match '^([a-zA-Z]{1,2}\d{2,3})') { $Matches[1].ToLowerInvariant() } else { "_other" }
    } | Sort-Object Name
    [void]$sb.AppendLine("PREFIX-ANALYSE (1-2 Buchstaben + 2-3 Ziffern):")
    foreach ($pg in $prefixGroups) { [void]$sb.AppendLine("  $($pg.Name): $($pg.Count) Dateien") }
    [void]$sb.AppendLine("")

    # Dateiliste
    [void]$sb.AppendLine("-" * 70)
    [void]$sb.AppendLine("DATEILISTE:")
    [void]$sb.AppendLine("-" * 70)
    foreach ($file in $allFiles) {
        $sizeKB = [math]::Round($file.Length / 1KB, 1)
        [void]$sb.AppendLine("$($file.Name)  ($sizeKB KB)")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=" * 70)

    $sb.ToString() | Out-File -FilePath $logPath -Encoding UTF8 -Force
    Write-Verbose "Exportiert: $($allFiles.Count) Dateinamen -> $logPath"
    return $logPath
}


# ============================================================================
# MULTI-PATTERN ANALYSE
# ============================================================================

function Get-FileGroups {
    <#
    .SYNOPSIS
        Analysiert Dateien mit Multi-Pattern-Engine und gruppiert

    .DESCRIPTION
        Scannt Dateien (nicht rekursiv), wendet aktivierte Pattern in
        Prioritäts-Reihenfolge an. Erstes Match bestimmt die Gruppe.
        Nicht gematchte Dateien landen in "_unsorted".

    .PARAMETER FolderPath
        Absoluter Pfad zum Ordner

    .PARAMETER ScriptRoot
        Projekt-Root (für Pattern-Profile JSON)

    .PARAMETER Extensions
        Optionale Einschränkung auf bestimmte Extensions

    .EXAMPLE
        $groups = Get-FileGroups -FolderPath "D:\Fotos\Unsortiert" -ScriptRoot $ScriptRoot

    .EXAMPLE
        $groups = Get-FileGroups -FolderPath $path -ScriptRoot $root -Extensions @(".jpg")
        $groups | ForEach-Object { "$($_.Prefix): $($_.FileCount) ($($_.PatternName))" }

    .OUTPUTS
        [PSCustomObject[]]
        Prefix, PatternName, SuggestedFolder, FileCount, TotalSize,
        TotalSizeFormatted, PreviewFiles, Files
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptRoot,

        [Parameter()]
        [string[]]$Extensions
    )

    Write-Verbose "Analysiere: $FolderPath"

    $allFiles = @(Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction Stop)
    if ($allFiles.Count -eq 0) { return @() }

    if ($Extensions -and $Extensions.Count -gt 0) {
        $lowerExts = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
        $allFiles = @($allFiles | Where-Object { $_.Extension.ToLowerInvariant() -in $lowerExts })
    }
    if ($allFiles.Count -eq 0) { return @() }

    Write-Verbose "Dateien: $($allFiles.Count)"

    # Pattern laden + kompilieren
    $patterns = @(Get-SorterPatterns -ScriptRoot $ScriptRoot |
        Where-Object { $_.Enabled } | Sort-Object Priority)

    $compiled = foreach ($p in $patterns) {
        try {
            @{
                Name         = $p.Name
                Regex        = [regex]::new($p.Regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                GroupCapture = $p.GroupCapture
            }
        }
        catch { Write-Warning "Pattern '$($p.Name)': ungültiger Regex — übersprungen" }
    }

    # Gruppierung
    $groups = @{}
    $patternHits = @{}

    foreach ($file in $allFiles) {
        $matched = $false

        foreach ($cp in $compiled) {
            $m = $cp.Regex.Match($file.BaseName)
            if ($m.Success) {
                $groupKey = if ($cp.GroupCapture -eq 0) {
                    $m.Value.ToLowerInvariant()
                } else {
                    $m.Groups[$cp.GroupCapture].Value.ToLowerInvariant()
                }

                $compositeKey = "$($cp.Name)::$groupKey"
                if (-not $groups.ContainsKey($compositeKey)) {
                    $groups[$compositeKey] = @{
                        Prefix = $groupKey; PatternName = $cp.Name
                        Files = [System.Collections.ArrayList]::new()
                    }
                }
                [void]$groups[$compositeKey].Files.Add($file)

                $patternHits[$cp.Name] = ($patternHits[$cp.Name] ?? 0) + 1
                $matched = $true
                break
            }
        }

        if (-not $matched) {
            $key = "_unsorted::_unsorted"
            if (-not $groups.ContainsKey($key)) {
                $groups[$key] = @{
                    Prefix = "_unsorted"; PatternName = "none"
                    Files = [System.Collections.ArrayList]::new()
                }
            }
            [void]$groups[$key].Files.Add($file)
        }
    }

    foreach ($pn in ($patternHits.Keys | Sort-Object)) {
        Write-Verbose "Pattern '$pn': $($patternHits[$pn]) Treffer"
    }

    # Ergebnis aufbauen
    $result = [System.Collections.ArrayList]::new()

    foreach ($key in ($groups.Keys | Sort-Object)) {
        $g = $groups[$key]
        $files = $g.Files
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum

        [void]$result.Add([PSCustomObject]@{
            Prefix             = $g.Prefix
            PatternName        = $g.PatternName
            SuggestedFolder    = $g.Prefix
            FileCount          = $files.Count
            TotalSize          = $totalSize
            TotalSizeFormatted = Format-FileSize -Bytes $totalSize
            PreviewFiles       = @($files | Sort-Object Name | Select-Object -First 5 | ForEach-Object { $_.Name })
            Files              = @($files | Sort-Object Name | ForEach-Object { $_.Name })
        })
    }

    Write-Verbose "Ergebnis: $($result.Count) Gruppen, $($allFiles.Count) Dateien"
    return @($result)
}


# ============================================================================
# GRUPPEN-MANIPULATION (in-memory, vor Invoke-FileSorting)
# ============================================================================

function Move-FileBetweenGroups {
    <#
    .SYNOPSIS
        Verschiebt eine Datei von einer Gruppe in eine andere (in-memory)

    .DESCRIPTION
        Ändert nur die Gruppen-Zuordnung. Keine Dateisystem-Operation.

    .PARAMETER Groups
        Array von Gruppen-Objekten (von Get-FileGroups)

    .PARAMETER FileName
        Name der zu verschiebenden Datei

    .PARAMETER TargetPrefix
        Prefix der Ziel-Gruppe (wird erstellt falls nicht vorhanden)

    .EXAMPLE
        $groups = Move-FileBetweenGroups -Groups $groups -FileName "w0001.jpg" -TargetPrefix "p006"

    .OUTPUTS
        [PSCustomObject[]] Aktualisiertes Groups-Array
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)][PSCustomObject[]]$Groups,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FileName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TargetPrefix
    )

    $sourceGroup = $Groups | Where-Object { $FileName -in $_.Files }
    if (-not $sourceGroup) { throw "Datei '$FileName' nicht in Gruppen gefunden" }

    $targetGroup = $Groups | Where-Object { $_.Prefix -eq $TargetPrefix }

    # Aus Quelle entfernen
    $sourceGroup.Files = @($sourceGroup.Files | Where-Object { $_ -ne $FileName })
    $sourceGroup.FileCount = $sourceGroup.Files.Count
    $sourceGroup.PreviewFiles = @($sourceGroup.Files | Select-Object -First 5)

    # In Ziel einfügen oder neue Gruppe
    if ($targetGroup) {
        $targetGroup.Files = @(@($targetGroup.Files) + @($FileName) | Sort-Object)
        $targetGroup.FileCount = $targetGroup.Files.Count
        $targetGroup.PreviewFiles = @($targetGroup.Files | Select-Object -First 5)
    }
    else {
        $Groups = @($Groups) + @([PSCustomObject]@{
            Prefix = $TargetPrefix; PatternName = "manual"; SuggestedFolder = $TargetPrefix
            FileCount = 1; TotalSize = 0; TotalSizeFormatted = "?"
            PreviewFiles = @($FileName); Files = @($FileName)
        })
    }

    $Groups = @($Groups | Where-Object { $_.FileCount -gt 0 })
    Write-Verbose "'$FileName': $($sourceGroup.Prefix) -> $TargetPrefix"
    return $Groups
}


function Merge-FileGroups {
    <#
    .SYNOPSIS
        Führt zwei Gruppen zusammen (in-memory)

    .DESCRIPTION
        Alle Dateien aus SourcePrefix → TargetPrefix. Quelle wird entfernt.

    .PARAMETER Groups
        Array von Gruppen-Objekten

    .PARAMETER SourcePrefix
        Prefix der aufzulösenden Gruppe

    .PARAMETER TargetPrefix
        Prefix der Ziel-Gruppe

    .EXAMPLE
        $groups = Merge-FileGroups -Groups $groups -SourcePrefix "p006" -TargetPrefix "p020"

    .OUTPUTS
        [PSCustomObject[]] Aktualisiertes Groups-Array
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)][PSCustomObject[]]$Groups,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourcePrefix,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TargetPrefix
    )

    if ($SourcePrefix -eq $TargetPrefix) { throw "Quelle und Ziel identisch" }

    $source = $Groups | Where-Object { $_.Prefix -eq $SourcePrefix }
    $target = $Groups | Where-Object { $_.Prefix -eq $TargetPrefix }

    if (-not $source) { throw "Quell-Gruppe '$SourcePrefix' nicht gefunden" }
    if (-not $target) { throw "Ziel-Gruppe '$TargetPrefix' nicht gefunden" }

    $target.Files = @(@($target.Files) + @($source.Files) | Sort-Object)
    $target.FileCount = $target.Files.Count
    $target.PreviewFiles = @($target.Files | Select-Object -First 5)
    $target.TotalSize += $source.TotalSize
    $target.TotalSizeFormatted = Format-FileSize -Bytes $target.TotalSize

    $Groups = @($Groups | Where-Object { $_.Prefix -ne $SourcePrefix })
    Write-Verbose "Merge: $SourcePrefix ($($source.FileCount)) -> $TargetPrefix ($($target.FileCount))"
    return $Groups
}


function Split-FileGroup {
    <#
    .SYNOPSIS
        Splittet eine Gruppe in zwei (in-memory)

    .DESCRIPTION
        Angegebene Dateien werden in neue Gruppe mit eigenem Prefix verschoben.

    .PARAMETER Groups
        Array von Gruppen-Objekten

    .PARAMETER SourcePrefix
        Prefix der zu splittenden Gruppe

    .PARAMETER FileNames
        Dateinamen die in die neue Gruppe sollen

    .PARAMETER NewPrefix
        Prefix für die neue Gruppe

    .EXAMPLE
        $groups = Split-FileGroup -Groups $groups -SourcePrefix "p006" `
            -FileNames @("p0060001.jpg","p0060002.jpg") -NewPrefix "p006_extra"

    .OUTPUTS
        [PSCustomObject[]] Aktualisiertes Groups-Array
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)][PSCustomObject[]]$Groups,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourcePrefix,
        [Parameter(Mandatory)][string[]]$FileNames,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NewPrefix
    )

    $source = $Groups | Where-Object { $_.Prefix -eq $SourcePrefix }
    if (-not $source) { throw "Gruppe '$SourcePrefix' nicht gefunden" }

    $missing = @($FileNames | Where-Object { $_ -notin $source.Files })
    if ($missing.Count -gt 0) { throw "Dateien nicht in '$SourcePrefix': $($missing -join ', ')" }

    if ($Groups | Where-Object { $_.Prefix -eq $NewPrefix }) {
        throw "Gruppe '$NewPrefix' existiert bereits"
    }

    $source.Files = @($source.Files | Where-Object { $_ -notin $FileNames })
    $source.FileCount = $source.Files.Count
    $source.PreviewFiles = @($source.Files | Select-Object -First 5)

    $Groups = @($Groups) + @([PSCustomObject]@{
        Prefix = $NewPrefix; PatternName = "manual_split"; SuggestedFolder = $NewPrefix
        FileCount = $FileNames.Count; TotalSize = 0; TotalSizeFormatted = "?"
        PreviewFiles = @($FileNames | Select-Object -First 5)
        Files = @($FileNames | Sort-Object)
    })

    $Groups = @($Groups | Where-Object { $_.FileCount -gt 0 })
    Write-Verbose "Split: $SourcePrefix -> $NewPrefix ($($FileNames.Count) Dateien)"
    return $Groups
}


# ============================================================================
# SORTIERUNG + UNDO
# ============================================================================

function Invoke-FileSorting {
    <#
    .SYNOPSIS
        Verschiebt Dateien in Unterordner und erstellt Undo-Log

    .DESCRIPTION
        Nimmt Gruppen + Mapping (Prefix → Ordnername), verschiebt Dateien.
        Erstellt _undo-sort.json für Rückgängig. Path-Traversal-Schutz.

    .PARAMETER FolderPath
        Absoluter Pfad zum Quell-Ordner

    .PARAMETER GroupMappings
        Hashtable: Key = Prefix, Value = Ziel-Ordnername

    .PARAMETER Groups
        Gruppen-Array von Get-FileGroups

    .EXAMPLE
        $map = @{ "p006" = "Set_006"; "p020" = "Set_020" }
        $result = Invoke-FileSorting -FolderPath $path -GroupMappings $map -Groups $groups

    .EXAMPLE
        if ($result.Failed -gt 0) { Write-Warning "$($result.Failed) fehlgeschlagen" }

    .OUTPUTS
        [PSCustomObject] Moved, Failed, Skipped, CreatedFolders, UndoLogPath, Details
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [hashtable]$GroupMappings,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Groups
    )

    Write-Verbose "Sortiere in: $FolderPath ($($GroupMappings.Count) Mappings)"

    $moved = 0; $failed = 0; $skipped = 0
    $createdFolders = [System.Collections.ArrayList]::new()
    $details = [System.Collections.ArrayList]::new()
    $undoEntries = [System.Collections.ArrayList]::new()

    foreach ($group in $Groups) {
        $prefix = $group.Prefix

        if (-not $GroupMappings.ContainsKey($prefix)) { $skipped += $group.FileCount; continue }

        $targetName = $GroupMappings[$prefix]
        if ([string]::IsNullOrWhiteSpace($targetName)) { $skipped += $group.FileCount; continue }

        # Path-Traversal Schutz
        if ($targetName -match '[/\\]' -or $targetName.Contains('..')) {
            foreach ($fn in $group.Files) {
                $failed++
                [void]$details.Add([PSCustomObject]@{
                    File = $fn; Prefix = $prefix; Target = $targetName
                    Status = "Error"; Message = "Ungültiger Ordnername (Path-Traversal)"
                })
            }
            continue
        }

        $targetFolder = Join-Path $FolderPath $targetName

        # Ordner erstellen
        if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
                [void]$createdFolders.Add($targetName)
            }
            catch {
                foreach ($fn in $group.Files) {
                    $failed++
                    [void]$details.Add([PSCustomObject]@{
                        File = $fn; Prefix = $prefix; Target = $targetName
                        Status = "Error"; Message = "Ordner erstellen fehlgeschlagen: $($_.Exception.Message)"
                    })
                }
                continue
            }
        }

        # Dateien verschieben
        foreach ($fileName in $group.Files) {
            $sourcePath = Join-Path $FolderPath $fileName
            $targetPath = Join-Path $targetFolder $fileName

            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $failed++
                [void]$details.Add([PSCustomObject]@{
                    File = $fileName; Prefix = $prefix; Target = $targetName
                    Status = "Error"; Message = "Quelldatei nicht gefunden"
                })
                continue
            }

            if (Test-Path -LiteralPath $targetPath) {
                $failed++
                [void]$details.Add([PSCustomObject]@{
                    File = $fileName; Prefix = $prefix; Target = $targetName
                    Status = "Error"; Message = "Existiert bereits im Ziel"
                })
                continue
            }

            try {
                # Thumbnail-Hash VOR dem Move berechnen (alter Pfad)
                $oldThumbsDir = Join-Path $FolderPath ".thumbs"
                $oldThumbHash = $null
                if (Test-Path -LiteralPath $oldThumbsDir -PathType Container) {
                    try {
                        $fi = [System.IO.FileInfo]::new($sourcePath)
                        $hashInput = "$($fi.FullName)-$($fi.LastWriteTimeUtc.Ticks)"
                        $oldThumbHash = [System.BitConverter]::ToString(
                            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                                [System.Text.Encoding]::UTF8.GetBytes($hashInput)
                            )
                        ).Replace('-', '').ToLowerInvariant()
                    }
                    catch { }
                }

                Move-Item -LiteralPath $sourcePath -Destination $targetPath -ErrorAction Stop
                $moved++

                # Thumbnail in neuen .thumbs/ kopieren
                if ($oldThumbHash) {
                    $oldThumbPath = Join-Path $oldThumbsDir "$oldThumbHash.jpg"
                    if (Test-Path -LiteralPath $oldThumbPath -PathType Leaf) {
                        $newThumbsDir = Join-Path $targetFolder ".thumbs"
                        if (-not (Test-Path -LiteralPath $newThumbsDir -PathType Container)) {
                            New-Item -ItemType Directory -Path $newThumbsDir -Force | Out-Null
                            # Hidden + System Attribute (OneDrive-Schutz)
                            $tf = Get-Item -LiteralPath $newThumbsDir -Force
                            $tf.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
                        }
                        # Neuen Hash berechnen (neuer Pfad, gleiche LastWriteTime)
                        try {
                            $newFi = [System.IO.FileInfo]::new($targetPath)
                            $newHashInput = "$($newFi.FullName)-$($newFi.LastWriteTimeUtc.Ticks)"
                            $newThumbHash = [System.BitConverter]::ToString(
                                [System.Security.Cryptography.MD5]::Create().ComputeHash(
                                    [System.Text.Encoding]::UTF8.GetBytes($newHashInput)
                                )
                            ).Replace('-', '').ToLowerInvariant()
                            $newThumbPath = Join-Path $newThumbsDir "$newThumbHash.jpg"
                            Copy-Item -LiteralPath $oldThumbPath -Destination $newThumbPath -Force
                        }
                        catch { }
                    }
                }

                [void]$undoEntries.Add(@{ File = $fileName; From = $sourcePath; To = $targetPath })
                [void]$details.Add([PSCustomObject]@{
                    File = $fileName; Prefix = $prefix; Target = $targetName
                    Status = "Moved"; Message = "OK"
                })
            }
            catch {
                $failed++
                [void]$details.Add([PSCustomObject]@{
                    File = $fileName; Prefix = $prefix; Target = $targetName
                    Status = "Error"; Message = $_.Exception.Message
                })
            }
        }
    }

    # Undo-Log
    $undoLogPath = $null
    if ($undoEntries.Count -gt 0) {
        $undoLogPath = Join-Path $FolderPath "_undo-sort.json"
        @{
            Timestamp      = (Get-Date).ToString('o')
            FolderPath     = $FolderPath
            MovedCount     = $moved
            CreatedFolders = @($createdFolders)
            Entries        = @($undoEntries)
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath $undoLogPath -Encoding UTF8 -Force
        Write-Verbose "Undo-Log: $undoLogPath"
    }

    Write-Verbose "Fertig: $moved verschoben, $failed fehlgeschlagen, $skipped übersprungen"

    return [PSCustomObject]@{
        Moved          = $moved
        Failed         = $failed
        Skipped        = $skipped
        CreatedFolders = @($createdFolders)
        UndoLogPath    = $undoLogPath
        Details        = @($details)
    }
}


function Undo-FileSorting {
    <#
    .SYNOPSIS
        Macht die letzte Sortierung rückgängig

    .DESCRIPTION
        Liest _undo-sort.json, verschiebt Dateien zurück, entfernt leere Ordner.

    .PARAMETER FolderPath
        Ordner mit _undo-sort.json

    .EXAMPLE
        $result = Undo-FileSorting -FolderPath "D:\Fotos\Unsortiert"
        Write-Host "$($result.Restored) zurück verschoben"

    .EXAMPLE
        $r = Undo-FileSorting -FolderPath $path
        if (-not $r.Success) { Write-Warning $r.Error }

    .OUTPUTS
        [PSCustomObject] Success, Restored, Failed, RemovedFolders, Error
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$FolderPath
    )

    $undoPath = Join-Path $FolderPath "_undo-sort.json"

    if (-not (Test-Path -LiteralPath $undoPath)) {
        return [PSCustomObject]@{
            Success = $false; Restored = 0; Failed = 0
            RemovedFolders = @(); Error = "Keine Undo-Datei gefunden"
        }
    }

    try {
        $undoData = Get-Content -LiteralPath $undoPath -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{
            Success = $false; Restored = 0; Failed = 0
            RemovedFolders = @(); Error = "Undo-Datei nicht lesbar: $($_.Exception.Message)"
        }
    }

    $restored = 0; $failed = 0

    foreach ($entry in $undoData.Entries) {
        if (-not (Test-Path -LiteralPath $entry.To -PathType Leaf)) {
            Write-Warning "Nicht mehr am Ziel: $($entry.File)"
            $failed++; continue
        }
        if (Test-Path -LiteralPath $entry.From) {
            Write-Warning "Original-Pfad belegt: $($entry.File)"
            $failed++; continue
        }

        try {
            Move-Item -LiteralPath $entry.To -Destination $entry.From -ErrorAction Stop
            $restored++
        }
        catch {
            Write-Warning "Zurückverschieben: $($entry.File) — $($_.Exception.Message)"
            $failed++
        }
    }

    # Leere erstellte Ordner entfernen
    $removedFolders = [System.Collections.ArrayList]::new()
    if ($undoData.CreatedFolders) {
        foreach ($folderName in $undoData.CreatedFolders) {
            $folderFull = Join-Path $FolderPath $folderName
            if ((Test-Path -LiteralPath $folderFull -PathType Container)) {
                $remaining = @(Get-ChildItem -LiteralPath $folderFull -ErrorAction SilentlyContinue)
                if ($remaining.Count -eq 0) {
                    try {
                        Remove-Item -LiteralPath $folderFull -Force
                        [void]$removedFolders.Add($folderName)
                    }
                    catch { Write-Warning "Ordner nicht entfernbar: $folderName" }
                }
            }
        }
    }

    try { Remove-Item -LiteralPath $undoPath -Force }
    catch { Write-Warning "Undo-Log nicht löschbar" }

    Write-Verbose "Undo: $restored zurück, $failed fehlgeschlagen, $($removedFolders.Count) Ordner entfernt"

    return [PSCustomObject]@{
        Success        = ($failed -eq 0)
        Restored       = $restored
        Failed         = $failed
        RemovedFolders = @($removedFolders)
        Error          = $null
    }
}