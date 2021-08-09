# https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/classification%20nodes/create%20or%20update?view=azure-devops-rest-6.1
# https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/classification%20nodes/get%20classification%20nodes?view=azure-devops-rest-6.1#get-the-area-tree-with-2-levels-of-children


# Classification Nodes - Get Classification Nodes: https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/classification%20nodes/get%20classification%20nodes?view=azure-devops-rest-6.1
$Uri = 'https://dev.azure.com/byvrate/PortfolioManagement/_apis/wit/classificationnodes?$depth=2&api-version=6.0'


$Method = "POST"

$encodedPat = [System.Text.Encoding]::ASCII.GetBytes($("{0}:{1}" -f "", $Pat))
$token = [System.Convert]::ToBase64String($encodedPat)
$Header = @{authorization = "Basic $token"}
$result = Invoke-RestMethod -Uri $Uri -Method $Method -ResponseHeadersVariable responseHeaders -ContentType "application/json" -Headers $Header

$jsonValue = $result | ConvertTo-Json -Depth 10

$fileName = (New-Guid).Guid + ".json"


Set-Content -Path $fileName -value $jsonValue
Write-Host $result



