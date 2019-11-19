##

<#
.SYNOPSIS
    Sets up Microsoft ADFS Application Groups via PowerShell.
.DESCRIPTION
    This script adds an ADFS Application Group and server and API applications and configures them correctly.
    I got the transform rules and other erratta by creating everything in the ADFS UI and then using GET-ADFSxxxx
    cmdlets to retrieve the correct syntax and content.
.EXAMPLE

.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    This script should be run on the ADFS system.

        ===========================================================================
		 Created by:    Mike Foley
		 Organization:  VMware
		 Blog:          yelof.com
		 Twitter:       @mikefoley
		===========================================================================
#>

#This is the name of your App Server. IP address or FQDN
$appserver = "192.168.1.171"

#This is the name of your application group and will be used as the root name of the application group components and applications.
$ClientRoleIdentifier = "AppServer-ADFS"

# Creates a new GUID for use by the application group
$identifier = (New-Guid).Guid
# The following are the redirect URL's on the app server. These should match the URLs in the UI setup.
$redirect1 = "https://$appserver/userinterface/login"
$redirect2 = "https://$appserver/userinterface/login/oauth2/authcode"

#Create the new Application Group in ADFS
New-AdfsApplicationGroup -Name $ClientRoleIdentifier -ApplicationGroupIdentifier $ClientRoleIdentifier

#Create the ADFS Server Application and generate the client secret.
$ADFSApp = Add-AdfsServerApplication -Name "$ClientRoleIdentifier - Server app" -ApplicationGroupIdentifier $ClientRoleIdentifier -RedirectUri $redirect1,$redirect2  -Identifier $Identifier -GenerateClientSecret

#Create the ADFS Web API application and configure the policy name it should use
Add-AdfsWebApiApplication -ApplicationGroupIdentifier $ClientRoleIdentifier  -Name "App Web API" -Identifier $identifier -AccessControlPolicyName "Permit everyone"

#Grant the ADFS Applciation the allatclaims and openid permissions
Grant-AdfsApplicationPermission -ClientRoleIdentifier $identifier -ServerRoleIdentifier $identifier -ScopeNames @('allatclaims', 'openid')

$transformrule = @"
@RuleTemplate = "LdapClaims"
@RuleName = "AD Groups with Qualified Long Name"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory", types = ("http://schemas.xmlsoap.org/claims/Group"), query = ";tokenGroups(longDomainQualifiedName);{0}", param = c.Value);

@RuleTemplate = "LdapClaims"
@RuleName = "Subject"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory", types = ("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"), query = ";userPrincipalName;{0}", param = c.Value);

@RuleTemplate = "LdapClaims"
@RuleName = "User Principal Name"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory", types = ("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"), query = ";userPrincipalName;{0}", param = c.Value);
"@

#Write out the tranform rules file

$transformrule |Out-File -FilePath .\issueancetransformrules.tmp -force -Encoding ascii

# Name the Web API Application and define its Issuance Transform Rules using an external file. 
Set-AdfsWebApiApplication -Name "$ClientRoleIdentifier - Web API" -TargetIdentifier $identifier -IssuanceTransformRulesFile .\issueancetransformrules.tmp

Write-Output "Please write down and save the following Client Secret: "($ADFSApp.ClientSecret)

$openidurl = (Get-AdfsEndpoint -addresspath "/adfs/.well-known/openid-configuration")

write-output "OpenID URL is: " $openidurl.FullUrl.OriginalString