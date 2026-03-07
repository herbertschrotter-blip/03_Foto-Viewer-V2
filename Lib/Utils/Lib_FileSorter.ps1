<#
ManifestHint:
  ExportFunctions = @("Get-FileGroups", "Invoke-FileSorting", "Export-FileNames",
                       "Get-SorterPatterns", "Save-SorterPatterns",
                       "Add-SorterPattern", "Remove-SorterPattern",
                       "Get-SorterSubLevels", "Save-SorterSubLevels",
                       "Move-FileBetweenGroups", "Merge-FileGroups", "Split-FileGroup",
                       "Undo-FileSorting",
                       "Get-MultiLevelGroups", "Invoke-MultiLevelSorting",
                       "Convert-SubKeyToShort")
  Description     = "Dateinamen-Analyse, Multi-Pattern-Gruppierung, N-stufige Sortierung"
  Category        = "Utils"
  Tags            = @("FileSorter", "Grouping", "Organize", "Pattern", "Undo", "MultiLevel")
  Dependencies    = @()

Zweck:
  - Multi-Pattern-Engine: Prefix, Datum, Custom-Regex (erweiterbar)
  - N-stufige Sortierung: Verschachtelte Ordner-Strukturen (Prefix/Variante/...)
  - Pattern-Profile als JSON gespeichert (file-sorter-patterns.json)
  - Dateinamen-Export in _filenames.log (manuelle Analyse)
  - Preview-Gruppierung VOR dem Sortieren
  - Gruppen-Manipulation: Umgruppieren, Mergen, Splitten
  - Sortierung mit Undo-Log (_undo-sort.json)

Funktionen:
  - Get-SorterPatterns:       Pattern-Profile laden (JSON oder Defaults)
  - Save-SorterPatterns:      Pattern-Profile speichern
  - Add-SorterPattern:        Neues Custom-Pattern hinzufuegen
  - Remove-SorterPattern:     Pattern entfernen / deaktivieren
  - Get-SorterSubLevels:      Sub-Level Patterns laden (JSON oder Defaults)
  - Save-SorterSubLevels:     Sub-Level Patterns speichern
  - Export-FileNames:         Dateinamen + Statistik in Log-Datei
  - Get-FileGroups:           Multi-Pattern Analyse + Gruppierung (Stufe 1)
  - Move-FileBetweenGroups:   Datei zwischen Gruppen verschieben (in-memory)
  - Merge-FileGroups:         Zwei Gruppen zusammenfuehren (in-memory)
  - Split-FileGroup:          Gruppe aufteilen (in-memory)
  - Invoke-FileSorting:       Dateien einstufig verschieben mit Undo-Log
  - Undo-FileSorting:         Letzte Sortierung rueckgaengig machen
  - Get-MultiLevelGroups:     Sub-Gruppierung (Stufe 2..N) auf bestehende Gruppen
  - Invoke-MultiLevelSorting: N-stufig verschachtelte Ordner erstellen + verschieben

Interne Helper:
  - Format-FileSize:          Bytes in menschenlesbare Groesse
  - Move-SingleFile:          Einzeldatei verschieben mit Thumbnail-Kopie
  - Split-IntoSubGroups:      Rekursive Sub-Gruppierung pro Ebene
  - Invoke-SubGroupSorting:   Rekursive Ordner-Erstellung + Verschiebung

Abhaengigkeiten:
  - Keine (eigenstaendig)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.1

    AENDERUNGEN v0.2.0:
    - N-stufige Sortierung (Get-MultiLevelGroups, Invoke-MultiLevelSorting)
    - Move-SingleFile als gemeinsamer Helper (refactored aus Invoke-FileSorting)
    - Rekursive Sub-Gruppierung mit beliebig vielen Ebenen
    - Undo-Log unterstuetzt verschachtelte Pfade
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# ============================================================================
# INTERNE HELPER
# ============================================================================

function Format-FileSize {
    <# Interner Helper: Bytes in menschenlesbare Groesse #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}


function Move-SingleFile {
    <#
    .SYNOPSIS
        Interner Helper: Einzelne Datei verschieben mit Thumbnail-Kopie

    .DESCRIPTION
        Verschiebt eine Datei von FolderPath in TargetFolder.
        Kopiert den zugehoerigen Thumbnail (Hash-basiert) mit.
        Gibt Ergebnis-Objekt zurueck fuer Statistik und Undo.

    .PARAMETER FolderPath
        Root-Ordner (Quelle der Datei)

    .PARAMETER FileName
        Dateiname (nur Name, kein Pfad)

    .PARAMETER TargetFolder
        Absoluter Ziel-Ordner

    .PARAMETER Prefix
        Gruppen-Prefix (fuer Logging/Details)

    .PARAMETER TargetName
        Relativer Ordner-Name (fuer Logging/Details)

    .EXAMPLE
        $r = Move-SingleFile -FolderPath "D:\Fotos" -FileName "p006_001.jpg" `
            -TargetFolder "D:\Fotos\p006" -Prefix "p006" -TargetName "p006"

    .OUTPUTS
        [PSCustomObject] Moved (0/1), Failed (0/1), Detail, UndoEntry
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$TargetFolder,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$TargetName
    )

    $sourcePath = Join-Path $FolderPath $FileName
    $targetPath = Join-Path $TargetFolder $FileName

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        return [PSCustomObject]@{
            Moved = 0; Failed = 1
            Detail = [PSCustomObject]@{
                File = $FileName; Prefix = $Prefix; Target = $TargetName
                Status = "Error"; Message = "Quelldatei nicht gefunden"
            }
            UndoEntry = $null
        }
    }

    if (Test-Path -LiteralPath $targetPath) {
        return [PSCustomObject]@{
            Moved = 0; Failed = 1
            Detail = [PSCustomObject]@{
                File = $FileName; Prefix = $Prefix; Target = $TargetName
                Status = "Error"; Message = "Existiert bereits im Ziel"
            }
            UndoEntry = $null
        }
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

        # Thumbnail in neuen .thumbs/ kopieren
        if ($oldThumbHash) {
            $oldThumbPath = Join-Path $oldThumbsDir "$oldThumbHash.jpg"
            if (Test-Path -LiteralPath $oldThumbPath -PathType Leaf) {
                $newThumbsDir = Join-Path $TargetFolder ".thumbs"
                if (-not (Test-Path -LiteralPath $newThumbsDir -PathType Container)) {
                    New-Item -ItemType Directory -Path $newThumbsDir -Force | Out-Null
                    # Hidden + System Attribute (OneDrive-Schutz)
                    $tf = Get-Item -LiteralPath $newThumbsDir -Force
                    $tf.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
                }
                try {
                    $newFi = [System.IO.FileInfo]::new($targetPath)
                    $newHashInput = "$($newFi.FullName)-$($newFi.LastWriteTimeUtc.Ticks)"
                    $newThumbHash = [System.BitConverter]::ToString(
                        [System.Security.Cryptography.MD5]::Create().ComputeHash(
                            [System.Text.Encoding]::UTF8.GetBytes($newHashInput)
                        )
                    ).Replace('-', '').ToLowerInvariant()
                    Copy-Item -LiteralPath $oldThumbPath -Destination (Join-Path $newThumbsDir "$newThumbHash.jpg") -Force
                }
                catch { }
            }
        }

        return [PSCustomObject]@{
            Moved = 1; Failed = 0
            Detail = [PSCustomObject]@{
                File = $FileName; Prefix = $Prefix; Target = $TargetName
                Status = "Moved"; Message = "OK"
            }
            UndoEntry = @{ File = $FileName; From = $sourcePath; To = $targetPath }
        }
    }
    catch {
        return [PSCustomObject]@{
            Moved = 0; Failed = 1
            Detail = [PSCustomObject]@{
                File = $FileName; Prefix = $Prefix; Target = $TargetName
                Status = "Error"; Message = $_.Exception.Message
            }
            UndoEntry = $null
        }
    }
}


# ============================================================================
# PATTERN PROFILE MANAGEMENT
# ============================================================================

function Get-SorterPatterns {
    <#
    .SYNOPSIS
        Laedt Pattern-Profile aus file-sorter-patterns.json

    .DESCRIPTION
        Liest gespeicherte Pattern-Definitionen. Falls Datei nicht existiert,
        werden Built-in Defaults zurueckgegeben. Jedes Pattern hat: Name,
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

        Write-Verbose "Pattern gespeichert: $($Patterns.Count) Eintraege"
    }
    catch {
        Write-Error "Fehler beim Speichern: $($_.Exception.Message)"
        throw
    }
}


function Add-SorterPattern {
    <#
    .SYNOPSIS
        Fuegt ein neues Custom-Pattern hinzu

    .DESCRIPTION
        Validiert Regex, prueft auf Name-Duplikate, speichert.

    .PARAMETER Name
        Eindeutiger Name

    .PARAMETER Regex
        Regulaerer Ausdruck mit Capture-Group(s)

    .PARAMETER GroupCapture
        Welche Capture-Group als Key (0 = gesamter Match, Default: 1)

    .PARAMETER Priority
        Reihenfolge (niedriger = frueher, Default: 50)

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
    catch { throw "Ungueltiger Regex '$Regex': $($_.Exception.Message)" }

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
    Write-Verbose "Pattern '$Name' hinzugefuegt"
    return $newPattern
}


function Remove-SorterPattern {
    <#
    .SYNOPSIS
        Entfernt Custom-Pattern oder deaktiviert Built-in Pattern

    .DESCRIPTION
        Custom = geloescht. Built-in = Enabled auf false gesetzt.

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
# SUB-LEVEL PATTERN MANAGEMENT
# ============================================================================

function Get-SorterSubLevels {
    <#
    .SYNOPSIS
        Laedt Sub-Level Patterns aus file-sorter-sublevels.json

    .DESCRIPTION
        Liest gespeicherte Sub-Level Definitionen. Falls Datei nicht existiert,
        wird ein Default-Array zurueckgegeben. Jedes Sub-Level hat: Name,
        Regex, GroupCapture, Enabled.

    .PARAMETER ScriptRoot
        Projekt-Root Pfad (wo file-sorter-sublevels.json liegt)

    .EXAMPLE
        $subLevels = Get-SorterSubLevels -ScriptRoot $ScriptRoot

    .EXAMPLE
        $active = Get-SorterSubLevels -ScriptRoot $root | Where-Object Enabled

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

    $jsonPath = Join-Path $ScriptRoot "file-sorter-sublevels.json"

    $defaults = @(
        [PSCustomObject]@{
            Name         = "Variante"
            Regex        = '_1_(result(?:_\d+)?)\.'
            GroupCapture = 1
            Enabled      = $true
        }
    )

    if (-not (Test-Path -LiteralPath $jsonPath)) {
        Write-Verbose "Keine Sub-Level-Datei gefunden, verwende Defaults"
        return $defaults
    }

    try {
        $json = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 -ErrorAction Stop
        $loaded = $json | ConvertFrom-Json -ErrorAction Stop

        $subLevels = [System.Collections.ArrayList]::new()
        foreach ($item in $loaded) {
            [void]$subLevels.Add([PSCustomObject]@{
                Name         = [string]$item.Name
                Regex        = [string]$item.Regex
                GroupCapture = [int]($item.GroupCapture ?? 1)
                Enabled      = [bool]($item.Enabled ?? $true)
            })
        }

        Write-Verbose "Sub-Levels geladen: $($subLevels.Count) Eintraege"
        return @($subLevels)
    }
    catch {
        Write-Warning "Sub-Level-Datei fehlerhaft: $($_.Exception.Message). Verwende Defaults."
        return $defaults
    }
}


function Save-SorterSubLevels {
    <#
    .SYNOPSIS
        Speichert Sub-Level Patterns nach file-sorter-sublevels.json

    .DESCRIPTION
        Schreibt Sub-Level-Array als JSON. Erstellt Backup falls vorhanden.

    .PARAMETER SubLevels
        Array von Sub-Level-Objekten

    .PARAMETER ScriptRoot
        Projekt-Root Pfad

    .EXAMPLE
        Save-SorterSubLevels -SubLevels $subLevels -ScriptRoot $ScriptRoot

    .EXAMPLE
        $sl = Get-SorterSubLevels -ScriptRoot $root
        $sl[0].Enabled = $false
        Save-SorterSubLevels -SubLevels $sl -ScriptRoot $root

    .OUTPUTS
        Keine (wirft bei Fehler)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$SubLevels,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptRoot
    )

    $jsonPath = Join-Path $ScriptRoot "file-sorter-sublevels.json"

    try {
        if (Test-Path -LiteralPath $jsonPath) {
            Copy-Item -LiteralPath $jsonPath -Destination "$jsonPath.backup" -Force
        }

        $SubLevels | ConvertTo-Json -Depth 5 |
            Out-File -FilePath $jsonPath -Encoding UTF8 -Force

        Write-Verbose "Sub-Levels gespeichert: $($SubLevels.Count) Eintraege"
    }
    catch {
        Write-Error "Fehler beim Speichern: $($_.Exception.Message)"
        throw
    }
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
        Optionale Einschraenkung auf bestimmte Extensions

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
# MULTI-PATTERN ANALYSE (STUFE 1)
# ============================================================================

function Get-FileGroups {
    <#
    .SYNOPSIS
        Analysiert Dateien mit Multi-Pattern-Engine und gruppiert

    .DESCRIPTION
        Scannt Dateien (nicht rekursiv), wendet aktivierte Pattern in
        Prioritaets-Reihenfolge an. Erstes Match bestimmt die Gruppe.
        Nicht gematchte Dateien landen in "_unsorted".

    .PARAMETER FolderPath
        Absoluter Pfad zum Ordner

    .PARAMETER ScriptRoot
        Projekt-Root (fuer Pattern-Profile JSON)

    .PARAMETER Extensions
        Optionale Einschraenkung auf bestimmte Extensions

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
        catch { Write-Warning "Pattern '$($p.Name)': ungueltiger Regex — uebersprungen" }
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

        # Prüfe ob Ziel-Ordner bereits existiert und Dateien enthält
        $folderExists = $false
        $folderFileCount = 0
        $suggestedPath = Join-Path $FolderPath $g.Prefix
        if (Test-Path -LiteralPath $suggestedPath -PathType Container) {
            $folderFileCount = @(Get-ChildItem -LiteralPath $suggestedPath -File -ErrorAction SilentlyContinue).Count
            $folderExists = ($folderFileCount -gt 0)
        }

        [void]$result.Add([PSCustomObject]@{
            Prefix             = $g.Prefix
            PatternName        = $g.PatternName
            SuggestedFolder    = $g.Prefix
            FileCount          = $files.Count
            TotalSize          = $totalSize
            TotalSizeFormatted = Format-FileSize -Bytes $totalSize
            PreviewFiles       = @($files | Sort-Object Name | Select-Object -First 5 | ForEach-Object { $_.Name })
            Files              = @($files | Sort-Object Name | ForEach-Object { $_.Name })
            FolderExists       = $folderExists
            FolderFileCount    = $folderFileCount
        })
    }

    Write-Verbose "Ergebnis: $($result.Count) Gruppen, $($allFiles.Count) Dateien"
    return @($result)
}


# ============================================================================
# N-STUFIGE GRUPPIERUNG (STUFE 2..N)
# ============================================================================

function Get-MultiLevelGroups {
    <#
    .SYNOPSIS
        Unterteilt bestehende Gruppen in Sub-Gruppen (N-stufig)

    .DESCRIPTION
        Nimmt ein Groups-Array (von Get-FileGroups, Stufe 1) und wendet
        zusaetzliche Pattern-Ebenen an, um verschachtelte Gruppen zu bilden.
        Jede Ebene erzeugt eine weitere Ordner-Tiefe.

        Ebene 1 (Stufe 1): p105, pa200, DSCF        (von Get-FileGroups)
        Ebene 2 (Stufe 2): result, result_1, result_2 (von SubLevels[0])
        Ebene 3 (Stufe 3): beliebig                   (von SubLevels[1])

        Dateien die auf einer Sub-Ebene nicht matchen landen in "_other".

    .PARAMETER Groups
        Array von Gruppen-Objekten (Output von Get-FileGroups)

    .PARAMETER SubLevels
        Array von Hashtables, jeweils mit:
        - Regex:        [string] Regulaerer Ausdruck
        - GroupCapture: [int]    Welche Capture-Group (Standard: 1)
        - Name:         [string] Bezeichnung der Ebene (optional)

    .EXAMPLE
        $subLevels = @(
            @{ Regex = '_1_(result(?:_\d+)?)\.'; GroupCapture = 1; Name = "Variante" }
        )
        $multi = Get-MultiLevelGroups -Groups $groups -SubLevels $subLevels

    .EXAMPLE
        # 3-stufig
        $subLevels = @(
            @{ Regex = '_1_(result(?:_\d+)?)\.'; GroupCapture = 1; Name = "Variante" }
            @{ Regex = '(\d{4})_1_result';       GroupCapture = 1; Name = "BildNr" }
        )
        $multi = Get-MultiLevelGroups -Groups $groups -SubLevels $subLevels

    .OUTPUTS
        [PSCustomObject[]]
        Jede Gruppe bekommt zusaetzlich:
        - SubGroups:    Array von Sub-Gruppen
        - IsMultiLevel: $true
        - LevelCount:   Anzahl der Ebenen
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Groups,

        [Parameter(Mandatory)]
        [hashtable[]]$SubLevels
    )

    Write-Verbose "Multi-Level: $($Groups.Count) Gruppen, $($SubLevels.Count) Sub-Ebenen"

    # Sub-Level Regex kompilieren
    $compiledLevels = [System.Collections.ArrayList]::new()
    foreach ($level in $SubLevels) {
        $regexStr = $level.Regex
        $capture = if ($null -ne $level.GroupCapture) { [int]$level.GroupCapture } else { 1 }
        $levelName = if ($level.Name) { $level.Name } else { "Ebene" }

        try {
            [void]$compiledLevels.Add(@{
                Name         = $levelName
                Regex        = [regex]::new($regexStr, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                GroupCapture = $capture
            })
        }
        catch {
            Write-Warning "Sub-Level '$levelName': ungueltiger Regex '$regexStr' — uebersprungen"
        }
    }

    if ($compiledLevels.Count -eq 0) {
        Write-Warning "Keine gueltigen Sub-Levels — gebe Original-Gruppen zurueck"
        foreach ($g in $Groups) {
            $g | Add-Member -NotePropertyName 'SubGroups' -NotePropertyValue @() -Force
            $g | Add-Member -NotePropertyName 'IsMultiLevel' -NotePropertyValue $false -Force
            $g | Add-Member -NotePropertyName 'LevelCount' -NotePropertyValue 1 -Force
        }
        return $Groups
    }

    # Sub-Gruppierung pro Top-Level-Gruppe
    $result = foreach ($group in $Groups) {
        $subGroups = Split-IntoSubGroups -Files $group.Files -Levels @($compiledLevels) -LevelIndex 0

        $group | Add-Member -NotePropertyName 'SubGroups' -NotePropertyValue @($subGroups) -Force
        $group | Add-Member -NotePropertyName 'IsMultiLevel' -NotePropertyValue $true -Force
        $group | Add-Member -NotePropertyName 'LevelCount' -NotePropertyValue ($compiledLevels.Count + 1) -Force

        $group
    }

    Write-Verbose "Multi-Level fertig: $($result.Count) Gruppen mit $($compiledLevels.Count) Sub-Ebenen"
    return @($result)
}


function Split-IntoSubGroups {
    <#
    .SYNOPSIS
        Interner Helper: Rekursive Sub-Gruppierung fuer eine Dateiliste

    .DESCRIPTION
        Wendet das Pattern der aktuellen Ebene auf die Dateinamen an und
        gruppiert. Fuer jede Sub-Gruppe wird rekursiv die naechste Ebene
        angewendet. Dateien ohne Match landen in "_other".

    .PARAMETER Files
        Array von Dateinamen (strings)

    .PARAMETER Levels
        Kompilierte Pattern-Ebenen (Array von Hashtables)

    .PARAMETER LevelIndex
        Aktuelle Ebene (0-basiert)

    .EXAMPLE
        $subs = Split-IntoSubGroups -Files $fileNames -Levels $compiled -LevelIndex 0

    .OUTPUTS
        [PSCustomObject[]] Sub-Gruppen mit SubKey, LevelName, Files, FileCount, SubGroups
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Files,

        [Parameter(Mandatory)]
        [hashtable[]]$Levels,

        [Parameter(Mandatory)]
        [int]$LevelIndex
    )

    if ($LevelIndex -ge $Levels.Count -or $Files.Count -eq 0) {
        return @()
    }

    $currentLevel = $Levels[$LevelIndex]
    $regex = $currentLevel.Regex
    $capture = $currentLevel.GroupCapture

    # Dateien nach aktuellem Pattern gruppieren
    $subGroupMap = @{}

    foreach ($fileName in $Files) {
        $m = $regex.Match($fileName)
        $subKey = if ($m.Success) {
            if ($capture -eq 0) { $m.Value.ToLowerInvariant() }
            else { $m.Groups[$capture].Value.ToLowerInvariant() }
        }
        else {
            "_other"
        }

        if (-not $subGroupMap.ContainsKey($subKey)) {
            $subGroupMap[$subKey] = [System.Collections.ArrayList]::new()
        }
        [void]$subGroupMap[$subKey].Add($fileName)
    }

    # Sub-Gruppen erstellen + rekursiv naechste Ebene
    $subGroups = foreach ($key in ($subGroupMap.Keys | Sort-Object)) {
        $subFiles = @($subGroupMap[$key] | Sort-Object)
        $childSubGroups = Split-IntoSubGroups -Files $subFiles -Levels $Levels -LevelIndex ($LevelIndex + 1)

        [PSCustomObject]@{
            SubKey     = $key
            LevelName  = $currentLevel.Name
            Files      = $subFiles
            FileCount  = $subFiles.Count
            SubGroups  = @($childSubGroups)
        }
    }

    return @($subGroups)
}


# ============================================================================
# GRUPPEN-MANIPULATION (in-memory, vor Sortierung)
# ============================================================================

function Move-FileBetweenGroups {
    <#
    .SYNOPSIS
        Verschiebt eine Datei von einer Gruppe in eine andere (in-memory)

    .DESCRIPTION
        Aendert nur die Gruppen-Zuordnung. Keine Dateisystem-Operation.

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

    # In Ziel einfuegen oder neue Gruppe
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
        Fuehrt zwei Gruppen zusammen (in-memory)

    .DESCRIPTION
        Alle Dateien aus SourcePrefix -> TargetPrefix. Quelle wird entfernt.

    .PARAMETER Groups
        Array von Gruppen-Objekten

    .PARAMETER SourcePrefix
        Prefix der aufzuloesenden Gruppe

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
        Prefix fuer die neue Gruppe

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
# EINSTUFIGE SORTIERUNG + UNDO
# ============================================================================

function Invoke-FileSorting {
    <#
    .SYNOPSIS
        Verschiebt Dateien in Unterordner und erstellt Undo-Log

    .DESCRIPTION
        Nimmt Gruppen + Mapping (Prefix -> Ordnername), verschiebt Dateien.
        Erstellt _undo-sort.json fuer Rueckgaengig. Path-Traversal-Schutz.
        Nutzt Move-SingleFile fuer Thumbnail-Kopie.

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
                    Status = "Error"; Message = "Ungueltiger Ordnername (Path-Traversal)"
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

        # Dateien verschieben (via gemeinsamen Helper)
        foreach ($fileName in $group.Files) {
            $moveResult = Move-SingleFile -FolderPath $FolderPath `
                -FileName $fileName -TargetFolder $targetFolder `
                -Prefix $prefix -TargetName $targetName

            $moved += $moveResult.Moved
            $failed += $moveResult.Failed
            if ($moveResult.Detail) { [void]$details.Add($moveResult.Detail) }
            if ($moveResult.UndoEntry) { [void]$undoEntries.Add($moveResult.UndoEntry) }
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

    Write-Verbose "Fertig: $moved verschoben, $failed fehlgeschlagen, $skipped uebersprungen"

    return [PSCustomObject]@{
        Moved          = $moved
        Failed         = $failed
        Skipped        = $skipped
        CreatedFolders = @($createdFolders)
        UndoLogPath    = $undoLogPath
        Details        = @($details)
    }
}


# ============================================================================
# N-STUFIGE SORTIERUNG
# ============================================================================

function Invoke-MultiLevelSorting {
    <#
    .SYNOPSIS
        Verschiebt Dateien in flache Ordner mit kombinierten Namen (N-stufig)

    .DESCRIPTION
        Nimmt Multi-Level-Gruppen (von Get-MultiLevelGroups) und erstellt
        flache Ordner mit kombinierten Namen aus Prefix + Sub-Key.

        Sub-Key Mapping (result-Varianten):
        - result   -> r0
        - result_1 -> r1
        - result_N -> rN
        - _other   -> other

        Ergebnis bei 2 Ebenen:
          FolderPath/
          +-- p105-r0/     (result)
          +-- p105-r1/     (result_1)
          +-- p105-r2/     (result_2)
          +-- DSCF-r0/
          +-- DSCF-r1/

    .PARAMETER FolderPath
        Absoluter Pfad zum Quell-Ordner

    .PARAMETER Groups
        Multi-Level-Gruppen (von Get-MultiLevelGroups, mit SubGroups)

    .PARAMETER GroupMappings
        Hashtable: Key = Prefix, Value = Basis-Ordnername (Stufe 1)
        Sub-Keys werden mit Bindestrich angehaengt.

    .PARAMETER Separator
        Trennzeichen zwischen Prefix und Sub-Key (Default: "-")

    .EXAMPLE
        $map = @{ "p105" = "p105"; "dscf" = "DSCF" }
        $result = Invoke-MultiLevelSorting -FolderPath $path -Groups $multiGroups -GroupMappings $map

    .EXAMPLE
        # Ergebnis: p105-r0/, p105-r1/, DSCF-r0/, DSCF-r1/

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
        [PSCustomObject[]]$Groups,

        [Parameter(Mandatory)]
        [hashtable]$GroupMappings,

        [Parameter()]
        [string]$Separator = "-"
    )

    Write-Verbose "Multi-Level Sortierung (flach): $FolderPath ($($GroupMappings.Count) Mappings)"

    $moved = 0; $failed = 0; $skipped = 0
    $createdFolders = [System.Collections.ArrayList]::new()
    $details = [System.Collections.ArrayList]::new()
    $undoEntries = [System.Collections.ArrayList]::new()

    foreach ($group in $Groups) {
        $prefix = $group.Prefix

        if (-not $GroupMappings.ContainsKey($prefix)) {
            $skipped += $group.FileCount
            continue
        }

        $baseName = $GroupMappings[$prefix]
        if ([string]::IsNullOrWhiteSpace($baseName)) {
            $skipped += $group.FileCount
            continue
        }

        # Path-Traversal Schutz
        if ($baseName -match '[/\\]' -or $baseName.Contains('..')) {
            $failed += $group.FileCount
            continue
        }

        # Hat Sub-Gruppen? -> Flache Ordner mit kombinierten Namen
        if ($group.IsMultiLevel -and $group.SubGroups.Count -gt 0) {
            # SubGroups zu flacher Liste aufloesen
            $flatList = Resolve-FlatSubGroups -SubGroups $group.SubGroups -BaseName $baseName -Separator $Separator

            foreach ($flat in $flatList) {
                $folderName = $flat.FolderName
                $targetFolder = Join-Path $FolderPath $folderName

                # Ordner erstellen
                if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
                    try {
                        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
                        [void]$createdFolders.Add($folderName)
                    }
                    catch {
                        $failed += $flat.Files.Count
                        continue
                    }
                }

                # Dateien verschieben
                foreach ($fileName in $flat.Files) {
                    $moveResult = Move-SingleFile -FolderPath $FolderPath `
                        -FileName $fileName -TargetFolder $targetFolder `
                        -Prefix $prefix -TargetName $folderName
                    $moved += $moveResult.Moved; $failed += $moveResult.Failed
                    if ($moveResult.Detail) { [void]$details.Add($moveResult.Detail) }
                    if ($moveResult.UndoEntry) { [void]$undoEntries.Add($moveResult.UndoEntry) }
                }
            }
        }
        else {
            # Fallback: Einstufig (keine Sub-Gruppen)
            $targetFolder = Join-Path $FolderPath $baseName

            if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
                    [void]$createdFolders.Add($baseName)
                }
                catch {
                    $failed += $group.FileCount
                    continue
                }
            }

            foreach ($fileName in $group.Files) {
                $moveResult = Move-SingleFile -FolderPath $FolderPath `
                    -FileName $fileName -TargetFolder $targetFolder `
                    -Prefix $prefix -TargetName $baseName
                $moved += $moveResult.Moved; $failed += $moveResult.Failed
                if ($moveResult.Detail) { [void]$details.Add($moveResult.Detail) }
                if ($moveResult.UndoEntry) { [void]$undoEntries.Add($moveResult.UndoEntry) }
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
            MultiLevel     = $true
            CreatedFolders = @($createdFolders)
            Entries        = @($undoEntries)
        } | ConvertTo-Json -Depth 10 | Out-File -FilePath $undoLogPath -Encoding UTF8 -Force
        Write-Verbose "Undo-Log: $undoLogPath"
    }

    Write-Verbose "Multi-Level fertig: $moved verschoben, $failed fehlgeschlagen, $skipped uebersprungen"

    return [PSCustomObject]@{
        Moved          = $moved
        Failed         = $failed
        Skipped        = $skipped
        CreatedFolders = @($createdFolders)
        UndoLogPath    = $undoLogPath
        Details        = @($details)
    }
}


function Resolve-FlatSubGroups {
    <#
    .SYNOPSIS
        Interner Helper: Loest SubGroups rekursiv in flache Ordnernamen auf

    .DESCRIPTION
        Wandelt verschachtelte SubGroup-Struktur in eine flache Liste um.
        Jeder Eintrag hat einen kombinierten Ordnernamen und seine Dateien.

        Sub-Key Mapping:
        - "result"   -> "r0"
        - "result_1" -> "r1"
        - "result_N" -> "rN"
        - "_other"   -> "other"
        - alles andere -> wie es ist

    .PARAMETER SubGroups
        Sub-Gruppen mit SubKey, Files, SubGroups

    .PARAMETER BaseName
        Basis-Ordnername (z.B. "p105")

    .PARAMETER Separator
        Trennzeichen (Default: "-")

    .EXAMPLE
        $flat = Resolve-FlatSubGroups -SubGroups $group.SubGroups -BaseName "p105"
        # Ergebnis: @( @{FolderName="p105-r0"; Files=@(...)}, @{FolderName="p105-r1"; Files=@(...)} )

    .OUTPUTS
        [hashtable[]] Array mit FolderName + Files
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)][PSCustomObject[]]$SubGroups,
        [Parameter(Mandatory)][string]$BaseName,
        [Parameter()][string]$Separator = "-"
    )

    $result = [System.Collections.ArrayList]::new()

    foreach ($sub in $SubGroups) {
        # Sub-Key in kurzen Ordnernamen umwandeln
        $shortKey = Convert-SubKeyToShort -SubKey $sub.SubKey

        $folderName = "$BaseName$Separator$shortKey"

        # Hat weitere Sub-Gruppen? -> Rekursiv mit erweitertem BaseName
        if ($sub.SubGroups -and $sub.SubGroups.Count -gt 0) {
            $childFlat = Resolve-FlatSubGroups -SubGroups $sub.SubGroups -BaseName $folderName -Separator $Separator
            foreach ($child in $childFlat) {
                [void]$result.Add($child)
            }
        }
        else {
            # Blatt-Ebene: Dateien zuordnen
            [void]$result.Add(@{
                FolderName = $folderName
                Files      = $sub.Files
            })
        }
    }

    return @($result)
}


function Convert-SubKeyToShort {
    <#
    .SYNOPSIS
        Interner Helper: Wandelt SubKey in kurzen Ordnernamen-Suffix um

    .DESCRIPTION
        Mapping:
        - "result"    -> "r0"
        - "result_1"  -> "r1"
        - "result_2"  -> "r2"
        - "result_N"  -> "rN"
        - "_other"    -> "other"
        - alles andere -> unveraendert

    .PARAMETER SubKey
        Der SubKey aus der Sub-Gruppierung

    .EXAMPLE
        Convert-SubKeyToShort -SubKey "result"    # -> "r0"
        Convert-SubKeyToShort -SubKey "result_3"  # -> "r3"
        Convert-SubKeyToShort -SubKey "_other"    # -> "other"

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SubKey
    )

    # result -> r0
    if ($SubKey -eq 'result') { return 'r0' }

    # result_N -> rN
    if ($SubKey -match '^result_(\d+)$') { return "r$($Matches[1])" }

    # _other -> other
    if ($SubKey -eq '_other') { return 'other' }

    # Alles andere: unveraendert
    return $SubKey
}


# ============================================================================
# UNDO (funktioniert fuer einstufig UND mehrstufig)
# ============================================================================

function Undo-FileSorting {
    <#
    .SYNOPSIS
        Macht die letzte Sortierung rueckgaengig

    .DESCRIPTION
        Liest _undo-sort.json, verschiebt Dateien zurueck, entfernt leere
        Ordner. Funktioniert fuer einstufige und mehrstufige Sortierungen.

    .PARAMETER FolderPath
        Ordner mit _undo-sort.json

    .EXAMPLE
        $result = Undo-FileSorting -FolderPath "D:\Fotos\Unsortiert"
        Write-Host "$($result.Restored) zurueck verschoben"

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
            Write-Warning "Zurueckverschieben: $($entry.File) — $($_.Exception.Message)"
            $failed++
        }
    }

    # Leere erstellte Ordner entfernen (tiefste zuerst fuer verschachtelte)
    $removedFolders = [System.Collections.ArrayList]::new()
    if ($undoData.CreatedFolders) {
        # Sortiere nach Tiefe absteigend (tiefste Unterordner zuerst)
        $sortedFolders = @($undoData.CreatedFolders | Sort-Object { ($_ -split '[/\\]').Count } -Descending)

        foreach ($folderName in $sortedFolders) {
            $folderFull = Join-Path $FolderPath $folderName
            if ((Test-Path -LiteralPath $folderFull -PathType Container)) {
                # Prüfe ob leer (ignoriere .thumbs)
                $remaining = @(Get-ChildItem -LiteralPath $folderFull -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '.thumbs' })
                if ($remaining.Count -eq 0) {
                    try {
                        # .thumbs Ordner auch entfernen
                        $thumbsDir = Join-Path $folderFull ".thumbs"
                        if (Test-Path -LiteralPath $thumbsDir -PathType Container) {
                            Remove-Item -LiteralPath $thumbsDir -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        Remove-Item -LiteralPath $folderFull -Force
                        [void]$removedFolders.Add($folderName)
                    }
                    catch { Write-Warning "Ordner nicht entfernbar: $folderName" }
                }
            }
        }
    }

    try { Remove-Item -LiteralPath $undoPath -Force }
    catch { Write-Warning "Undo-Log nicht loeschbar" }

    Write-Verbose "Undo: $restored zurueck, $failed fehlgeschlagen, $($removedFolders.Count) Ordner entfernt"

    return [PSCustomObject]@{
        Success        = ($failed -eq 0)
        Restored       = $restored
        Failed         = $failed
        RemovedFolders = @($removedFolders)
        Error          = $null
    }
}