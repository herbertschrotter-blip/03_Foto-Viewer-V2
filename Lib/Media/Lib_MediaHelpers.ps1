<#
ManifestHint:
  ExportFunctions = @("Find-FFmpegPath", "Find-FFprobePath", "Get-FFmpegMissingHtml")
  Description     = "Zentralisierte FFmpeg/FFprobe Pfad-Erkennung"
  Category        = "Media"
  Tags            = @("FFmpeg","FFprobe","Paths","Helper")
  Dependencies    = @()

Zweck:
  - Einheitliche FFmpeg/FFprobe Pfad-Suche fuer alle Libs
  - Sucht im Projekt-Root: ffmpeg\ffmpeg.exe / ffmpeg\ffprobe.exe
  - Ergebnis wird gecacht ($script:) - nur einmal suchen pro Session
  - Bei Fehlen: Benutzerfreundliche HTML-Anleitung fuer den Browser
  - Ersetzt 3 verschiedene hardcoded Pfad-Logiken in:
    Lib_Thumbnails.ps1, Lib_VideoHLS.ps1, Lib_SystemCheck.ps1

Funktionen:
  - Find-FFmpegPath: Sucht ffmpeg.exe im Projekt-Root
  - Find-FFprobePath: Sucht ffprobe.exe im Projekt-Root
  - Get-FFmpegMissingHtml: HTML-Anleitung wenn FFmpeg fehlt

Abhaengigkeiten:
  - Keine (standalone, keine Config noetig)

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0

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
        Sucht ffmpeg.exe im Projekt-Root (ffmpeg\ffmpeg.exe)

    .DESCRIPTION
        Prueft ob ffmpeg.exe unter $ScriptRoot\ffmpeg\ liegt.
        Ergebnis wird in $script:CachedFFmpegPath gecacht.
        Kein System-PATH-Fallback (Performance in Runspaces!).

    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (Ordner der start.ps1 enthaelt)

    .PARAMETER Force
        Ignoriert Cache, sucht erneut

    .EXAMPLE
        $ffmpeg = Find-FFmpegPath -ScriptRoot $PSScriptRoot
        if ($ffmpeg) { & $ffmpeg -version }

    .EXAMPLE
        $ffmpeg = Find-FFmpegPath -ScriptRoot $PSScriptRoot -Force

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

    # Projekt-Root: ffmpeg\ffmpeg.exe
    $localPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"

    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        Write-Verbose "FFmpeg gefunden: $localPath"
        $script:CachedFFmpegPath = $localPath
        return $localPath
    }

    # Nicht gefunden
    Write-Warning "FFmpeg nicht gefunden: $localPath"
    return $null
}


function Find-FFprobePath {
    <#
    .SYNOPSIS
        Sucht ffprobe.exe im Projekt-Root (ffmpeg\ffprobe.exe)

    .DESCRIPTION
        Prueft ob ffprobe.exe unter $ScriptRoot\ffmpeg\ liegt.
        Ergebnis wird in $script:CachedFFprobePath gecacht.
        Kein System-PATH-Fallback (Performance in Runspaces!).

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

    # Projekt-Root: ffmpeg\ffprobe.exe
    $localPath = Join-Path $ScriptRoot "ffmpeg\ffprobe.exe"

    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        Write-Verbose "FFprobe gefunden: $localPath"
        $script:CachedFFprobePath = $localPath
        return $localPath
    }

    # Nicht gefunden
    Write-Warning "FFprobe nicht gefunden: $localPath"
    return $null
}


function Get-FFmpegMissingHtml {
    <#
    .SYNOPSIS
        Gibt benutzerfreundliche HTML-Seite zurueck wenn FFmpeg fehlt

    .DESCRIPTION
        Zeigt im Browser eine verstaendliche Anleitung mit:
        - Was ist FFmpeg und warum wird es gebraucht
        - Link zur offiziellen Download-Seite
        - Schritt-fuer-Schritt Anleitung (auch fuer Laien)
        - Erwartete Ordner-Struktur

    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (wird in der Anleitung angezeigt)

    .EXAMPLE
        $html = Get-FFmpegMissingHtml -ScriptRoot "D:\Projekte\PhotoFolder"
        Send-ResponseHtml -Response $res -Html $html -StatusCode 503

    .EXAMPLE
        if (-not (Find-FFmpegPath -ScriptRoot $ScriptRoot)) {
            $html = Get-FFmpegMissingHtml -ScriptRoot $ScriptRoot
            Send-ResponseHtml -Response $res -Html $html -StatusCode 503
        }

    .OUTPUTS
        String - Komplette HTML-Seite
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    $expectedPath = Join-Path $ScriptRoot "ffmpeg"
    # HTML-Escape fuer Sicherheit
    $escapedPath = [System.Web.HttpUtility]::HtmlEncode($expectedPath)

    $html = @"
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FFmpeg fehlt - PhotoFolder Setup</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f0f4f8;
            color: #2d3748;
            line-height: 1.6;
            padding: 40px 20px;
        }
        .container {
            max-width: 720px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #e53e3e, #c53030);
            color: white;
            padding: 30px 40px;
        }
        .header h1 { font-size: 24px; margin-bottom: 8px; }
        .header p { opacity: 0.9; font-size: 15px; }
        .content { padding: 40px; }
        .info-box {
            background: #ebf8ff;
            border-left: 4px solid #3182ce;
            padding: 16px 20px;
            border-radius: 0 8px 8px 0;
            margin-bottom: 30px;
        }
        .info-box p { font-size: 14px; color: #2c5282; }
        h2 {
            font-size: 18px;
            color: #2d3748;
            margin-bottom: 16px;
            padding-bottom: 8px;
            border-bottom: 2px solid #e2e8f0;
        }
        .step {
            display: flex;
            gap: 16px;
            margin-bottom: 24px;
            align-items: flex-start;
        }
        .step-number {
            background: #4299e1;
            color: white;
            width: 32px; height: 32px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
            font-size: 14px;
            flex-shrink: 0;
            margin-top: 2px;
        }
        .step-content { flex: 1; }
        .step-content h3 { font-size: 15px; margin-bottom: 6px; color: #2d3748; }
        .step-content p { font-size: 14px; color: #4a5568; }
        .download-btn {
            display: inline-block;
            background: #4299e1;
            color: white;
            padding: 12px 24px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            font-size: 15px;
            margin: 8px 0;
            transition: background 0.2s;
        }
        .download-btn:hover { background: #3182ce; }
        .folder-structure {
            background: #1a202c;
            color: #a0aec0;
            padding: 20px 24px;
            border-radius: 8px;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 13px;
            line-height: 1.8;
            margin: 16px 0;
            overflow-x: auto;
        }
        .folder-structure .hl { color: #68d391; font-weight: bold; }
        .path-display {
            background: #edf2f7;
            padding: 8px 14px;
            border-radius: 6px;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 13px;
            color: #2d3748;
            word-break: break-all;
            margin: 8px 0;
        }
        .warning-box {
            background: #fffbeb;
            border-left: 4px solid #d69e2e;
            padding: 16px 20px;
            border-radius: 0 8px 8px 0;
            margin: 24px 0;
        }
        .warning-box p { font-size: 14px; color: #744210; }
        .footer {
            text-align: center;
            padding: 24px;
            background: #f7fafc;
            border-top: 1px solid #e2e8f0;
        }
        .retry-btn {
            display: inline-block;
            background: #48bb78;
            color: white;
            padding: 14px 32px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            font-size: 16px;
            transition: background 0.2s;
        }
        .retry-btn:hover { background: #38a169; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>&#9888; FFmpeg nicht gefunden</h1>
            <p>PhotoFolder braucht FFmpeg fuer Video-Thumbnails und Video-Wiedergabe.</p>
        </div>

        <div class="content">
            <div class="info-box">
                <p><strong>Was ist FFmpeg?</strong> Ein kostenloses Programm zur Video-Verarbeitung.
                PhotoFolder nutzt es, um Vorschaubilder aus Videos zu erstellen und Videos im Browser
                abzuspielen. Ohne FFmpeg funktionieren nur Fotos &mdash; keine Videos.</p>
            </div>

            <h2>Anleitung: FFmpeg installieren</h2>

            <div class="step">
                <div class="step-number">1</div>
                <div class="step-content">
                    <h3>FFmpeg herunterladen</h3>
                    <p>Klicke auf den Button. Auf der Seite unter <strong>&quot;release builds&quot;</strong>
                    die Datei <strong>&quot;ffmpeg-release-essentials.zip&quot;</strong> herunterladen (ca. 80 MB).</p>
                    <a href="https://www.gyan.dev/ffmpeg/builds/" target="_blank" class="download-btn">
                        FFmpeg Download-Seite &#8599;
                    </a>
                </div>
            </div>

            <div class="step">
                <div class="step-number">2</div>
                <div class="step-content">
                    <h3>ZIP-Datei entpacken</h3>
                    <p>Rechtsklick auf die heruntergeladene ZIP-Datei &rarr; <strong>&quot;Alle extrahieren...&quot;</strong>.
                    Es entsteht ein Ordner mit langem Namen (z.B. <em>ffmpeg-7.1-essentials_build</em>).</p>
                </div>
            </div>

            <div class="step">
                <div class="step-number">3</div>
                <div class="step-content">
                    <h3>Ordner &quot;ffmpeg&quot; im Projekt erstellen</h3>
                    <p>Erstelle im PhotoFolder-Ordner einen neuen Ordner mit dem Namen <strong>ffmpeg</strong>:</p>
                    <div class="path-display">$escapedPath</div>
                </div>
            </div>

            <div class="step">
                <div class="step-number">4</div>
                <div class="step-content">
                    <h3>3 Dateien in den ffmpeg-Ordner kopieren</h3>
                    <p>&Ouml;ffne den entpackten Ordner &rarr; gehe in den Unterordner <strong>bin</strong>
                    &rarr; dort liegen 3 Dateien. Kopiere alle 3 in den neuen <strong>ffmpeg</strong>-Ordner:</p>
                    <div class="folder-structure">
PhotoFolder\<br>
&#9500;&#9472;&#9472; start.ps1<br>
&#9500;&#9472;&#9472; config.json<br>
&#9500;&#9472;&#9472; <span class="hl">ffmpeg\</span><br>
&#9474;&nbsp;&nbsp; &#9500;&#9472;&#9472; <span class="hl">ffmpeg.exe</span>&nbsp;&nbsp;&nbsp;&#10004;<br>
&#9474;&nbsp;&nbsp; &#9500;&#9472;&#9472; <span class="hl">ffprobe.exe</span>&nbsp;&nbsp;&#10004;<br>
&#9474;&nbsp;&nbsp; &#9492;&#9472;&#9472; <span class="hl">ffplay.exe</span>&nbsp;&nbsp;&nbsp;&#10004;<br>
&#9500;&#9472;&#9472; Lib\<br>
&#9492;&#9472;&#9472; Templates\
                    </div>
                </div>
            </div>

            <div class="step">
                <div class="step-number">5</div>
                <div class="step-content">
                    <h3>PhotoFolder neu starten</h3>
                    <p>Schliesse das PowerShell-Fenster und starte PhotoFolder erneut
                    (Doppelklick auf <strong>PhotoFolder.bat</strong> oder <strong>start.ps1</strong>).
                    Diese Seite verschwindet automatisch sobald FFmpeg erkannt wird.</p>
                </div>
            </div>

            <div class="warning-box">
                <p><strong>Wichtig:</strong> Die 3 EXE-Dateien muessen <em>direkt</em> im
                <strong>ffmpeg</strong>-Ordner liegen &mdash; nicht in einem weiteren Unterordner!
                Wenn nach dem Entpacken noch ein Ordner wie &quot;ffmpeg-7.1-essentials_build&quot;
                dazwischen liegt, &ouml;ffne diesen und kopiere die Dateien aus dessen
                <strong>bin</strong>-Ordner.</p>
            </div>
        </div>

        <div class="footer">
            <a href="/" class="retry-btn">Erneut versuchen &#8635;</a>
        </div>
    </div>
</body>
</html>
"@

    return $html
}