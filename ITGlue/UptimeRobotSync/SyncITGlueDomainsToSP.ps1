<#
This script will sync IT Glue domains with a SharePoint list in the root sharepoint site (eg tenantname.sharepoint.com).
The list is called 'ITGlue domains Register'
It should be run on a schedule to keep the SharePoint list up to date.
#>
 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$key = "EnterYourITGlueAPIKeyHere"
$client_id = "EnterYourSharePointAppClientIDHere"
$client_secret = "EnterYourSharePointAppClientSecretHere"
$tenant_id = "EnterYourTenantIDHere"

# Note that EU hosted IT Glue Tenants may need to update the below value to "https://api.eu.itglue.com"
$ITGbaseURI = "https://api.itglue.com"
$headers = @{
    "x-api-key" = $key
}

$graphBaseUri = "https://graph.microsoft.com/v1.0/"
$siteid = "root"
$ListName = "ITGlue Domain Register"

function Get-ITGlueItem($Resource) {
    $array = @()
    $body = Invoke-RestMethod -Method get -Uri "$ITGbaseUri/$Resource" -Headers $headers -ContentType application/vnd.api+json
    $array += $body.data
    if ($body.links.next) {
        do {
            $body = Invoke-RestMethod -Method get -Uri $body.links.next -Headers $headers -ContentType application/vnd.api+json
            $array += $body.data
        } while ($body.links.next)
    }
    return $array
}
 
function New-SharePointColumn($Name, $Type, $Indexed) {
    $column = [ordered]@{
        name    = $Name
        indexed = $Indexed
        $Type   = @{}
    }
    return $column
}
 
function New-SharePointList ($Name, $ColumnCollection) {
    $list = @{
        displayName = $Name
        columns     = $columnCollection
    } | Convertto-json -Depth 10
      
    $newList = Invoke-RestMethod `
        -Uri "$graphBaseUri/sites/$siteid/lists/" `
        -Headers $SPHeaders `
        -ContentType "application/json" `
        -Method POST -Body $list
    return $newList
}
 
function Remove-SharePointList ($ListId) {
    $removeList = Invoke-RestMethod `
        -Uri "$graphBaseUri/sites/$siteid/lists/$ListId" `
        -Headers $SPHeaders `
        -ContentType "application/json" `
        -Method DELETE
    return $removeList
}
 
function Remove-SharePointListItem ($ListId, $ItemId) {
    $removeItem = Invoke-RestMethod `
        -Uri "$graphBaseUri/sites/$siteid/lists/$ListId/items/$ItemId" `
        -Headers $SPHeaders `
        -ContentType "application/json" `
        -Method DELETE
    return $removeItem
}
 
function New-SharePointListItem($ItemObject, $ListId) {
 
    $itemBody = @{
        fields = $ItemObject
    } | ConvertTo-Json -Depth 10
 
    $listItem = Invoke-RestMethod `
        -Uri "$graphBaseUri/sites/$siteid/lists/$listId/items" `
        -Headers $SPHeaders `
        -ContentType "application/json" `
        -Method Post `
        -Body $itemBody
    }
 
function Get-SharePointItem($ListId, $ItemId) {
 
    if ($ItemId) {
        $listItem = Invoke-RestMethod -Uri $graphBaseUri/sites/$siteid/lists/$listId/items/$ItemId `
            -Method Get -headers $SPHeaders `
            -ContentType application/json
        $value = $listItem
    }
    else {
        $listItems = $null
        $listItems = Invoke-RestMethod -Uri $graphBaseUri/sites/$siteid/lists/$listId/items?expand=fields `
            -Method Get -headers $SPHeaders `
            -ContentType application/json  
        $value = @()
        $value = $listItems.value
        if ($listitems."@odata.nextLink") {
            $nextLink = $true
        }
        if ($nextLink) {
            do {
                $listItems = Invoke-RestMethod -Uri  $listitems."@odata.nextLink"`
                    -Method Get -headers $SPHeaders `
                    -ContentType application/json
                $value += $listItems.value
                if (!$listitems."@odata.nextLink") {
                    $nextLink = $false
                }
            } until (!$nextLink)
        }
    }
    return $value
}
 
function Set-SharePointListItem($ListId, $ItemId, $ItemObject) {
    $listItem = Invoke-RestMethod -Uri $graphBaseUri/sites/$siteid/lists/$listId/items/$ItemId/fields `
        -Method Patch -headers $SPHeaders `
        -ContentType application/json `
        -Body ($itemObject | ConvertTo-Json)
    $return = $listItem
}
 
function Get-AccessToken {
    $authority = "https://login.microsoftonline.com/$tenant_id"
    $tokenEndpointUri = "$authority/oauth2/token"
    $resource = "https://graph.microsoft.com"
    $content = "grant_type=client_credentials&client_id=$client_id&client_secret=$client_secret&resource=$resource"
    $response = Invoke-RestMethod -Uri $tokenEndpointUri -Body $content -Method Post -UseBasicParsing
    $access_token = $response.access_token
    return $access_token
}
 
function Get-MSGraphResource($Resource) {
    $graphBaseUri = "https://graph.microsoft.com/v1.0"
    $values = @()
    $result = Invoke-RestMethod -Uri "$graphBaseUri/$resource" -Headers $headers
    $values += $result.value
    if ($result.'@odata.nextLink') {
        do {
            $result = Invoke-RestMethod -Uri $result.'@odata.nextLink' -Headers $headers
            $values += $result.value
        } while ($result.'@odata.nextLink')
    }
    return $values
}
 
function Get-SharePointList($ListName) {
    $list = Invoke-RestMethod `
        -Uri "$graphBaseUri/sites/$siteid/lists?expand=columns&`$filter=displayName eq '$ListName'" `
        -Headers $SPHeaders `
        -ContentType "application/json" `
        -Method GET
    $list = $list.value
    return $list
}
 
$domains = Get-ITGlueItem -Resource domains
 
$access_token = Get-AccessToken
$SPHeaders = @{Authorization = "Bearer $access_token"}

$list = Get-SharePointList -ListName $ListName

# Checks for existing SharePoint list and creates it if necessary
if (!$list) {
    Write-Output "List not found, creating List"
    # Initiate Columns
    $columnCollection = @()
    $columnCollection += New-SharePointColumn -Name Owner -Type text -Indexed $true
    $columnCollection += New-SharePointColumn -Name ITGlueID -Type number -Indexed $true
    $columnCollection += New-SharePointColumn -Name Redirect -Type text -Indexed $true
    $columnCollection += New-SharePointColumn -Name TrimmedRedirect -Type text -Indexed $true
    $columnCollection += New-SharePointColumn -Name RedirectMatch -Type text -Indexed $true
    $columnCollection += New-SharePointColumn -Name LastChecked -Type dateTime -Indexed $true
    $List = New-SharePointList -Name $ListName -ColumnCollection $columnCollection
}
else {
    Write-Output "List Exists, retrieving existing items"
    $existingItems = Get-SharePointItem -ListId $list.id
    Write-Output "Retrieved $($existingItems.count) existing items"
}

# Compares the SharePoint list against the domain list pulled from ITGlue
foreach ($domain in $domains) {
    Write-Output "Checking $($domain.attributes.name)"
    $existingitem = $existingItems | Where-Object {$_.fields.Title -contains $domain.attributes.name}
 
    # if there is no match in SharePoint for the existing domain, create the item and appends it to list of domains that need to be updated
    if (!$existingitem) {
        $item = @{
            "Title"     = $domain.attributes.name
            "Owner"     = $domain.attributes.'organization-name'
            "ITGlueID"  = $domain.id
        }
        Write-Output "Creating $($domain.attributes.name)"
        New-SharePointListItem -ListId $list.id -ItemObject $item
    }
}