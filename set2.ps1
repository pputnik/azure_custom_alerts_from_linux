Login-AzureRmAccount
Select-AzureRmSubscription -SubscriptionId a0d64279-8ead-4f02-9569-bd8b17322e44  

cd O:\_my\azure\oms\

$RGName = "rg.cybercom.Cloud.Alex_test.OMS2"
$Location = "West Europe"
$VmName = "myVM"

$resourceGroup = Get-AzureRmResourceGroup -Name $RGName -ErrorAction SilentlyContinue
if($resourceGroup)
{
    Write-Host "Resource group '$RGName' exist. Will delete first";
    Remove-AzureRmResourceGroup  -Name $RGName -Force
    Write-Host "Done";
} else {
    Write-Host "Resource group '$resourceGroupName' does not exist.";
}

Write-Host "Creating resource group '$RGName' in location '$Location'";
New-AzureRmResourceGroup -Name $RGName -Location "$Location"

# https://docs.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-powershell

# Create a subnet configuration
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name mySubnet -AddressPrefix 192.168.1.0/24

# Create a virtual network
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $RGName `
-Location "$Location" -Name "myVNET" -AddressPrefix 192.168.0.0/16 -Subnet $subnetConfig
echo ("vnet " + $vnet.ResourceGuid)

# Create a public IP address and specify a DNS name
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $RGName `
-Location "$Location" -AllocationMethod Static -IdleTimeoutInMinutes 4 -Name "oms2$(Get-Random)"
echo ("public ip " + $pip.IpAddress.tostring())

# Create an inbound network security group rule for port 22
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name "myNetworkSecurityGroupRuleSSH"  `
-Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix * -SourcePortRange * `
-DestinationAddressPrefix * -DestinationPortRange 22 -Access "Allow"

# Create an inbound network security group rule for port 80
$nsgRuleWeb = New-AzureRmNetworkSecurityRuleConfig -Name "myNetworkSecurityGroupRuleWWW" `
-Protocol "Tcp" -Direction "Inbound" -Priority 1001 -SourceAddressPrefix * -SourcePortRange * `
-DestinationAddressPrefix * -DestinationPortRange 80 -Access "Allow"

# Create a network security group
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $RGName -Location "$Location" `
-Name "myNetworkSecurityGroup" -SecurityRules $nsgRuleSSH,$nsgRuleWeb
echo ("nsg " + $nsg.ResourceGuid)

# Create a virtual network card and associate with public IP address and NSG
$nic = New-AzureRmNetworkInterface -Name "myNic" -ResourceGroupName $RGName `
-Location "$Location" -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id `
-NetworkSecurityGroupId $nsg.Id
echo ("nic " + $nic.ResourceGuid)

# Define a credential object
$securePassword = ConvertTo-SecureString 'MyV#ryl0ngp@sswOr6' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create a virtual machine configuration
# https://docs.microsoft.com/en-us/powershell/module/azurerm.compute/new-azurermvmconfig?view=azurermps-6.1.0
$vmConfig = New-AzureRmVMConfig -VMName $VmName -VMSize "Standard_B1s" | `
Set-AzureRmVMOperatingSystem -Linux -ComputerName $VmName -Credential $cred `
 | Set-AzureRmVMSourceImage -PublisherName "Canonical" `
-Offer "UbuntuServer" -Skus "16.04-LTS" -Version "latest" | `
Add-AzureRmVMNetworkInterface -Id $nic.Id | Set-AzureRmVMOSDisk -DiskSizeInGB 31 `
-Name ($VmName + "disk") -StorageAccountType "Standard_LRS" -CreateOption fromImage

#-Name "myVMdisk" -StorageAccountType "Standard_LRS" -CreateOption fromImage

# Configure SSH Keys
#$sshPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
$sshPublicKey = Get-Content "C:\_CC\loc\Alex-test.pub"

Add-AzureRmVMSshPublicKey -VM $vmconfig -KeyData $sshPublicKey `
-Path "/home/azureuser/.ssh/authorized_keys"

# Now, combine the previous configuration definitions to create with New-AzureRmVM:
New-AzureRmVM -ResourceGroupName $RGName -Location "$Location" -VM $vmConfig

# https://docs.microsoft.com/en-us/azure/virtual-machines/scripts/virtual-machines-linux-powershell-sample-create-vm-oms?toc=%2fpowershell%2fmodule%2ftoc.json
# ==========================
$WorkSpace = New-AzureRmOperationalInsightsWorkspace -ResourceGroupName $RGName -Name MyOIWorkspace -Location "$Location" -Sku "Standard"
echo $WorkSpace.CustomerId.ToString()
$Keys = Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName  $RGName -Name MyOIWorkspace
echo $Keys.PrimarySharedKey.ToString()

# https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-quick-collect-azurevm
# https://github.com/Microsoft/OMS-Agent-for-Linux/blob/master/docs/Troubleshooting.md
# wget https://raw.githubusercontent.com/Microsoft/OMS-Agent-for-Linux/master/installer/scripts/onboard_agent.sh && sh onboard_agent.sh -w $WorkSpace.CustomerId -s "$Keys.PrimarySharedKey"
# /opt/microsoft/omsagent/bin/service_control restart $WorkSpace.CustomerId
# less /etc/opt/microsoft/omsagent/sysconf/syslog-ng-lad.conf

$url = "https://raw.githubusercontent.com/Microsoft/OMS-Agent-for-Linux/master/installer/scripts/onboard_agent.sh"
$script1 = ("wget $url && sh onboard_agent.sh -w " +$WorkSpace.CustomerId.ToString() + " -s """ +$Keys.PrimarySharedKey.ToString() + """ >> /tmp/automation.log 2>&1 ")
 
az vm run-command invoke -g $RGName -n $VmName --command-id RunShellScript --scripts $script1 

$script2 = ("/opt/microsoft/omsagent/bin/service_control restart " +$WorkSpace.CustomerId.ToString() + " >> /tmp/automation.log 2>&1 ")
az vm run-command invoke -g $RGName -n $VmName --command-id RunShellScript --scripts $script2

$script3 = "echo 'postfix postfix/mailname string your.hostname.com' | debconf-set-selections; echo 'postfix postfix/main_mailer_type string """"Internet Site""""' | debconf-set-selections; /usr/bin/apt-get install postfix mailutils -y"
az vm run-command invoke -g $RGName -n $VmName --command-id RunShellScript --scripts $script3


# ----------------
# https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-powershell-workspace-configuration

$PublicSettings = New-Object psobject | Add-Member -PassThru NoteProperty workspaceId $WorkSpace.CustomerId | ConvertTo-Json
$protectedSettings = New-Object psobject | Add-Member -PassThru NoteProperty workspaceKey $Keys.PrimarySharedKey | ConvertTo-Json

Set-AzureRmVMExtension -ExtensionName "OMS" -ResourceGroupName $RGName -VMName $VmName `
  -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "OmsAgentForLinux" `
  -TypeHandlerVersion 1.0 -SettingString $PublicSettings -ProtectedSettingString $protectedSettings `
  -Location $Location

#Remove-AzureRmVMExtension -ExtensionName "OMS" -ResourceGroupName $RGName -VMName $VmName 

Get-AzureRmPublicIpAddress -ResourceGroupName $RGName | select-object -ExpandProperty IpAddress
# =================================

# https://docs.microsoft.com/en-us/powershell/module/azurerm.operationalinsights/new-azurermoperationalinsightscustomlogdatasource?view=azurermps-6.2.0
# https://blogs.technet.microsoft.com/mohammedabutaleb/2017/10/07/collect-linux-data-using-custom-json-data-source/

# set up pinger to fill log
$script4 = "/usr/bin/wget --no-cache https://raw.githubusercontent.com/pputnik/tmp/master/vmss_monit.sh && /bin/bash -vx vmss_monit.sh >> /tmp/test 2>&1"
az vm run-command invoke -g $RGName -n $VmName --command-id RunShellScript --scripts $script4

# config:    /etc/opt/microsoft/omsagent/afb17e72-YourWorkspaceID-5605127cf18c/conf/omsagent.d/serverdetails.conf
# check log: /var/opt/microsoft/omsagent/afb17e72-YourWorkspaceID-5605127cf18c/log/omsagent.log
# serverdetails_CL  | project todatetime(TimeGenerated) , todouble(key_d)| render timechart  


search * | where ( Type == "var_log_num_log_CL" )
search * | where ( Type == "serverdetails_CL" )
serverdetails_CL | project TimeGenerated, key_d
serverdetails_CL | summarize avg(key_d) by bin(TimeGenerated, 10s)| render timechart


# Perf | where ObjectName == 'Memory' | summarize avg(CounterValue) by Computer, bin(TimeGenerated, 10s) | render timechart
# search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = sum(csBytes) by cIP
#// Oql: Type=W3CIISLog | Measure Sum(csBytes) by cIP // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122

# Alerts: ---------------
serverdetails_CL | summarize AggregatedValue=avg(key_d) by bin(TimeGenerated, 10s) 

# https://docs.microsoft.com/en-us/powershell/module/azurerm.insights/new-azurermalertruleemail?view=azurermps-6.3.0
$newEmailObj = New-AzureRmAlertRuleEmail -CustomEmail "alexander.lutchko@cybercom.com"
echo $newEmailObj 

# https://docs.microsoft.com/en-us/powershell/module/azurerm.insights/add-azurermmetricalertrule?view=azurermps-6.3.0
# https://powershellposse.com/2016/11/18/updating-azure-alert-email/

Add-AzureRmMetricAlertRule -Name PostfixCheck -Location $Location -ResourceGroup $RGName `
-Operator GreaterThan -Threshold 4 -WindowSize 00:00:30 -MetricName "key_d" -Description "Postfix alive" `
-TimeAggregationOperator Average -TargetResourceId $WorkSpace -Action $newEmailObj 

echo $Location
echo $RGName
echo $WorkSpace 


# +++++++ ======= skip that ================================================
Get-AzureRmAlertRule -ResourceGroupName $RGName
Remove-AzureRmAlertRule -ResourceGroupName $RGName -Name PostfixCheck

# https://powershellposse.com/2016/11/18/updating-azure-alert-email/
get-AzureRmResource | Where-Object{$_.resourcetype -like '*alert*'}
get-azureRmalertRule -ResourceGroup $RGName -Name PostfixCheck -DetailedOutput
Get-AzureRmMetric -ResourceId $WorkSpace

# +++++++ ======= / skip that - END ========================================
# +++======= skip that ================================================

after
New-AzureRmOperationalInsightsLinuxSyslogDataSource -ResourceGroupName $RGName `
-WorkspaceName $workspace.Name -Name $VmName -CollectEmergency -CollectAlert -CollectCritical `
-CollectError -CollectWarning -CollectNotice -CollectDebug -CollectInformational `
-Facility "local1"

# Facilities /etc/rsyslog.d/50-default.conf ???

Enable-AzureRmOperationalInsightsLinuxSyslogCollection -ResourceGroupName $RGName `
-WorkspaceName $workspace.Name 

# just to test :
# List all solutions and their installation status
# Get-AzureRmOperationalInsightsIntelligencePacks -ResourceGroupName $RGName `
#-WorkspaceName $workspace.Name

# enable what is needed
$Solutions = "Security", "Updates"

# turn them on
foreach ($solution in $Solutions) {
    Set-AzureRmOperationalInsightsIntelligencePack -ResourceGroupName $RGName -WorkspaceName $workspace.Name -IntelligencePackName $solution -Enabled $true
}

# List enabled solutions
(Get-AzureRmOperationalInsightsIntelligencePacks -ResourceGroupName $RGName -WorkspaceName $workspace.Name).Where({($_.enabled -eq $true)})

# Linux Perf
New-AzureRmOperationalInsightsLinuxPerformanceObjectDataSource -ResourceGroupName $RGName -WorkspaceName $workspace.Name -ObjectName "Logical Disk" -InstanceName "*"  -CounterNames @("% Used Inodes", "Free Megabytes", "% Used Space", "Disk Transfers/sec", "Disk Reads/sec", "Disk Reads/sec", "Disk Writes/sec") -IntervalSeconds 20  -Name "Example Linux Disk Performance Counters"
Enable-AzureRmOperationalInsightsLinuxCustomLogCollection -ResourceGroupName $RGName -WorkspaceName $workspace.Name

# Linux Syslog
New-AzureRmOperationalInsightsLinuxSyslogDataSource -ResourceGroupName $RGName -WorkspaceName $workspace.Name -Facility "kern" -CollectEmergency -CollectAlert -CollectCritical -CollectError -CollectWarning -Name "Example kernal syslog collection"
Enable-AzureRmOperationalInsightsLinuxSyslogCollection -ResourceGroupName $RGName -WorkspaceName $workspace.Name

$CustomLog = @"
{
    "customLogName": "var_log_num_log", 
    "description": "Example custom log datasource", 
    "inputs": [
        { 
            "location": { 
            "fileSystemLocations": { 
                "linuxFileTypeLogPaths": [ "/var/log/num.log" ] 
                } 
            }, 
        "recordDelimiter": { 
            "regexDelimiter": { 
                "pattern": "\\n", 
                "matchIndex": 0, 
                "matchIndexSpecified": true, 
                "numberedGroup": null 
                } 
            } 
        }
    ], 
    "extractions": [
        { 
            "extractionName": "TimeGenerated", 
            "extractionType": "DateTime", 
            "extractionProperties": { 
                "dateTimeExtraction": { 
                    "regex": null, 
                    "joinStringRegex": null 
                    } 
                } 
            }
        ] 
}
"@

# https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-powershell-workspace-configuration
# https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-custom-fields
New-AzureRmOperationalInsightsCustomLogDataSource -ResourceGroupName $RGName `
-WorkspaceName $workspace.Name -Name ($VmName + "CLDsource") -CustomLogRawJson "$CustomLog"
Enable-AzureRmOperationalInsightsLinuxCustomLogCollection -ResourceGroupName $RGName `
-WorkspaceName $workspace.Name



#I think I found the answer, in case someone else might need it:
#"recordDelimiter": {
#              "regexDelimiter": {
#                "matchIndex": 0,
#                "pattern": "(^.*((\\d{2})|(\\d{4}))-([0-1]\\d)-(([0-3]\\d)|(\\d))\\s((\\d)|([0-1]\\d)|(2[0-4])):[0-5][0-9]:[0-5][0-9].*$)"
#              }
#            } 
# +++======= / skip that - END ================================================
