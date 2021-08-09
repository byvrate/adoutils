#Requires -Version 7.0

<#
.Synopsis
    Creates report file on all the projects in an 
    organization by process template. 

.PARAMETER Pat
    Personal access token as a secure string type.

.PARAMETER Organization
    The Azure DevOps organization.

.NOTES
    The following reference documentation was used:
    REST API: https://docs.microsoft.com/en-us/rest/api/azure/devops/core/projects/list?view=azure-devops-rest-6.1
    REST API: https://docs.microsoft.com/en-us/rest/api/azure/devops/core/projects/get?view=azure-devops-rest-6.1

    This script uses a personal access token (PAT), but the type used is a secure string. 
    In order to pass this type in you can to convert the PAT to a secure string. Use this example snippet of script:
    $patss = ConvertTo-SecureString -String "ExamplePAT" -AsPlainText -Force

    This script can be tailored for use and it runs, but is pretty raw. It's not intended for production used, but 
    merely a tool to gather information in ADO or as a reference. 
#>

[CmdletBinding()]
param ( 
    [Security.SecureString][Parameter(Mandatory=$true)] $Pat,
    [string][Parameter(Mandatory=$true)] $Organization
)

$projectListUri = "https://dev.azure.com/{0}/_apis/projects?api-version=6.1-preview.1" -f $Organization
$Method = "GET"
$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $(ConvertFrom-SecureString -SecureString $Pat -AsPlainText)))
$token = [System.Convert]::ToBase64String($encodedPat)
$header = @{authorization = "Basic $token"}

$projectListResult = Invoke-RestMethod -Uri $projectListUri -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $header

$projectArray = [System.Collections.ArrayList]@()

$projectListResult.value | ForEach-Object {
    $projectId = $_.id
    $projectUri = "https://dev.azure.com/{0}/_apis/projects/{1}?api-version=6.1-preview.1&includeCapabilities=true&includeHistory=true" -f $Organization, $projectId
    $projectResult = Invoke-RestMethod -Uri $projectUri -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $header
    $projectArray += $projectResult
}
$groupByTemplateNameResult = $projectArray | Group-Object -Property {$_.capabilities.processTemplate.templateName}

$groupByTemplateNameResultJson = $groupByTemplateNameResult | ConvertTo-Json -Depth 10
$projectArrayJson = projectArray | ConvertTo-Json -Depth 10

$guid = (New-Guid).Guid
$projectListFileName = $guid + "-projectlist" + ".json"
$processGroupFileName = $guid + "-processgroup" + ".json"

Set-Content -Path $projectListFileName -value $projectArrayJson
Set-Content -Path $processGroupFileName -value $groupByTemplateNameResultJson