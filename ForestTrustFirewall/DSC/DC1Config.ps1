Configuration DcConfig
{
	[CmdletBinding()]

	Param
	(
		[string]$NodeName = 'localhost',
		[Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
		[PSCredential]$DomainAdminCredentials,
        [string]$DomainName,
		[string]$NetBiosDomainname,
    	[string]$DataDiskNumber,
		[string]$DataDriveLetter,
		[string]$ForwarderIPaddress,
		[string]$ForwarderDomain

	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration, xActiveDirectory, xStorage, xComputerManagement,xNetworking, xTimeZone
	


	Node $nodeName
	{             
  		LocalConfigurationManager
		{
			ConfigurationMode = 'ApplyAndAutoCorrect'
			RebootNodeIfNeeded = $true
			ActionAfterReboot = 'ContinueConfiguration'
			AllowModuleOverwrite = $true
		}
		xTimeZone TimeZoneExample

        {
			isSingleInstance = 'Yes'
            TimeZone = 'Eastern Standard Time'

        }

		WindowsFeature DNS_RSAT
		{ 
			Ensure = "Present" 
			Name = "RSAT-DNS-Server"
		}

		WindowsFeature ADDS_Install 
		{ 
			Ensure = 'Present' 
			Name = 'AD-Domain-Services' 
		} 

		WindowsFeature RSAT_AD_AdminCenter 
		{
			Ensure = 'Present'
			Name   = 'RSAT-AD-AdminCenter'
		}

		WindowsFeature RSAT_ADDS 
		{
			Ensure = 'Present'
			Name   = 'RSAT-ADDS'
		}

		WindowsFeature RSAT_AD_PowerShell 
		{
			Ensure = 'Present'
			Name   = 'RSAT-AD-PowerShell'
		}

		WindowsFeature RSAT_AD_Tools 
		{
			Ensure = 'Present'
			Name   = 'RSAT-AD-Tools'
		}

		WindowsFeature RSAT_Role_Tools 
		{
			Ensure = 'Present'
			Name   = 'RSAT-Role-Tools'
		}      

		xWaitForDisk Wait_Data_Disk
		{
			DiskNumber = $DataDiskNumber
			RetryCount = 3
			RetryIntervalSec = 60
			DependsOn = '[WindowsFeature]RSAT_Role_Tools'
		}

		xDisk Data_Disk
		{
			DiskNumber = $DataDiskNumber
			DriveLetter = $DataDriveLetter
			AllocationUnitSize = 4096
			DependsOn = '[xWaitforDisk]Wait_Data_Disk'
		}

		xADDomain CreateForest 
		{ 
			DomainName = $DomainName            
			DomainAdministratorCredential = $DomainAdminCredentials
			SafemodeAdministratorPassword = $DomainAdminCredentials
			DomainNetbiosName = $NetBiosDomainname
			DataBasePath = "$($DataDriveLetter):\NTDS"
			LogPath = "$($DataDriveLetter):\NTDS"
			SysvolPath = "$($DataDriveLetter):\SYSVOL"
			DependsOn = '[xDisk]Data_Disk', '[WindowsFeature]ADDS_Install'
		}
	Script SetForwarders
	  {
		  TestScript = 
		  {
			 $result = $null
			 $result = (Get-DnsServerZone -Name $using:ForwarderDomain -ErrorAction SilentlyContinue)
			if ($result -eq $null)
			  {
				  return $false
			  }
			  else
			  {
				  return $true
			  }

		  
		  }
		  GetScript =
		  {
				$TestResult = Test-ADDSDomainControllerInstallation -DomainName $using:domainname -SafeModeAdministratorPassword $using:DomainAdminCredentials.Password -Credential $using:DomainAdminCredentials
				if ($testresult.status -notcontains "Error")
				{
					$results = @{"domain"=$True}
				}
			  else
				{
					$results = @{"domain"=$false}
				}
		      return $results
			}
		  SetScript = 
		  {
			  Add-DnsServerConditionalForwarderZone -MasterServers $using:ForwarderIPaddress -Name $using:ForwarderDomain
		  
		  }
		  Dependson = '[xADDomain]CreateForest'
	  }
	 xWaitForADDomain DscForestWait
        {
            DomainName = $ForwarderDomain
            DomainUserCredential = $DomainAdminCredentials
            DependsOn = '[Script]SetForwarders'
			RetryCount = 4
            RetryIntervalSec = 300
            
        }
		xADDomainTrust SetTrust
		{
			SourceDomainName = $DomainName
			TargetDomainName = $ForwarderDomain
			TargetDomainAdministratorCredential = $DomainAdminCredentials
			TrustType = "Forest"
			TrustDirection = "Bidirectional"
			Dependson = '[xWaitForADDomain]DscForestWait'
		}
		
	}
}