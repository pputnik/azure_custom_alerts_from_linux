Login-AzureRmAccount
Get-AzureRmSubscription
Select-AzureRmSubscription -SubscriptionId a0d64279-8ead-4f02-9569-bd8b17322e44  

cd O:\_my\azure\oms\
#Find-AzureRmResourceGroup
$RGName = "rg.cybercom.Cloud.Alex_test.OMS3"
$Location = "West Europe"

#az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/a0d64279-8ead-4f02-9569-bd8b17322e44"
#az login --service-principal -u fc618a49-c66a-489a-ad17-452296011581 -p ea6850ae-3293-4d9e-a354-da8bdf1ed454 --tenant 811f3560-fe37-49b9-9d5c-fc7d9014ee1f
#az vm list-sizes --location "West Europe"

Remove-AzureRmResourceGroup  -Name $RGName
New-AzureRmResourceGroup -Name $RGName -Location $Location


# Get-AzurePublishSettingsFile
# -TemplateParameterFile azuredeploy.parameters.json 

#New-AzureRmResourceGroupDeployment -Verbose -ResourceGroupName $RGName -TemplateFile azuredeploy.json -DeploymentDebugLogLevel All 
New-AzureRmResourceGroupDeployment -Verbose -ResourceGroupName $RGName -TemplateFile azuredeploy.json -DeploymentDebugLogLevel All 

# New-AzureRmStorageAccount -Location "West Europe" -Name satestalex -ResourceGroupName rg.cybercom.Cloud.Alex_test.TF -SkuName Standard_LRS

Add-AzureRmAccount 
Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Network

