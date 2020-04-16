﻿param ([String]$solutionsSite = 'oneplacesolutions')
<#
    This script creates a new Site collection ('Team Site (Modern)'), and applies the configuration changes for the OnePlace Solutions site.
    All major actions are logged to 'OPSScriptLog.txt' in the user's or Administrators Documents folder, and it is uploaded to the Solutions Site at the end of provisioning.
#>
$ErrorActionPreference = 'Stop'
$script:logFile = "OPSScriptLog.txt"
$script:logPath = "$env:userprofile\Documents\$script:logFile"

#Set this to $true to deploy to an existing site
$script:forceProvision = $false

#Set this to $true to use only the PnP auth, not SharePoint Online Management Shell
$script:onlyPnP = $false

#Set this to $false to skip automatically creating the site. This will require manual creation of the site prior to running the script
$script:doSiteCreation = $true

Write-Host "Beginning script. Logging script actions to $script:logPath" -ForegroundColor Cyan
Start-Sleep -Seconds 3

Try { 
    Set-ExecutionPolicy Bypass -Scope Process

    function Write-Log { 
        <#
        .NOTES 
            Created by: Jason Wasser @wasserja 
            Modified by: Ashley Gregory
        .LINK (original)
            https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0 
        #>
        [CmdletBinding()] 
        Param ( 
            [Parameter(Mandatory=$true, 
                       ValueFromPipelineByPropertyName=$true)] 
            [ValidateNotNullOrEmpty()] 
            [Alias("LogContent")] 
            [string]$Message, 
 
            [Parameter(Mandatory=$false)] 
            [Alias('LogPath')] 
            [string]$Path = $script:logPath, 
         
            [Parameter(Mandatory=$false)] 
            [ValidateSet("Error","Warn","Info")] 
            [string]$Level = "Info", 
         
            [Parameter(Mandatory=$false)] 
            [switch]$NoClobber 
        ) 
 
        Begin {
            $VerbosePreference = 'SilentlyContinue' 
            $ErrorActionPreference = 'Continue'
        } 
        Process {
            # If the file already exists and NoClobber was specified, do not write to the log. 
            If ((Test-Path $Path) -AND $NoClobber){ 
                Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
                Return 
            } 
 
            # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
            ElseIf (!(Test-Path $Path)){ 
                Write-Verbose "Creating $Path." 
                $NewLogFile = New-Item $Path -Force -ItemType File 
            } 
 
            Else { 
                # Nothing to see here yet. 
            } 
 
            # Format Date for our Log File 
            $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss K" 
 
            # Write message to error, warning, or verbose pipeline and specify $LevelText 
            Switch($Level) { 
                'Error' { 
                    Write-Error $Message 
                    $LevelText = 'ERROR:' 
                 } 
                'Warn' { 
                    Write-Warning $Message 
                    $LevelText = 'WARNING:' 
                 } 
                'Info' { 
                    Write-Verbose $Message 
                    $LevelText = 'INFO:' 
                 } 
            } 
         
            # Write log entry to $Path 
            "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
        }
        End {
            $ErrorActionPreference = 'Stop'
        } 
    }

    function Send-OutlookEmail ($attachment,$body){
        Try{
            #create COM object named Outlook
            $Outlook = New-Object -ComObject Outlook.Application
            #create Outlook MailItem named Mail using CreateItem() method
            $Mail = $Outlook.CreateItem(0)
            #add properties as desired
            $Mail.To = "success@oneplacesolutions.com"
            $Mail.CC = "support@oneplacesolutions.com"
            $from = $Outlook.Session.CurrentUser.Name
            $Mail.Subject = "Solutions Site and License List Information generated by $from"
            $Mail.Body = "Hello Customer Success Team`n`nPlease find our Solutions Site and License List details below:`n`n$body"
    
            $mail.Attachments.Add($attachment) | Out-Null
            Write-Host "Please open the new email being composed in Outlook, add information as necessary, and send it to the address indicated (success@oneplacesolutions.com)" -ForegroundColor Yellow
            $mail.Display()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Outlook) | Out-Null
        }
        Catch{
            Write-Host "Failed to open a new email in Outlook." -ForegroundColor Red
            Write-Log -Level Error -Message $_
        }
    }
    
    function Attempt-Provision ([int]$count){
        #Our first provisioning run can encounter a 403 if SharePoint has incorrectly told us the site is ready, this function will retry 
        Try {
            Apply-PnPProvisioningTemplate -path $Script:TemplatePath -ExcludeHandlers Pages, SiteSecurity
        }
        Catch [System.Net.WebException]{
            If($($_.Exception.Message) -match '(403)'){
                #SPO returning a trigger happy ready response, sleep for a bit...
                $filler = "SharePoint Online incorrectly indicated the site is ready to provision, pausing the script to wait for it to catch up. Retrying in 5 minutes. Retry $count/4"
                Write-Host $filler -ForegroundColor Yellow
                Write-Log -Level Info -Message $filler

                If($count -lt 4){
                    Start-Sleep -Seconds 300
                    $count = $count + 1
                    Attempt-Provision -count $count
                }
                Else{
                    $filler = "SharePoint Online is taking an unusual amount of time to create the site. Please check your SharePoint Admin Site in Office 365, and when the site is created please continue the script. Do not press Enter until you have confirmed the site has been completely created."
                    Write-Host $filler -ForegroundColor Red
                    Write-Log -Level Info -Message $filler
                    Write-Host "`n"
                    Pause
                    Apply-PnPProvisioningTemplate -path $Script:TemplatePath -ExcludeHandlers Pages, SiteSecurity
                }
            }
            Else{
                Throw $_
            }
        }
        Catch {
            Throw $_
        }
    }

    If($solutionsSite -ne 'oneplacesolutions'){
        Write-Log -Level Info -Message "Script has been passed $solutionsSite for the Solutions Site URL"
    }
    Write-Log -Level Info -Message "Logging script actions to $script:logPath"
    Write-Log -Level Info -Message "Forcing provision? $script:forceProvision"
    Write-Log -Level Info -Message "Only PnP Auth? $script:onlyPnP"

    Write-Host "`n--------------------------------------------------------------------------------`n" -ForegroundColor Red
    Write-Host 'Welcome to the Solutions Site deployment script for OnePlace Solutions.' -ForegroundColor Green
    Write-Host "`n--------------------------------------------------------------------------------`n" -ForegroundColor Red
    
    $stage = "Stage 1/3 - Team Site (Modern) creation"
    Write-Host "`n$stage`n" -ForegroundColor Yellow
    Write-Progress -Activity "Solutions Site Deployment" -CurrentOperation $stage -PercentComplete (33)

    $tenant = Read-Host "Please enter the name of your Office 365 Tenant, eg for 'https://contoso.sharepoint.com/' just enter 'contoso'."
    $tenant = $tenant.Trim()
    If($tenant.Length -eq 0){
        Write-Host "No tenant entered. Exiting script."
        Write-Log -Level Error -Message "No tenant entered. Exiting script."
        Exit
    }
    
    $adminSharePoint = "https://$tenant-admin.sharepoint.com"
    $rootSharePoint = "https://$tenant.sharepoint.com"

    Write-Log -Level Info -Message "Tenant set to $tenant"
    Write-Log -Level Info -Message "Admin SharePoint set to $adminSharePoint"
    Write-Log -Level Info -Message "Root SharePoint set to $rootSharePoint"

    If($script:doSiteCreation){
        Try{
            If($script:onlyPnP){
                Connect-PnPOnline -Url $adminSharePoint -UseWebLogin
            }
            Else{
                Connect-SPOService -url $adminSharePoint
                Write-Host "Passing authentication from SharePoint Online Management Shell to SharePoint PnP..."
                Start-Sleep -Seconds 3
                Connect-PnPOnline -Url $adminSharePoint -SPOManagementShell
            }
        }
        Catch{
            $exMessage = $($_.Exception.Message)
            If($exMessage -match "(403)"){
                Write-Log -Level Error -Message $exMessage
                $filler = "Error connecting to '$adminSharePoint'. Please ensure you have sufficient rights to create Site Collections in your Microsoft 365 Tenant. `nThis usually requires Global Administrative rights, or alternatively ask your SharePoint Administrator to perform the Solutions Site Setup."
                Write-Host $filler
                Write-Host "Please contact OnePlace Solutions Support if you are still encountering difficulties."
                Write-Log -Level Info -Message $filler
                Throw $_
            }
        }
    }
    Else{
        $script:onlyPnP = $true
    }
    
    $solutionsSite = $solutionsSite.Trim()
    If ($solutionsSite.Length -eq 0){
        $solutionsSite = Read-Host "Please enter the URL suffix for the Solutions Site you wish to provision, eg to create 'https://contoso.sharepoint.com/sites/oneplacesolutions', just enter 'oneplacesolutions'."
        $solutionsSite = $solutionsSite.Trim()
        If ($solutionsSite.Length -eq 0){
            Write-Host "Can't have an empty URL. Exiting script"
            Write-Log -Level Error -Message "No URL suffix entered. Exiting script."
            Exit
        }
    }
    Write-Log -Level Info -Message "Solutions Site URL suffix set to $solutionsSite"

    $SolutionsSiteUrl = $rootSharePoint + '/sites/' + $solutionsSite
    $LicenseListUrl = $SolutionsSiteUrl + '/lists/Licenses'

    Try {
        If($script:doSiteCreation){
            Try{
                $ownerEmail = Read-Host "Please enter the email address of the owner for this site."
                $ownerEmail = $ownerEmail.Trim()
                If($ownerEmail.Length -eq 0){
                    $filler = 'No Site Collection owner has been entered. Exiting script.'
                    Write-Host $filler
                    Write-Log -Level Error -Message $filler
                    Exit
                }
                #Provisioning the site collection
                $filler = "Creating site collection with URL '$SolutionsSiteUrl' for the Solutions Site, and owner '$ownerEmail'. This may take a while, please do not close this window, but feel free to minimize the PowerShell window and check back in 10 minutes."
                Write-Host $filler -ForegroundColor Yellow
                Write-Log -Level Info -Message $filler

                $timeStartCreate = Get-Date
                $filler = "Starting site creation at $timeStartCreate...."
                Write-Host $filler -ForegroundColor Yellow
                Write-Log -Level Info -Message $filler
                New-PnPTenantSite -Title 'OnePlace Solutions Admin Site' -Url $SolutionsSiteUrl -Template STS#3 -Owner $ownerEmail -Timezone 0 -StorageQuota 110 -Wait
            }
            Catch [Microsoft.SharePoint.Client.ServerException]{
                $exMessage = $($_.Exception.Message)
                If(($exMessage -match 'A site already exists at url') -and ($false -eq $script:forceProvision)){
                    Write-Host $exMessage -ForegroundColor Red
                    Write-Log -Level Error -Message $exMessage
                    If($solutionsSite -ne 'oneplacesolutions'){
                        Write-Host "Site with URL $SolutionsSiteUrl already exists. Please run the script again and choose a different Solutions Site suffix." -ForegroundColor Red
                    }
                    Else{
                        Write-Host "Site with URL $SolutionsSiteUrl already exists. Please contact OnePlace Solutions for further assistance." -ForegroundColor Red
                    }
                    Throw $_
                }
                ElseIf(($exMessage -match 'A site already exists at url') -and $script:forceProvision){
                    $filler = "Force provision has been set to true, site exists and script is continuing."
                    Write-Log -Level Warn -Message $filler
                }
                Else{
                    Throw $_
                }
            }
            Catch{
                Throw $_
            }
            Finally{
                $timeEndCreate = Get-Date
                $timeToCreate = New-TimeSpan -Start $timeStartCreate -End $timeEndCreate
                $filler = "Site Created. Finished at $timeEndCreate. Took $timeToCreate"
                Write-Host "`n"
                Write-Host $filler "`n" -ForegroundColor Green
                Write-Log -Level Info -Message $filler
            }
        }

        $stage = "Stage 2/3 - Apply Solutions Site template"
        Write-Host "`n$stage`n" -ForegroundColor Yellow
        Write-Progress -Activity "Solutions Site Deployment" -CurrentOperation $stage -PercentComplete (66)

        #Connecting to the site collection to apply the template
        If($script:onlyPnP){
            Write-Host  "Please authenticate against the newly created Site Collection"
            Start-Sleep -Seconds 3
            Connect-PnPOnline -Url $SolutionsSiteUrl -UseWebLogin
        }
        Else{
            Connect-PnPOnline -Url $SolutionsSiteUrl -SPOManagementShell
            Start-Sleep -Seconds 3
        }

        #Download OnePlace Solutions Site provisioning template
        $WebClient = New-Object System.Net.WebClient   

        
        $Url = "https://raw.githubusercontent.com/OnePlaceSolutions/OnePlaceLiveSitePnP/master/oneplaceSolutionsSite-template-v3-modern.xml"    
        $Script:TemplatePath = "$env:temp\oneplaceSolutionsSite-template-v3-modern.xml" 

        $filler = "Downloading provisioning xml template to: $Script:TemplatePath"
        Write-Host $filler -ForegroundColor Yellow  
        Write-Log -Level Info -Message $filler
        $WebClient.DownloadFile( $Url, $Script:TemplatePath )
        

        #Download OnePlace Solutions Company logo to be used as Site logo    
        $UrlSiteImage = "https://raw.githubusercontent.com/OnePlaceSolutions/OnePlaceLiveSitePnP/master/oneplacesolutions-logo.png"
        $PathImage = "$env:temp\oneplacesolutions-logo.png" 
        $WebClient.DownloadFile( $UrlSiteImage, $PathImage )
        Write-Log -Level Info -Message "Downloading OPS logo for Solutions Site"
       
        #Apply provisioning xml to new site collection
        $filler = "Applying configuration changes..."
        Write-Host $filler -ForegroundColor Yellow
        Write-Log -Level Info -Message $filler

        Attempt-Provision -count 0

        $licenseList = Get-PnPList -Identity "Licenses"
        $licenseListId = $licenseList.ID
        $licenseListId = $licenseListId.ToString()

        $filler = "Applying Site Security and Page changes separately..."
        Write-Host $filler -ForegroundColor Yellow
        Write-Log -Level Info -Message $filler
        Start-Sleep -Seconds 2															

        Apply-PnPProvisioningTemplate -path $Script:TemplatePath -Handlers SiteSecurity, Pages -Parameters @{"licenseListID"=$licenseListId;"site"=$SolutionsSiteUrl}												  
        
        Try {
            #workaround for a PnP bug
            $addLogo = Add-PnPfile -Path $PathImage -Folder "SiteAssets"
        }
        Catch {
            Throw $_
        }

        $filler = "Provisioning complete!"
        Write-Host $filler -ForeGroundColor Green
        Write-Log -Level Info -Message $filler

        $stage = "Stage 3/3 - License Item creation"
        Write-Host "`n$stage`n" -ForegroundColor Yellow
        Write-Progress -Activity "Solutions Site Deployment" -CurrentOperation $stage -PercentComplete (100)

        $filler = "Creating License Item..."
        Write-Host $filler -ForegroundColor Yellow
        Write-Log -Level Info -Message $filler

        $licenseItemCount = ((Get-PnPListItem -List "Licenses" -Query "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>License</Value></Eq></Where></Query></View>").Count)
        If ($licenseItemCount -eq 0){
            Add-PnPListItem -List "Licenses" -Values @{"Title" = "License"} | Out-Null
            $filler = "License Item created!"
            Write-Host "`n$filler" -ForegroundColor Green
            Write-Log -Level Info -Message $filler
        }
        Else {
            $filler = "License Item not created or is duplicate!"
            Write-Log -Level Warn -Message $filler
        }
    
        Write-Log -Level Info -Message "Solutions Site URL = $SolutionsSiteUrl"
        Write-Log -Level Info -Message "License List URL = $LicenseListUrl"
        Write-Log -Level Info -Message "License List ID = $licenseListId"
        Write-Log -Level Info -Message "Uploading log file to $SolutionsSiteUrl/Shared%20Documents"
    
        Try {
            #workaround for a PnP bug
            $logToSharePoint = Add-PnPfile -Path $script:LogPath -Folder "Shared Documents"
        }
        Catch {
            Throw $_
        }

        Write-Progress -Activity "Completed" -Completed

        Write-Host "`nPlease record the OnePlace Solutions Site URL and License Location / License List URL for usage in the OnePlaceMail Desktop and OnePlaceDocs clients, and the License List Id for the licensing process. " -ForegroundColor Yellow
        Write-Host "`nThese have also been written to a log file at '$script:logPath', and '$SolutionsSiteUrl/Shared%20Documents/$script:logFile'." -ForegroundColor Yellow
        Write-Host "`n-------------------`n" -ForegroundColor Red
    
        $importants = "Solutions Site URL = $SolutionsSiteUrl`nLicense List URL   = $LicenseListUrl`nLicense List ID    = $licenseListId"
        Write-Host $importants

        Write-Host "`n-------------------`n" -ForegroundColor Red
        
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        
        If($false -eq $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
            $input = Read-Host "Would you like to email this information and Log file to OnePlace Solutions now? (yes or no)"
            $input = $input[0]
            If($input -eq 'y'){
                $file = Get-ChildItem $script:logPath
                Send-OutlookEmail -attachment $file.FullName -body $importants
            }
        }
        Else{
            Write-Host "Script is run as Administrator, cannot compose email details. Please email the above information and the log file generated to 'success@oneplacesolutions.com'." -ForegroundColor Yellow
        }
        Write-Host "Opening Solutions Site at $SolutionsSiteUrl..." -ForegroundColor Yellow

        Pause
        Start-Process $SolutionsSiteUrl | Out-Null
    }
    Catch{
        Throw $_
    }

}
Catch {
    $exType = $($_.Exception.GetType().FullName)
    $exMessage = $($_.Exception.Message)
    write-host "`nCaught an exception, further debugging information below:" -ForegroundColor Red
    Write-Log -Level Error -Message "Caught an exception. Exception Type: $exType"
    Write-Log -Level Error -Message $exMessage
    Pause
}
Finally {
    Try{
        Disconnect-PnPOnline
        Disconnect-SPOService
    }
    Catch{}
    Write-Log -Level Info -Message "End of script."
}
