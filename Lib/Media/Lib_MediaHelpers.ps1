<#
ManifestHint:
  ExportFunctions = @("Find-FFmpegPath", "Find-FFprobePath")
  Description     = "Zentralisierte FFmpeg/FFprobe Pfad-Erkennung"
  Category        = "Media"
  Tags            = @("FFmpeg","FFprobe","Paths","Helper")
  Dependencies    = @()

Zweck:
  - Einheitliche FFmpeg/FFprobe Pfad-Suche fuer alle Libs
  - Sucht erst im Projekt-Root (ffmpeg\), dann im System-PATH
  - Ergebnis wird gecacht ($script:) - nur einmal suchen
  - Ersetzt 3 verschiedene hardcoded Pfad-Logiken in:
    Lib_Thumbnails.ps1, Lib_VideoHLS.ps1, Lib_SystemCheck.ps1

Funktionen:
  - Find-FFmpegPath: Sucht ffmpeg.exe (Projekt → PATH)
  - Find-FFprobePath: Sucht ffprobe.exe (Projekt → PATH)

Abhaengigkeiten:
  - Keine (standalone, keine Config noetig)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0

.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cache fuer gefundene Pfade (nur einmal suchen pro Session)
$script:CachedFFmpegPath  = $null
$script:CachedFFprobePath = $null


function Find-FFmpegPath {
    <#
    .SYNOPSIS
        Sucht ffmpeg.exe - erst Projekt-Root, dann System-PATH

    .DESCRIPTION
        Suchstrategie:
        1. $ScriptRoot\ffmpeg\ffmpeg.exe (lokale Installation im Projekt)
        2. System-PATH (Get-Command ffmpeg.exe)

        Ergebnis wird in $script:CachedFFmpegPath gecacht.
        Bei erneutem Aufruf ohne -Force wird Cache zurueckgegeben.

    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (Ordner der start.ps1 enthaelt)

    .PARAMETER Force
        Ignoriert Cache, sucht erneut

    .EXAMPLE
        $ffmpeg = Find-FFmpegPath -ScriptRoot $PSScriptRoot
        if ($ffmpeg) { & $ffmpeg -version }

    .EXAMPLE
        $ffmpeg = Find-FFmpegPath -ScriptRoot $PSScriptRoot -Force
        # Erzwingt Neusuche

    .OUTPUTS
        String - Vollstaendiger Pfad zu ffmpeg.exe oder $null wenn nicht gefunden
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot,

        [Parameter()]
        [switch]$Force
    )

    # Cache-Hit?
    if ($script:CachedFFmpegPath -and -not $Force) {
        Write-Verbose "FFmpeg aus Cache: $script:CachedFFmpegPath"
        return $script:CachedFFmpegPath
    }

    # Strategie 1: Projekt-Root (ffmpeg\ffmpeg.exe)
    $localPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"

    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        Write-Verbose "FFmpeg gefunden (Projekt): $localPath"
        $script:CachedFFmpegPath = $localPath
        return $localPath
    }

    # Strategie 2: System-PATH
    try {
        $systemCmd = Get-Command -Name "ffmpeg.exe" -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($systemCmd) {
            $systemPath = $systemCmd.Source
            Write-Verbose "FFmpeg gefunden (System-PATH): $systemPath"
            $script:CachedFFmpegPath = $systemPath
            return $systemPath
        }
    }
    catch {
        Write-Verbose "Fehler bei System-PATH Suche: $($_.Exception.Message)"
    }

    # Nicht gefunden
    Write-Verbose "FFmpeg NICHT gefunden (weder in $ScriptRoot\ffmpeg\ noch im System-PATH)"
    return $null
}


function Find-FFprobePath {
    <#
    .SYNOPSIS
        Sucht ffprobe.exe - erst Projekt-Root, dann System-PATH

    .DESCRIPTION
        Suchstrategie:
        1. $ScriptRoot\ffmpeg\ffprobe.exe (lokale Installation im Projekt)
        2. System-PATH (Get-Command ffprobe.exe)

        Ergebnis wird in $script:CachedFFprobePath gecacht.
        Bei erneutem Aufruf ohne -Force wird Cache zurueckgegeben.

    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (Ordner der start.ps1 enthaelt)

    .PARAMETER Force
        Ignoriert Cache, sucht erneut

    .EXAMPLE
        $ffprobe = Find-FFprobePath -ScriptRoot $PSScriptRoot
        if ($ffprobe) { & $ffprobe -version }

    .EXAMPLE
        $ffprobe = Find-FFprobePath -ScriptRoot $PSScriptRoot -Force

    .OUTPUTS
        String - Vollstaendiger Pfad zu ffprobe.exe oder $null wenn nicht gefunden
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot,

        [Parameter()]
        [switch]$Force
    )

    # Cache-Hit?
    if ($script:CachedFFprobePath -and -not $Force) {
        Write-Verbose "FFprobe aus Cache: $script:CachedFFprobePath"
        return $script:CachedFFprobePath
    }

    # Strategie 1: Projekt-Root (ffmpeg\ffprobe.exe)
    $localPath = Join-Path $ScriptRoot "ffmpeg\ffprobe.exe"

    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        Write-Verbose "FFprobe gefunden (Projekt): $localPath"
        $script:CachedFFprobePath = $localPath
        return $localPath
    }

    # Strategie 2: System-PATH
    try {
        $systemCmd = Get-Command -Name "ffprobe.exe" -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($systemCmd) {
            $systemPath = $systemCmd.Source
            Write-Verbose "FFprobe gefunden (System-PATH): $systemPath"
            $script:CachedFFprobePath = $systemPath
            return $systemPath
        }
    }
    catch {
        Write-Verbose "Fehler bei System-PATH Suche: $($_.Exception.Message)"
    }

    # Nicht gefunden
    Write-Verbose "FFprobe NICHT gefunden (weder in $ScriptRoot\ffmpeg\ noch im System-PATH)"
    return $null
}