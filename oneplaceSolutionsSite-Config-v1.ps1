 <#
        This script prompt creates a new site collection in your Office 365 tenant
        The user is prompted for the SharePoint Site Collection url, Site Owner and TimeZone of the newly created
        Site Collection  
#>

try {    
    Set-ExecutionPolicy Bypass -Scope Process

    #Prompt for SharePoint Url     
    $SharePointUrl = Read-Host -Prompt 'Enter the url of your OnePlaceLive Site Collection'
        
    #Connect to newly created site collection
    Write-Host "Enter SharePoint credentials(email address if SharePoint Online or domain\username if on-premise):" $Path -ForegroundColor Green  
    Connect-pnpOnline -url $SharePointUrl    

    #Download OnePlaceLive site provisioning template
   
    $WebClient = New-Object System.Net.WebClient   
    $Url = "https://raw.githubusercontent.com/OnePlaceSolutions/OnePlaceLiveSitePnP/ColinLiveSite-FixPowershell/oneplaceSolutionsSite-template-v1.xml"    
    $Path = "$env:temp\oneplaceSolutionsSite-template-v1.xml" 
    Write-Host "Downloading provisioning xml template:" $Path -ForegroundColor Green  
    $WebClient.DownloadFile( $Url, $Path ) 

    #Download OnePlace Solutions Company logo to be used as Site logo    
    $UrlSiteImage = "https://raw.githubusercontent.com/OnePlaceSolutions/OnePlaceLiveSitePnP/ColinLiveSite-FixPowershell/oneplacesolutions-logo.png"
    $PathImage = "$env:temp\oneplacesolutions-logo.png" 
    $WebClient.DownloadFile( $UrlSiteImage, $PathImage )
    Write-Host "Downloading site branding:" $PathImage -ForegroundColor Green
       
    #Apply provisioning xml to new site collection
    Write-Host "Applying configuration changes..." -ForegroundColor Green
    Apply-PnPProvisioningTemplate -path $Path    

}
catch {
    Write-Host $error[0].Message
}
