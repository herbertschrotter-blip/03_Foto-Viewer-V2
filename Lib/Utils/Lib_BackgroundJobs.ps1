<#
.SYNOPSIS
    Background-Job System für Thumbnail-Generierung

.DESCRIPTION
    Verwaltet Background-Jobs für Thumbnail-Cache:
    - Cache-Rebuild für ALLE Ordner (manuell über Tools-Menü)
    - Auto-Generierung für EINZELNE Ordner (beim Öffnen)
    
    Einzelordner-Jobs:
    - Prüfen Manifest auf Änderungen
    - Leeren .thumbs/ bei Änderungen
    - Generieren Thumbnails im Hintergrund
    - Priorisierung: Aktuell geöffneter Ordner zuerst

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.3
    
    ÄNDERUNGEN v0.1.3:
    - Fix: Verhindere doppelte Jobs für denselben Ordner
    - Verhindert File-Lock Konflikte
    
    ÄNDERUNGEN v0.1.2:
    - DEBUG: Umfangreiches Logging für Troubleshooting
    
    ÄNDERUNGEN v0.1.1:
    - Fix: Update-ThumbnailCache nur bei ungültigem Cache
    
    ÄNDERUNGEN v0.1.0:
    - Neue Lib für Background-Job System
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# CACHE REBUILD - ALLE ORDNER
# ============================================================================

function Start-CacheRebuildJob {
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
        if (-not $LogFile) {
            $LogFile = Join-Path $ScriptRoot "cache-rebuild.log"
        }
        
        if (Test-Path -LiteralPath $LogFile) {
            Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
        }
        
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "[$timestamp] Cache-Rebuild Job gestartet" | Out-File -FilePath $LogFile -Encoding UTF8
        "[$timestamp] Total Folders: $($Folders.Count)" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        "" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        
        if (Get-Variable -Name 'CacheRebuildJob' -Scope Script -ErrorAction SilentlyContinue) {
            if ($script:CacheRebuildJob -and $script:CacheRebuildJob.Job) {
                if ($script:CacheRebuildJob.Job.State -eq 'Running') {
                    Write-Verbose "Stoppe alten Cache-Rebuild Job"
                    Stop-Job -Job $script:CacheRebuildJob.Job
                    Remove-Job -Job $script:CacheRebuildJob.Job -Force
                }
            }
        }
        
        $progress = [hashtable]::Synchronized(@{
            TotalFolders = $Folders.Count
            ProcessedFolders = 0
            UpdatedFolders = 0
            ValidFolders = 0
            CurrentFolder = ""
            Status = "Running"
            Error = $null
        })
        
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
                        
                        if (-not (Test-ThumbnailCacheValid -FolderPath $folder.Path)) {
                            Write-JobLog "  Cache ungültig, rebuild nötig"
                            
                            $generated = Update-ThumbnailCache -FolderPath $folder.Path -ScriptRoot $ScriptRoot -MaxSize 300
                            Write-JobLog "  Generiert: $generated Thumbnails"
                            
                            if ($generated -gt 0) {
                                $removed = Remove-OrphanedThumbnails -FolderPath $folder.Path
                                Write-JobLog "  Orphans entfernt: $removed"
                                $Progress.UpdatedFolders++
                            }
                        } else {
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
        
        Write-Verbose "Starte Cache-Rebuild Job für $($Folders.Count) Ordner"
        Write-Verbose "Log-Datei: $LogFile"
        
        $job = Start-Job -ScriptBlock $jobScript -ArgumentList $RootPath, $Folders, $ScriptRoot, $progress, $LogFile
        
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
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
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
        
        $percent = 0
        if ($prog.TotalFolders -gt 0) {
            $percent = [Math]::Round(($prog.ProcessedFolders / $prog.TotalFolders) * 100, 1)
        }
        
        $duration = [Math]::Round(((Get-Date) - $job.StartTime).TotalSeconds, 1)
        
        $jobState = $job.Job.State
        
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

# ============================================================================
# EINZELORDNER THUMBNAIL-JOB
# ============================================================================

function Start-FolderThumbnailJob {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )
    
    try {
        if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
            throw "Ordner existiert nicht: $FolderPath"
        }
        
        Write-Verbose "Starte Thumbnail-Job für: $FolderPath"
        
        # Hashtable initialisieren
        if (-not (Get-Variable -Name 'FolderThumbnailJobs' -Scope Script -ErrorAction SilentlyContinue)) {
            $script:FolderThumbnailJobs = @{}
        }
        
        # Prüfe ob bereits ein Job für diesen Ordner läuft
        if ($script:FolderThumbnailJobs.ContainsKey($FolderPath)) {
            $existingJob = $script:FolderThumbnailJobs[$FolderPath]
            if ($existingJob.Job.State -eq 'Running') {
                Write-Verbose "Job läuft bereits für: $FolderPath - Überspringe"
                return $existingJob
            } else {
                # Alter Job beendet, aufräumen
                Write-Verbose "Alter Job beendet, starte neu: $FolderPath"
                Remove-Job -Job $existingJob.Job -Force -ErrorAction SilentlyContinue
            }
        }
        
        $progress = [hashtable]::Synchronized(@{
            Status = "Running"
            ManifestChanged = $false
            ThumbnailsGenerated = 0
            Error = $null
        })
        
        $jobScript = {
            param($FolderPath, $ScriptRoot, $Progress)
            
            $libThumbsPath = Join-Path $ScriptRoot "Lib\Media\Lib_Thumbnails.ps1"
            
            if (-not (Test-Path -LiteralPath $libThumbsPath)) {
                $Progress.Status = "Error"
                $Progress.Error = "Lib_Thumbnails.ps1 nicht gefunden"
                return
            }
            
            try {
                . $libThumbsPath
            } catch {
                $Progress.Status = "Error"
                $Progress.Error = "Fehler beim Laden von Lib_Thumbnails.ps1: $($_.Exception.Message)"
                return
            }
            
            try {
                $thumbsDir = Join-Path $FolderPath ".thumbs"
                
                $cacheValid = Test-ThumbnailCacheValid -FolderPath $FolderPath
                
                if (-not $cacheValid) {
                    $Progress.ManifestChanged = $true
                    
                    if (Test-Path -LiteralPath $thumbsDir) {
                        Remove-Item -LiteralPath $thumbsDir -Recurse -Force -ErrorAction Stop
                    }
                    
                    $generated = Update-ThumbnailCache -FolderPath $FolderPath -ScriptRoot $ScriptRoot -MaxSize 300
                    $Progress.ThumbnailsGenerated = $generated
                    
                    if ($generated -gt 0) {
                        $removed = Remove-OrphanedThumbnails -FolderPath $FolderPath
                    }
                } else {
                    $Progress.ThumbnailsGenerated = 0
                }
                
                $Progress.Status = "Completed"
                
            } catch {
                $Progress.Status = "Error"
                $Progress.Error = $_.Exception.Message
            }
        }
        
        $job = Start-Job -ScriptBlock $jobScript -ArgumentList $FolderPath, $ScriptRoot, $progress
        
        $jobInfo = [PSCustomObject]@{
            JobId = $job.Id
            Job = $job
            FolderPath = $FolderPath
            StartTime = Get-Date
            Progress = $progress
        }
        
        $script:FolderThumbnailJobs[$FolderPath] = $jobInfo
        
        Write-Verbose "Job gestartet (ID: $($job.Id)) für: $FolderPath"
        
        return $jobInfo
        
    } catch {
        Write-Error "Fehler beim Starten des Folder-Jobs: $($_.Exception.Message)"
        throw
    }
}

function Get-FolderJobStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    
    try {
        if (-not (Get-Variable -Name 'FolderThumbnailJobs' -Scope Script -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                Status = "NotStarted"
                ManifestChanged = $false
                ThumbnailsGenerated = 0
                Duration = 0
                Error = $null
            }
        }
        
        if (-not $script:FolderThumbnailJobs.ContainsKey($FolderPath)) {
            return [PSCustomObject]@{
                Status = "NotStarted"
                ManifestChanged = $false
                ThumbnailsGenerated = 0
                Duration = 0
                Error = $null
            }
        }
        
        $jobInfo = $script:FolderThumbnailJobs[$FolderPath]
        $prog = $jobInfo.Progress
        
        $duration = [Math]::Round(((Get-Date) - $jobInfo.StartTime).TotalSeconds, 1)
        
        $jobState = $jobInfo.Job.State
        
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
        
        if ($status -in @("Completed", "Error") -and $jobInfo.Job.State -ne "Running") {
            Write-Verbose "Cleanup: Entferne Job für $FolderPath"
            Remove-Job -Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
            $script:FolderThumbnailJobs.Remove($FolderPath)
        }
        
        return [PSCustomObject]@{
            Status = $status
            ManifestChanged = $prog.ManifestChanged
            ThumbnailsGenerated = $prog.ThumbnailsGenerated
            Duration = $duration
            Error = $prog.Error
        }
        
    } catch {
        Write-Error "Fehler beim Abrufen des Folder-Job-Status: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

function Stop-FolderJob {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    
    try {
        if (-not (Get-Variable -Name 'FolderThumbnailJobs' -Scope Script -ErrorAction SilentlyContinue)) {
            return $false
        }
        
        if (-not $script:FolderThumbnailJobs.ContainsKey($FolderPath)) {
            return $false
        }
        
        $jobInfo = $script:FolderThumbnailJobs[$FolderPath]
        $job = $jobInfo.Job
        
        if ($job.State -eq 'Running') {
            Write-Verbose "Stoppe Folder-Job für: $FolderPath"
            Stop-Job -Job $job
            Remove-Job -Job $job -Force
            
            $script:FolderThumbnailJobs.Remove($FolderPath)
            
            return $true
        } else {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $script:FolderThumbnailJobs.Remove($FolderPath)
            return $false
        }
        
    } catch {
        Write-Error "Fehler beim Stoppen des Folder-Jobs: $($_.Exception.Message)"
        return $false
    }
}