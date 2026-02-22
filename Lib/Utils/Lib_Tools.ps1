<#
.SYNOPSIS
    Tools & Maintenance für Foto_Viewer_V2

.DESCRIPTION
    Verwaltung von .thumbs Cache-Ordnern:
    - Statistiken anzeigen
    - Liste aller .thumbs Ordner (rekursiv)
    - Ausgewählte löschen
    - Alle löschen

.EXAMPLE
    $stats = Get-ThumbsCacheStats -RootPath "C:\Photos"

.NOTES
    Autor: Herbert Schrotter
    Version: 0.3.0
    
    ÄNDERUNGEN v0.3.0:
    - Background-Job System für Cache-Rebuild
    - Start-CacheRebuildJob: Non-blocking Cache-Generierung
    - Get-CacheRebuildStatus: Job-Status mit Progress
    - Stop-CacheRebuildJob: Abbruch laufender Jobs
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# CACHE STATISTIKEN
# ============================================================================

function Get-ThumbsCacheStats {
    <#
    .SYNOPSIS
        Gibt Statistiken über alle .thumbs Ordner zurück
    
    .DESCRIPTION
        Findet rekursiv alle .thumbs Ordner im Root und zählt:
        - Anzahl .thumbs Ordner
        - Anzahl Thumbnail-Dateien gesamt
        - Gesamtgröße in Bytes
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .EXAMPLE
        $stats = Get-ThumbsCacheStats -RootPath "C:\Photos"
        Write-Host "$($stats.ThumbsDirectories) Ordner, $($stats.ThumbnailFiles) Dateien"
    
    .OUTPUTS
        PSCustomObject mit ThumbsDirectories, ThumbnailFiles, TotalSize, TotalSizeFormatted
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    try {
        if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
            throw "Root-Ordner existiert nicht: $RootPath"
        }
        
        # Finde ALLE .thumbs Ordner rekursiv
        $allThumbsDirs = @(Get-ChildItem -LiteralPath $RootPath -Recurse -Directory -Filter ".thumbs" -Force -ErrorAction SilentlyContinue)
        
        if ($allThumbsDirs.Count -eq 0) {
            return [PSCustomObject]@{
                ThumbsDirectories = 0
                ThumbnailFiles = 0
                TotalSize = 0
                TotalSizeFormatted = "0 MB"
            }
        }
        
        # Zähle alle Dateien in allen .thumbs Ordnern
        $totalFiles = 0
        $totalSize = 0
        
        foreach ($dir in $allThumbsDirs) {
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue)
            $totalFiles += $files.Count
            if ($files.Count -gt 0) {
                $size = ($files | Measure-Object -Property Length -Sum).Sum
                if ($size) { $totalSize += $size }
            }
        }
        
        # Formatiere Größe
        $sizeFormatted = if ($totalSize -gt 1GB) {
            "$([Math]::Round($totalSize / 1GB, 2)) GB"
        } elseif ($totalSize -gt 1MB) {
            "$([Math]::Round($totalSize / 1MB, 2)) MB"
        } elseif ($totalSize -gt 1KB) {
            "$([Math]::Round($totalSize / 1KB, 2)) KB"
        } else {
            "$totalSize Bytes"
        }
        
        Write-Verbose "Cache Stats: $($allThumbsDirs.Count) Ordner, $totalFiles Dateien, $sizeFormatted"
        
        return [PSCustomObject]@{
            ThumbsDirectories = $allThumbsDirs.Count
            ThumbnailFiles = $totalFiles
            TotalSize = $totalSize
            TotalSizeFormatted = $sizeFormatted
        }
        
    } catch {
        Write-Error "Fehler beim Abrufen der Statistiken: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# LISTE ALLER .THUMBS ORDNER
# ============================================================================

function Get-ThumbsDirectoriesList {
    <#
    .SYNOPSIS
        Gibt Liste aller .thumbs Ordner mit Details zurück
    
    .DESCRIPTION
        Findet rekursiv alle .thumbs Ordner und gibt für jeden:
        - Absoluter Pfad
        - Relativer Pfad (zu Root)
        - Anzahl Dateien
        - Größe in Bytes
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .EXAMPLE
        $list = Get-ThumbsDirectoriesList -RootPath "C:\Photos"
        $list | ForEach-Object { Write-Host "$($_.RelativePath): $($_.FileCount) Dateien" }
    
    .OUTPUTS
        Array von PSCustomObjects mit Path, RelativePath, FileCount, Size, SizeFormatted
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    try {
        if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
            throw "Root-Ordner existiert nicht: $RootPath"
        }
        
        # Finde ALLE .thumbs Ordner rekursiv
        $allThumbsDirs = @(Get-ChildItem -LiteralPath $RootPath -Recurse -Directory -Filter ".thumbs" -Force -ErrorAction SilentlyContinue)
        
        if ($allThumbsDirs.Count -eq 0) {
            Write-Verbose "Keine .thumbs Ordner gefunden"
            return @()
        }
        
        $result = foreach ($dir in $allThumbsDirs) {
            # Relativer Pfad
            $relativePath = $dir.FullName.Substring($RootPath.Length).TrimStart('\', '/')
            if ([string]::IsNullOrEmpty($relativePath)) {
                $relativePath = ".thumbs"
            }
            
            # Dateien zählen
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue)
            $fileCount = $files.Count
            $size = 0
            if ($files.Count -gt 0) {
                $measured = ($files | Measure-Object -Property Length -Sum).Sum
                if ($measured) { $size = $measured }
            }
            
            # Größe formatieren
            $sizeFormatted = if ($size -gt 1GB) {
                "$([Math]::Round($size / 1GB, 2)) GB"
            } elseif ($size -gt 1MB) {
                "$([Math]::Round($size / 1MB, 2)) MB"
            } elseif ($size -gt 1KB) {
                "$([Math]::Round($size / 1KB, 2)) KB"
            } else {
                "$size Bytes"
            }
            
            [PSCustomObject]@{
                Path = $dir.FullName
                RelativePath = $relativePath
                FileCount = $fileCount
                Size = $size
                SizeFormatted = $sizeFormatted
            }
        }
        
        Write-Verbose "Gefunden: $($result.Count) .thumbs Ordner"
        return $result
        
    } catch {
        Write-Error "Fehler beim Auflisten: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# AUSGEWÄHLTE .THUMBS ORDNER LÖSCHEN
# ============================================================================

function Remove-SelectedThumbsDirectories {
    <#
    .SYNOPSIS
        Löscht ausgewählte .thumbs Ordner
    
    .DESCRIPTION
        Löscht die angegebenen .thumbs Ordner rekursiv.
        Prüft vorher ob Pfade gültig sind.
    
    .PARAMETER Paths
        Array mit absoluten Pfaden zu .thumbs Ordnern
    
    .EXAMPLE
        $paths = @("C:\Photos\.thumbs", "C:\Photos\Urlaub\.thumbs")
        $result = Remove-SelectedThumbsDirectories -Paths $paths
    
    .OUTPUTS
        PSCustomObject mit DeletedCount, DeletedSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths
    )
    
    try {
        $deletedCount = 0
        $deletedSize = 0
        
        foreach ($path in $Paths) {
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                Write-Warning "Ordner existiert nicht (übersprungen): $path"
                continue
            }
            
            # Prüfe ob es ein .thumbs Ordner ist
            $dirName = Split-Path -Leaf $path
            if ($dirName -ne ".thumbs") {
                Write-Warning "Kein .thumbs Ordner (übersprungen): $path"
                continue
            }
            
            # Größe berechnen
            $files = @(Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue)
            $size = 0
            if ($files.Count -gt 0) {
                $measured = ($files | Measure-Object -Property Length -Sum).Sum
                if ($measured) { $size = $measured }
            }
            
            # Löschen
            Write-Verbose "Lösche: $path"
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            
            $deletedCount++
            $deletedSize += $size
        }
        
        Write-Verbose "Gelöscht: $deletedCount Ordner, $([Math]::Round($deletedSize / 1MB, 2)) MB"
        
        return [PSCustomObject]@{
            DeletedCount = $deletedCount
            DeletedSize = $deletedSize
        }
        
    } catch {
        Write-Error "Fehler beim Löschen: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# ALLE .THUMBS ORDNER LÖSCHEN
# ============================================================================

function Remove-AllThumbsDirectories {
    <#
    .SYNOPSIS
        Löscht ALLE .thumbs Ordner im Root rekursiv
    
    .DESCRIPTION
        Findet rekursiv alle .thumbs Ordner im Root und löscht sie alle.
        ACHTUNG: Keine Rückfrage, direktes Löschen!
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .EXAMPLE
        $result = Remove-AllThumbsDirectories -RootPath "C:\Photos"
        Write-Host "Gelöscht: $($result.DeletedCount) Ordner"
    
    .OUTPUTS
        PSCustomObject mit DeletedCount, DeletedSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    try {
        if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
            throw "Root-Ordner existiert nicht: $RootPath"
        }
        
        # Finde ALLE .thumbs Ordner rekursiv
        $allThumbsDirs = @(Get-ChildItem -LiteralPath $RootPath -Recurse -Directory -Filter ".thumbs" -Force -ErrorAction SilentlyContinue)
        
        if ($allThumbsDirs.Count -eq 0) {
            Write-Verbose "Keine .thumbs Ordner gefunden"
            return [PSCustomObject]@{
                DeletedCount = 0
                DeletedSize = 0
            }
        }
        
        $deletedCount = 0
        $deletedSize = 0
        
        foreach ($dir in $allThumbsDirs) {
            # Größe berechnen
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue)
            $size = 0
            if ($files.Count -gt 0) {
                $measured = ($files | Measure-Object -Property Length -Sum).Sum
                if ($measured) { $size = $measured }
            }
            
            # Löschen
            Write-Verbose "Lösche: $($dir.FullName)"
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
            
            $deletedCount++
            $deletedSize += $size
        }
        
        Write-Verbose "Alle .thumbs gelöscht: $deletedCount Ordner, $([Math]::Round($deletedSize / 1MB, 2)) MB"
        
        return [PSCustomObject]@{
            DeletedCount = $deletedCount
            DeletedSize = $deletedSize
        }
        
    } catch {
        Write-Error "Fehler beim Löschen aller .thumbs: $($_.Exception.Message)"
        throw
    }
}

# ============================================================================
# BACKGROUND-JOB CACHE REBUILD
# ============================================================================

function Start-CacheRebuildJob {
    <#
    .SYNOPSIS
        Startet Background-Job für Cache-Rebuild
    
    .DESCRIPTION
        Validiert/Rebuilt Thumbnail-Cache für ALLE Ordner im Hintergrund.
        Non-Blocking: Server bleibt responsiv.
        
        Job speichert Progress in shared Hashtable:
        - TotalFolders: Gesamtzahl Ordner
        - ProcessedFolders: Bisher verarbeitet
        - UpdatedFolders: Anzahl Rebuilds
        - ValidFolders: Anzahl valide Caches
        - CurrentFolder: Aktuell bearbeiteter Ordner
        - Status: Running/Completed/Error
        - Error: Fehlermeldung (falls Error)
    
    .PARAMETER RootPath
        Root-Ordner der Medien
    
    .PARAMETER Folders
        Array von Ordner-Objekten (aus Get-MediaFolders)
    
    .PARAMETER ScriptRoot
        Projekt-Root (für FFmpeg)
    
    .PARAMETER LogFile
        Optional: Pfad zur Log-Datei (Default: ScriptRoot\cache-rebuild.log)
    
    .EXAMPLE
        $job = Start-CacheRebuildJob -RootPath $RootPath -Folders $script:State.Folders -ScriptRoot $PSScriptRoot
        # Job läuft im Hintergrund
    
    .OUTPUTS
        PSCustomObject mit JobId, StartTime, Progress (Hashtable)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        
        [Parameter(Mandatory)]
        [array]$Folders,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot,
        
        [Parameter()]
        [string]$LogFile
    )
    
    try {
        # Log-Datei initialisieren
        if (-not $LogFile) {
            $LogFile = Join-Path $ScriptRoot "cache-rebuild.log"
        }
        
        # Alte Log-Datei löschen
        if (Test-Path -LiteralPath $LogFile) {
            Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
        }
        
        # Log-Header schreiben
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "[$timestamp] Cache-Rebuild Job gestartet" | Out-File -FilePath $LogFile -Encoding UTF8
        "[$timestamp] Total Folders: $($Folders.Count)" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        "" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        
        # Stoppe alten Job falls noch läuft
        if (Get-Variable -Name 'CacheRebuildJob' -Scope Script -ErrorAction SilentlyContinue) {
            if ($script:CacheRebuildJob -and $script:CacheRebuildJob.Job) {
                if ($script:CacheRebuildJob.Job.State -eq 'Running') {
                    Write-Verbose "Stoppe alten Cache-Rebuild Job"
                    Stop-Job -Job $script:CacheRebuildJob.Job
                    Remove-Job -Job $script:CacheRebuildJob.Job -Force
                }
            }
        }
        
        # Progress-Hashtable (Synchronized für Thread-Safety)
        $progress = [hashtable]::Synchronized(@{
            TotalFolders = $Folders.Count
            ProcessedFolders = 0
            UpdatedFolders = 0
            ValidFolders = 0
            CurrentFolder = ""
            Status = "Running"
            Error = $null
        })
        
        # ScriptBlock für Background-Job
        $jobScript = {
            param($RootPath, $Folders, $ScriptRoot, $Progress, $LogFile)
            
            function Write-JobLog {
                param([string]$Message, [string]$Level = "INFO")
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                "[$timestamp] [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
            }
            
            Write-JobLog "Job gestartet im Background"
            Write-JobLog "ScriptRoot: $ScriptRoot"
            Write-JobLog "Total Folders: $($Folders.Count)"
            
            # Libs laden (im Job-Context)
            $libThumbsPath = Join-Path $ScriptRoot "Lib\Media\Lib_Thumbnails.ps1"
            Write-JobLog "Lade Lib: $libThumbsPath"
            
            if (Test-Path -LiteralPath $libThumbsPath) {
                try {
                    . $libThumbsPath
                    Write-JobLog "Lib geladen: OK"
                } catch {
                    $Progress.Status = "Error"
                    $Progress.Error = "Fehler beim Laden: $($_.Exception.Message)"
                    Write-JobLog "Fehler beim Laden: $($_.Exception.Message)" "ERROR"
                    Write-JobLog "StackTrace: $($_.ScriptStackTrace)" "ERROR"
                    return
                }
            } else {
                $Progress.Status = "Error"
                $Progress.Error = "Lib_Thumbnails.ps1 nicht gefunden: $libThumbsPath"
                Write-JobLog "Lib nicht gefunden: $libThumbsPath" "ERROR"
                return
            }
            
            try {
                foreach ($folder in $Folders) {
                    try {
                        $Progress.CurrentFolder = $folder.RelativePath
                        Write-JobLog "Verarbeite: $($folder.RelativePath)"
                        
                        # Cache validieren
                        if (-not (Test-ThumbnailCacheValid -FolderPath $folder.Path)) {
                            Write-JobLog "  Cache ungültig, rebuild nötig"
                            
                            # Rebuild nötig
                            $generated = Update-ThumbnailCache -FolderPath $folder.Path -ScriptRoot $ScriptRoot -MaxSize 300
                            Write-JobLog "  Generiert: $generated Thumbnails"
                            
                            if ($generated -gt 0) {
                                # Orphans aufräumen
                                $removed = Remove-OrphanedThumbnails -FolderPath $folder.Path
                                Write-JobLog "  Orphans entfernt: $removed"
                                $Progress.UpdatedFolders++
                            }
                        } else {
                            # Cache valide
                            Write-JobLog "  Cache valide"
                            $Progress.ValidFolders++
                        }
                        
                        $Progress.ProcessedFolders++
                    }
                    catch {
                        $errorMsg = "Fehler bei $($folder.RelativePath): $($_.Exception.Message)"
                        Write-JobLog $errorMsg "ERROR"
                        Write-JobLog "  StackTrace: $($_.ScriptStackTrace)" "ERROR"
                        $Progress.CurrentFolder = "ERROR: $($folder.RelativePath)"
                        $Progress.ProcessedFolders++
                    }
                }
                
                $Progress.Status = "Completed"
                $Progress.CurrentFolder = ""
                Write-JobLog "Job erfolgreich abgeschlossen"
                Write-JobLog "Verarbeitet: $($Progress.ProcessedFolders), Aktualisiert: $($Progress.UpdatedFolders), Valide: $($Progress.ValidFolders)"
                
            } catch {
                $Progress.Status = "Error"
                $Progress.Error = "FATAL: $($_.Exception.Message)"
                Write-JobLog "FATAL ERROR: $($_.Exception.Message)" "ERROR"
                Write-JobLog "StackTrace: $($_.ScriptStackTrace)" "ERROR"
            }
        }
        
        # Job starten
        Write-Verbose "Starte Cache-Rebuild Job für $($Folders.Count) Ordner"
        Write-Verbose "Log-Datei: $LogFile"
        
        $job = Start-Job -ScriptBlock $jobScript -ArgumentList $RootPath, $Folders, $ScriptRoot, $progress, $LogFile
        
        # In Script-Scope speichern
        $script:CacheRebuildJob = [PSCustomObject]@{
            JobId = $job.Id
            Job = $job
            StartTime = Get-Date
            Progress = $progress
        }
        
        return $script:CacheRebuildJob
        
    } catch {
        Write-Error "Fehler beim Starten des Cache-Rebuild Jobs: $($_.Exception.Message)"
        throw
    }
}

function Get-CacheRebuildStatus {
    <#
    .SYNOPSIS
        Gibt Status des Cache-Rebuild Jobs zurück
    
    .DESCRIPTION
        Liefert aktuellen Progress des Background-Jobs:
        - Status: Running/Completed/Error/NotStarted
        - Progress: Prozentsatz (0-100)
        - Details: Anzahl verarbeitet/updated/valide
        - CurrentFolder: Aktuell bearbeiteter Ordner
        - Duration: Laufzeit in Sekunden
    
    .EXAMPLE
        $status = Get-CacheRebuildStatus
        if ($status.Status -eq "Running") {
            Write-Host "Progress: $($status.Progress)%"
        }
    
    .OUTPUTS
        PSCustomObject mit Status, Progress, Details, Duration
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        # Kein Job vorhanden?
        if (-not (Get-Variable -Name 'CacheRebuildJob' -Scope Script -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                Status = "NotStarted"
                Progress = 0
                TotalFolders = 0
                ProcessedFolders = 0
                UpdatedFolders = 0
                ValidFolders = 0
                CurrentFolder = ""
                Duration = 0
                Error = $null
            }
        }
        
        $job = $script:CacheRebuildJob
        $prog = $job.Progress
        
        # Progress berechnen
        $percent = 0
        if ($prog.TotalFolders -gt 0) {
            $percent = [Math]::Round(($prog.ProcessedFolders / $prog.TotalFolders) * 100, 1)
        }
        
        # Laufzeit berechnen
        $duration = [Math]::Round(((Get-Date) - $job.StartTime).TotalSeconds, 1)
        
        # Job-State prüfen
        $jobState = $job.Job.State
        
        # Status ermitteln
        $status = switch ($prog.Status) {
            "Running" {
                if ($jobState -eq "Completed") { "Completed" } 
                elseif ($jobState -eq "Failed") { "Error" }
                else { "Running" }
            }
            "Completed" { "Completed" }
            "Error" { "Error" }
            default { "Running" }
        }
        
        # Cleanup bei Completed/Error
        if ($status -in @("Completed", "Error") -and $job.Job.State -ne "Running") {
            Write-Verbose "Cleanup: Entferne abgeschlossenen Job"
            Remove-Job -Job $job.Job -Force -ErrorAction SilentlyContinue
        }
        
        return [PSCustomObject]@{
            Status = $status
            Progress = $percent
            TotalFolders = $prog.TotalFolders
            ProcessedFolders = $prog.ProcessedFolders
            UpdatedFolders = $prog.UpdatedFolders
            ValidFolders = $prog.ValidFolders
            CurrentFolder = $prog.CurrentFolder
            Duration = $duration
            Error = $prog.Error
        }
        
    } catch {
        Write-Error "Fehler beim Abrufen des Job-Status: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Status = "Error"
            Progress = 0
            Error = $_.Exception.Message
        }
    }
}

function Stop-CacheRebuildJob {
    <#
    .SYNOPSIS
        Stoppt laufenden Cache-Rebuild Job
    
    .DESCRIPTION
        Bricht den aktuell laufenden Background-Job ab und
        räumt Ressourcen auf.
    
    .EXAMPLE
        Stop-CacheRebuildJob
        # Job wird abgebrochen
    
    .OUTPUTS
        Boolean - $true wenn gestoppt, $false wenn kein Job läuft
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        if (-not (Get-Variable -Name 'CacheRebuildJob' -Scope Script -ErrorAction SilentlyContinue)) {
            Write-Verbose "Kein Cache-Rebuild Job aktiv"
            return $false
        }
        
        $job = $script:CacheRebuildJob.Job
        
        if ($job.State -eq 'Running') {
            Write-Verbose "Stoppe Cache-Rebuild Job (ID: $($job.Id))"
            Stop-Job -Job $job
            Remove-Job -Job $job -Force
            
            # Status aktualisieren
            $script:CacheRebuildJob.Progress.Status = "Stopped"
            
            return $true
        } else {
            Write-Verbose "Job läuft nicht mehr (State: $($job.State))"
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            return $false
        }
        
    } catch {
        Write-Error "Fehler beim Stoppen des Jobs: $($_.Exception.Message)"
        return $false
    }
}