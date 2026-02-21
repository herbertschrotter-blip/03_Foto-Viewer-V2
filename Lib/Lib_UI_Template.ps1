<#
.SYNOPSIS
    UI Template Loader für Foto-Viewer V2

.DESCRIPTION
    Lädt HTML/CSS/JS Templates aus separaten Dateien und kombiniert sie
    zu einer vollständigen HTML-Response mit Platzhalter-Ersetzung.
    
    Templates:
    - index.html: HTML-Struktur mit Placeholders
    - styles.css: Komplettes CSS
    - app.js: Komplettes JavaScript

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-IndexHTML {
    <#
    .SYNOPSIS
        Erstellt die vollständige HTML-Seite aus Templates
    
    .DESCRIPTION
        Lädt Templates aus Templates/ Ordner, ersetzt Platzhalter
        und gibt fertiges HTML zurück.
        
        Lädt automatisch:
        - index.html (HTML-Struktur)
        - styles.css (eingebettet in <style>)
        - app.js (eingebettet in <script>)
    
    .PARAMETER RootPath
        Aktueller Root-Pfad für Medien
    
    .PARAMETER FolderCards
        HTML für Folder-Cards (bereits generiert)
    
    .PARAMETER Config
        Config-Objekt mit Settings
    
    .EXAMPLE
        $html = Get-IndexHTML -RootPath "C:\Photos" -FolderCards $cards -Config $config
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        
        [Parameter(Mandatory)]
        [string]$FolderCards,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    try {
        # Template-Pfade
        $templateRoot = Join-Path $PSScriptRoot "..\Templates"
        $htmlPath = Join-Path $templateRoot "index.html"
        $cssPath = Join-Path $templateRoot "styles.css"
        $jsPath = Join-Path $templateRoot "app.js"
        
        # Templates laden
        Write-Verbose "Lade Templates aus: $templateRoot"
        
        if (-not (Test-Path $htmlPath)) {
            throw "Template nicht gefunden: $htmlPath"
        }
        if (-not (Test-Path $cssPath)) {
            throw "Template nicht gefunden: $cssPath"
        }
        if (-not (Test-Path $jsPath)) {
            throw "Template nicht gefunden: $jsPath"
        }
        
        $htmlTemplate = Get-Content -Path $htmlPath -Raw -Encoding UTF8
        $cssContent = Get-Content -Path $cssPath -Raw -Encoding UTF8
        $jsContent = Get-Content -Path $jsPath -Raw -Encoding UTF8
        
        # Config-Werte extrahieren
        $thumbnailSize = $Config.UI.ThumbnailSize
        $theme = $Config.UI.Theme
        
        # Platzhalter ersetzen
        $html = $htmlTemplate
        
        # 1. CSS einbetten (als <style> Tag)
        $cssEmbedded = "<style>`n$cssContent`n</style>"
        $html = $html -replace '\{\{STYLES\}\}', $cssEmbedded
        
        # 2. JavaScript einbetten (als <script> Tag)
        $jsEmbedded = "<script>`n$jsContent`n</script>"
        $html = $html -replace '\{\{SCRIPTS\}\}', $jsEmbedded
        
        # 3. Root-Pfad
        $html = $html -replace '\{\{ROOT_PATH\}\}', [System.Web.HttpUtility]::HtmlEncode($RootPath)
        
        # 4. Folder-Cards
        $html = $html -replace '\{\{FOLDER_CARDS\}\}', $FolderCards
        
        # 5. Config-Werte
        $html = $html -replace '\{\{THUMBNAIL_SIZE\}\}', $thumbnailSize
        $html = $html -replace '\{\{THEME\}\}', $theme
        
        Write-Verbose "Template erfolgreich generiert ($(($html.Length / 1KB).ToString('F2')) KB)"
        
        return $html
    }
    catch {
        Write-Error "Fehler beim Generieren des Templates: $_"
        throw
    }
}
