<#
This script will query the domains from your SharePoint Site List and initiate a web request to try and determine that website forwards elsewhere
The list is called 'ITGlue domains Register'
It should be run on a schedule to keep the SharePoint list up to date.
#>
 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$client_id = "EnterYourSharePointAppClientIDHere"
$client_secret = "EnterYourSharePointAppClientSecretHere"
$tenant_id = "EnterYourTenantIDHere"
$graphBaseUri = "https://graph.microsoft.com/v1.0/"
$siteid = "root"
$ListName = "ITGlue Domain Register"

# Number of days before a domain's forwarding should be re-checked
$DaysToCheck = 30

function Get-SharePointItem($ListId, $ItemId) {
 
    if ($ItemId) {
        $listItem = Invoke-RestMethod -Uri $graphBaseUri/sites/$siteid/lists/$listId/items/$ItemId `
            -Method Get -headers $SPHeaders `
            -ContentType application/json
        $cleandomain = $listItem
    }
    else {
        $listItems = $null
        $listItems = Invoke-RestMethod -Uri $graphBaseUri/sites/$siteid/lists/$listId/items?expand=fields `
            -Method Get -headers $SPHeaders `
            -ContentType application/json  
        $cleandomain = @()
        $cleandomain = $listItems.value
        if ($listitems."@odata.nextLink") {
            $nextLink = $true
        }
        if ($nextLink) {
            do {
                $listItems = Invoke-RestMethod -Uri  $listitems."@odata.nextLink"`
                    -Method Get -headers $SPHeaders `
                    -ContentType application/json
                $cleandomain += $listItems.value
                if (!$listitems."@odata.nextLink") {
                    $nextLink = $false
                }
            } until (!$nextLink)
        }
    }
    return $cleandomain
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

function Get-CleanURL($Address) {
    # Strips URL of protocol prefix and www sub domain. Returns the domain and wether the www sub domain was in use
    $pos = $Address.IndexOf(':')
    $cleandomain = $Address.Substring($pos+3)
    $cleandomain = $cleandomain.split('/')[0]
    $cleandomain = $cleandomain.split('\')[0]
    If ($cleandomain.SubString(0,4) -match "www.") {
        $cleandomain = $cleandomain.replace('www.','')
    }
    return $cleandomain
}

function Get-TrimmedURL ($Address) {
    # Removes any trailing / or \ and any direct URL path therafter
    $pos = $address.LastIndexOf('/')
    $trimdomain = $address.Substring(0,$pos)
    return $trimdomain

}
$access_token = Get-AccessToken
$SPHeaders = @{Authorization = "Bearer $access_token"}
 
$domainsToUpdate = @()
$DateThreshold = (get-date).AddDays(-$DaysToCheck).ToString("yyy-MM-dd")
$list = Get-SharePointList -ListName $ListName

# Pulls the existing list of SharePoint list items
Write-Output "Retrieving existing items"
$existingItems = Get-SharePointItem -ListId $list.id
Write-Output "Retrieved $($existingItems.count) existing items"

# Evaluates each domain based on when it was last marked as checked
foreach ($domain in $existingItems) {
    # Checks domain to verify if it is due for a lookup date
    Write-Output "Considering $($domain.fields.title)"
    If (!$domain.fields.LastChecked)  {
        # LastCheked field is Null, assume it needs to be updated
        $domainInfo = new-object psobject
        $domainInfo | Add-Member -MemberType noteproperty -Name "URL" -Value $domain.fields.title
        $domainInfo | Add-Member -MemberType noteproperty -Name "ID" -Value $domain.fields.id
        $domainsToUpdate += @($domainInfo)
    } else {
        $lastUpdated = [datetime]::ParseExact($domain.fields.LastChecked,'yyyy-MM-ddTHH:mm:ssZ',$null)
        If ($lastUpdated -lt $DateThreshold) {
            Write-Output "$($domain.fields.title) last updated over $($DaysToCheck) days ago."
            $domainInfo = new-object psobject
            $domainInfo | Add-Member -MemberType noteproperty -Name "URL" -Value $domain.fields.title
            $domainInfo | Add-Member -MemberType noteproperty -Name "ID" -Value $domain.fields.id
            $domainsToUpdate += $domainInfo
        }
    }
}

# Domain lookup for domains that need updating
Foreach ($lookup in $domainsToUpdate) {
    Write-Output "Requesting $($lookup.URL)"
    $request = $null
    $url = "http://$($lookup.URL)"
    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect=$true
    $redirect = try{
    $response=$request.GetResponse()
    $response.ResponseUri.AbsoluteUri
    $response.Close()
    }
    catch {
    }
    if ($redirect) {
        $cleanRedirect = Get-CleanURL -Address $redirect
        $trimmedRedirect = Get-TrimmedURL -address $redirect
        $domainmatch = If ($lookup.url.equals($cleanRedirect)) {"True"} Else {"False"}
        $domainResults = @{
            "Redirect"          = $redirect
            "TrimmedRedirect"   = $trimmedRedirect
            "RedirectMatch"     = $domainmatch
            "LastChecked"       = (Get-Date).DateTime  
        }
        set-SharepointListItem -ListID $list.id -ItemID $lookup.ID -ItemObject $domainResults
    } Else {
        $domainResults =@{
            "Redirect"          = "None"
            "RedirectMatch"     = "False"
            "LastChecked"       = (Get-Date).DateTime
        }
        set-SharepointListItem -ListID $list.id -ItemID $lookup.ID -ItemObject $domainResults
    }
}