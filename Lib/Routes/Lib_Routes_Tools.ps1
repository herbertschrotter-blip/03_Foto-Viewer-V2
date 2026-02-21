<#
.SYNOPSIS
    Routes Handler für Tools-Menü

.DESCRIPTION
    Behandelt alle /tools/* Routes:
    - /tools/cache-stats - Cache-Statistiken
    - /tools/list-thumbs - Liste aller .thumbs Ordner
    - /tools/delete-selected - Ausgewählte .thumbs löschen
    - /tools/delete-all-thumbs - Alle .thumbs löschen

.NOTES
    Autor: Herbert Schrotter
    Version: 0.3.0
    
    ÄNDERUNGEN v0.3.0:
    - Cache-Rebuild Routes entfernt (/tools/cache/*)
    - Cache wird automatisch bei Änderungen rebuilt
    - Cleanup-Routes bleiben erhalten
    
    ÄNDERUNGEN v0.2.0:
    - /tools/cache/start - Startet Background-Job für Cache-Rebuild
    - /tools/cache/status - Liefert Job-Progress
    - /tools/cache/stop - Stoppt laufenden Job
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

function Handle-ToolsRoute {
    <#
    .SYNOPSIS
        Behandelt alle /tools/* Routes
    
    .PARAMETER Context
        HttpListenerContext
    
    .PARAMETER RootPath
        Root-Pfad für Medien
    
    .EXAMPLE
        Handle-ToolsRoute -Context $ctx -RootPath $root
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    $req = $Context.Request
    $res = $Context.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()
    
    try {
        # Route: /tools/cache-stats
        if ($path -eq "/tools/cache-stats" -and $req.HttpMethod -eq "GET") {
            try {
                $stats = Get-ThumbsCacheStats -RootPath $RootPath
                $json = @{
                    success = $true
                    data = @{
                        ThumbsDirectories = $stats.ThumbsDirectories
                        ThumbnailFiles = $stats.ThumbnailFiles
                        TotalSize = $stats.TotalSize
                        TotalSizeFormatted = $stats.TotalSizeFormatted
                    }
                } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }
        
        # Route: /tools/list-thumbs
        if ($path -eq "/tools/list-thumbs" -and $req.HttpMethod -eq "GET") {
            try {
                $list = Get-ThumbsDirectoriesList -RootPath $RootPath
                $json = @{
                    success = $true
                    data = @($list | ForEach-Object {
                        @{
                            Path = $_.Path
                            RelativePath = $_.RelativePath
                            FileCount = $_.FileCount
                            Size = $_.Size
                            SizeFormatted = $_.SizeFormatted
                        }
                    })
                } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }
        
        # Route: /tools/delete-selected
        if ($path -eq "/tools/delete-selected" -and $req.HttpMethod -eq "POST") {
            try {
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $body = $reader.ReadToEnd()
                $reader.Close()
                $data = $body | ConvertFrom-Json
                $paths = $data.paths
                if (-not $paths -or $paths.Count -eq 0) {
                    $json = @{ success = $false; error = "Keine Pfade" } | ConvertTo-Json -Compress
                    Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
                    return $true
                }
                $result = Remove-SelectedThumbsDirectories -Paths $paths
                $json = @{
                    success = $true
                    data = @{
                        DeletedCount = $result.DeletedCount
                        DeletedSize = $result.DeletedSize
                    }
                } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }
        
        # Route: /tools/delete-all-thumbs
        if ($path -eq "/tools/delete-all-thumbs" -and $req.HttpMethod -eq "POST") {
            try {
                $result = Remove-AllThumbsDirectories -RootPath $RootPath
                $json = @{
                    success = $true
                    data = @{
                        DeletedCount = $result.DeletedCount
                        DeletedSize = $result.DeletedSize
                    }
                } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
                return $true
            } catch {
                $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-ResponseText -Response $res -Text $json -StatusCode 500 -ContentType "application/json; charset=utf-8"
                return $true
            }
        }
        
        # Route nicht gefunden in Tools
        return $false
        
    } catch {
        Write-Error "Tools Route Error: $($_.Exception.Message)"
        Send-ResponseText -Response $res -Text "Error" -StatusCode 500
        return $true
    }
}