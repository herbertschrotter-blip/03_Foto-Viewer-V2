<#
.SYNOPSIS
    Quick Test für Lib_State.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DebugDir = Split-Path -Parent $ScriptDir
$ProjectRoot = Split-Path -Parent $DebugDir
$libPath = Join-Path $ProjectRoot "Lib\Core\Lib_State.ps1"

Write-Host "`n═══ LIB_STATE - QUICK TEST ═══`n" -ForegroundColor Cyan

# Lib laden
. $libPath

Write-Host "Test 1: Get-EmptyState" -ForegroundColor Yellow
try {
    $emptyState = Get-EmptyState
    
    Write-Host "✅ Empty State erstellt" -ForegroundColor Green
    Write-Host "  RootPath: '$($emptyState.RootPath)'" -ForegroundColor Gray
    Write-Host "  Folders: $($emptyState.Folders.Count) items" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 2: Save-State" -ForegroundColor Yellow
try {
    $testState = [PSCustomObject]@{
        RootPath = "C:\Test\Photos"
        Folders = @(
            @{ Name = "Urlaub"; Path = "C:\Test\Photos\Urlaub" }
        )
    }
    
    Save-State -State $testState -Verbose
    
    Write-Host "✅ State gespeichert" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 3: Get-State (lädt gespeicherten)" -ForegroundColor Yellow
try {
    $loadedState = Get-State -Verbose
    
    Write-Host "✅ State geladen" -ForegroundColor Green
    Write-Host "  RootPath: '$($loadedState.RootPath)'" -ForegroundColor Gray
    Write-Host "  Folders: $($loadedState.Folders.Count) items" -ForegroundColor Gray
    
    # Validierung
    if ($loadedState.RootPath -eq "C:\Test\Photos") {
        Write-Host "  ✓ RootPath korrekt" -ForegroundColor Green
    } else {
        Write-Host "  ✗ RootPath falsch!" -ForegroundColor Red
    }
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`n═══ TESTS ABGESCHLOSSEN ═══`n" -ForegroundColor Green

# Cleanup
Write-Host "Cleanup: state.json löschen? (J/N)" -ForegroundColor Yellow
$answer = Read-Host
if ($answer -eq 'J') {
    $statePath = Join-Path $ProjectRoot "state.json"
    if (Test-Path $statePath) {
        Remove-Item $statePath
        Write-Host "✅ state.json gelöscht" -ForegroundColor Green
    }
}