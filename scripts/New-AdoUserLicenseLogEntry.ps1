#Requires -Version 7.0

<#
.Synopsis
    Creates custom log entries of ADO end user licenses into an Azure Monitor Logs (Log Analytics) workspace. 

.DESCRIPTION
    Uses the data collector API to create a custom log entries in a 
    Azure Monoitor Logs workspace. This data comes from the ADO REST 
    API for User Entitlements. It grabs all the Repo data within a single project at a time.

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
    User Entitlements - List: https://docs.microsoft.com/en-us/rest/api/azure/devops/memberentitlementmanagement/user-entitlements/list?view=azure-devops-rest-4.1

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
function Get-RestCallResult
{
    [CmdletBinding()]
    param 
    (
        [string][Parameter(Mandatory=$true)] $Uri,
        [string] $Method = "Get",
        [int] $Take = 100,
        [Parameter(Mandatory=$true)] $Header
    )

    $counter = 0
    $skip = 0
    $updatedUri = "{0}&top={1}&skip={2}" -f $Uri, $Take, $skip
    $pagedResult = Invoke-RestMethod -Uri $updatedUri -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $Header
    $result = $pagedResult
    $skip += $Take

    # Log all JSON data to Log Analytics (Azure Monitor Logs) workspace
    # Specify the name of the record type that you'll be creating
    $logType = "{0}AdoUserEntitlementType" -f $Organization
    $jsonValue = $pagedResult.value | ConvertTo-Json -Depth 10
    Submit-LogAnalyticsData -customerId $WorkspaceId -sharedKey $WorkspaceSharedKey -body ($jsonValue) -logType $logType

    while ($pagedResult.count -gt 0) {
        $updatedUri = "{0}&top={1}&skip={2}" -f $uri, $Take, $skip
        $pagedResult = Invoke-RestMethod -Uri $updatedUri -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $Header
        $counter++
        if ($pagedResult) {
            $result.value += $pagedResult.value
            $result.count += $pagedResult.count
        }

        # Log all JSON data to Log Analytics (Azure Monitor Logs) workspace
        # Specify the name of the record type that you'll be creating
        $jsonValue = $pagedResult.value | ConvertTo-Json -Depth 10
        Submit-LogAnalyticsData -customerId $WorkspaceId -sharedKey $WorkspaceSharedKey -body ($jsonValue) -logType $logType


        $skip += $Take
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
    if ($null -eq $body) {
        Write-Host "Skipping log entry. Empty body"
        return
    }

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

    try {
        $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    } catch {
        Write-Host $_
    }
    
    return $response.StatusCode

}

$coreServer = "vsaex.dev.azure.com/{0}" -f $Organization
if ($Legacy) {
    $coreServer = "{0}.visualstudio.com" -f $Organization
}

Write-Host "Generating PAT token"
$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $(ConvertFrom-SecureString -SecureString $Pat -AsPlainText)))
$token = [System.Convert]::ToBase64String($encodedPat)
$header = @{authorization = "Basic $token"}

$apiVersion = "4.1-preview.1"
Write-Host "Retrieving all User Entitlements in organization: $Organization"
$projectsUri = "https://{0}/_apis/userentitlements?api-version={1}" -f $coreServer, $apiVersion
Get-RestCallResult -Uri $projectsUri -Header $header -ErrorAction Stop




