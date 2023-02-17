# Based on Update-Version from https://github.com/shiftkey/chocolatey-beyondcompare

function Parse-ReleaseNotes()
{
    $response = Invoke-WebRequest -Uri https://msdn.microsoft.com/en-us/library/mt588477.aspx

    $html = $response.ParsedHtml

    $mainBody = $html.getElementById('mainBody')
    
    ""

    # find first H3
    foreach ($n in $mainBody.children) {
        if ($n.nodeName -eq "H3") {
            "#### [$($n.innerText)](https://msdn.microsoft.com/en-us/library/mt588477.aspx)"
            ""
            break;
        }
    }

    # find first UL
    $h3count = 0

    foreach ($ul in $mainBody.children) {
        if ($ul.nodeName -eq "UL") {

            foreach ($li in $ul.children)
            {
                # linebreaks
               $li.getElementsByTagName("BR") | ForEach-Object {
                    $mdText = $html.createTextNode("  `n")

                    [void] $_.replaceNode($mdText)
                }

                # process hyperlinks
                $li.getElementsByTagName("A") | ForEach-Object {
                    $mdText = $html.createTextNode("[$($_.innerText)]($($_.href))")

                    [void] $_.replaceNode($mdText)
                }

                # emphasis
                $li.getElementsByTagName("EM") | ForEach-Object {
                    $mdText = $html.createTextNode("*$($_.innerText)*")

                    [void] $_.replaceNode($mdText)
                }

                "* " + $li.innerText.Replace("#", "\#").Trim()

            }            
        }
        # stop when we find the next heading
        elseif ($ul.nodeName -eq "H3") {
            $h3count++

            if ($h3count -eq 2) {
                break
            }
        }
    }

    ""            

}

function Update-Version
{
   $response = Invoke-WebRequest -Uri "https://msdn.microsoft.com/en-US/library/mt238290.aspx"
   $content = $response.Content

   # The version number for this latest preview is: 13.0.12000.65
   $isMatch = $content -match "(The version number)|(The build number for this release).*: (?<version>\d+\.\d+\.\d+\.\d+)"

   if ($isMatch)
   {
        $version = $matches.version

        Write-Host "Found version $version"

        $releaseNotes = (Parse-ReleaseNotes) -join "`n"

        $nuspec = Join-Path $PSScriptRoot "src/sql-server-management-studio.nuspec"
        $contents = [xml] (Get-Content $nuspec -Encoding Utf8)

        $contents.package.metadata.version = "$version"
        $contents.package.metadata.releaseNotes = $releaseNotes

        $contents.Save($nuspec)

        # Reprocess file to make line-endings consistent
        (Get-Content $nuspec -Encoding UTF8) | Set-Content $nuspec -Encoding UTF8

        Write-Host
        Write-Host "Updated nuspec, commit this change and open a pull request to the upstream repository on GitHub!"

   }
   else
   {
        Write-Host "Unable to find the release on the download page. Check the regex above"
   }

   $isMatch = $content -match '\<a href\=\"(?<url>https://([\w+?\.\w+])+([a-zA-Z0-9\~\!\@\#\$\%\^\&\*\(\)_\-\=\+\\\/\?\.\:\;\''\,]*))\"\>Download SQL Server Management Studio'

   if ($isMatch)
   {
        $installScript = Join-Path $PSScriptRoot "src/tools/chocolateyInstall.ps1"
        $contents = Get-Content $installScript -Encoding Utf8

        # Find actual download URL
        $request = Invoke-WebRequest -Uri $($Matches.url) -MaximumRedirection 0 -ErrorAction Ignore
 
        if($request.StatusCode -lt 400)
        {
            # $url        = 'http://download.microsoft.com/download/E/E/1/EE12CC0F-A1A5-4B55-9425-2AFBB2D63979/SSMS-Full-Setup.exe'

            $location = [UriBuilder] $request.Headers.Location

            # Switch to https
            $location.Scheme = "https"
            $location.Port = 443

            $newContents = $contents -replace "\`$url\s*=\s*['`"]http.+['`"]", "`$url = '$($location.Uri.ToString())'"

            Write-Host "Downloading $($location.Uri)"

            $tempFile = New-TemporaryFile

            Invoke-WebRequest -Uri $location.Uri -OutFile $tempFile

            $hash = Get-FileHash $tempFile -Algorithm SHA256

            #$tempFile.Delete()
            Write-Host "Delete $tempFile if no longer required"

            #   checksum      = '34843BEB2A42D5BDE4822027B9619851'
            $newContents = $newContents -replace "checksum\s*=\s*'[a-fA-F0-9]+'", "checksum      = '$($hash.Hash)'"

            $newContents | Out-File $installScript -Encoding Utf8

            Write-Host
            Write-Host "Updated install script. Manually update 'softwareName', commit this change and open a pull request to the upstream repository on GitHub!"
            
        }

    }
   else
   {
       Write-Host "Unable to find the download link on the download page. Check the regex above"
   }

}

Update-Version

