#Requires -Version 7.0

<#
.Synopsis
    Generates a report in markdown on specific built in ADO groups. 

.DESCRIPTION
    Generates a report in Markdown by using the results of the ADO 
    REST API. It uses the results to capture specific organization
    level metrics as well as iterate over all projects. 

    The script specifically targets these built in groups:
    - "Project Administrators"
    - "Endpoint Administrators"
    - "Endpoint Creators"
    - "Build Administrators"

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
    Helpful link for context: https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/data-sources/users

    This script uses a personal access token (PAT) but the type used is a secure string. 
    In order to pass this type in you can to convert the PAT to a secure string. Use this snippet of script:
    ConvertTo-SecureString -String "ExamplePAT" -AsPlainText -Force
#>

[CmdletBinding()]
param ( 
    [Security.SecureString][Parameter(Mandatory=$true)] $Pat,
    [string][Parameter(Mandatory=$true)] $Organization,
    [switch] $Legacy
)

Import-Module (Join-Path $PSScriptRoot "/markdownreport/Get-MarkdownReportHelpers.psm1") -DisableNameChecking

$sw = [Diagnostics.Stopwatch]::StartNew()


function Get-GroupUniqueTotalUserCount 
{
    [CmdletBinding()]
    param 
    (
        [string][Parameter(Mandatory=$true)] $GroupName,
        [Parameter(Mandatory=$true)] $Groups
    )

    [System.Collections.ArrayList]$totalUserInGroup = @()

    $Groups | Where-Object { $_.principalName -match $GroupName } | ForEach-Object {
        Write-Verbose "Found group $_ that matches group name $GroupName"

        # It's assumed that a user collection is hanging off 
        # the _users property that was set in this script
        $intermediateUsers = $_._users
        $totalUserInGroup += $intermediateUsers
    }

    if ($totalUserInGroup.Count -eq 0)
    {
        Write-Warning "There are no users found in group $GroupName"
    }

    # You need to sort first before calling Get-Unique
    [array]$uniqueUsers = $($totalUserInGroup.ToArray()) | Sort-Object | Get-Unique

    return $uniqueUsers.Count
}

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

function Get-UsersInGroup 
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)] $Group
    )

    Write-Host "Getting all unique users in group principle $($Group.principalName)"

    if ($($Group.principalName) -eq "[NFCUDEVTEST]\Project Administrators") {
        Write-Host "Stop here"
    }

    [System.Collections.ArrayList]$userPrincipleNames = @()

    $memberShipUri = "https://{0}/_apis/graph/Memberships/{1}?api-version={2}&direction=down" -f $graphServer, $($Group.descriptor), "6.1-preview.1"

    $retries = 3
    $retrycount = 0
    $completed = $false
    while (-not $completed) {
        try {
            $membershipsResult = Invoke-RestMethod -Uri $memberShipUri -Method Get -ContentType "application/json" -Headers $header
            $completed = $true
        } catch {
            if ($retrycount -ge $retries) {
                Write-Verbose ("Command Invoke-RestMethod failed the maximum number of {0} times." -f $retrycount)
                throw
            } else {
                Write-Verbose "Command Invoke-RestMethod failed. Retrying in 2 seconds."
                Start-Sleep 2
                $retrycount++
            }
        }
    }
    Write-Host "Group memberships found: $($membershipsResult.count)"

    $membershipsResult.value | ForEach-Object {
        # Subject / User Lookup
        Write-Host "`tFind user based on descriptor: $($_.memberDescriptor)"

        $body= @{
            'lookupKeys' = @(@{'descriptor' = "$($_.memberDescriptor)" })
                } | ConvertTo-Json
        $lookupSubjectUri = "https://{0}/_apis/graph/subjectlookup?api-version={1}" -f $graphServer, "6.1-preview.1"

        $retries = 3
        $retrycount = 0
        $completed = $false
        while (-not $completed) {
            try {
                $lookupSubjectsResult = Invoke-RestMethod -Uri $lookupSubjectUri -Method Post -ContentType "application/json" -Body $body -Headers $header
                $completed = $true
            } catch {
                if ($retrycount -ge $retries) {
                    Write-Verbose ("Command Invoke-RestMethod failed the maximum number of {0} times." -f $retrycount)
                    throw
                } else {
                    Write-Verbose "Command Invoke-RestMethod failed. Retrying in 2 seconds."
                    Start-Sleep 2
                    $retrycount++
                }
            }
        }

        $lookupSubjectValue = $lookupSubjectsResult.value.$($_.memberDescriptor)
    
        if ($lookupSubjectValue.subjectKind -eq "user") {
            Write-Verbose "Adding user $($lookupSubjectValue.displayName) to users list"
            $userPrincipleNames.Add($lookupSubjectValue.principalName)
        } elseif ($lookupSubjectValue.subjectKind -eq "group") {
            $foundUserInGroup = $null
            $foundUserInGroup = Get-UsersInGroup -Group $lookupSubjectValue # recursive call
            if ($foundUserInGroup) {
                $foundUserInGroup = $foundUserInGroup[$foundUserInGroup.length - 1]
                $userPrincipleNames += $foundUserInGroup
            }
        } else {
            Write-Warning "{0} is not handled by this script." -f $($lookupSubjectValue.subjectKind)
        }
    }

    [array]$uniqueUsers = $($userPrincipleNames.ToArray()) | Sort-Object | Get-Unique
    return (, $uniqueUsers)
}

function New-MDItemizedProjectSectionAdoPermissionsReport  
{

    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)] $Projects,
        [Parameter(Mandatory=$true)] $FilteredGroups
    )

    $section = "## Itemized Azure DevOps Projects"
    $section += New-MDNewLine -Count 2
    $section += "Itemized list of Azure DevOps projects with the groups metrics."
    $section += New-MDNewLine -Count 2
    $section += "---" 
    $section += New-MDNewLine -Count 2

    $Projects | ForEach-Object { 

        $projectAdminCount = Get-GroupUserCount -ProjectName $_.name -Groups $FilteredGroups  -GroupName "Project Administrators"
        $endpointAdminCount = Get-GroupUserCount -ProjectName $_.name -Groups $FilteredGroups -GroupName "Endpoint Administrators"
        $endpointCreatorCount = Get-GroupUserCount -ProjectName $_.name -Groups $FilteredGroups -GroupName "Endpoint Creators"
        $buildAdminCount = Get-GroupUserCount -ProjectName $_.name -Groups $FilteredGroups -GroupName "Build Administrators"

        $section += "### {0}" -f $_.name
        $section += New-MDNewLine -Count 2
        if ($_.description) {
            $section += "{0} {1}" -f ">", $_.description
            $section += New-MDNewLine -Count 2
        } else {
            $section += "> _No description available for this project._"
            $section += New-MDNewLine -Count 2
        }
        $section += "- Id: {0}" -f $_._projectmetadata.id
        $section += New-MDNewLine
        $section += "- Url: [{0}]({1})" -f $($_._projectmetadata._links.web.href), $($_._projectmetadata._links.web.href.Replace(' ', '%20'))
        $section += New-MDNewLine
        $section += "- Project Administrators user count: {0}" -f $projectAdminCount 
        $section += New-MDNewLine
        $section += "- Endpoint Administrators user count: {0}"  -f $endpointAdminCount
        $section += New-MDNewLine
        $section += "- Endpoint Creators user count: {0}" -f $endpointCreatorCount
        $section += New-MDNewLine
        $section += "- Build Administrators: {0}" -f $buildAdminCount
        $section += New-MDNewLine -Count 2
        $section += "---" 
        $section += New-MDNewLine -Count 2
    }
    return $section
}

function Get-GroupUserCount 
{
    [CmdletBinding()]
    param 
    (
        [string][Parameter(Mandatory=$true)] $ProjectName,
        [Parameter(Mandatory=$true)] $Groups,
        [string][Parameter(Mandatory=$true)] $GroupName
    )

    $userCount = 0
    # Find the group based on the principalName
    $generatedPrincipalName = "[{0}]\{1}" -f $ProjectName, $GroupName
    Write-Verbose "Finding group based on principal name $generatedPrincipalName"
    [array]$foundGroup = $Groups | Where-Object { $_.principalName -eq $generatedPrincipalName }
    Write-Verbose "Found $($foundGroup.length) group(s) based on principle name $generatedPrincipalName"
    if ($foundGroup.Length -eq 1) {
        $userCount = $foundGroup[0]._users.Count 
    } else {
        Write-Warning "An exact match for group '$GroupName' in project '$ProjectName' was not found. A user acount of zero will be returned."
    }
    return $userCount
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

Write-Host "Retrieving all the groups in the organization"
$groupsUri = "https://{0}/_apis/graph/groups?api-version={1}" -f $graphServer, "6.1-preview.1"
$groupsResult = Get-RestCallWithContinuationTokenResult -Uri $groupsUri -Header $header -ErrorAction Stop

Write-Host "Retrieving all Projects in organization"
$projectsUri = "https://{0}/_apis/projects?api-version={1}" -f $coreServer, "6.0"
$projectsResult = Get-RestCallWithContinuationTokenResult -Uri $projectsUri -Header $header -ErrorAction Stop

Write-Host "Retrieving all Users in the organization"
$usersUri = "https://{0}/_apis/graph/users?api-version={1}" -f $graphServer, "6.1-preview.1"
$usersResult = Get-RestCallWithContinuationTokenResult -Uri $usersUri -Header $header -ErrorAction Stop

Write-Host "Filtering / grouping users based on criteria (user type and origin)"
$allUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" }
$aadUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "ad" }         # Windows Active Directory
$adUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "aad" }         # Azure Active Directory
$msaUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "msa" }        # Windows Live Account
$vstsUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "vsts" }      # DevOps
$gitHubUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "ghb" }     # GitHub

Write-Host "Filtering groups by group name: Endpoint Administrators, Project Administrators, Build Administrators, and Endpoint Creators"
$groupDisplayNameFilter = @("Endpoint Administrators", "Project Administrators", "Build Administrators", "Endpoint Creators")
$filteredGroups = $groupsResult.value | Where-Object {
    ($_.displayName -in $groupDisplayNameFilter)
}

# Organization level user metrics
$totalUsers = $allUsers.count
$totalWindowsActiveDirectoryUsers = $adUsers.count ?? 0
$totalAzureActiveDirectoryUsers = $aadUsers.count ?? 0
$totalMsaUsers = $msaUsers.count ?? 0
$totalDevOpsUsers = $vstsUsers.count ?? 0
$totalGitHubUsers = $gitHubUsers.count ?? 0

# Project Metrics
$totalProjectCount = $projectsResult.count

# Iterate through all groups to identify group metrics
Write-Host "Retrieving over all ADO Group memberships"
$filteredGroups | ForEach-Object {
    Write-Host "Get users in group $_"
    $usersInGroupResult = Get-UsersInGroup -Group $_ -ErrorAction Stop
    if ($usersInGroupResult -and $usersInGroupResult.length -gt 0) {
        [array]$usersInGroup = $usersInGroupResult[$usersInGroupResult.length - 1]
        Add-Member -InputObject $_ -NotePropertyName _users -NotePropertyValue $usersInGroup -Force
    }
}

# Iterate through all projects to get metadata
Write-Host "Retrieving all projects to report metadata"
$projectsResult.value | ForEach-Object {
    $projectResult = Invoke-RestMethod -Uri $($_.url) -Method Get -ContentType "application/json" -Headers $header
    Write-Host "Retrieved project meta data for $($_.name)"
    Add-Member -InputObject $_ -NotePropertyName _projectmetadata -NotePropertyValue $projectResult -Force
}

# Group Metrics
$totalUniqueProjectAdminCount = Get-GroupUniqueTotalUserCount -GroupName "Project Administrators" -Groups $filteredGroups
$totalUniqueEndpointAdminCount = Get-GroupUniqueTotalUserCount -GroupName "Endpoint Administrators" -Groups $filteredGroups
$totalUniqueEndpointCreatorCount = Get-GroupUniqueTotalUserCount -GroupName "Endpoint Creators" -Groups $filteredGroups
$totalUniqueBuildAdminCount = Get-GroupUniqueTotalUserCount -GroupName "Build Administrators" -Groups $filteredGroups

$markdown = ""
$markdown += New-MDPrimarySectionAdoPermissionsReport  -Organization $Organization -TotalProjectCount $totalProjectCount
$markdown += New-MDCaveatSectionAdoPermissionsReport
$markdown += New-MDOrganizationSummarySectionAdoGroupAdoPermissionsReport  `
    -TotalUserCount $totalUsers `
    -TotalAadUserCount $totalAzureActiveDirectoryUsers `
    -TotalAdUserCount $totalWindowsActiveDirectoryUsers `
    -TotalLiveAccountUserCount $totalMsaUsers `
    -TotalDevOpsUserCount $totalDevOpsUsers `
    -TotalGitHubUserCount $totalGitHubUsers `
    -TotalProjectCount $totalProjectCount `
    -TotalUniqueProjectAdminCount $totalUniqueProjectAdminCount `
    -TotalUniqueEndpointAdminCount $totalUniqueEndpointAdminCount `
    -TotalUniqueEndpointCreatorCount $totalUniqueEndpointCreatorCount `
    -TotalUniqueBuildAdminCount $totalUniqueBuildAdminCount 

$markdown += New-MDItemizedProjectSectionAdoPermissionsReport -Projects $($projectsResult.value) -FilteredGroups $filteredGroups

New-Item -Path . -Name "$((New-Guid).Guid).md" -ItemType "file" -Value $markdown

Write-Output "Completed."
$sw.Stop()
$sw.Elapsed
