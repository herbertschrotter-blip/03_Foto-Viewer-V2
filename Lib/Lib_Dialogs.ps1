<#
.SYNOPSIS
    Windows Dialog Funktionen für Foto_Viewer_V2

.DESCRIPTION
    Folder-Browser Dialog mit Windows Forms.

.EXAMPLE
    $folder = Show-FolderDialog -Title "Root wählen"

.NOTES
    Autor: Herbert Schrotter
    Version: 0.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Show-FolderDialog {
    <#
    .SYNOPSIS
        Zeigt Windows Folder-Browser Dialog
    
    .PARAMETER Title
        Dialog-Titel (Default: "Ordner wählen")
    
    .PARAMETER InitialDirectory
        Start-Ordner (Default: Desktop)
    
    .EXAMPLE
        $folder = Show-FolderDialog -Title "Root wählen"
        if ($folder) { Write-Host "Gewählt: $folder" }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Title = "Ordner wählen",
        
        [Parameter()]
        [string]$InitialDirectory = ""
    )
    
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Title
        $dialog.ShowNewFolderButton = $false
        
        # Initial Directory setzen (falls angegeben UND existiert)
        if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory)) {
            $dialog.SelectedPath = $InitialDirectory
        }
        
        $result = $dialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            Write-Verbose "Ordner gewählt: $($dialog.SelectedPath)"
            return $dialog.SelectedPath
        } else {
            Write-Verbose "Dialog abgebrochen"
            return $null
        }
        
    } catch {
        Write-Error "Fehler beim Anzeigen des Folder-Dialogs: $($_.Exception.Message)"
        throw
    }
}