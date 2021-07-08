#Requires -Version 7.0

<#
.Synopsis
    Generates a report to identify all "developers" in an ADO organization. 

.DESCRIPTION
    Generates a report in markdown that outputs all "developers" or 
    more specifically all individuals that have committed code in an
    Azure Git repo.

    It clones all repos in an organization and uses the git shortlog
    command to get all the users that have committed code since 1-1-2021

.PARAMETER Pat
    Personal access token as a secure string type.

.PARAMETER Organization
    The Azure DevOps organization.

.PARAMETER Legacy
    Switch to indicate using the legacy REST api 
    such as *.visualstudio.com (un-tested)

.NOTES
    The following reference documentation was used:
    REST API: https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-6.1&viewFallbackFrom=azure-devops
    Work with URLs in extensions and integrations: https://docs.microsoft.com/en-us/azure/devops/extend/develop/work-with-urls?view=azure-devops&tabs=http
    Azure DevOps CLI: https://docs.microsoft.com/en-us/cli/azure/ext/azure-devops/?view=azure-cli-latest
    Git shortlog: https://git-scm.com/docs/git-shortlog

    This script uses a personal access token (PAT) but the type used is a secure string. 
    In order to pass this type in you can to convert the PAT to a secure string. Use this snippet of script:
    $patss = ConvertTo-SecureString -String "ExamplePAT" -AsPlainText -Force

    A shallow clone was tried but that is not supported by ADO. This would have made cloning much faster
    due to not pulling the whole history. 

    The users data is only as good as the develoeprs git config setting for name and email. Most seem
    fine, but there are non org emails.

    This is a very raw script. There is some hardcoding of dates so just use as a reference. 
#>

[CmdletBinding()]
param ( 
    [Security.SecureString][Parameter(Mandatory=$true)] $Pat,
    [string][Parameter(Mandatory=$true)] $Organization,
    [switch] $Legacy
)

Import-Module (Join-Path $PSScriptRoot "/markdownreport/Get-MarkdownReportHelpers.psm1") -DisableNameChecking

$sw = [Diagnostics.Stopwatch]::StartNew()
function Get-RestCallWithContinuationTokenResult 
{
    [CmdletBinding()]
    param 
    (
        [string][Parameter(Mandatory=$true)] $Uri,
        [string] $Method = "Get",
        [Parameter(Mandatory=$true)] $Header
    )

    $result = Invoke-RestMethod -Uri $Uri -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $Header
    $continuationToken = $responseHeaders["X-MS-ContinuationToken"]
    $iterationCount = 0
    $iteationCountLimit = 10
    while ($continuationToken -and $($iterationCount -lt $iteationCountLimit)) {
        $uriWithContinuationToken = $Uri + "&ContinuationToken=$continuationToken"
        $pagedResult = Invoke-RestMethod -Uri $uriWithContinuationToken -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $Header
        if ($pagedResult) {
            $result.value += $pagedResult.value
            $result.count += $pagedResult.count
        }
        $continuationToken = $responseHeaders["X-MS-ContinuationToken"]
        Write-Verbose "Response had $($pagedResult.count)"
        $iterationCount++
    }
    if ($iterationCount -gt ($iteationCountLimit - 1)) {
        Write-Warning "Ran out of retries on finding paged groups. Results may be inaccurate."
    }

    return $result
}

$coreServer = "dev.azure.com/{0}" -f $Organization
if ($Legacy) {
    $coreServer = "{0}.visualstudio.com" -f $Organization
}

Write-Host "Generating PAT token"
$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $(ConvertFrom-SecureString -SecureString $Pat -AsPlainText)))
$token = [System.Convert]::ToBase64String($encodedPat)
$header = @{authorization = "Basic $token"}

Write-Host "Retrieving all Projects in organization"
$projectsUri = "https://{0}/_apis/projects?api-version={1}" -f $coreServer, "6.0"
$projectsResult = Get-RestCallWithContinuationTokenResult -Uri $projectsUri -Header $header -ErrorAction Stop

# Iterate through all projects to get all repos
$reposHashTable = @{}
Write-Host "Retrieving all Azure Repos"

$projectsResult.value | ForEach-Object {
    $projectId = $_.id
    $listRepoUri = "https://{0}/{1}/_apis/git/repositories?api-version={2}" -f $coreServer, $projectId, "6.0"
    $reposResult = Invoke-RestMethod -Uri $listRepoUri -Method Get -ContentType "application/json" -Headers $header
    
    $reposResult.value | ForEach-Object {
        $isEmpty = $_.size -eq 0
        $isDisabled = $_.isDisabled
        $pushUri = "https://{0}/_apis/git/repositories/{1}/pushes?api-version={2}" -f $coreServer, $_.id, "6.1-preview.2"
        $pushesError = $null
        try {
            $pushesResult = Invoke-RestMethod -Uri $pushUri -Method Get -ContentType "application/json" -Headers $header
        } catch {
            $pushesError = $_.Exception
        }
        
        $pushCount = $pushesResult.count
        $isValid = (!$isEmpty -and !$isDisabled -and ($pushCount -gt 0))
        
        $reposHashTable[$_.id] = @{
            value=$_;
            isValid=$isValid;
            error=$pushesError 
        }
    }
}

# Log repos to file
$reposFileContents = $reposHashTable | ConvertTo-Json
New-Item -Path . -Name "repos-$((New-Guid).Guid).json" -ItemType "file" -Value $reposFileContents
$developersArray = @()

$repoCount = $reposHashTable.Count 
$currentRepoIteration = 1
$currentPath = (Get-Location).Path
$reposHashTable.keys | ForEach-Object {
    Write-Host "Cloning $currentRepoIteration of $repoCount"
    $currentRepoIteration++

    if (($reposHashTable.Item($_).isValid -eq $false) -or ($reposHashTable.Item($_).error -ne $null)) {
        return
    }

    New-Item -Path 'c:\' -Name "s" -ItemType "directory"
    Set-Location -Path "C:\s"

    $remoteUrl = $reposHashTable.Item($_).value.remoteUrl 
    git clone $remoteUrl
    Set-Location -Path (Get-ChildItem).Name
    $logResult = (git shortlog --summary --email --all --since="2021-01-01" --format="%aN`t%aE") | ConvertFrom-Csv -Delimiter "`t" -Header ("Number", "Email")
    $emailArray = $logResult | ForEach-Object { $_.Email }
    $developersArray += $emailArray

    Set-Location -Path $currentPath
    # hardcoded path and close to the root since some repos have very deep directories which fails on windows
    Remove-Item -Path "c:\s" -Force -Recurse
}

[array]$uniqueDevelopers = $developersArray | Sort-Object | Get-Unique
$CsvArray = $uniqueDevelopers | Select-Object @{Name='Name';Expression={$_}}
$CsvArray | Export-Csv -Path "outfile.csv" -NoTypeInformation

Write-Output "Completed."
$sw.Stop()
$sw.Elapsed
