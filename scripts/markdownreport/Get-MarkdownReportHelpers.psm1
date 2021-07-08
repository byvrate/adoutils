#Requires -Version 7.0

# Powershell module for related markdown helper
# functions used to create common operation while creating
# a text based markdown file.
# see: https://en.wikipedia.org/wiki/Markdown

function New-MDNewLine 
{
    <#
    .SYNOPSIS
    Creates a new line character in markdown.
    .DESCRIPTION
    Create a cross platform new line in a Markdown file.
    .PARAMETER Count
    The number of new lines to create. Defaults to one.

    .EXAMPLE
    exampleMarkdown = New-MDNewLine -Count 2
    #>

    [CmdletBinding()]
    param 
    (
        [int] $Count = 1
    )

    $newLineSymbol = [System.Environment]::NewLine
    return $newLineSymbol * $Count
}

function New-MDPrimarySectionAdoPermissionsReport 
{
    <#
    .SYNOPSIS
    Creates primary section for ADO Group report.
    .DESCRIPTION
    Creates a new markdown section targeted at the beginning
    of the report for the Azure DevOps Group and permissions report.
    .PARAMETER Organization
    The Azure DevOps organization.
    .PARAMETER TotalProjectCount
    The total amount of projects in the Azure DevOps organization.

    .EXAMPLE
    exampleMarkdown = New-MDPrimarySectionAdoPermissionsReport -Organization nfcudevlabs -TotalProjectCount 100 
    #>

    [CmdletBinding()]
    param 
    (
        [string][Parameter(Mandatory=$true)] $Organization,
        [int][Parameter(Mandatory=$true)] $TotalProjectCount
    )

    $section = "# Azure DevOps Group Membership Report"
    $section += New-MDNewLine -Count 2
    $section += "- This file was generated on: {0} UTC" -f $(Get-Date -AsUTC)
    $section += New-MDNewLine
    $section += "- Azure DevOps Organization: {0}" -f $Organization
    $section += New-MDNewLine
    $section += "- Number of project in the organization: {0}" -f $TotalProjectCount
    $section += New-MDNewLine -Count 2

    return $section
}

function New-MDCaveatSectionAdoPermissionsReport
{
    <#
    .SYNOPSIS
    Creates the caveat section of ADO group report.
    .DESCRIPTION
    Creates the caveat section of ADO group report. All
    values are hardcoded. 

    .EXAMPLE
    exampleMarkdown = New-MDCaveatSectionAdoPermissionsReport
    #>

    [CmdletBinding()]

    $section = "## Caveats"
    $section += New-MDNewLine -Count 2
    $section += "- The following report queries the default groups, so if any permission modifications are made to these groups, this report won't reflect that."
    $section += New-MDNewLine
    $section += "- This report doesn't capture organization level (collections) groups"
    $section += New-MDNewLine
    $section += "- Not all project contain the Endpoint Creators and Endpoint Administrators groups"
    $section += New-MDNewLine
    $section += "- This report doesn't list names of individuals"
    $section += New-MDNewLine
    $section += "- The following built in project level Azure DevOps groups are included in the report:"
    $section += New-MDNewLine
    $section += "  - Project Administrators"
    $section += New-MDNewLine -Count 2
    $section += "  - Endpoint Administrators"
    $section += New-MDNewLine -Count 2
    $section += "  - Endpoint Creators"
    $section += New-MDNewLine -Count 2
    $section += "  - Build Administrators"
    $section += New-MDNewLine -Count 2

    return $section
}

function New-MDOrganizationSummarySectionAdoGroupAdoPermissionsReport 
{
    <#
    .SYNOPSIS
    Creates ADO summary section.
    .DESCRIPTION
    Creates the ADO organization summary section that contains
    high level metrics accross the organization.
    .PARAMETER TotalUserCount
    Total count of users in the organziation
    .PARAMETER TotalAadUserCount
    The total count of Azure Active Directory users
    .PARAMETER TotalAdUserCount
    The total count of Windows Active Directory users
    .PARAMETER TotalLiveAccountUserCount
    The total count of Windows Live account users
    .PARAMETER TotalGitHubUserCount
    The total count of GitHub users
    .PARAMETER TotalProjectCount
    The total project count
    .PARAMETER TotalUniqueProjectAdminCount
    The total count of unique accounts that belong
    to a Project Administrator group
    .PARAMETER TotalUniqueEndpointAdminCount
    The total count of unique accounts that belong
    to an Endpoint Administrator group
    .PARAMETER TotalUniqueEndpointCreatorCount
    The total count of unique accounts that belong
    to an Endpoint Creator group
    .PARAMETER TotalUniqueBuildAdminCount
    The total count of unique accounts that belong
    to a Build Administrator group

    .EXAMPLE
    exampleMarkdown = New-MDOrganizationSummarySectionAdoGroupAdoPermissionsReport `
        -TotalUserCount 100 `
        -TotalAadUserCount 100 `
        -TotalAdUserCount 100 `
        -TotalLiveAccountUserCount 100 `
        -TotalDevOpsUserCount 100 `
        -TotalProjectCount 100 `
        -TotalGitHubUserCount 100 `
        -TotalUniqueProjectAdminCount 100 `
        -TotalUniqueEndpointAdminCount 100 `
        -TotalUniqueEndpointCreatorCount 100 `
        -TotalUniqueBuildAdminCount 100 `

    #>

    [CmdletBinding()]
    param (
        [int][Parameter(Mandatory=$true)] $TotalUserCount,
        [int][Parameter(Mandatory=$true)] $TotalAadUserCount,
        [int][Parameter(Mandatory=$true)] $TotalAdUserCount,
        [int][Parameter(Mandatory=$true)] $TotalLiveAccountUserCount,
        [int][Parameter(Mandatory=$true)] $TotalDevOpsUserCount,
        [int][Parameter(Mandatory=$true)] $TotalGitHubUserCount,
        [int][Parameter(Mandatory=$true)] $TotalProjectCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueProjectAdminCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueEndpointAdminCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueEndpointCreatorCount,
        [int][Parameter(Mandatory=$true)] $TotalUniqueBuildAdminCount
    )

    $section = "## Organization Summary"
    $section += New-MDNewLine -Count 2
    $section += "- Total projects: {0}" -f $TotalProjectCount
    $section += New-MDNewLine
    $section += "- Total users: {0}" -f $TotalUserCount
    $section += New-MDNewLine
    if ($TotalAadUserCount) {
        $section += "  - Total Azure Active Directy users: {0}" -f $TotalAadUserCount
        $section += New-MDNewLine
    }
    if ($TotalAdUserCount) {
        $section += "  - Total Windows Active Directy users: {0}" -f $TotalAdUserCount
        $section += New-MDNewLine
    }
    if ($TotalLiveAccountUserCount) {
        $section += "  - Total Windows Live Account users: {0}" -f $TotalLiveAccountUserCount
        $section += New-MDNewLine
    }
    if ($TotalDevOpsUserCount) {
        $section += "  - Total DevOps users: {0}" -f $TotalDevOpsUserCount
        $section += New-MDNewLine
    }
    if ($TotalGitHubUserCount) {
        $section += "  - Total GitHub users: {0}" -f $TotalGitHubUserCount
        $section += New-MDNewLine
    }

    $section += "- Total unique members in Project Administrators: {0}" -f $TotalUniqueProjectAdminCount
    $section += New-MDNewLine
    $section += "- Total unique members in Endpoint Administrators: {0}" -f $TotalUniqueEndpointAdminCount
    $section += New-MDNewLine
    $section += "- Total unique members in Endpoint Creators: {0}" -f $TotalUniqueEndpointCreatorCount
    $section += New-MDNewLine
    $section += "- Total unique members in Build Administrators: {0}" -f $TotalUniqueBuildAdminCount
    $section += New-MDNewLine -Count 2

    return $section
}
