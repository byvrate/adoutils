#Requires -Version 7.0

<#
.Synopsis
    Creates custom log entries of ADO projects data into an Azure Monitor Logs (Log Analytics) workspace. 

.DESCRIPTION
    Uses the data collector API to create a custom log entries in a 
    Azure Monoitor Logs workspace. This data comes from the ADO REST 
    API for projects. It grabs all the Project within a single organization.

.PARAMETER WorkspaceId
    The Workspace ID of the Log Analytics Workspace

.PARAMETER WorkspaceSharedKey
    A workspace key to access the Log Analytics  Workspace

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
    Project - List: https://docs.microsoft.com/en-us/rest/api/azure/devops/core/projects/list?view=azure-devops-rest-6.1

    This script uses a personal access token (PAT) and workspace key but the type used is a secure string. 
    In order to pass this type in you can to convert the PAT to a secure string. Use this snippet of script:
    $patss = ConvertTo-SecureString -String "ExamplePAT" -AsPlainText -Force
#>

[CmdletBinding()]
param ( 
    [string][Parameter(Mandatory=$true)] $WorkspaceId,
    [Security.SecureString][Parameter(Mandatory=$true)] $WorkspaceSharedKey,
    [Security.SecureString][Parameter(Mandatory=$true)] $Pat,
    [string][Parameter(Mandatory=$true)] $Organization,
    [switch] $Legacy
)

# https://docs.microsoft.com/en-us/azure/azure-monitor/logs/log-standard-columns#timegenerated
# Time generated field based on UTC ISO 8601
$TimeStampField = Get-Date ((Get-Date).ToUniversalTime()) -Format "o"
Write-Host "TimeGenerated " + $TimeStampField
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


Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


Function Submit-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $(ConvertFrom-SecureString -SecureString $sharedKey -AsPlainText) `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode
}

$coreServer = "dev.azure.com/{0}" -f $Organization
if ($Legacy) {
    $coreServer = "{0}.visualstudio.com" -f $Organization
}

Write-Host "Generating PAT token"
$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $(ConvertFrom-SecureString -SecureString $Pat -AsPlainText)))
$token = [System.Convert]::ToBase64String($encodedPat)
$header = @{authorization = "Basic $token"}

$apiVersion = "6.1-preview.4"
Write-Host "Retrieving all Projects in organization"
$projectsUri = "https://{0}/_apis/projects?api-version={1}" -f $coreServer, $apiVersion
$projectsResult = Get-RestCallWithContinuationTokenResult -Uri $projectsUri -Header $header -ErrorAction Stop

# Log all JSON data to Log Analytics (Azure Monitor Logs) workspace
# Specify the name of the record type that you'll be creating
$logType = "{0}AdoProjectType" -f $Organization
$jsonValue = $projectsResult.value | ConvertTo-Json -Depth 10
Submit-LogAnalyticsData -customerId $WorkspaceId -sharedKey $WorkspaceSharedKey -body ($jsonValue) -logType $logType
