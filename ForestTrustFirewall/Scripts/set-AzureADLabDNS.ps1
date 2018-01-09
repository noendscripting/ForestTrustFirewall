<#
.SYNOPSIS  
 The srcipt sets static IP on deisgnated Domain controller in  lab and configured that IP to be a DNS name resolution adrres

.DESCRIPTION
  The script collects list of all VMs in the provided resource group. Obtaines IP Address of the deisgnated via parameter Domain Controller,
  sets that IP address to Static and then assign the IP as a DNS resolution server to all VMs in the resource group
  DISCLAIMER
    THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  
    We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object
    code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software
    product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the
    Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims
    or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.
    Please note: None of the conditions outlined in the disclaimer above will supersede the terms and conditions contained within
    the Premier Customer Services Description.
 .PARAMETER ResourceGroupName
  Name of the resource group where lab servers reside.

 .PARAMETER Dcname
  Name of the designate Domain Controller
  

  
  .EXAMPLE
   .\set-AzureADLabDNS.ps1 -ResourceGroupName test-dclab -DCName dc1
   Sets static IP adress on Domain controller Dc1 in Resource Group test-dclab and
   sets DC1s IP address as DNS server in all VMs int the Resource Group test-dclab
   
#>

[Cmdletbinding()]          
param(
    [parameter(Mandatory=$true)]     
     $ResourceGroupName,
    [parameter(Mandatory=$true)]
     $DCName 
     )
function Get-NIC ($vMObject) {
    return get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroupName |?{$_.VirtualMachine.id -eq $vMObject.Id -and $_.Primary -eq $true} 
    
}
Function GenerateMenu ([object]$items)
{
    $menu=@{}
    $i=1
     Foreach ($item in $items)
    {
        $menu.Add($i,$item)
        Write-Host "$($i)) $($item)" -ForegroundColor DarkGray
        $i+=1
        
    }
    return $menu
}


$ResourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

$subscriptionName = (Get-AzureRmSubscription -SubscriptionId $ResourceGroup.ResourceId.split("/")[2]).Name
Write-Verbose "Collecting list of VMs from resource group $($ResourceGroupName)"
$labVMs = Get-AzureRmVm -ResourceGroupName $ResourceGroupName
write-host "Displaying VM List"

$labVMs.Name | format-list 



$message = "You selected to make changes to VMs listed above in`nResource Group: $($ResourceGroupName.toUpper())`nsubscription: $($subscriptionName.ToUpper()).`nAll VMs listed above will be updated`nPlease reveiw VM list, Resource Group and Subscription information carefully before proceeding.`nSelect ""yes"" to proceed"
$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes"
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No"
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
$result = $host.ui.PromptForChoice($title, $message, $options, 1) 
switch ($result)
{
   
    1 {
        Write-Output "Operation canceled.Ending script" 
        exit
      }
}

Write-Verbose "Getting NetworkCard information from Dc $($DCName)"
$dcVM = $labVMs |Where-Object{$_.Name -eq $DCName}
$dcNic = Get-NIC -vMObject $dcVM

Write-Verbose "Getting IP Address for DC $($DCname) "
$dcIPAddress = (Get-AzureRmNetworkInterfaceIpConfig -NetworkInterface $dcNic |Where-Object{$_.Primary -eq $true}).PrivateIpAddress
Write-Verbose "Obtained IP Adress for $($DCname). IP Adress = $($dcIPAddress)"


Write-Verbose "Setting DC $($DCname) NIC Ip Allocation to Static"
 ($dcNic.IpConfigurations | Where-Object{$_.Primary -eq $true}).PrivateIpAllocationMethod = "Static"
 $dcNicResult = Set-AzureRmNetworkInterface -NetworkInterface $dcNic
if (($dcNicResult.IpConfigurations | Where-Object{$_.Primary -eq $true}).PrivateIpAllocationMethod -eq "Static")
{
    Write-Verbose "Ip Allocation for $($DCname) is set succesfully"
}
Write-Verbose "Updating DNS settings for the VM in $($ResourceGroupname)"
$result = @()
ForEach($VmEntry in $labVMs)
{
    Write-Verbose "Getting NetworkCard information from VM $($vmEntry.Name)"
    $nicObject = Get-NIC -vMObject $VmEntry

    Write-Verbose "Setting DNS on $($vmEntry.Name) NIC"
    $nicObject.DnsSettings.DnsServers.Add($dcIPAddress)
    $nicResult = Set-AzureRmNetworkInterface -NetworkInterface $nicObject
    if ($nicResult.DnsSettings.AppliedDnsServers -eq $dcIPAddress)
        {
        Write-Verbose "DNS confguration for  $($vmEntry.Name) is set succesfully"
    }
    $item = New-Object psobject -Property @{
        "Name"=$VmEntry.Name
        "IpAddress" = (Get-AzureRmNetworkInterfaceIpConfig -NetworkInterface $nicObject |Where-Object{$_.Primary -eq $true}).PrivateIpAddress
    }
    $result += $item
    Clear-Variable nicObject,nicResult,item
}
Write-Output "Listing VMs Private IP Addresses"
$result | Format-Table
    