#Requires -Version 7.0
Add-Type -AssemblyName System.Windows.Forms

$dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
$dialog.Description = "Ordner mit unsortierten Fotos wählen"
$dialog.ShowNewFolderButton = $false

if ($dialog.ShowDialog() -eq 'OK') {
    $path = $dialog.SelectedPath
    $files = Get-ChildItem -LiteralPath $path -File | Sort-Object Name
    
    $logPath = Join-Path $PSScriptRoot "filenames.log"
    
    $lines = [System.Collections.ArrayList]::new()
    [void]$lines.Add("Ordner: $path")
    [void]$lines.Add("Dateien: $($files.Count)")
    [void]$lines.Add("")
    
    foreach ($f in $files) {
        [void]$lines.Add($f.Name)
    }
    
    $lines | Out-File -LiteralPath $logPath -Encoding UTF8
    
    Write-Host "Fertig: $($files.Count) Dateien -> $logPath" -ForegroundColor Green
} else {
    Write-Host "Abgebrochen." -ForegroundColor Yellow
}