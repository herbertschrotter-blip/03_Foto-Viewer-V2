<#
.SYNOPSIS
    Quick Test für Lib_FileSystem.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestToolsDir = $ScriptDir  # Klarheit
$DebugDir = Split-Path -Parent $TestToolsDir
$ProjectRoot = Split-Path -Parent $DebugDir
$libPath = Join-Path $ProjectRoot "Lib\Media\Lib_FileSystem.ps1"

Write-Host "`n═══ LIB_FILESYSTEM - QUICK TEST ═══`n" -ForegroundColor Cyan

. $libPath

Write-Host "Test 1: Resolve-SafePath (sicher)" -ForegroundColor Yellow
try {
    $safe = Resolve-SafePath -RootPath "C:\Photos" -RelativePath "subfolder\test.jpg"
    
    if ($safe) {
        Write-Host "✅ Sicherer Pfad: $safe" -ForegroundColor Green
    } else {
        Write-Host "❌ Pfad wurde blockiert" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 2: Resolve-SafePath (Path-Traversal Angriff)" -ForegroundColor Yellow
try {
    $unsafe = Resolve-SafePath -RootPath "C:\Photos" -RelativePath "..\..\..\Windows\System32"
    
    if ($unsafe) {
        Write-Host "❌ SICHERHEITSLÜCKE! Path-Traversal nicht blockiert: $unsafe" -ForegroundColor Red
    } else {
        Write-Host "✅ Path-Traversal korrekt blockiert" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 3: Get-MediaContentType (ALLE aus Config)" -ForegroundColor Yellow
try {
    # Config laden
    $libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"
    . $libConfigPath
    $config = Get-Config
    
    if (-not $config.Media.MimeTypes) {
        Write-Host "❌ Config.Media.MimeTypes nicht gefunden!" -ForegroundColor Red
    } else {
        $totalMimeTypes = $config.Media.MimeTypes.Count
        Write-Host "  Teste $totalMimeTypes MimeTypes aus Config..." -ForegroundColor Cyan
        
        $allOk = $true
        $passed = 0
        $failed = 0
        
        foreach ($ext in $config.Media.MimeTypes.Keys | Sort-Object) {
            $expectedMime = $config.Media.MimeTypes[$ext]
            $testFile = "test$ext"
            $actualMime = Get-MediaContentType -Path $testFile
            
            if ($actualMime -eq $expectedMime) {
                Write-Host "  ✓ $ext → $actualMime" -ForegroundColor Gray
                $passed++
            } else {
                Write-Host "  ✗ $ext → $actualMime (erwartet: $expectedMime)" -ForegroundColor Red
                $allOk = $false
                $failed++
            }
        }
        
        Write-Host ""
        Write-Host "  Ergebnis: $passed/$totalMimeTypes bestanden" -ForegroundColor Cyan
        
        if ($allOk) {
            Write-Host "✅ Alle $totalMimeTypes Content-Types korrekt" -ForegroundColor Green
        } else {
            Write-Host "❌ $failed von $totalMimeTypes fehlgeschlagen" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`nTest 4: Test-IsVideoFile" -ForegroundColor Yellow
try {
    # Config sollte schon geladen sein (von Test 3)
    if (-not $config) {
        $libConfigPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"
        . $libConfigPath
        $config = Get-Config
    }
    
    $videoExts = $config.Media.VideoExtensions
    $imageExts = $config.Media.ImageExtensions
    
    Write-Host "  Prüfe Video-Erkennung gegen Config..." -ForegroundColor Cyan
    
    $allOk = $true
    $passed = 0
    $failed = 0
    
    # Teste: Alle Video-Extensions werden als Video erkannt
    foreach ($ext in $videoExts) {
        $testFile = "test$ext"
        $isVideo = Test-IsVideoFile -Path $testFile
        
        if ($isVideo) {
            $passed++
        } else {
            Write-Host "  ✗ $ext wird NICHT als Video erkannt" -ForegroundColor Red
            $allOk = $false
            $failed++
        }
    }
    
    # Teste: Keine Image-Extensions werden als Video erkannt
    foreach ($ext in $imageExts) {
        $testFile = "test$ext"
        $isVideo = Test-IsVideoFile -Path $testFile
        
        if (-not $isVideo) {
            $passed++
        } else {
            Write-Host "  ✗ $ext wird fälschlich als Video erkannt" -ForegroundColor Red
            $allOk = $false
            $failed++
        }
    }
    
    $totalVideos = $videoExts.Count
    $totalImages = $imageExts.Count
    $totalTests = $totalVideos + $totalImages
    
    if ($allOk) {
        Write-Host "  ✓ Alle $totalVideos Video-Extensions erkannt" -ForegroundColor Gray
        Write-Host "  ✓ Alle $totalImages Image-Extensions korrekt als Foto" -ForegroundColor Gray
        Write-Host "✅ Test-IsVideoFile funktioniert korrekt ($totalTests/$totalTests)" -ForegroundColor Green
    } else {
        Write-Host "❌ $failed von $totalTests Tests fehlgeschlagen" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
}

Write-Host "`n═══ TESTS ABGESCHLOSSEN ═══`n" -ForegroundColor Green