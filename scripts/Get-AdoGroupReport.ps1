#Requires -Version 5.1

<#
.Synopsis
    Generates a report in markdown on specific built in ADO groups. 

.DESCRIPTION
    Uses the Azure DevOps REST API to grab data and then aggregate that
    and display the information as a markdown file. 

    The script specifically targets four built in groups:
    - "Project Administrators"
    - "Endpoint Administrators"
    - "Endpoint Creators"
    - "Build Administrators"

    These groups are used to retrieve important metrics at the organization level. That 
    is this script will iterate over all projects in the organization and look for these
    built in groups. However, if these groups are modified and the permissions are altered, 
    consideration must be taken into account.

.PARAMETER Pat
    Personal access token. This is a secure string. 

.PARAMETER Org
    The Azure DevOps organization.

.PARAMETER Legacy
    Switch to indicate using the legacy REST api 
    such as *.visualstudio.com

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
Param ( 
    [Security.SecureString][Parameter(Mandatory=$true)] $Pat,
    [string][Parameter(Mandatory=$true)] $Org,
    [switch] $Legacy
)

$sw = [Diagnostics.Stopwatch]::StartNew()

function New-MDNewLine {
    param (
        [int] $Count = 1
    )
    $newLineSymbol = [System.Environment]::NewLine
    return $newLineSymbol * $Count
}

function New-MDPrimarySection {
    param (
        [string][Parameter(Mandatory=$true)] $Org,
        [int][Parameter(Mandatory=$true)] $TotalProjectCount
    )

    $newSection = "# Azure DevOps Group Membership Report"
    $newSection += New-MDNewLine -Count 2
    $newSection += "- This file was generated: {0}" -f $(Get-Date -AsUTC)
    $newSection += New-MDNewLine
    $newSection += "- Azure DevOps Organization: {0}" -f $Org
    $newSection += New-MDNewLine
    $newSection += "- Number of project in the organization: {0}" -f $TotalProjectCount
    $newSection += New-MDNewLine -Count 2

    return $newSection
}

function New-MDCaveatSection {
    $newSection = "## Caveats"
    $newSection += New-MDNewLine -Count 2
    $newSection += "- The following report queries the default groups, so if any permission modifications are made to these groups, this report won't reflect that."
    $newSection += New-MDNewLine
    $newSection += "- This report doesn't capture organization level groups"
    $newSection += New-MDNewLine
    $newSection += "- This report doesn't list out names of individuals"
    $newSection += New-MDNewLine
    $newSection += "- The following built in project level Azure DevOps groups are included in the report:"
    $newSection += New-MDNewLine
    $newSection += "  - Project Administrators"
    $newSection += New-MDNewLine -Count 2
    $newSection += "  - Endpoint Administrators"
    $newSection += New-MDNewLine -Count 2
    $newSection += "  - Endpoint Creators"
    $newSection += New-MDNewLine -Count 2
    $newSection += "  - Build Administrators"
    $newSection += New-MDNewLine -Count 2

    return $newSection
}

function New-MDOrganizationSummarySection {
    param (
        [int][Parameter(Mandatory=$true)] $TotalProjectCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueProjectAdminCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueEndpointAdminCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueEndpointCreatorCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueBuildAdminCount
    )

    $newSection = "## Organization Summary"
    $newSection += New-MDNewLine -Count 2
    $newSection += "- Total count of projects queried: {0}" -f $TotalProjectCount
    $newSection += New-MDNewLine
    $newSection += "- Total count of unique members the Project Administrators: {0}" -f $TotalUniqueProjectAdminCount
    $newSection += New-MDNewLine
    $newSection += "- Total count of unique members the Endpoint Administrators: {0}" -f $TotalUniqueEndpointAdminCount
    $newSection += New-MDNewLine
    $newSection += "- Total count of unique members the Endpoint Creators: {0}" -f $TotalUniqueEndpointCreatorCount
    $newSection += New-MDNewLine
    $newSection += "- Total count of unique members the Build Administrators: {0}" -f $TotalUniqueBuildAdminCount
    $newSection += New-MDNewLine -Count 2

    return $newSection
}

function New-MDItemizedProjectSection {
    param (
        [System.Array][Parameter(Mandatory=$true)] $Projects
    )

    $newSection = "## Itemized Azure DevOps Projects"
    $newSection += New-MDNewLine -Count 2
    $newSection += "The following is an itemized list of Azure DevOps projects with the groups listed out as well as other metrics."
    $newSection += New-MDNewLine -Count 2
    $newSection += "---" 
    $newSection += New-MDNewLine -Count 2

    $Projects | ForEach-Object { 

        $projectAdminCount = Get-GroupUserCount -ProjectName $_.name -GroupName "Project Administrators"
        $endpointAdminCount = Get-GroupUserCount -ProjectName $_.name -GroupName "Endpoint Administrators"
        $endpointCreatorCount = Get-GroupUserCount -ProjectName $_.name -GroupName "Endpoint Creators"
        $buildAdminCount = Get-GroupUserCount -ProjectName $_.name -GroupName "Build Administrators"

        $newSection += "### {0}" -f $_.name
        $newSection += New-MDNewLine -Count 2
        if ($_.description) {
            $newSection += $_.description
            $newSection += New-MDNewLine -Count 2
        } else {
            $newSection += "_No description available for this project._"
            $newSection += New-MDNewLine -Count 2
        }
        $newSection += "- Id: {0}" -f $_.id
        $newSection += New-MDNewLine
        $newSection += "- Url: [{0}]({0})" -f $_.url
        $newSection += New-MDNewLine
        $newSection += "- Project Administrators user count: {0}" -f $projectAdminCount 
        $newSection += New-MDNewLine
        $newSection += "- Endpoint Administrators user count: {0}"  -f $endpointAdminCount
        $newSection += New-MDNewLine
        $newSection += "- Endpoint Creators user count: {0}" -f $endpointCreatorCount
        $newSection += New-MDNewLine
        $newSection += "- Build Administrators: {0}" -f $buildAdminCount
        $newSection += New-MDNewLine -Count 2
        $newSection += "---" 
        $newSection += New-MDNewLine -Count 2
    }
    return $newSection
}

function Get-GroupUserCount {
    param (
        [string] $ProjectName,
        [string] $GroupName
    )

    $userCount = 0
    # Find the group based on the principleName
    $generatedPrincipleName = "[{0}]\{1}" -f $ProjectName, $GroupName

    [array]$foundGroup = $filteredGroups | Where-Object { $_.principalName -eq $generatedPrincipleName }
    if ($foundGroup.Length -eq 1) {
        $userCount = $foundGroup[0]._users.Count 
    } else {
        Write-Warning "An exact match for group '$GroupName' in project '$ProjectName' was not found"
    }
    return $userCount
}

function Get-GroupUniqueTotalUserCount {
    param (
        [string] $GroupName
    )

    $usersFound = @()

    $filteredGroups | Where-Object { $_.principalName -match $GroupName } | ForEach-Object {
        $usersHashTable = $_._users

        $usersHashTable.Keys | ForEach-Object {
            $value = $usersHashTable.Item($_)
            $usersFound += $value.principalName
        }
    }

    [array]$uniqueUsers = $usersFound | Sort-Object | Get-Unique
    return $uniqueUsers.Length
}

$coreServer = "dev.azure.com/{0}" -f $Org
if ($Legacy) {
    $coreServer = "{0}.visualstudio.com" -f $Org
}
$graphServer = "vssps.{0}" -f $coreServer

Write-Host "Generating PAT token"
$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $(ConvertFrom-SecureString -SecureString $Pat -AsPlainText)))
$token = [System.Convert]::ToBase64String($encodedPat)
$header = @{authorization = "Basic $token"}

Write-Host "Retrieving all Group in org $Org"
$groupsUri = "https://{0}/_apis/graph/groups?api-version={1}" -f $graphServer, "6.1-preview.1"
$groupsResult = Invoke-RestMethod -Uri $groupsUri -Method Get -ContentType "application/json" -Headers $header

Write-Host "Retrieving all Projects in org $Org"
$projectsUri = "https://{0}/_apis/projects?api-version={1}" -f $coreServer, "6.0"
$projectsResult = Invoke-RestMethod -Uri $projectsUri -Method Get -ContentType "application/json" -Headers $header

Write-Host "Retrieving all Users in org $Org"
$usersUri = "https://{0}/_apis/graph/users?api-version={1}" -f $graphServer, "6.1-preview.1"
$usersResult = Invoke-RestMethod -Uri $usersUri -Method Get -ContentType "application/json" -Headers $header

# Filtering / grouping users based on criteria (user type and origin)
$allUsersGroupByOrigin = $usersResult.value | Group-Object -Property origin
$allUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" }
$aadUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "ad" }         # Windows Active Directory
$adUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "aad" }         # Azure Active Directory
$msaUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "msa" }        # Windows Live Account
$vstsUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "vsts" }      # DevOps
$importedUsers = $usersResult.value | Where-Object { $_.subjectKind -eq "user" -and $_.origin -eq "ghb" }   # GitHub

Write-Host "Filtering groups by group name: Endpoint Administrators, Project Administrators, Build Administrators, and Endpoint Creators"
$groupDisplayNameFilter = @("Endpoint Administrators", "Project Administrators", "Build Administrators", "Endpoint Creators")
$filteredGroups = $groupsResult.value | Where-Object {
    ($_.displayName -in $groupDisplayNameFilter)
}

# User Metrics
$totalUsers = $allUsers.count
$totalWindowsActiveDirectoryUsers = $allUsersGroupByOrigin | Where-Object { $_.Name -eq "ad"} | Select-Object -Property Count
$totalAzureActiveDirectoryUsers = $allUsersGroupByOrigin | Where-Object { $_.Name -eq "aad"} | Select-Object -Property Count
$totalMsaUsers = $allUsersGroupByOrigin | Where-Object { $_.Name -eq "msa"} | Select-Object -Property Count
$totalDevOpsUsers = $allUsersGroupByOrigin | Where-Object { $_.Name -eq "vsts"} | Select-Object -Property Count
$totalGitHubUsers = $allUsersGroupByOrigin | Where-Object { $_.Name -eq "ghb"} | Select-Object -Property Count

# Project Metrics
$totalProjectCount = $projectsResult.count

# Iterate through all groups to identify group metrics
Write-Host "Retrieving over all ADO Group memberships"
$filteredGroups | ForEach-Object {
    $users = @{}

    Write-Host "$($_.principalName)"
    $memberShipUri = "https://{0}/_apis/graph/Memberships/{1}?api-version={2}&direction=down" -f $graphServer, $($_.descriptor), "6.1-preview.1"
    $membershipsResult = Invoke-RestMethod -Uri $memberShipUri -Method Get -ContentType "application/json" -Headers $header
    Write-Host "Group memberships found: $($membershipsResult.count)"

    $membershipsResult.value | ForEach-Object {
        # Subject / User Lookup
        Write-Host "Find user based on descriptor: $($_.memberDescriptor)"

        $body= @{
            'lookupKeys' = @(@{'descriptor' = "$($_.memberDescriptor)" })
                } | ConvertTo-Json
        $lookupSubjectUri = "https://{0}/_apis/graph/subjectlookup?api-version={1}" -f $graphServer, "6.1-preview.1"
        $lookupSubjectsResult = Invoke-RestMethod -Uri $lookupSubjectUri -Method Post -ContentType "application/json" -Body $body -Headers $header
        $lookupSubjectValue = $lookupSubjectsResult.value.$($_.memberDescriptor)

        if ($lookupSubjectValue.subjectKind -eq "user") {
            Write-Host $lookupSubjectValue
            $users[$($_.memberDescriptor)] = $lookupSubjectValue
        }
    }

    Write-Host "Found '$($users.count)' user(s) in group '$($_.principalName)'"
    Add-Member -InputObject $_ -NotePropertyName _users -NotePropertyValue $users -Force
}

# Iterate through all projects to get metadata
Write-Host "Retrieving over all ADO projects"
$projectsResult.value | ForEach-Object {
    $projectUri = "https://{0}/_apis/projects/{1}?api-version={2}" -f $coreServer, $($_.id), "6.1-preview.1"
    $projectResult = Invoke-RestMethod -Uri $projectUri -Method Get -ContentType "application/json" -Headers $header
    Write-Host "Retrieved project meta data for $($_.name)"
    Add-Member -InputObject $_ -NotePropertyName _projectmetadata -NotePropertyValue $projectResult -Force
}

# Group Metrics
$totalUniqueProjectAdminCount = Get-GroupUniqueTotalUserCount -GroupName "Project Administrators"
$totalUniqueEndpointAdminCount = Get-GroupUniqueTotalUserCount -GroupName "Endpoint Administrators"
$totalUniqueEndpointCreatorCount = Get-GroupUniqueTotalUserCount -GroupName "Endpoint Creators"
$totalUniqueBuildAdminCount = Get-GroupUniqueTotalUserCount -GroupName "Build Administrators"

$markdown = ""
$markdown += New-MDPrimarySection -Org $Org -TotalProjectCount $totalProjectCount
$markdown += New-MDCaveatSection
$markdown += New-MDOrganizationSummarySection -TotalProjectCount $totalProjectCount -TotalUniqueProjectAdminCount $totalUniqueProjectAdminCount -TotalUniqueEndpointAdminCount $totalUniqueEndpointAdminCount -TotalUniqueEndpointCreatorCount $totalUniqueEndpointCreatorCount -TotalUniqueBuildAdminCount $totalUniqueBuildAdminCount
$markdown += New-MDItemizedProjectSection -Project $($projectsResult.value)

New-Item -Path . -Name "$((New-Guid).Guid).md" -ItemType "file" -Value $markdown

Write-Output "Completed."
$sw.Stop()
$sw.Elapsed
