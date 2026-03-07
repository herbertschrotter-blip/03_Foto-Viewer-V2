<#
.SYNOPSIS
    Routes Handler fuer Flatten & Move Tool

.DESCRIPTION
    Behandelt alle /tools/flatten-* Routes:
    - POST /tools/analyze-flatten   - Ordnerstruktur analysieren + Preview
    - POST /tools/flatten-target    - Ziel-Ordner Dialog oeffnen
    - POST /tools/flatten-execute   - Flatten ausfuehren (Move + Undo-Log)
    - POST /tools/flatten-delete    - Leere Quellordner loeschen
    - POST /tools/flatten-undo      - Letzte Flatten-Aktion rueckgaengig
    - POST /tools/flatten-rescan    - Einzelnen Ordner neu scannen

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0

    Abhaengigkeiten:
    - Lib_FlattenMove.ps1 (Get-FlattenPreview)
    - Lib_Http.ps1 (Send-ResponseText)
    - Lib_Dialogs.ps1 (Show-FolderDialog)
    - Lib_FileSystem.ps1 (Resolve-SafePath)
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Session-Cache fuer Flatten (zwischen Analyse und Ausfuehrung)
$script:FlattenSession = @{
    Preview    = $null
    TargetPath = $null
    Timestamp  = $null
}


function Handle-FlattenRoute {
    <#
    .SYNOPSIS
        Behandelt alle /tools/flatten-* Routes

    .PARAMETER Context
        HttpListenerContext

    .PARAMETER RootPath
        Root-Pfad fuer Medien

    .PARAMETER ScriptRoot
        Projekt-Root

    .PARAMETER Config
        App-Config Hashtable

    .EXAMPLE
        if (Handle-FlattenRoute -Context $ctx -RootPath $root -ScriptRoot $SR -Config $cfg) { continue }

    .OUTPUTS
        [bool] True wenn Route behandelt, False wenn nicht zustaendig
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$ScriptRoot,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $req = $Context.Request
    $res = $Context.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()

    try {

        # ================================================================
        # POST /tools/analyze-flatten
        # Body: { "folderPath": "relative/path" } oder { "folderPath": "." }
        # Scannt Ordnerstruktur und gibt Flatten-Preview zurueck
        # ================================================================
        if ($path -eq "/tools/analyze-flatten" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-FlattenRequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $relativePath = $data.folderPath
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Kein folderPath" } -StatusCode 400
                    return $true
                }

                # Relativen Pfad aufloesen
                $absolutePath = if ($relativePath -eq ".") { $RootPath }
                                else { Join-Path $RootPath $relativePath }

                if (-not (Test-Path -LiteralPath $absolutePath -PathType Container)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Ordner nicht gefunden" } -StatusCode 404
                    return $true
                }

                # Separator aus Body (optional, Default: _)
                $separator = "_"
                if ($data.PSObject.Properties['separator'] -and -not [string]::IsNullOrWhiteSpace($data.separator)) {
                    $separator = [string]$data.separator
                }

                # Extensions aus Config
                $extensions = @($Config.Media.ImageExtensions) + @($Config.Media.VideoExtensions)

                # Preview erstellen
                $preview = Get-FlattenPreview -RootPath $absolutePath -Extensions $extensions -Separator $separator

                # Session speichern
                $script:FlattenSession.Preview = $preview
                $script:FlattenSession.TargetPath = $null
                $script:FlattenSession.Timestamp = (Get-Date).ToString('o')

                # Response aufbauen
                $foldersData = [System.Collections.ArrayList]::new()
                foreach ($f in $preview.Folders) {
                    [void]$foldersData.Add(@{
                        absolutePath       = $f.AbsolutePath
                        relativePath       = $f.RelativePath
                        levels             = @($f.Levels)
                        levelCount         = $f.LevelCount
                        suggestedName      = $f.SuggestedName
                        fileCount          = $f.FileCount
                        files              = @($f.Files)
                        totalSize          = $f.TotalSize
                        totalSizeFormatted = $f.TotalSizeFormatted
                        isRoot             = $f.IsRoot
                    })
                }

                Send-FlattenJsonResponse -Response $res -Data @{
                    success            = $true
                    rootPath           = $preview.RootPath
                    totalFolders       = $preview.TotalFolders
                    totalFiles         = $preview.TotalFiles
                    totalSize          = $preview.TotalSize
                    totalSizeFormatted = $preview.TotalSizeFormatted
                    maxDepth           = $preview.MaxDepth
                    levelNames         = @($preview.LevelNames)
                    separator          = $preview.Separator
                    folders            = @($foldersData)
                } -StatusCode 200
                return $true
            }
            catch {
                Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/flatten-target
        # Oeffnet Ordner-Auswahl-Dialog fuer Ziel-Ordner
        # Body: { } (leer) oder { "initialPath": "..." }
        # ================================================================
        if ($path -eq "/tools/flatten-target" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-FlattenRequestBody -Request $req
                $data = $null
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    $data = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
                }

                $initialDir = $RootPath
                if ($null -ne $data -and $data.PSObject.Properties['initialPath'] -and -not [string]::IsNullOrWhiteSpace($data.initialPath)) {
                    $initialDir = $data.initialPath
                }

                $targetPath = Show-FolderDialog -Title "Ziel-Ordner fuer Flatten waehlen" -InitialDirectory $initialDir

                if (-not $targetPath) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $true; cancelled = $true; targetPath = $null } -StatusCode 200
                    return $true
                }

                if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Ziel-Ordner existiert nicht" } -StatusCode 400
                    return $true
                }

                # Session updaten
                $script:FlattenSession.TargetPath = $targetPath

                Send-FlattenJsonResponse -Response $res -Data @{
                    success    = $true
                    cancelled  = $false
                    targetPath = $targetPath
                } -StatusCode 200
                return $true
            }
            catch {
                Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/flatten-execute
        # Body: {
        #   "targetPath": "D:\Ziel",
        #   "mappings": [
        #     { "sourcePath": "D:\Quelle\sub1\sub2", "targetName": "sub1_sub2" },
        #     ...
        #   ]
        # }
        # ================================================================
        if ($path -eq "/tools/flatten-execute" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-FlattenRequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $targetPath = $data.targetPath
                if ([string]::IsNullOrWhiteSpace($targetPath)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Kein targetPath" } -StatusCode 400
                    return $true
                }

                if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Ziel-Ordner existiert nicht" } -StatusCode 400
                    return $true
                }

                $mappings = $data.mappings
                if ($null -eq $mappings -or @($mappings).Count -eq 0) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Keine mappings" } -StatusCode 400
                    return $true
                }

                $moved = 0
                $failed = 0
                $skipped = 0
                $createdFolders = [System.Collections.ArrayList]::new()
                $undoEntries = [System.Collections.ArrayList]::new()
                $details = [System.Collections.ArrayList]::new()

                foreach ($mapping in @($mappings)) {
                    $sourcePath = [string]$mapping.sourcePath
                    $targetName = [string]$mapping.targetName

                    if ([string]::IsNullOrWhiteSpace($sourcePath) -or [string]::IsNullOrWhiteSpace($targetName)) {
                        $skipped++
                        continue
                    }

                    # Path-Traversal Schutz
                    if ($targetName -match '[/\\]' -or $targetName.Contains('..')) {
                        $failed++
                        [void]$details.Add(@{ source = $sourcePath; target = $targetName; status = "Error"; message = "Ungueltiger Ordnername" })
                        continue
                    }

                    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
                        $failed++
                        [void]$details.Add(@{ source = $sourcePath; target = $targetName; status = "Error"; message = "Quellordner nicht gefunden" })
                        continue
                    }

                    $targetFolder = Join-Path $targetPath $targetName

                    # Ziel-Ordner erstellen
                    if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
                        try {
                            New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
                            [void]$createdFolders.Add($targetName)
                        }
                        catch {
                            $failed++
                            [void]$details.Add(@{ source = $sourcePath; target = $targetName; status = "Error"; message = "Ordner erstellen fehlgeschlagen: $($_.Exception.Message)" })
                            continue
                        }
                    }

                    # Extensions aus Config fuer Dateifilter
                    $mediaExts = @($Config.Media.ImageExtensions) + @($Config.Media.VideoExtensions)
                    $lowerExts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($ext in $mediaExts) { [void]$lowerExts.Add($ext.ToLowerInvariant()) }

                    # Medien-Dateien aus Quellordner (NICHT rekursiv)
                    $sourceFiles = Get-ChildItem -LiteralPath $sourcePath -File -ErrorAction SilentlyContinue
                    if ($null -eq $sourceFiles) { continue }

                    foreach ($file in @($sourceFiles)) {
                        if (-not $lowerExts.Contains($file.Extension.ToLowerInvariant())) { continue }

                        $destPath = Join-Path $targetFolder $file.Name

                        # Namenskollision
                        if (Test-Path -LiteralPath $destPath) {
                            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                            $ext = $file.Extension
                            $counter = 1
                            do {
                                $destPath = Join-Path $targetFolder "${baseName}_${counter}${ext}"
                                $counter++
                            } while (Test-Path -LiteralPath $destPath)
                        }

                        try {
                            # Thumbnail-Hash VOR Move berechnen
                            $oldThumbsDir = Join-Path $sourcePath ".thumbs"
                            $oldThumbHash = $null
                            if (Test-Path -LiteralPath $oldThumbsDir -PathType Container) {
                                try {
                                    $hashInput = "$($file.FullName)-$($file.LastWriteTimeUtc.Ticks)"
                                    $oldThumbHash = [System.BitConverter]::ToString(
                                        [System.Security.Cryptography.MD5]::Create().ComputeHash(
                                            [System.Text.Encoding]::UTF8.GetBytes($hashInput)
                                        )
                                    ).Replace('-', '').ToLowerInvariant()
                                }
                                catch { }
                            }

                            Move-Item -LiteralPath $file.FullName -Destination $destPath -ErrorAction Stop

                            # Thumbnail in neuen .thumbs/ kopieren
                            if ($null -ne $oldThumbHash) {
                                $oldThumbPath = Join-Path $oldThumbsDir "$oldThumbHash.jpg"
                                if (Test-Path -LiteralPath $oldThumbPath -PathType Leaf) {
                                    $newThumbsDir = Join-Path $targetFolder ".thumbs"
                                    if (-not (Test-Path -LiteralPath $newThumbsDir -PathType Container)) {
                                        New-Item -ItemType Directory -Path $newThumbsDir -Force | Out-Null
                                        $tf = Get-Item -LiteralPath $newThumbsDir -Force
                                        $tf.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
                                    }
                                    try {
                                        $newFi = [System.IO.FileInfo]::new($destPath)
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

                            $moved++
                            [void]$undoEntries.Add(@{
                                File = $file.Name
                                From = $file.FullName
                                To   = $destPath
                            })
                        }
                        catch {
                            $failed++
                            [void]$details.Add(@{
                                source  = $sourcePath
                                target  = $targetName
                                file    = $file.Name
                                status  = "Error"
                                message = $_.Exception.Message
                            })
                        }
                    }
                }

                # Undo-Log speichern
                $undoSaved = $false
                if (@($undoEntries).Count -gt 0) {
                    $historyPath = Join-Path $ScriptRoot "_flatten-undo.json"

                    $newEntry = @{
                        Id             = [guid]::NewGuid().ToString('N').Substring(0, 8)
                        Timestamp      = (Get-Date).ToString('o')
                        TargetPath     = $targetPath
                        MovedCount     = $moved
                        CreatedFolders = @($createdFolders)
                        Entries        = @($undoEntries)
                        Undone         = $false
                    }

                    try {
                        $history = @()
                        if (Test-Path -LiteralPath $historyPath) {
                            $json = Get-Content -LiteralPath $historyPath -Raw -Encoding UTF8 -ErrorAction Stop
                            $history = @($json | ConvertFrom-Json -ErrorAction Stop)
                        }
                        $history = @(@($newEntry) + @($history) | Select-Object -First 30)
                        $history | ConvertTo-Json -Depth 10 |
                            Out-File -FilePath $historyPath -Encoding UTF8 -Force
                        $undoSaved = $true
                    }
                    catch {
                        Write-Warning "Flatten Undo-History speichern fehlgeschlagen: $($_.Exception.Message)"
                    }
                }

                # Re-Scan State (wenn $script:State verfuegbar)
                if ($moved -gt 0 -and $null -ne $script:State) {
                    try {
                        $mediaExts = $Config.Media.ImageExtensions + $Config.Media.VideoExtensions
                        $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExts -ScriptRoot $ScriptRoot)
                        Save-State -State $script:State
                        Write-Verbose "Re-Scan nach Flatten: $(@($script:State.Folders).Count) Ordner"
                    }
                    catch {
                        Write-Warning "Re-Scan nach Flatten fehlgeschlagen: $($_.Exception.Message)"
                    }
                }

                Send-FlattenJsonResponse -Response $res -Data @{
                    success        = $true
                    moved          = $moved
                    failed         = $failed
                    skipped        = $skipped
                    createdFolders = @($createdFolders)
                    undoAvailable  = $undoSaved
                    details        = @($details)
                } -StatusCode 200
                return $true
            }
            catch {
                Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/flatten-delete
        # Body: { "folderPaths": ["D:\Quelle\sub1\sub2", ...] }
        # Loescht leere Quellordner (nur wenn keine Medien mehr drin)
        # ================================================================
        if ($path -eq "/tools/flatten-delete" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-FlattenRequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $folderPaths = @($data.folderPaths)
                if (@($folderPaths).Count -eq 0) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Keine folderPaths" } -StatusCode 400
                    return $true
                }

                $deleted = [System.Collections.ArrayList]::new()
                $notDeleted = [System.Collections.ArrayList]::new()

                # Extensions fuer Medien-Check
                $mediaExts = @($Config.Media.ImageExtensions) + @($Config.Media.VideoExtensions)
                $lowerExts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($ext in $mediaExts) { [void]$lowerExts.Add($ext.ToLowerInvariant()) }

                # Von tiefstem Pfad zuerst loeschen (damit Eltern danach leer sind)
                $sortedPaths = @($folderPaths | Sort-Object { @($_ -split '[/\\]').Count } -Descending)

                foreach ($folderPath in $sortedPaths) {
                    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                        [void]$deleted.Add($folderPath)
                        continue
                    }

                    # Pruefen ob noch Medien drin (rekursiv)
                    $hasMedia = $false
                    $remainingFiles = Get-ChildItem -LiteralPath $folderPath -File -Recurse -ErrorAction SilentlyContinue
                    if ($null -ne $remainingFiles) {
                        foreach ($f in @($remainingFiles)) {
                            if ($lowerExts.Contains($f.Extension.ToLowerInvariant())) {
                                $hasMedia = $true
                                break
                            }
                        }
                    }

                    if ($hasMedia) {
                        [void]$notDeleted.Add(@{ path = $folderPath; reason = "Enthaelt noch Medien-Dateien" })
                        continue
                    }

                    try {
                        Remove-Item -LiteralPath $folderPath -Recurse -Force -ErrorAction Stop
                        [void]$deleted.Add($folderPath)
                    }
                    catch {
                        [void]$notDeleted.Add(@{ path = $folderPath; reason = $_.Exception.Message })
                    }
                }

                # Re-Scan State
                if (@($deleted).Count -gt 0 -and $null -ne $script:State) {
                    try {
                        $mediaExtsAll = $Config.Media.ImageExtensions + $Config.Media.VideoExtensions
                        $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExtsAll -ScriptRoot $ScriptRoot)
                        Save-State -State $script:State
                    }
                    catch {
                        Write-Warning "Re-Scan nach Delete fehlgeschlagen: $($_.Exception.Message)"
                    }
                }

                Send-FlattenJsonResponse -Response $res -Data @{
                    success    = $true
                    deleted    = @($deleted)
                    notDeleted = @($notDeleted)
                } -StatusCode 200
                return $true
            }
            catch {
                Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/flatten-undo
        # Body: { "undoId": "abc12345" } (optional, sonst letzter aktiver)
        # ================================================================
        if ($path -eq "/tools/flatten-undo" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-FlattenRequestBody -Request $req
                $data = $null
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    $data = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
                }

                $undoId = $null
                if ($null -ne $data -and $data.PSObject.Properties['undoId'] -and -not [string]::IsNullOrWhiteSpace($data.undoId)) {
                    $undoId = [string]$data.undoId
                }

                $historyPath = Join-Path $ScriptRoot "_flatten-undo.json"
                if (-not (Test-Path -LiteralPath $historyPath)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Keine Flatten Undo-History" } -StatusCode 400
                    return $true
                }

                $json = Get-Content -LiteralPath $historyPath -Raw -Encoding UTF8 -ErrorAction Stop
                $history = @($json | ConvertFrom-Json -ErrorAction Stop)

                # Eintrag finden
                $undoEntry = $null
                $undoIndex = -1
                for ($i = 0; $i -lt @($history).Count; $i++) {
                    $e = $history[$i]
                    if ($null -ne $undoId) {
                        if ($e.Id -eq $undoId -and -not $e.Undone) { $undoEntry = $e; $undoIndex = $i; break }
                    }
                    else {
                        if (-not $e.Undone) { $undoEntry = $e; $undoIndex = $i; break }
                    }
                }

                if ($null -eq $undoEntry) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Kein aktiver Undo-Eintrag" } -StatusCode 400
                    return $true
                }

                $restored = 0
                $failedUndo = 0

                foreach ($entry in $undoEntry.Entries) {
                    if (-not (Test-Path -LiteralPath $entry.To -PathType Leaf)) {
                        $failedUndo++
                        continue
                    }
                    if (Test-Path -LiteralPath $entry.From) {
                        $failedUndo++
                        continue
                    }
                    # Quell-Ordner sicherstellen
                    $fromDir = Split-Path -Parent $entry.From
                    if (-not (Test-Path -LiteralPath $fromDir -PathType Container)) {
                        try {
                            New-Item -ItemType Directory -Path $fromDir -Force | Out-Null
                        }
                        catch { $failedUndo++; continue }
                    }
                    try {
                        Move-Item -LiteralPath $entry.To -Destination $entry.From -ErrorAction Stop
                        $restored++
                    }
                    catch { $failedUndo++ }
                }

                # Leere erstellte Ordner entfernen
                $removedFolders = [System.Collections.ArrayList]::new()
                if ($null -ne $undoEntry.CreatedFolders -and $null -ne $undoEntry.TargetPath) {
                    foreach ($folderName in @($undoEntry.CreatedFolders)) {
                        $folderFull = Join-Path $undoEntry.TargetPath $folderName
                        if (Test-Path -LiteralPath $folderFull -PathType Container) {
                            $remaining = @(Get-ChildItem -LiteralPath $folderFull -Force -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -ne '.thumbs' })
                            if (@($remaining).Count -eq 0) {
                                try {
                                    Remove-Item -LiteralPath $folderFull -Recurse -Force
                                    [void]$removedFolders.Add($folderName)
                                }
                                catch { }
                            }
                        }
                    }
                }

                # Eintrag als Undone markieren
                $history[$undoIndex].Undone = $true
                try {
                    $history | ConvertTo-Json -Depth 10 |
                        Out-File -FilePath $historyPath -Encoding UTF8 -Force
                }
                catch { Write-Warning "Flatten History-Update fehlgeschlagen" }

                # Re-Scan State
                if ($restored -gt 0 -and $null -ne $script:State) {
                    try {
                        $mediaExts = $Config.Media.ImageExtensions + $Config.Media.VideoExtensions
                        $script:State.Folders = @(Get-MediaFolders -RootPath $script:State.RootPath -Extensions $mediaExts -ScriptRoot $ScriptRoot)
                        Save-State -State $script:State
                    }
                    catch { Write-Warning "Re-Scan nach Undo fehlgeschlagen" }
                }

                Send-FlattenJsonResponse -Response $res -Data @{
                    success        = ($failedUndo -eq 0)
                    restored       = $restored
                    failed         = $failedUndo
                    removedFolders = @($removedFolders)
                } -StatusCode 200
                return $true
            }
            catch {
                Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/flatten-rescan
        # Body: { "folderPath": "absolute/path" }
        # Scannt einzelnen Ordner neu und gibt Dateien zurueck
        # ================================================================
        if ($path -eq "/tools/flatten-rescan" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-FlattenRequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $folderPath = $data.folderPath
                if ([string]::IsNullOrWhiteSpace($folderPath) -or -not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                    Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = "Ordner nicht gefunden" } -StatusCode 404
                    return $true
                }

                $mediaExts = @($Config.Media.ImageExtensions) + @($Config.Media.VideoExtensions)
                $lowerExts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($ext in $mediaExts) { [void]$lowerExts.Add($ext.ToLowerInvariant()) }

                $dirFiles = Get-ChildItem -LiteralPath $folderPath -File -ErrorAction SilentlyContinue
                $files = [System.Collections.ArrayList]::new()
                $totalSize = [long]0

                if ($null -ne $dirFiles) {
                    foreach ($f in @($dirFiles)) {
                        if ($lowerExts.Contains($f.Extension.ToLowerInvariant())) {
                            [void]$files.Add($f.Name)
                            $totalSize += $f.Length
                        }
                    }
                }

                Send-FlattenJsonResponse -Response $res -Data @{
                    success            = $true
                    folderPath         = $folderPath
                    fileCount          = @($files).Count
                    files              = @($files | Sort-Object)
                    totalSize          = $totalSize
                    totalSizeFormatted = Format-FlattenSize -Bytes $totalSize
                } -StatusCode 200
                return $true
            }
            catch {
                Send-FlattenJsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # Nicht zustaendig
        return $false

    }
    catch {
        Write-Error "Flatten Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}


# ============================================================================
# INTERNE HELPER FUER ROUTES
# ============================================================================

function Read-FlattenRequestBody {
    <# Liest POST-Body als String #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerRequest]$Request
    )

    $reader = [System.IO.StreamReader]::new($Request.InputStream, [System.Text.Encoding]::UTF8)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
}


function Send-FlattenJsonResponse {
    <# Sendet JSON-Response mit Status-Code #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory)]
        [hashtable]$Data,

        [Parameter()]
        [int]$StatusCode = 200
    )

    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    Send-ResponseText -Response $Response -Text $json -StatusCode $StatusCode -ContentType "application/json; charset=utf-8"
}