# Sync domains from ITGlue into UptimeRobot

This project pulls domains from ITGlue, stores them in a SharePoint List, queries the domain to try and detect forwarders, then creates alerts in UptimeRobot for domains that don't have forwarders. The assumption is a domain that forwards is on a different host that we're not likely responsible for.

### Prerequisites

* ITGlue Enterprise licensing
* UptimeRobot account
* It is assumed that you've already created an application in your Azure Active Directory Tenant with permission to work with your SharePoint sites. If you haven't gone through that process, check https://gcits.com/knowledge-base/create-a-sharepoint-application-for-the-microsoft-graph-via-powershell/

```
 This project will work with the a free UptimeRobot account, but the free accounts are limited to 50 domains.
```

### Getting Started

This project can be run manually from powershell ISE, but is being written with the intention of living as an Azure Function to run at regular occurances.

Each script needs to have the appropriate ids, API keys, etc added. SharePointDomainsToURAlerts.ps1 is where you define the account that will receive the alerts.

The scripts need to be run in the following order:

1. SyncITGlueDomainsToSP.sp1
2. SharePointDomainLookup.ps1
3. SharePoinntDomainsToURAlerts.ps1

Please keep in mind that doing the web lookup on the domains may be time consuming. It's possible a long list of domains and/or slower web hosts could make this portion of the script exceed the default 5 minute time limit on Azure Functions.

## Acknowledgments

* Elliot Munro from Gold Coast IT deserves the majority of the credit here, as I basically took his code and played with it like Legos.
* While I didn't actually use any of the code from Cavorter's PSUptimeRobot project (https://github.com/Cavorter/PSUptimeRobot), I wouldn't have been able to understand the UptimeRobot API properly without being able to review how he did it.
