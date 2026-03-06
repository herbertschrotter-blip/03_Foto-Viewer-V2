<#
.SYNOPSIS
    Routes Handler fuer Datei-Operationen

.DESCRIPTION
    Behandelt alle Datei-Operations-Routes:
    - /delete-files - Dateien und Ordner loeschen (Papierkorb oder permanent)
    Geplant: /move-files, /flatten-and-move, /sort-by-name

.NOTES
    Autor: Herbert Schrotter
    Version: 0.2.0
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Handle-FileOperationsRoute {
    <#
    .SYNOPSIS
        Behandelt Datei-Operations-Routes

    .DESCRIPTION
        Router fuer alle Datei-Operationen:
        - /delete-files: Loescht Dateien und Ordner (Papierkorb oder permanent)
        Geplant: /move-files, /flatten-and-move, /sort-by-name

    .PARAMETER Context
        HttpListenerContext

    .PARAMETER RootPath
        Root-Pfad fuer Medien

    .PARAMETER Config
        Config-Objekt

    .EXAMPLE
        Handle-FileOperationsRoute -Context $ctx -RootPath $root -Config $config

    .EXAMPLE
        if (Handle-FileOperationsRoute -Context $ctx -RootPath $root -Config $config) { continue }

    .OUTPUTS
        [bool] - $true wenn Route behandelt, $false wenn nicht zustaendig
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $req = $Context.Request
    $res = $Context.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()

    try {
        # Route: /delete-files
        if ($path -eq "/delete-files" -and $req.HttpMethod -eq "POST") {
            try {
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $body = $reader.ReadToEnd()
                $reader.Close()
                $data = $body | ConvertFrom-Json

                $files = @()
                if ($data.PSObject.Properties['files']) { $files = @($data.files) }
                $folders = @()
                if ($data.PSObject.Properties['folders']) { $folders = @($data.folders) }

                if ($files.Count -eq 0 -and $folders.Count -eq 0) {
                    $json = @{ success = $false; error = "Keine Dateien oder Ordner angegeben" } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                    return $true
                }

                $deletedCount = 0
                $errors = @()
                $useRecycleBin = $Config.FileOperations.UseRecycleBin

                # Einzelne Dateien loeschen
                foreach ($relativePath in $files) {
                    $fullPath = Resolve-SafePath -RootPath $RootPath -RelativePath $relativePath
                    if (-not $fullPath -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                        $errors += "Nicht gefunden: $relativePath"
                        continue
                    }

                    try {
                        if ($useRecycleBin) {
                            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
                            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                                $fullPath,
                                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                            )
                        } else {
                            Remove-Item -LiteralPath $fullPath -Force
                        }
                        $deletedCount++
                    } catch {
                        $errors += "Fehler bei $relativePath : $($_.Exception.Message)"
                    }
                }

                # Ganze Ordner loeschen
                foreach ($relativeFolderPath in $folders) {
                    $fullFolderPath = Resolve-SafePath -RootPath $RootPath -RelativePath $relativeFolderPath
                    if (-not $fullFolderPath -or -not (Test-Path -LiteralPath $fullFolderPath -PathType Container)) {
                        $errors += "Ordner nicht gefunden: $relativeFolderPath"
                        continue
                    }

                    try {
                        if ($useRecycleBin) {
                            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
                            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                                $fullFolderPath,
                                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                            )
                        } else {
                            Remove-Item -LiteralPath $fullFolderPath -Recurse -Force
                        }
                        $deletedCount++
                    } catch {
                        $errors += "Fehler bei Ordner $relativeFolderPath : $($_.Exception.Message)"
                    }
                }

                $json = @{
                    success = $true
                    deletedCount = $deletedCount
                    errors = $errors
                } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }

        # Route nicht gefunden in FileOperations
        return $false

    } catch {
        Write-Error "FileOperations Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}