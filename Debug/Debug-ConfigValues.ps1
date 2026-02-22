<#
.SYNOPSIS
    Debug Config-Werte - Was kommt wirklich zurück?
#>

#Requires -Version 7.0
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$libPath = Join-Path $ProjectRoot "Lib\Core\Lib_Config.ps1"

. $libPath

$config = Get-Config

Write-Host "`n=== CONFIG DEBUG ===" -ForegroundColor Yellow

Write-Host "`nServer.Port:" -ForegroundColor Cyan
Write-Host "  Wert: $($config.Server.Port)" -ForegroundColor Gray
Write-Host "  Type: $($config.Server.Port.GetType().Name)" -ForegroundColor Gray
Write-Host "  Ist Int? $($config.Server.Port -is [int])" -ForegroundColor Gray

Write-Host "`nVideo.ThumbnailCount:" -ForegroundColor Cyan
Write-Host "  Wert: $($config.Video.ThumbnailCount)" -ForegroundColor Gray
Write-Host "  Type: $($config.Video.ThumbnailCount.GetType().Name)" -ForegroundColor Gray
Write-Host "  Ist Int? $($config.Video.ThumbnailCount -is [int])" -ForegroundColor Gray

Write-Host "`nPerformance.MaxParallelJobs:" -ForegroundColor Cyan
Write-Host "  Wert: $($config.Performance.MaxParallelJobs)" -ForegroundColor Gray
Write-Host "  Type: $($config.Performance.MaxParallelJobs.GetType().Name)" -ForegroundColor Gray
Write-Host "  Ist Int? $($config.Performance.MaxParallelJobs -is [int])" -ForegroundColor Gray

Write-Host "`nUI.Theme:" -ForegroundColor Cyan
Write-Host "  Wert: $($config.UI.Theme)" -ForegroundColor Gray
Write-Host "  Type: $($config.UI.Theme.GetType().Name)" -ForegroundColor Gray
Write-Host "  Ist String? $($config.UI.Theme -is [string])" -ForegroundColor Gray

Write-Host "`nConfig Type:" -ForegroundColor Cyan
Write-Host "  $($config.GetType().Name)" -ForegroundColor Gray