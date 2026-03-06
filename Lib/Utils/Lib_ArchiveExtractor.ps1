<#
ManifestHint:
  ExportFunctions = @("Get-Extractor", "Expand-OneArchive", "Invoke-ArchiveExtraction")
  Description     = "Archiv-Entpackung mit 7-Zip/WinRAR/Expand-Archive"
  Category        = "Utils"
  Tags            = @("Archive", "Extract", "7-Zip", "WinRAR")
  Dependencies    = @()

Zweck:
  - Erkennt installierte Entpack-Tools (7-Zip bevorzugt)
  - Entpackt einzelne Archive oder rekursiv alle in einem Ordner
  - Unterstützt verschachtelte Archive (maxRounds)
  - Nach Entpacken: Papierkorb/Löschen/Behalten (Config)

Funktionen:
  - Get-Extractor: Findet bestes verfügbares Entpack-Tool
  - Expand-OneArchive: Entpackt ein einzelnes Archiv
  - Invoke-ArchiveExtraction: Rekursiv alle Archive entpacken

Abhängigkeiten:
  - Lib_Config.ps1 (Get-Config)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.1
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function Get-Extractor {
    <#
    .SYNOPSIS
        Findet das beste verfügbare Entpack-Tool

    .DESCRIPTION
        Prüft in dieser Reihenfolge:
        1. 7-Zip (7z.exe) - Bevorzugt, unterstützt alle Formate
        2. WinRAR (UnRAR.exe) - Fallback für .rar
        3. Expand-Archive - PowerShell Built-in, nur .zip
        
        Sucht in Standard-Installationspfaden und PATH.

    .EXAMPLE
        $extractor = Get-Extractor
        # @{ Tool = "7zip"; Path = "C:\Program Files\7-Zip\7z.exe"; Formats = @(".zip",".rar",".7z",".tar",".gz") }

    .EXAMPLE
        $extractor = Get-Extractor
        if ($extractor.Tool -eq "expand-archive") {
            Write-Warning "Nur .zip wird unterstützt"
        }

    .OUTPUTS
        [hashtable]
        Tool (string), Path (string), Formats (string[])
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # 7-Zip prüfen (bevorzugt)
    $sevenZipPaths = @(
        "C:\Program Files\7-Zip\7z.exe"
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )

    foreach ($szPath in $sevenZipPaths) {
        if (Test-Path -LiteralPath $szPath -PathType Leaf) {
            Write-Verbose "7-Zip gefunden: $szPath"
            return @{
                Tool    = "7zip"
                Path    = $szPath
                Formats = @(".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz")
            }
        }
    }

    # 7z.exe in PATH?
    $szInPath = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if ($szInPath) {
        Write-Verbose "7-Zip in PATH: $($szInPath.Source)"
        return @{
            Tool    = "7zip"
            Path    = $szInPath.Source
            Formats = @(".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz")
        }
    }

    # WinRAR prüfen (Fallback)
    $winRarPaths = @(
        "C:\Program Files\WinRAR\UnRAR.exe"
        "C:\Program Files (x86)\WinRAR\UnRAR.exe"
    )

    foreach ($wrPath in $winRarPaths) {
        if (Test-Path -LiteralPath $wrPath -PathType Leaf) {
            Write-Verbose "WinRAR gefunden: $wrPath"
            return @{
                Tool    = "winrar"
                Path    = $wrPath
                Formats = @(".zip", ".rar", ".7z", ".tar", ".gz")
            }
        }
    }

    $wrInPath = Get-Command "UnRAR.exe" -ErrorAction SilentlyContinue
    if ($wrInPath) {
        Write-Verbose "WinRAR in PATH: $($wrInPath.Source)"
        return @{
            Tool    = "winrar"
            Path    = $wrInPath.Source
            Formats = @(".zip", ".rar", ".7z", ".tar", ".gz")
        }
    }

    # Fallback: Expand-Archive (nur .zip)
    Write-Verbose "Kein externes Tool gefunden, verwende Expand-Archive (nur .zip)"
    return @{
        Tool    = "expand-archive"
        Path    = $null
        Formats = @(".zip")
    }
}


function Expand-OneArchive {
    <#
    .SYNOPSIS
        Entpackt ein einzelnes Archiv in den gleichen Ordner

    .DESCRIPTION
        Entpackt das Archiv in einen Unterordner mit dem Archiv-Namen
        (ohne Extension). Verwendet das übergebene Extractor-Tool.
        
        Nach erfolgreichem Entpacken wird das Archiv je nach
        AfterExtract-Einstellung behandelt (recycle/delete/keep).

    .PARAMETER ArchivePath
        Vollständiger Pfad zum Archiv

    .PARAMETER Extractor
        Extractor-Hashtable von Get-Extractor

    .PARAMETER AfterExtract
        Was nach dem Entpacken passiert: "recycle", "delete", "keep"

    .EXAMPLE
        $ext = Get-Extractor
        Expand-OneArchive -ArchivePath "C:\Fotos\bilder.zip" -Extractor $ext -AfterExtract "recycle"

    .EXAMPLE
        Expand-OneArchive -ArchivePath "C:\Fotos\set.7z" -Extractor $ext -AfterExtract "keep"

    .OUTPUTS
        [PSCustomObject]
        Success (bool), ArchivePath (string), OutputFolder (string), Message (string)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [hashtable]$Extractor,

        [Parameter()]
        [ValidateSet("recycle", "delete", "keep")]
        [string]$AfterExtract = "recycle"
    )

    $archiveItem = Get-Item -LiteralPath $ArchivePath
    $archiveExt = $archiveItem.Extension.ToLowerInvariant()
    $parentDir = $archiveItem.DirectoryName

    # Ziel-Ordner = Archiv-Name ohne Extension
    $outputFolder = Join-Path $parentDir $archiveItem.BaseName

    # Prüfe ob Extractor das Format unterstützt
    if ($archiveExt -notin $Extractor.Formats) {
        return [PSCustomObject]@{
            Success      = $false
            ArchivePath  = $ArchivePath
            OutputFolder = $null
            Message      = "Format '$archiveExt' wird von $($Extractor.Tool) nicht unterstützt"
        }
    }

    # Ziel-Ordner erstellen (falls nicht vorhanden)
    if (-not (Test-Path -LiteralPath $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
        Write-Verbose "Ziel-Ordner erstellt: $outputFolder"
    }

    try {
        switch ($Extractor.Tool) {
            "7zip" {
                # 7z x = extract mit Verzeichnisstruktur
                # -o = Output-Ordner, -y = Überschreiben ohne Frage
                $args7z = @("x", $ArchivePath, "-o$outputFolder", "-y")
                $result = & $Extractor.Path @args7z 2>&1
                $exitCode = $LASTEXITCODE

                if ($exitCode -ne 0) {
                    $errorMsg = ($result | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "; "
                    if ([string]::IsNullOrWhiteSpace($errorMsg)) {
                        $errorMsg = "7-Zip Exit-Code: $exitCode"
                    }
                    throw $errorMsg
                }

                Write-Verbose "7-Zip: Erfolgreich entpackt -> $outputFolder"
            }

            "winrar" {
                # UnRAR x = extract mit Verzeichnisstruktur
                $argsWr = @("x", "-y", $ArchivePath, "$outputFolder\")
                $result = & $Extractor.Path @argsWr 2>&1
                $exitCode = $LASTEXITCODE

                if ($exitCode -ne 0) {
                    $errorMsg = ($result | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "; "
                    if ([string]::IsNullOrWhiteSpace($errorMsg)) {
                        $errorMsg = "UnRAR Exit-Code: $exitCode"
                    }
                    throw $errorMsg
                }

                Write-Verbose "WinRAR: Erfolgreich entpackt -> $outputFolder"
            }

            "expand-archive" {
                if ($archiveExt -ne ".zip") {
                    throw "Expand-Archive unterstützt nur .zip (Archiv: $archiveExt). Installiere 7-Zip für andere Formate."
                }

                Expand-Archive -LiteralPath $ArchivePath -DestinationPath $outputFolder -Force
                Write-Verbose "Expand-Archive: Erfolgreich entpackt -> $outputFolder"
            }

            default {
                throw "Unbekannter Extractor: $($Extractor.Tool)"
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            Success      = $false
            ArchivePath  = $ArchivePath
            OutputFolder = $outputFolder
            Message      = "Fehler: $($_.Exception.Message)"
        }
    }

    # Nach Entpacken: Archiv behandeln
    try {
        switch ($AfterExtract) {
            "recycle" {
                # In Papierkorb verschieben (Windows Shell API)
                Add-Type -AssemblyName Microsoft.VisualBasic
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $ArchivePath,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
                Write-Verbose "Archiv in Papierkorb: $($archiveItem.Name)"
            }
            "delete" {
                Remove-Item -LiteralPath $ArchivePath -Force
                Write-Verbose "Archiv gelöscht: $($archiveItem.Name)"
            }
            "keep" {
                Write-Verbose "Archiv behalten: $($archiveItem.Name)"
            }
        }
    }
    catch {
        # Entpacken war erfolgreich, nur Archiv-Cleanup fehlgeschlagen
        return [PSCustomObject]@{
            Success      = $true
            ArchivePath  = $ArchivePath
            OutputFolder = $outputFolder
            Message      = "Entpackt, aber Archiv-Cleanup fehlgeschlagen: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        Success      = $true
        ArchivePath  = $ArchivePath
        OutputFolder = $outputFolder
        Message      = "Erfolgreich entpackt ($($Extractor.Tool))"
    }
}


function Invoke-ArchiveExtraction {
    <#
    .SYNOPSIS
        Entpackt rekursiv alle Archive in einem Ordner

    .DESCRIPTION
        Sucht alle Archive (nach Config-Extensions) im RootPath und
        entpackt sie sequenziell. Unterstützt verschachtelte Archive
        über mehrere Runden (maxRounds), z.B. .zip in .zip.
        
        Nutzt Config-Werte:
        - Features.ArchiveExtraction (muss true sein)
        - Features.ArchiveExtensions (welche Endungen)
        - Features.ArchiveAfterExtract (recycle/delete/keep)

    .PARAMETER RootPath
        Root-Ordner in dem gesucht wird

    .PARAMETER MaxRounds
        Maximale Entpack-Runden für verschachtelte Archive

    .EXAMPLE
        $results = Invoke-ArchiveExtraction -RootPath "D:\Fotos"
        Write-Host "$($results.Extracted) Archive entpackt, $($results.Failed) fehlgeschlagen"

    .EXAMPLE
        $results = Invoke-ArchiveExtraction -RootPath "D:\Fotos" -MaxRounds 5
        # Bis zu 5 Runden für tief verschachtelte Archive

    .OUTPUTS
        [PSCustomObject]
        Extracted (int), Failed (int), Skipped (int), Rounds (int), Details (array)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$RootPath,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRounds = 3
    )

    # Config laden
    $config = Get-Config

    # Feature aktiviert?
    if (-not $config.Features.ArchiveExtraction) {
        Write-Verbose "Archive Extraction ist deaktiviert (Features.ArchiveExtraction = false)"
        return [PSCustomObject]@{
            Extracted = 0
            Failed    = 0
            Skipped   = 0
            Rounds    = 0
            Details   = @()
        }
    }

    $extensions = $config.Features.ArchiveExtensions
    $afterExtract = $config.Features.ArchiveAfterExtract

    if (-not $extensions -or $extensions.Count -eq 0) {
        Write-Verbose "Keine Archive-Extensions konfiguriert"
        return [PSCustomObject]@{
            Extracted = 0
            Failed    = 0
            Skipped   = 0
            Rounds    = 0
            Details   = @()
        }
    }

    # Extractor bestimmen
    $extractor = Get-Extractor
    Write-Verbose "Extractor: $($extractor.Tool) ($($extractor.Formats -join ', '))"

    # Welche konfigurierten Extensions kann der Extractor?
    $supportedExts = @($extensions | Where-Object { $_ -in $extractor.Formats })
    $unsupportedExts = @($extensions | Where-Object { $_ -notin $extractor.Formats })

    if ($unsupportedExts.Count -gt 0) {
        Write-Warning "Extractor '$($extractor.Tool)' unterstützt nicht: $($unsupportedExts -join ', '). Installiere 7-Zip für alle Formate."
    }

    if ($supportedExts.Count -eq 0) {
        Write-Warning "Keine der konfigurierten Extensions wird unterstützt"
        return [PSCustomObject]@{
            Extracted = 0
            Failed    = 0
            Skipped   = 0
            Rounds    = 0
            Details   = @()
        }
    }

    # Statistiken
    $totalExtracted = 0
    $totalFailed = 0
    $totalSkipped = 0
    $allDetails = [System.Collections.ArrayList]::new()
    $round = 0

    # Runden-basiertes Entpacken (für verschachtelte Archive)
    while ($round -lt $MaxRounds) {
        $round++
        Write-Verbose "=== Runde ${round} von $MaxRounds ==="

        # Archive suchen
        $archives = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension.ToLowerInvariant() -in $supportedExts })

        if ($archives.Count -eq 0) {
            Write-Verbose "Keine Archive gefunden in Runde $round"
            break
        }

        Write-Verbose "Runde ${round}: $($archives.Count) Archive gefunden"

        $roundExtracted = 0

        foreach ($archive in $archives) {
            Write-Verbose "Entpacke: $($archive.FullName)"

            $result = Expand-OneArchive -ArchivePath $archive.FullName -Extractor $extractor -AfterExtract $afterExtract
            [void]$allDetails.Add($result)

            if ($result.Success) {
                $totalExtracted++
                $roundExtracted++
                Write-Verbose "  -> $($result.Message)"
            }
            else {
                $totalFailed++
                Write-Warning "  X $($archive.Name): $($result.Message)"
            }
        }

        # Keine Archive entpackt -> keine weiteren Runden nötig
        if ($roundExtracted -eq 0) {
            Write-Verbose "Runde ${round}: Keine Archive entpackt, stoppe"
            break
        }
    }

    Write-Verbose "Fertig: $totalExtracted entpackt, $totalFailed fehlgeschlagen, $round Runden"

    return [PSCustomObject]@{
        Extracted = $totalExtracted
        Failed    = $totalFailed
        Skipped   = $totalSkipped
        Rounds    = $round
        Details   = @($allDetails)
    }
}
