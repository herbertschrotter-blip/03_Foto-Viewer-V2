<#
.SYNOPSIS
    Quick Test für Lib_Http.ps1 - Config-Integration
#>

#Requires -Version 7.0
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$libPath = Join-Path $ProjectRoot "Lib\Core\Lib_Http.ps1"

Write-Host "`n═══ LIB_HTTP - QUICK TEST ═══`n" -ForegroundColor Cyan

# Lib laden
. $libPath

Write-Host "Test 1: Start-HttpListener mit Config" -ForegroundColor Yellow
try {
    $listener = Start-HttpListener -Verbose
    
    Write-Host "✅ Listener gestartet" -ForegroundColor Green
    Write-Host "  Prefixes: $($listener.Prefixes -join ', ')" -ForegroundColor Gray
    
    # Cleanup
    $listener.Stop()
    $listener.Close()
    
    Write-Host "✅ Listener gestoppt" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 2: Start-HttpListener mit Custom Port" -ForegroundColor Yellow
try {
    $listener = Start-HttpListener -Port 9999 -Hostname "localhost" -Verbose
    
    Write-Host "✅ Listener gestartet (Custom)" -ForegroundColor Green
    Write-Host "  Prefixes: $($listener.Prefixes -join ', ')" -ForegroundColor Gray
    
    # Cleanup
    $listener.Stop()
    $listener.Close()
    
    Write-Host "✅ Listener gestoppt" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 3: Get-PowerShellVersionInfo" -ForegroundColor Yellow
try {
    $psInfo = Get-PowerShellVersionInfo
    
    Write-Host "✅ Version Info:" -ForegroundColor Green
    Write-Host "  Version: $($psInfo.Version)" -ForegroundColor Gray
    Write-Host "  DisplayName: $($psInfo.DisplayName)" -ForegroundColor Gray
    Write-Host "  IsPS7: $($psInfo.IsPS7)" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`n═══ TESTS ABGESCHLOSSEN ═══`n" -ForegroundColor Green