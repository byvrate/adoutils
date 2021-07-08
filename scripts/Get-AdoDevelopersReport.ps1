#Requires -Version 7.0

<#
.Synopsis
    Generates a report to identify all "developers" in an ADO organization. 

.DESCRIPTION
    Generates a report in markdown that outputs all "developers" or 
    more specifically all individuals that pushed commits to all 
    Azure Report in an organization. 

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
    Pushes - List: https://docs.microsoft.com/en-us/rest/api/azure/devops/git/pushes/list?view=azure-devops-rest-6.0

    This script uses a personal access token (PAT), but the type used is a secure string. 
    In order to pass this type in you can to convert the PAT to a secure string. Use this example snippet of script:
    $patss = ConvertTo-SecureString -String "ExamplePAT" -AsPlainText -Force

    This script takes too long to run over a full organiation with many users/projects/repos. It can 
    be tailored for use and it runs but is pretty raw. It's not intended for production used, but 
    merely a tool to gather information in ADO or as a reference. 
#>

[CmdletBinding()]
param ( 
    [Security.SecureString][Parameter(Mandatory=$true)] $Pat,
    [string][Parameter(Mandatory=$true)] $Organization,
    [switch] $Legacy
)

$ErrorActionPreference = "Continue"

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
$graphServer = "vssps.{0}" -f $coreServer

Write-Host "Generating PAT token"
$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $(ConvertFrom-SecureString -SecureString $Pat -AsPlainText)))
$token = [System.Convert]::ToBase64String($encodedPat)
$header = @{authorization = "Basic $token"}

Write-Host "Retrieving all Users in the organization"
$usersUri = "https://{0}/_apis/graph/users?api-version={1}" -f $graphServer, "6.1-preview.1"
$usersResult = Get-RestCallWithContinuationTokenResult -Uri $usersUri -Header $header -ErrorAction Stop

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

# Iterate over every user and find all pushes based on date
Write-Host "Iterating over all users and all repos to determine if user has pushed a commit to any repos"
$fromDate = "{0:s}" -f ((Get-Date).AddDays(-90))
$toDate = Get-Date -format s
$developerCollection = @{}
$i = 0
$userCount = $usersResult.count
$usersResult.value | ForEach-Object {
    $userObject = $_
    $userId = $_.originId

    $reposHashTable.keys | ForEach-Object {
        if (($reposHashTable.Item($_).isValid -eq $false) -or ($reposHashTable.Item($_).error -ne $null)) {
            return
        }

        $repoId = $reposHashTable.Item($_).value.id 
        #$repoObject = $reposHashTable.Item($_).value
        $pushUri = "https://{0}/_apis/git/repositories/{1}/pushes?api-version={2}&searchCriteria.fromDate={3}&searchCriteria.toDate={4}&searchCriteria.pusherId={5}" -f $coreServer, $repoId, "6.1-preview.2", $fromDate, $toDate, $userId

        
        $pushesResult = Invoke-RestMethod -Uri $pushUri -Method Get -ContentType "application/json" -Headers $header
        if ($pushesResult.count -gt 0) {
            $developerCollection[$userId] = $userObject
            Write-Host "user: $userId repo: $repoId :count:$($pushesResult.count)"
            return
        }

        $retries = 0
        $retrycount = 0
        $completed = $false
        while (-not $completed) {
            try {
                $pushesResult = Invoke-RestMethod -Uri $pushUri -Method Get -ContentType "application/json" -Headers $header
                if ($pushesResult.count -gt 0) {
                    $developerCollection[$userId] = $userObject
                    Write-Host "user: $userId repo: $repoId :count:$($pushesResult.count)"
                    return
                }
                $completed = $true
            } catch {
                if ($retrycount -ge $retries) {
                    Write-Host ("Command Invoke-RestMethod failed the maximum number of {0} times." -f $retrycount)
                    Write-Verbose $PSItem.Exception
                    $reposHashTable.Item($repoId).error = $PSItem.Exception
                    $completed = $true
                    throw   # Should not stop the script due to $ErrorActionPreference  is set to "Continue"
                } else {
                    Write-Verbose $_
                    Write-Host "Command Invoke-RestMethod failed for user $($userObject.principalName) for repo $($repoObject.name) in project $($repoObject.project.name). Retrying in 2 seconds."
                    Start-Sleep 1
                    $retrycount++
                }
            }
        }
    }
    Write-Host "User $i of $userCount"
    $i++
}
Write-host "Found results: $($developerCollection.count)"
Write-Host $developerCollection

$userContent = $developerCollection | ConvertTo-Json
New-Item -Path . -Name "users-$((New-Guid).Guid).json" -ItemType "file" -Value $userContent

Write-Output "Completed."
$sw.Stop()
$sw.Elapsed
