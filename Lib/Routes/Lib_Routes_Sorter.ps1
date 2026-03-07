<#
.SYNOPSIS
    Routes Handler für File Sorter Tool

.DESCRIPTION
    Behandelt alle /tools/sorter/* und verwandte Routes:
    - /tools/analyze-files      - Dateien analysieren + gruppieren
    - /tools/sort-files         - Dateien in Unterordner verschieben
    - /tools/export-filenames   - Dateinamen in Log exportieren
    - /tools/undo-sort          - Letzte Sortierung rückgängig
    - /tools/check-undo         - Prüft ob Undo verfügbar
    - /tools/sorter-patterns    - Pattern-Liste laden
    - /tools/sorter-patterns/add    - Neues Pattern
    - /tools/sorter-patterns/remove - Pattern entfernen
    - /tools/move-file-group    - Datei umgruppieren (in-memory via Session)
    - /tools/merge-groups       - Gruppen zusammenführen
    - /tools/split-group        - Gruppe aufteilen

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0

    Abhängigkeiten:
    - Lib_FileSorter.ps1 (Get-FileGroups, Invoke-FileSorting, etc.)
    - Lib_Http.ps1 (Send-ResponseText)
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Session-Cache fuer Gruppen (zwischen Analyse und Sortierung)
$script:SorterSession = @{
    Groups     = $null
    FolderPath = $null
    Timestamp  = $null
    MultiLevel = $false
    SubLevels  = $null
}


function Handle-SorterRoute {
    <#
    .SYNOPSIS
        Behandelt alle /tools/sorter-relevanten Routes

    .PARAMETER Context
        HttpListenerContext

    .PARAMETER RootPath
        Root-Pfad für Medien

    .PARAMETER ScriptRoot
        Projekt-Root (für Pattern-JSON, dot-sourcing)

    .PARAMETER Config
        App-Config Hashtable

    .EXAMPLE
        if (Handle-SorterRoute -Context $ctx -RootPath $root -ScriptRoot $SR -Config $cfg) { continue }

    .OUTPUTS
        [bool] True wenn Route behandelt, False wenn nicht zuständig
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
        # POST /tools/analyze-files
        # Body: { "folderPath": "relative/path" } oder { "folderPath": "." }
        # ================================================================
        if ($path -eq "/tools/analyze-files" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $relativePath = $data.folderPath
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Kein folderPath" } -StatusCode 400
                    return $true
                }

                # Relativen Pfad auflösen
                $absolutePath = if ($relativePath -eq ".") { $RootPath }
                                else { Join-Path $RootPath $relativePath }

                if (-not (Test-Path -LiteralPath $absolutePath -PathType Container)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Ordner nicht gefunden" } -StatusCode 404
                    return $true
                }

                # Extensions aus Body (optional)
                $extensions = $null
                if ($data.PSObject.Properties['extensions'] -and $data.extensions) {
                    $extensions = @($data.extensions)
                }

                if (-not $extensions) {
                    $extensions = @($Config.Media.ImageExtensions) + @($Config.Media.VideoExtensions)
                }
                $groups = Get-FileGroups -FolderPath $absolutePath -ScriptRoot $ScriptRoot -Extensions $extensions

                # Multi-Level: Sub-Levels aus Body (optional)
                $isMultiLevel = $false
                if ($data.PSObject.Properties['subLevels'] -and $data.subLevels -and $data.subLevels.Count -gt 0) {
                    $subLevels = @($data.subLevels | ForEach-Object {
                        @{
                            Regex        = [string]$_.regex
                            GroupCapture = [int]($_.groupCapture ?? 1)
                            Name         = [string]($_.name ?? "Ebene")
                        }
                    })
                    $multiGroups = Get-MultiLevelGroups -Groups $groups -SubLevels $subLevels


                    # Dateigroessen-Lookup einmal aufbauen (Performance!)
                    $fileSizeLookup = @{}
                    foreach ($f in (Get-ChildItem -LiteralPath $absolutePath -File -ErrorAction SilentlyContinue)) {
                        $fileSizeLookup[$f.Name] = $f.Length
                    }

                    # Zu flachen Gruppen aufloesen (p105-r0, p105-r1, etc.)
                    $flatGroups = [System.Collections.ArrayList]::new()
                    foreach ($mg in $multiGroups) {
                        if ($mg.IsMultiLevel -and $mg.SubGroups.Count -gt 0) {
                            $flatList = Resolve-FlatSubGroups -SubGroups $mg.SubGroups -BaseName $mg.Prefix -Separator "-"
                            foreach ($flat in $flatList) {
                                $flatSize = [long]0
                                foreach ($fn in $flat.Files) {
                                    if ($fileSizeLookup.ContainsKey($fn)) {
                                        $flatSize += $fileSizeLookup[$fn]
                                    }
                                }

                                [void]$flatGroups.Add([PSCustomObject]@{
                                    Prefix             = $flat.FolderName
                                    PatternName        = $mg.PatternName
                                    SuggestedFolder    = $flat.FolderName
                                    FileCount          = $flat.Files.Count
                                    TotalSize          = $flatSize
                                    TotalSizeFormatted = Format-FileSize -Bytes $flatSize
                                    PreviewFiles       = @($flat.Files | Select-Object -First 5)
                                    Files              = @($flat.Files)
                                })
                            }
                        }
                        else {
                            # Keine SubGroups (z.B. _unsorted) -> direkt uebernehmen
                            [void]$flatGroups.Add($mg)
                        }
                    }
                    $groups = @($flatGroups)
                    $isMultiLevel = $true
                }

                # Session speichern (fuer spaetere Manipulation + Sortierung)
                $script:SorterSession.Groups = $groups
                $script:SorterSession.FolderPath = $absolutePath
                $script:SorterSession.Timestamp = (Get-Date).ToString('o')
                $script:SorterSession.MultiLevel = $isMultiLevel
                $script:SorterSession.SubLevels = $null

                # Pattern-Info für Frontend
                $patternSummary = @{}
                foreach ($g in $groups) {
                    if (-not $patternSummary.ContainsKey($g.PatternName)) {
                        $patternSummary[$g.PatternName] = @{ Groups = 0; Files = 0 }
                    }
                    $patternSummary[$g.PatternName].Groups++
                    $patternSummary[$g.PatternName].Files += $g.FileCount
                }

                $responseData = @{
                    success        = $true
                    folderPath     = $absolutePath
                    totalGroups    = $groups.Count
                    totalFiles     = ($groups | Measure-Object -Property FileCount -Sum).Sum
                    multiLevel     = $isMultiLevel
                    patternSummary = $patternSummary
                    groups         = @($groups | ForEach-Object {
                        @{
                            prefix             = $_.Prefix
                            patternName        = $_.PatternName
                            suggestedFolder    = $_.SuggestedFolder
                            fileCount          = $_.FileCount
                            totalSize          = $_.TotalSize
                            totalSizeFormatted = $_.TotalSizeFormatted
                            previewFiles       = $_.PreviewFiles
                            files              = $_.Files
                        }
                    })
                }

                Send-JsonResponse -Response $res -Data $responseData -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/sort-files
        # Body: { "mappings": { "p006": "Set_006", "p020": "Set_020" } }
        # ================================================================
        if ($path -eq "/tools/sort-files" -and $req.HttpMethod -eq "POST") {
            try {
                if (-not $script:SorterSession.Groups -or -not $script:SorterSession.FolderPath) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Keine aktive Analyse-Session. Zuerst /tools/analyze-files aufrufen." } -StatusCode 400
                    return $true
                }

                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                if (-not $data.mappings) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Keine mappings angegeben" } -StatusCode 400
                    return $true
                }

                # PSObject in Hashtable konvertieren
                $mappings = @{}
                $data.mappings.PSObject.Properties | ForEach-Object {
                    $mappings[$_.Name] = $_.Value
                }

                # Client-Gruppen verwenden (enthalten manuelle Umgruppierungen)
                $groupsToSort = $script:SorterSession.Groups
                if ($data.PSObject.Properties['groups'] -and $data.groups -and $data.groups.Count -gt 0) {
                    $groupsToSort = @($data.groups | ForEach-Object {
                        [PSCustomObject]@{
                            Prefix             = [string]$_.prefix
                            PatternName        = [string]$_.patternName
                            SuggestedFolder    = [string]$_.suggestedFolder
                            FileCount          = [int]$_.fileCount
                            TotalSize          = [long]($_.totalSize ?? 0)
                            TotalSizeFormatted = [string]($_.totalSizeFormatted ?? '?')
                            PreviewFiles       = @($_.previewFiles ?? @())
                            Files              = @($_.files)
                        }
                    })
                    Write-Verbose "Verwende Client-Gruppen: $($groupsToSort.Count) Gruppen"
                }

                # Immer einstufig sortieren (Multi-Level ist bereits zu flachen Gruppen aufgeloest)
                $result = Invoke-FileSorting `
                    -FolderPath $script:SorterSession.FolderPath `
                    -GroupMappings $mappings `
                    -Groups $groupsToSort

                # Session leeren nach Sortierung
                $script:SorterSession.Groups = $null

                # Re-Scan: Ordner-Struktur aktualisieren
                if ($result.Moved -gt 0 -and $script:State) {
                    try {
                        $mediaExts = $Config.Media.ImageExtensions + $Config.Media.VideoExtensions
                        $script:State.Folders = @(Get-MediaFolders -RootPath $RootPath -Extensions $mediaExts -ScriptRoot $ScriptRoot)
                        Save-State -State $script:State
                        Write-Verbose "Re-Scan nach Sortierung: $($script:State.Folders.Count) Ordner"
                    }
                    catch {
                        Write-Warning "Re-Scan fehlgeschlagen: $($_.Exception.Message)"
                    }
                }

                Send-JsonResponse -Response $res -Data @{
                    success        = $true
                    moved          = $result.Moved
                    failed         = $result.Failed
                    skipped        = $result.Skipped
                    createdFolders = $result.CreatedFolders
                    undoAvailable  = ($null -ne $result.UndoLogPath)
                    details        = @($result.Details | ForEach-Object {
                        @{ file = $_.File; prefix = $_.Prefix; target = $_.Target; status = $_.Status; message = $_.Message }
                    })
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/export-filenames
        # Body: { "folderPath": "relative/path" }
        # ================================================================
        if ($path -eq "/tools/export-filenames" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $relativePath = $data.folderPath
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Kein folderPath" } -StatusCode 400
                    return $true
                }

                $absolutePath = if ($relativePath -eq ".") { $RootPath }
                                else { Join-Path $RootPath $relativePath }

                if (-not (Test-Path -LiteralPath $absolutePath -PathType Container)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Ordner nicht gefunden" } -StatusCode 404
                    return $true
                }

                $extensions = $null
                if ($data.PSObject.Properties['extensions'] -and $data.extensions) {
                    $extensions = @($data.extensions)
                }

                if (-not $extensions) {
                    $extensions = @($Config.Media.ImageExtensions) + @($Config.Media.VideoExtensions)
                }
                $logPath = Export-FileNames -FolderPath $absolutePath -Extensions $extensions

                Send-JsonResponse -Response $res -Data @{
                    success = $true
                    logPath = $logPath
                    message = "Dateinamen exportiert nach _filenames.log"
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/undo-sort
        # Body: { "folderPath": "relative/path" }
        # ================================================================
        if ($path -eq "/tools/undo-sort" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $relativePath = $data.folderPath
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Kein folderPath" } -StatusCode 400
                    return $true
                }

                $absolutePath = if ($relativePath -eq ".") { $RootPath }
                                else { Join-Path $RootPath $relativePath }

                $result = Undo-FileSorting -FolderPath $absolutePath

                Send-JsonResponse -Response $res -Data @{
                    success        = $result.Success
                    restored       = $result.Restored
                    failed         = $result.Failed
                    removedFolders = $result.RemovedFolders
                    error          = $result.Error
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # GET /tools/check-undo?folderPath=relative/path
        # ================================================================
        if ($path -eq "/tools/check-undo" -and $req.HttpMethod -eq "GET") {
            try {
                $relativePath = $req.QueryString["folderPath"]
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Kein folderPath" } -StatusCode 400
                    return $true
                }

                $absolutePath = if ($relativePath -eq ".") { $RootPath }
                                else { Join-Path $RootPath $relativePath }

                $undoPath = Join-Path $absolutePath "_undo-sort.json"
                $hasUndo = Test-Path -LiteralPath $undoPath

                $undoInfo = $null
                if ($hasUndo) {
                    try {
                        $undoData = Get-Content -LiteralPath $undoPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $undoInfo = @{
                            timestamp  = $undoData.Timestamp
                            movedCount = $undoData.MovedCount
                        }
                    }
                    catch { }
                }

                Send-JsonResponse -Response $res -Data @{
                    success   = $true
                    hasUndo   = $hasUndo
                    undoInfo  = $undoInfo
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # GET /tools/sorter-patterns
        # ================================================================
        if ($path -eq "/tools/sorter-patterns" -and $req.HttpMethod -eq "GET") {
            try {
                $patterns = Get-SorterPatterns -ScriptRoot $ScriptRoot

                Send-JsonResponse -Response $res -Data @{
                    success  = $true
                    patterns = @($patterns | ForEach-Object {
                        @{
                            name = $_.Name; regex = $_.Regex; groupCapture = $_.GroupCapture
                            priority = $_.Priority; enabled = $_.Enabled; builtIn = $_.BuiltIn
                            description = $_.Description
                        }
                    })
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/sorter-patterns/add
        # Body: { "name": "...", "regex": "...", "groupCapture": 1, "priority": 50, "description": "..." }
        # ================================================================
        if ($path -eq "/tools/sorter-patterns/add" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                if ([string]::IsNullOrWhiteSpace($data.name) -or [string]::IsNullOrWhiteSpace($data.regex)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "name und regex sind Pflicht" } -StatusCode 400
                    return $true
                }

                $splat = @{
                    Name        = $data.name
                    Regex       = $data.regex
                    ScriptRoot  = $ScriptRoot
                }
                if ($null -ne $data.groupCapture) { $splat.GroupCapture = [int]$data.groupCapture }
                if ($null -ne $data.priority)     { $splat.Priority = [int]$data.priority }
                if ($data.description)             { $splat.Description = $data.description }

                $newPattern = Add-SorterPattern @splat

                Send-JsonResponse -Response $res -Data @{
                    success = $true
                    pattern = @{
                        name = $newPattern.Name; regex = $newPattern.Regex
                        groupCapture = $newPattern.GroupCapture; priority = $newPattern.Priority
                        enabled = $newPattern.Enabled; builtIn = $newPattern.BuiltIn
                        description = $newPattern.Description
                    }
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/sorter-patterns/remove
        # Body: { "name": "PatternName" }
        # ================================================================
        if ($path -eq "/tools/sorter-patterns/remove" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                if ([string]::IsNullOrWhiteSpace($data.name)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "name ist Pflicht" } -StatusCode 400
                    return $true
                }

                $removed = Remove-SorterPattern -Name $data.name -ScriptRoot $ScriptRoot

                Send-JsonResponse -Response $res -Data @{
                    success = $removed
                    message = if ($removed) { "Pattern '$($data.name)' entfernt/deaktiviert" } else { "Pattern nicht gefunden" }
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/sorter-patterns/toggle
        # Body: { "name": "PatternName", "enabled": true/false }
        # ================================================================
        if ($path -eq "/tools/sorter-patterns/toggle" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                if ([string]::IsNullOrWhiteSpace($data.name)) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "name ist Pflicht" } -StatusCode 400
                    return $true
                }

                $patterns = @(Get-SorterPatterns -ScriptRoot $ScriptRoot)
                $target = $patterns | Where-Object { $_.Name -eq $data.name }

                if (-not $target) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Pattern '$($data.name)' nicht gefunden" } -StatusCode 404
                    return $true
                }

                $target.Enabled = [bool]$data.enabled
                Save-SorterPatterns -Patterns $patterns -ScriptRoot $ScriptRoot

                Send-JsonResponse -Response $res -Data @{
                    success = $true
                    name    = $target.Name
                    enabled = $target.Enabled
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # GET /tools/sorter-sublevels
        # ================================================================
        if ($path -eq "/tools/sorter-sublevels" -and $req.HttpMethod -eq "GET") {
            try {
                $subLevels = Get-SorterSubLevels -ScriptRoot $ScriptRoot

                Send-JsonResponse -Response $res -Data @{
                    success   = $true
                    subLevels = @($subLevels | ForEach-Object {
                        @{
                            name         = $_.Name
                            regex        = $_.Regex
                            groupCapture = $_.GroupCapture
                            enabled      = $_.Enabled
                        }
                    })
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/sorter-sublevels/save
        # Body: { "subLevels": [ { "name": "...", "regex": "...", "groupCapture": 1, "enabled": true } ] }
        # ================================================================
        if ($path -eq "/tools/sorter-sublevels/save" -and $req.HttpMethod -eq "POST") {
            try {
                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                if (-not $data.subLevels) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Keine subLevels angegeben" } -StatusCode 400
                    return $true
                }

                $subLevelObjects = @($data.subLevels | ForEach-Object {
                    [PSCustomObject]@{
                        Name         = [string]$_.name
                        Regex        = [string]$_.regex
                        GroupCapture = [int]($_.groupCapture ?? 1)
                        Enabled      = [bool]($_.enabled ?? $true)
                    }
                })

                Save-SorterSubLevels -SubLevels $subLevelObjects -ScriptRoot $ScriptRoot

                Send-JsonResponse -Response $res -Data @{
                    success = $true
                    count   = $subLevelObjects.Count
                    message = "$($subLevelObjects.Count) Sub-Levels gespeichert"
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/move-file-group
        # Body: { "fileName": "test.jpg", "targetPrefix": "p020" }
        # ================================================================
        if ($path -eq "/tools/move-file-group" -and $req.HttpMethod -eq "POST") {
            try {
                if (-not $script:SorterSession.Groups) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Keine aktive Session" } -StatusCode 400
                    return $true
                }

                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $script:SorterSession.Groups = Move-FileBetweenGroups `
                    -Groups $script:SorterSession.Groups `
                    -FileName $data.fileName `
                    -TargetPrefix $data.targetPrefix

                Send-JsonResponse -Response $res -Data @{
                    success     = $true
                    totalGroups = $script:SorterSession.Groups.Count
                    groups      = @($script:SorterSession.Groups | ForEach-Object {
                        @{ prefix = $_.Prefix; fileCount = $_.FileCount; files = $_.Files }
                    })
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/merge-groups
        # Body: { "sourcePrefix": "p006", "targetPrefix": "p020" }
        # ================================================================
        if ($path -eq "/tools/merge-groups" -and $req.HttpMethod -eq "POST") {
            try {
                if (-not $script:SorterSession.Groups) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Keine aktive Session" } -StatusCode 400
                    return $true
                }

                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $script:SorterSession.Groups = Merge-FileGroups `
                    -Groups $script:SorterSession.Groups `
                    -SourcePrefix $data.sourcePrefix `
                    -TargetPrefix $data.targetPrefix

                Send-JsonResponse -Response $res -Data @{
                    success     = $true
                    totalGroups = $script:SorterSession.Groups.Count
                    groups      = @($script:SorterSession.Groups | ForEach-Object {
                        @{ prefix = $_.Prefix; fileCount = $_.FileCount; files = $_.Files }
                    })
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # POST /tools/split-group
        # Body: { "sourcePrefix": "p006", "fileNames": [...], "newPrefix": "p006_extra" }
        # ================================================================
        if ($path -eq "/tools/split-group" -and $req.HttpMethod -eq "POST") {
            try {
                if (-not $script:SorterSession.Groups) {
                    Send-JsonResponse -Response $res -Data @{ success = $false; error = "Keine aktive Session" } -StatusCode 400
                    return $true
                }

                $body = Read-RequestBody -Request $req
                $data = $body | ConvertFrom-Json

                $script:SorterSession.Groups = Split-FileGroup `
                    -Groups $script:SorterSession.Groups `
                    -SourcePrefix $data.sourcePrefix `
                    -FileNames @($data.fileNames) `
                    -NewPrefix $data.newPrefix

                Send-JsonResponse -Response $res -Data @{
                    success     = $true
                    totalGroups = $script:SorterSession.Groups.Count
                    groups      = @($script:SorterSession.Groups | ForEach-Object {
                        @{ prefix = $_.Prefix; fileCount = $_.FileCount; files = $_.Files }
                    })
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # ================================================================
        # GET /tools/folder-list
        # Liefert alle bekannten Ordner aus dem Scanner-State
        # ================================================================
        if ($path -eq "/tools/folder-list" -and $req.HttpMethod -eq "GET") {
            try {
                $folders = [System.Collections.ArrayList]::new()
                
                # Root immer als erste Option
                [void]$folders.Add(@{
                    relativePath = "."
                    displayName  = "Root"
                    mediaCount   = 0
                })
                
                # Unterordner aus State (vom Scanner befüllt)
                if ($script:State -and $script:State.Folders) {
                    foreach ($f in $script:State.Folders) {
                        if ($f.RelativePath -ne ".") {
                            [void]$folders.Add(@{
                                relativePath = $f.RelativePath
                                displayName  = $f.RelativePath
                                mediaCount   = $f.MediaCount
                            })
                        }
                        else {
                            # Root-Eintrag aktualisieren mit MediaCount
                            $folders[0].mediaCount = $f.MediaCount
                        }
                    }
                }

                Send-JsonResponse -Response $res -Data @{
                    success  = $true
                    rootPath = $RootPath
                    folders  = @($folders)
                } -StatusCode 200
                return $true
            }
            catch {
                Send-JsonResponse -Response $res -Data @{ success = $false; error = $_.Exception.Message } -StatusCode 500
                return $true
            }
        }


        # Nicht zuständig
        return $false

    }
    catch {
        Write-Error "Sorter Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}


# ============================================================================
# INTERNE HELPER FÜR ROUTES
# ============================================================================

function Read-RequestBody {
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


function Send-JsonResponse {
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