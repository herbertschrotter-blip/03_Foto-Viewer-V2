<#
.SYNOPSIS
    Kopiert Ordnerstruktur mit anonymisierten Datei- und Ordnernamen

.DESCRIPTION
    Kopiert eine komplette Ordnerstruktur inkl. Dateien in einen Zielordner.
    Alle Namen werden anonymisiert, aber der Aufbau bleibt erhalten:
    - Leerzeichen, Unterstriche, Bindestriche bleiben an gleicher Position
    - Buchstaben werden durch zufällige Buchstaben ersetzt
    - Zahlen werden durch zufällige Zahlen ersetzt
    - Dateiendungen bleiben erhalten
    - Ordner-Tiefe bleibt gleich

.PARAMETER SourcePath
    Quell-Ordner der kopiert werden soll

.PARAMETER DestinationPath
    Ziel-Ordner (wird erstellt falls nicht vorhanden)

.EXAMPLE
    .\Copy-AnonymizedStructure.ps1 -SourcePath "J:\Fotos" -DestinationPath "D:\TestData"

.NOTES
    Autor: Herbert
    Version: 1.0.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms | Out-Null

# Quell-Ordner wählen
$topForm = New-Object System.Windows.Forms.Form
$topForm.TopMost = $true
$topForm.ShowInTaskbar = $false
$topForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized

$srcDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$srcDialog.Description = "QUELLE wählen (wird kopiert)"
$srcDialog.ShowNewFolderButton = $false
$result = $srcDialog.ShowDialog($topForm)
if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    $topForm.Dispose()
    return
}
$SourcePath = $srcDialog.SelectedPath

# Ziel-Ordner wählen
$dstDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dstDialog.Description = "ZIEL wählen (anonymisierte Kopie hier)"
$dstDialog.ShowNewFolderButton = $true
$result = $dstDialog.ShowDialog($topForm)
$topForm.Dispose()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    return
}
$DestinationPath = $dstDialog.SelectedPath

Write-Host "Quelle: $SourcePath" -ForegroundColor Cyan
Write-Host "Ziel:   $DestinationPath" -ForegroundColor Cyan
Write-Host ""

function Get-AnonymizedName {
    <#
    .SYNOPSIS
        Anonymisiert einen Namen (Datei oder Ordner)
    .DESCRIPTION
        Ersetzt Buchstaben durch zufällige Buchstaben, Zahlen durch zufällige Zahlen.
        Sonderzeichen (Leerzeichen, _, -, ., etc.) bleiben erhalten.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    $result = [System.Text.StringBuilder]::new()
    $random = [System.Random]::new()
    
    $lowerLetters = 'abcdefghijklmnopqrstuvwxyz'
    $upperLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $digits = '0123456789'
    
    foreach ($char in $Name.ToCharArray()) {
        if ($char -cmatch '[a-z]') {
            [void]$result.Append($lowerLetters[$random.Next($lowerLetters.Length)])
        }
        elseif ($char -cmatch '[A-Z]') {
            [void]$result.Append($upperLetters[$random.Next($upperLetters.Length)])
        }
        elseif ($char -match '\d') {
            [void]$result.Append($digits[$random.Next($digits.Length)])
        }
        else {
            # Sonderzeichen beibehalten (Leerzeichen, _, -, ., (, ), etc.)
            [void]$result.Append($char)
        }
    }
    
    return $result.ToString()
}

# Ziel erstellen
if (-not (Test-Path -LiteralPath $DestinationPath)) {
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    Write-Host "Ziel-Ordner erstellt: $DestinationPath" -ForegroundColor Green
}

$sourceFull = [System.IO.Path]::GetFullPath($SourcePath)

# Alle Ordner sammeln (inkl. Root)
$allDirs = @([System.IO.DirectoryInfo]::new($sourceFull))
$allDirs += @(Get-ChildItem -LiteralPath $sourceFull -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.thumbs|\\\.temp|\\\.cache|\\\.converted|\\ffmpeg|\\.git' })

Write-Host "Gefunden: $($allDirs.Count) Ordner" -ForegroundColor Cyan

# Mapping: Original-Pfad → Anonymisierter Pfad
$pathMapping = @{}

# Root-Mapping
$pathMapping[$sourceFull] = $DestinationPath

# Ordner anonymisieren und erstellen
$dirCount = 0
foreach ($dir in $allDirs) {
    if ($dir.FullName -eq $sourceFull) { continue }
    
    $dirCount++
    $parentPath = $dir.Parent.FullName
    
    # Anonymisierten Namen generieren
    $anonName = Get-AnonymizedName -Name $dir.Name
    
    # Parent muss bereits gemappt sein
    if ($pathMapping.ContainsKey($parentPath)) {
        $anonFullPath = Join-Path $pathMapping[$parentPath] $anonName
    }
    else {
        Write-Warning "Parent nicht gefunden: $parentPath"
        continue
    }
    
    # Ordner erstellen
    if (-not (Test-Path -LiteralPath $anonFullPath)) {
        New-Item -ItemType Directory -Path $anonFullPath -Force | Out-Null
    }
    
    $pathMapping[$dir.FullName] = $anonFullPath
    
    Write-Progress -Activity "Ordner erstellen" -Status "$dirCount Ordner" -PercentComplete (($dirCount / $allDirs.Count) * 100)
}

Write-Progress -Activity "Ordner erstellen" -Completed
Write-Host "Ordner erstellt: $dirCount" -ForegroundColor Green

# Dateien kopieren mit anonymisierten Namen
$files = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -notmatch '\\\.thumbs|\\\.temp|\\\.cache|\\\.converted|\\ffmpeg|\\.git' })

Write-Host "Gefunden: $($files.Count) Dateien" -ForegroundColor Cyan

$fileCount = 0
foreach ($file in $files) {
    $fileCount++
    
    # Extension beibehalten, nur Name anonymisieren
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $ext = $file.Extension  # z.B. ".jpg"
    
    $anonName = Get-AnonymizedName -Name $nameWithoutExt
    $anonFileName = "${anonName}${ext}"
    
    # Ziel-Ordner aus Mapping
    $dirPath = $file.DirectoryName
    if ($pathMapping.ContainsKey($dirPath)) {
        $destFilePath = Join-Path $pathMapping[$dirPath] $anonFileName
    }
    else {
        Write-Warning "Ordner nicht gemappt: $dirPath"
        continue
    }
    
    # Datei kopieren
    Copy-Item -LiteralPath $file.FullName -Destination $destFilePath -Force
    
    if ($fileCount % 50 -eq 0) {
        Write-Progress -Activity "Dateien kopieren" -Status "$fileCount / $($files.Count)" -PercentComplete (($fileCount / $files.Count) * 100)
    }
}

Write-Progress -Activity "Dateien kopieren" -Completed
Write-Host "`nFertig!" -ForegroundColor Green
Write-Host "  Ordner: $dirCount" -ForegroundColor Cyan
Write-Host "  Dateien: $fileCount" -ForegroundColor Cyan
Write-Host "  Ziel: $DestinationPath" -ForegroundColor Cyan