<#
ManifestHint:
  ExportFunctions = @("Get-AnonymizedLogPath")
  Description     = "Logging-Hilfsfunktionen fuer PhotoFolder"
  Category        = "Core"
  Tags            = @("Logging","Privacy","Paths","Anonymization")
  Dependencies    = @()

Zweck:
  - Buchstaben in Pfaden anonymisieren fuer Log-Ausgaben (Privacy)
  - Struktur (Laenge, Sonderzeichen, Zahlen) bleibt erhalten
  - Persistente Substitutions-Map (char-map.json) fuer konsistente Logs

Funktionen:
  - Get-AnonymizedLogPath: Anonymisiert Buchstaben in Pfad

Abhaengigkeiten:
  - keine

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Map-Cache (einmal laden pro Session)
$script:CharMap = $null
$script:CharMapPath = $null

function Initialize-CharMap {
    <#
    .SYNOPSIS
        Laedt oder erstellt die persistente Buchstaben-Substitutions-Map

    .DESCRIPTION
        Laedt char-map.json falls vorhanden.
        Erstellt neue zufaellige Map falls nicht vorhanden und speichert sie.
        Map bleibt persistent - gleicher Buchstabe = immer gleiche Ausgabe.

    .PARAMETER ProjectRoot
        Projekt-Root-Pfad (fuer char-map.json Speicherort)

    .EXAMPLE
        Initialize-CharMap -ProjectRoot "C:\PhotoFolder"

    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $script:CharMapPath = Join-Path $ProjectRoot "Lib\Core\char-map.json"

    # Bereits geladen?
    if ($script:CharMap) {
        return
    }

    # Von Disk laden falls vorhanden
    if (Test-Path -LiteralPath $script:CharMapPath) {
        try {
            $json = Get-Content -LiteralPath $script:CharMapPath -Raw -Encoding UTF8
            $script:CharMap = $json | ConvertFrom-Json -AsHashtable
            Write-Verbose "Char-Map geladen: $($script:CharMapPath)"
            return
        } catch {
            Write-Warning "Char-Map konnte nicht geladen werden, erstelle neue: $_"
        }
    }

    # Neue zufaellige Map erstellen
    Write-Verbose "Erstelle neue persistente Char-Map..."

    $lower = 'a'..'z' | ForEach-Object { [char]$_ }
    $upper = 'A'..'Z' | ForEach-Object { [char]$_ }

    # Zufaellige Permutationen (kein Buchstabe mappt auf sich selbst)
    $shuffledLower = Get-ShuffledAlphabet -Chars $lower
    $shuffledUpper = Get-ShuffledAlphabet -Chars $upper

    $map = @{}
    for ($i = 0; $i -lt 26; $i++) {
        $map[[string]$lower[$i]] = [string]$shuffledLower[$i]
        $map[[string]$upper[$i]] = [string]$shuffledUpper[$i]
    }

    $script:CharMap = $map

    # Persistieren
    $json = $map | ConvertTo-Json
    $json | Out-File -FilePath $script:CharMapPath -Encoding UTF8 -Force
    Write-Verbose "Neue Char-Map gespeichert: $($script:CharMapPath)"
}

function Get-ShuffledAlphabet {
    <#
    .SYNOPSIS
        Erstellt zufaellige Permutation eines Buchstaben-Arrays
        ohne Fixpunkte (kein Element mappt auf sich selbst)

    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [char[]]$Chars
    )

    $arr = [char[]]$Chars.Clone()
    $n = $arr.Length
    $rng = [System.Random]::new()

    # Fisher-Yates Shuffle
    for ($i = $n - 1; $i -gt 0; $i--) {
        $j = $rng.Next(0, $i + 1)
        $tmp = $arr[$i]
        $arr[$i] = $arr[$j]
        $arr[$j] = $tmp
    }

    # Fixpunkte korrigieren (kein a→a, b→b, etc.)
    for ($i = 0; $i -lt $n; $i++) {
        if ($arr[$i] -eq $Chars[$i]) {
            # Tausche mit naechstem Element (wrap-around)
            $j = ($i + 1) % $n
            $tmp = $arr[$i]
            $arr[$i] = $arr[$j]
            $arr[$j] = $tmp
        }
    }

    return $arr
}

function Get-AnonymizedLogPath {
    <#
    .SYNOPSIS
        Anonymisiert Buchstaben in Pfad fuer Log-Ausgaben (Privacy)

    .DESCRIPTION
        Ersetzt alle Buchstaben durch konsistente Substitutionen.
        Zahlen, Leerzeichen, Sonderzeichen (\ / . - _ : usw.) bleiben erhalten.
        Struktur und Laenge des Pfades bleiben vollstaendig erhalten.

        Persistente Map (char-map.json) stellt sicher dass gleicher
        Buchstabe immer gleich ausgegeben wird - auch session-uebergreifend.

        Beispiel:
          Input:  "Urlaub 2024\strand.jpg"
          Output: "Xkoeqf 2024\ghkoqz.jpg"

    .PARAMETER FullPath
        Pfad der anonymisiert werden soll

    .PARAMETER ProjectRoot
        Projekt-Root-Pfad (fuer char-map.json)

    .EXAMPLE
        Get-AnonymizedLogPath -FullPath "D:\Fotos\Urlaub 2024\foto.jpg" -ProjectRoot $ScriptRoot
        # Output: "Z:\Xbgbh\Xkoeqf 2024\xbgb.jpg"

    .EXAMPLE
        Write-Warning "Datei nicht gefunden: $(Get-AnonymizedLogPath -FullPath $fullPath -ProjectRoot $ScriptRoot)"

    .NOTES
        Version: 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FullPath,

        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    # Map laden (lazy, einmalig)
    Initialize-CharMap -ProjectRoot $ProjectRoot

    # Zeichen fuer Zeichen ersetzen
    $result = [System.Text.StringBuilder]::new($FullPath.Length)

    foreach ($char in $FullPath.ToCharArray()) {
        $key = [string]$char
        if ($script:CharMap.ContainsKey($key)) {
            [void]$result.Append($script:CharMap[$key])
        } else {
            [void]$result.Append($char)
        }
    }

    return $result.ToString()
}