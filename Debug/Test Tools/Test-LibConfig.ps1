<#
.SYNOPSIS
    Vollständiges Test-Tool - Validiert ALLE Config-Werte automatisch

.DESCRIPTION
    Durchläuft rekursiv die komplette Config-Struktur:
    - Findet alle Bereiche (Video, Server, etc.)
    - Findet alle Parameter automatisch
    - Validiert jeden Wert (Type-Check)
    - Zählt Erfolge/Fehler

.EXAMPLE
    .\Test-LibConfig-Full.ps1

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Farben
function Write-OK { param([string]$M) Write-Host "✅ $M" -ForegroundColor Green }
function Write-Fail { param([string]$M) Write-Host "❌ $M" -ForegroundColor Red }
function Write-Info { param([string]$M) Write-Host "ℹ️  $M" -ForegroundColor Cyan }

# Zähler
$script:totalChecks = 0
$script:passedChecks = 0
$script:failedChecks = 0

function Test-ConfigValue {
    <#
    .SYNOPSIS
        Validiert einen einzelnen Config-Wert
    #>
    param(
        [string]$Path,
        $Value
    )
    
    $script:totalChecks++
    
    $typeName = if ($Value -eq $null) { "null" } else { $Value.GetType().Name }
    
    # Validierungs-Regeln
    $valid = $false
    $reason = ""
    
    switch ($typeName) {
        'String' {
            # RootFolder darf leer sein (wird beim Start gewählt)
            if ($Path -eq 'Paths.RootFolder') {
                $valid = $true
                $reason = if ([string]::IsNullOrEmpty($Value)) { "✓ (leer, wird beim Start gesetzt)" } else { "✓" }
            } else {
                $valid = -not [string]::IsNullOrEmpty($Value)
                $reason = if ($valid) { "✓" } else { "leer" }
            }
        }
        'Boolean' {
            $valid = $true
            $reason = "✓ ($Value)"
        }
        'Int32' {
            $valid = $true
            $reason = "✓ ($Value)"
        }
        'Int64' {
            $valid = $true
            $reason = "✓ ($Value)"
        }
        'Object[]' {
            $valid = $Value.Count -gt 0
            $reason = if ($valid) { "✓ ($($Value.Count) items)" } else { "leer" }
        }
        'Hashtable' {
            # Verschachtelte Hashtable → rekursiv testen
            return Test-ConfigSection -Path $Path -Section $Value
        }
        default {
            $valid = $Value -ne $null
            $reason = if ($valid) { "✓ ($typeName)" } else { "null" }
        }
    }
    
    if ($valid) {
        $script:passedChecks++
        Write-Host "  $Path : $reason" -ForegroundColor Gray
    } else {
        $script:failedChecks++
        Write-Host "  $Path : ❌ $reason" -ForegroundColor Red
    }
}

function Test-ConfigSection {
    <#
    .SYNOPSIS
        Testet rekursiv eine Config-Section (Hashtable)
    #>
    param(
        [string]$Path,
        [hashtable]$Section
    )
    
    foreach ($key in $Section.Keys) {
        $fullPath = if ($Path) { "$Path.$key" } else { $key }
        $value = $Section[$key]
        
        Test-ConfigValue -Path $fullPath -Value $value
    }
}

Write-Host "`n══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  LIB_CONFIG - FULL VALIDATION" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════`n" -ForegroundColor Cyan

# Lib laden
try {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $DebugDir = Split-Path -Parent $ScriptDir
    $ProjectRoot = Split-Path -Parent $DebugDir
    $libPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"
    
    . $libPath
    Write-OK "Lib_Config.ps1 geladen"
} catch {
    Write-Fail "Fehler: $($_.Exception.Message)"
    exit 1
}

Write-Host ""

#region Test 1: Config laden
Write-Info "TEST 1: Config laden"
try {
    Clear-ConfigCache
    $config = Get-Config
    
    if ($config) {
        Write-OK "Config geladen"
    } else {
        Write-Fail "Config ist leer!"
        exit 1
    }
} catch {
    Write-Fail "Laden fehlgeschlagen: $_"
    exit 1
}
#endregion

Write-Host ""

#region Test 2: Cache funktioniert
Write-Info "TEST 2: Cache Performance"
try {
    Clear-ConfigCache
    
    # 1. Aufruf (von Disk)
    $sw1 = [Diagnostics.Stopwatch]::StartNew()
    $config1 = Get-Config
    $sw1.Stop()
    $time1 = $sw1.Elapsed.TotalMilliseconds
    
    # 2. Aufruf (aus Cache)
    $sw2 = [Diagnostics.Stopwatch]::StartNew()
    $config2 = Get-Config
    $sw2.Stop()
    $time2 = $sw2.Elapsed.TotalMilliseconds
    
    $speedup = [math]::Round($time1 / $time2, 1)
    
    Write-Host "  1. Aufruf (Disk):  $([math]::Round($time1, 2)) ms" -ForegroundColor Gray
    Write-Host "  2. Aufruf (Cache): $([math]::Round($time2, 2)) ms" -ForegroundColor Gray
    
    if ($time2 -lt $time1) {
        Write-OK "Cache funktioniert (${speedup}x schneller)"
    } else {
        Write-Fail "Cache funktioniert NICHT!"
    }
} catch {
    Write-Fail "Test fehlgeschlagen: $_"
}
#endregion

Write-Host ""

#region Test 3: Alle Werte validieren
Write-Info "TEST 3: Validiere ALLE Config-Werte"
Write-Host ""

try {
    $config = Get-Config
    
    # Automatisch alle Bereiche durchlaufen
    foreach ($section in $config.Keys | Sort-Object) {
        Write-Host "${section}:" -ForegroundColor Cyan
        Test-ConfigSection -Path $section -Section $config[$section]
        Write-Host ""
    }
    
} catch {
    Write-Fail "Test fehlgeschlagen: $_"
}
#endregion

#region Zusammenfassung
Write-Host "══════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  ERGEBNIS" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════`n" -ForegroundColor Yellow

Write-Host "Gesamte Parameter: $script:totalChecks" -ForegroundColor Cyan
Write-Host "  Bestanden: $script:passedChecks" -ForegroundColor Green
Write-Host "  Fehlerhaft: $script:failedChecks" -ForegroundColor $(if ($script:failedChecks -gt 0) { 'Red' } else { 'Gray' })

$percentage = if ($script:totalChecks -gt 0) {
    [math]::Round(($script:passedChecks / $script:totalChecks) * 100, 1)
} else {
    0
}

Write-Host "`nErfolgsquote: $percentage%" -ForegroundColor $(if ($percentage -eq 100) { 'Green' } else { 'Yellow' })

$allPassed = ($script:failedChecks -eq 0)

Write-Host "`n══════════════════════════════════════" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
Write-Host "  STATUS: $(if ($allPassed) { 'Alle Tests bestanden ✅' } else { 'Tests fehlgeschlagen ❌' })" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
Write-Host "══════════════════════════════════════`n" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
#endregion