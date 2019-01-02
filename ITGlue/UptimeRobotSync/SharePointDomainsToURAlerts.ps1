<#
This script will evaluate the domains stored in SharePoint and create UptimeRobot monitors for each one that has a matched redirect
The list is called 'ITGlue domains Register'
It should be run on a schedule to keep the UptimeRobot monitors up to date.
#>
 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$client_id = "EnterYourSharePointAppClientIDHere"
$client_secret = "EnterYourSharePointAppClientSecretHere"
$tenant_id = "EnterYourTenantIDHere"
$URAPI = "EnterYourUptimeRobotAPIKeyHere"
$URAlertAddress = 'EmailAlert@Address'
$URAlertName = 'NameOfAlertContact'

$graphBaseUri = "https://graph.microsoft.com/v1.0/"
$siteid = "root"
$ListName = "ITGlue Domain Register"

$URBaseURI = "https://api.uptimerobot.com/v2/"
$URBody = "api_key=$URAPI&format=json"
# AlertType of 2 = email
$URAlertType = '2'

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
 
function Get-SharePointList($ListName) {
    $list = Invoke-RestMethod `
        -Uri "$graphBaseUri/sites/$siteid/lists?expand=columns&`$filter=displayName eq '$ListName'" `
        -Headers $SPHeaders `
        -ContentType "application/json" `
        -Method GET
    $list = $list.value
    return $list
}

function Get-UptimeRobotMonitors {
    $list = Invoke-RestMethod -Method Post -UseBasicParsing -Uri $URBaseURI'getAccountDetails' -Body $URBody -ContentType "application/x-www-form-urlencoded"
    $list = $list.value
    return $list
}

$access_token = Get-AccessToken
$SPHeaders = @{Authorization = "Bearer $access_token"}
 
$monitorsExpected = @()
$list = Get-SharePointList -ListName $ListName

$monitorsExisting = @()

# Check for existing alert contact, creates it missing
$alertContacts = @()
$contactExists = $false
$alertContacts = Invoke-RestMethod -Method Post -UseBasicParsing -Uri $URBaseURI'getAlertContacts' -Body $URBody -ContentType "application/x-www-form-urlencoded"
foreach ($contact in $alertContacts.alert_contacts) {
    if ($contact.friendly_name -match $URAlertname) {
        Write-Output "Contact $($contact.friendly_name) with ID $($contact.id) Exists"
        $alertContactID = $contact.id
        $contactExists = $true
        break
    }
}
If (!$contactExists) {
    $URAlertBody = $URBody +="&friendly_name=$($URAlertName)&type=$($URAlertType)&value=$($URAlertAddress)"
    $createContact = Invoke-RestMethod -Method Post -UseBasicParsing -Uri $URBaseURI'newAlertContact' -Body $URAlertBody -ContentType "application/x-www-form-urlencoded"
    If ($createContact.stat -match "ok") {
        Write-Output "Alert Contact ID $($createContact.alertcontact) created."
        $alertContactID = $createContact.alertcontact
    } else {
        Write-Output "WARNING - Failed to create alert contact."
        break
    }
}

# Pulls the existing list of SharePoint list items
Write-Output "Retrieving existing SharePoint items"
$existingItems = Get-SharePointItem -ListId $list.id
Write-Output "Retrieved $($existingItems.count) existing items"
foreach ($domain in $existingItems) {
    Write-Output "Checking $($domain.fields.title)"
    If ($domain.fields.RedirectMatch -match "True")  {
        $domainInfo = new-object psobject
        $domainInfo | Add-Member -MemberType noteproperty -Name "URL" -Value $domain.fields.title
        $domainInfo | Add-Member -MemberType noteproperty -Name "Owner" -Value $domain.fields.Owner
        $domainInfo | Add-Member -MemberType noteproperty -Name "Redirect" -Value $domain.fields.TrimmedRedirect
        $monitorsExpected += @($domainInfo)
    }
}


# Pulls list of existing monitors
Write-Output "Retrieving existing UptimeRobot monitors"
$monitorsExisting = Invoke-RestMethod -Method Post -UseBasicParsing -Uri $URBaseURI'getMonitors' -Body $URBody -ContentType "application/x-www-form-urlencoded"
$monitorsExisting = $monitorsExisting.monitors
Write-Output $monitorsExisting
Write-Output "Retrieved $($monitorsExisting.count) existing monitors"

# Builds the list of domains with existing monitors 
$ExistingMatches = @()
foreach ($domain in $monitorsExisting.url) {
    foreach ($redirect in $monitorsExpected.Redirect) {
        if ($redirect -match $domain) {
            Write-Output "$($redirect) has matching monitor for $($domain)."
            $ExistingMatches += @($domain)
            break
            }
        }
}

# Creates the list of domains that still require monitors, assigns it a name based on the company name and the domain
$stillneeded = Compare-Object -ReferenceObject $monitorsExpected.redirect -DifferenceObject $ExistingMatches -PassThru
forEach ($domain in $stillneeded) {
    forEach ($Redirect in $monitorsExpected) {
        if ($redirect.redirect -match $domain) {
            $monitorName = $redirect.owner + "-" + $domain
            $monitorBody = $URBody + "&type=1&url=$($domain)&friendly_name=$($monitorName)&alert_contacts=$($alertContactID)_0_0"
            Invoke-RestMethod -Method Post -UseBasicParsing -Uri $URBaseURI'newMonitor' -Body $monitorBody -ContentType "application/x-www-form-urlencoded"
            break
        }
    }
}