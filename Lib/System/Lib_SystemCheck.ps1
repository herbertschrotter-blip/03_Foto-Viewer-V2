<#
ManifestHint:
  ExportFunctions = @("Test-SystemRequirements", "Test-LongPathSupport", "Get-SystemInfo")
  Description     = "System-Requirements Check für PhotoFolder"
  Category        = "System"
  Tags            = @("System", "Requirements", "Registry", "PowerShell")
  Dependencies    = @()

Zweck:
  - Prüft System-Requirements für PhotoFolder
  - Long Path Support Check
  - PowerShell Version Check
  - FFmpeg Verfügbarkeit
  - Admin-Rechte Check

Funktionen:
  - Test-SystemRequirements: Vollständige System-Prüfung
  - Test-LongPathSupport: Prüft Registry für Long Paths
  - Get-SystemInfo: Sammelt System-Informationen

Abhängigkeiten:
  - Keine

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
    
.LINK
    https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Prüft ob PowerShell als Administrator läuft
    
    .OUTPUTS
        Boolean - True wenn Admin, sonst False
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-LongPathSupport {
    <#
    .SYNOPSIS
        Prüft ob Windows Long Path Support aktiviert ist
    
    .DESCRIPTION
        Prüft Registry-Eintrag HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled
        
        Wert 1 = Aktiviert (max 32.767 Zeichen)
        Wert 0 oder nicht vorhanden = Deaktiviert (max 260 Zeichen)
    
    .EXAMPLE
        $enabled = Test-LongPathSupport
        if (-not $enabled) {
            Write-Warning "Long Path Support deaktiviert!"
        }
    
    .OUTPUTS
        Boolean - True wenn aktiviert, False wenn deaktiviert
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        $regName = "LongPathsEnabled"
        
        # Registry-Wert lesen
        $value = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
        
        if ($value -and $value.LongPathsEnabled -eq 1) {
            Write-Verbose "Long Path Support: Aktiviert (max 32.767 Zeichen)"
            return $true
        } else {
            Write-Verbose "Long Path Support: Deaktiviert (max 260 Zeichen)"
            return $false
        }
        
    } catch {
        Write-Verbose "Long Path Support: Konnte nicht geprüft werden (default: Deaktiviert)"
        return $false
    }
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Sammelt relevante System-Informationen
    
    .DESCRIPTION
        Gibt PSCustomObject mit System-Details zurück:
        - PowerShell Version
        - OS Version
        - Admin-Rechte
        - Long Path Support
        - .NET Version
    
    .EXAMPLE
        $info = Get-SystemInfo
        $info | Format-List
    
    .OUTPUTS
        PSCustomObject mit System-Details
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $isAdmin = Test-IsAdmin
    $longPathEnabled = Test-LongPathSupport
    
    $info = [PSCustomObject]@{
        PSTypeName = 'PhotoFolder.SystemInfo'
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition = $PSVersionTable.PSEdition
        OSVersion = [System.Environment]::OSVersion.VersionString
        OSPlatform = [System.Environment]::OSVersion.Platform
        IsAdmin = $isAdmin
        LongPathSupport = $longPathEnabled
        DotNetVersion = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        MachineName = $env:COMPUTERNAME
        UserName = $env:USERNAME
    }
    
    return $info
}

function Test-SystemRequirements {
    <#
    .SYNOPSIS
        Führt vollständigen System-Requirements Check durch
    
    .DESCRIPTION
        Prüft alle Requirements für PhotoFolder:
        1. PowerShell 7.0+
        2. Long Path Support (Warnung wenn deaktiviert)
        3. FFmpeg (Optional - Warnung wenn fehlt)
        
        Gibt PSCustomObject mit Check-Ergebnissen zurück.
    
    .PARAMETER ScriptRoot
        Projekt-Root-Pfad (für FFmpeg-Check)
    
    .PARAMETER ShowWarnings
        Zeigt Warnungen direkt in Console (default: true)
    
    .EXAMPLE
        $check = Test-SystemRequirements -ScriptRoot $PSScriptRoot
        
        if (-not $check.AllPassed) {
            Write-Host "System-Checks fehlgeschlagen!" -ForegroundColor Red
            exit 1
        }
    
    .EXAMPLE
        # Mit interaktivem Prompt:
        $check = Test-SystemRequirements -ScriptRoot $PSScriptRoot -ShowWarnings $true
    
    .OUTPUTS
        PSCustomObject mit Check-Ergebnissen
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ScriptRoot,
        
        [Parameter()]
        [bool]$ShowWarnings = $true
    )
    
    $checks = [PSCustomObject]@{
        PSTypeName = 'PhotoFolder.SystemCheck'
        PowerShellVersion = $null
        LongPathSupport = $null
        FFmpegAvailable = $null
        AllPassed = $false
        Warnings = @()
        Errors = @()
    }
    
    # Check 1: PowerShell Version
    try {
        $psVersion = $PSVersionTable.PSVersion
        
        if ($psVersion.Major -ge 7) {
            $checks.PowerShellVersion = $true
            Write-Verbose "✓ PowerShell Version: $psVersion"
        } else {
            $checks.PowerShellVersion = $false
            $checks.Errors += "PowerShell $psVersion nicht unterstützt (benötigt: 7.0+)"
            
            if ($ShowWarnings) {
                Write-Host "❌ PowerShell Version: $psVersion" -ForegroundColor Red
                Write-Host "   PhotoFolder benötigt PowerShell 7.0 oder höher!" -ForegroundColor Yellow
            }
        }
    } catch {
        $checks.PowerShellVersion = $false
        $checks.Errors += "Konnte PowerShell Version nicht prüfen"
    }
    
    # Check 2: Long Path Support
    try {
        $longPathEnabled = Test-LongPathSupport
        $checks.LongPathSupport = $longPathEnabled
        
        if ($longPathEnabled) {
            Write-Verbose "✓ Long Path Support: Aktiviert"
        } else {
            $checks.Warnings += "Long Path Support deaktiviert (max 260 Zeichen)"
            
            if ($ShowWarnings) {
                Write-Host "⚠️  Long Path Support: DEAKTIVIERT" -ForegroundColor Yellow
                Write-Host "   Maximale Pfad-Länge: 260 Zeichen" -ForegroundColor Gray
                Write-Host "   Für lange Pfade aktivieren? (Benötigt Admin-Rechte)" -ForegroundColor Gray
                Write-Host "   Siehe: Lib\System\Lib_AdminTools.ps1 → Enable-LongPathSupport" -ForegroundColor Gray
            }
        }
    } catch {
        $checks.LongPathSupport = $false
        $checks.Warnings += "Long Path Support konnte nicht geprüft werden"
    }
    
    # Check 3: FFmpeg (Optional)
    if ($ScriptRoot) {
        try {
            $ffmpegPath = Join-Path $ScriptRoot "ffmpeg\ffmpeg.exe"
            
            if (Test-Path -LiteralPath $ffmpegPath -PathType Leaf) {
                $checks.FFmpegAvailable = $true
                Write-Verbose "✓ FFmpeg gefunden: $ffmpegPath"
            } else {
                $checks.FFmpegAvailable = $false
                $checks.Warnings += "FFmpeg nicht gefunden (Video-Thumbnails deaktiviert)"
                
                if ($ShowWarnings) {
                    Write-Host "⚠️  FFmpeg: NICHT GEFUNDEN" -ForegroundColor Yellow
                    Write-Host "   Pfad: $ffmpegPath" -ForegroundColor Gray
                    Write-Host "   Video-Thumbnails werden nicht funktionieren!" -ForegroundColor Gray
                }
            }
        } catch {
            $checks.FFmpegAvailable = $false
            $checks.Warnings += "FFmpeg-Check fehlgeschlagen"
        }
    } else {
        $checks.FFmpegAvailable = $null  # Nicht geprüft
    }
    
    # Gesamt-Status
    $checks.AllPassed = $checks.PowerShellVersion -and 
                        ($checks.Errors.Count -eq 0)
    
    return $checks
}