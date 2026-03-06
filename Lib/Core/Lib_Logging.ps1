<#
ManifestHint:
  ExportFunctions = @("Get-RelativeLogPath")
  Description     = "Logging-Hilfsfunktionen fuer PhotoFolder"
  Category        = "Core"
  Tags            = @("Logging","Privacy","Paths")
  Dependencies    = @()

Zweck:
  - Absolute Pfade in Log-Ausgaben durch relative ersetzen (Privacy)
  - Verhindert dass private Ordnerstrukturen in Write-Warning erscheinen

Funktionen:
  - Get-RelativeLogPath: Kuerzt absoluten Pfad fuer Logging

Abhängigkeiten:
  - keine

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RelativeLogPath {
    <#
    .SYNOPSIS
        Kuerzt absoluten Pfad fuer Log-Ausgaben (Privacy)

    .DESCRIPTION
        Entfernt RootFull-Prefix aus Pfad fuer Write-Warning/Verbose Ausgaben.
        Verhindert dass private Ordnerstrukturen im Log erscheinen.

        Beispiel:
          Input:  "D:\OneDrive\Private\Fotos\2024\foto.jpg"
          Root:   "D:\OneDrive\Private\Fotos"
          Output: "2024/foto.jpg"

        Fallback (kein Root-Match): Nur Dateiname wird zurueckgegeben.

    .PARAMETER FullPath
        Absoluter Pfad der gekuerzt werden soll

    .PARAMETER RootFull
        Root-Ordner der Mediathek (wird als Prefix entfernt)

    .EXAMPLE
        Get-RelativeLogPath -FullPath "D:\Private\Fotos\2024\foto.jpg" -RootFull "D:\Private\Fotos"
        # Returns: "2024/foto.jpg"

    .EXAMPLE
        Write-Warning "Datei nicht gefunden: $(Get-RelativeLogPath -FullPath $fullPath -RootFull $RootFull)"

    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FullPath,

        [Parameter(Mandatory)]
        [string]$RootFull
    )

    if ($FullPath.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($RootFull.Length).TrimStart('\', '/').Replace('\', '/')
    }

    # Fallback: nur Dateiname (kein Root-Match)
    return [System.IO.Path]::GetFileName($FullPath)
}
