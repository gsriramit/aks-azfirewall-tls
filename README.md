# Azure Firewall TLS for AKS Egress Traffic
This repository contains scripts and instructions to setup azure firewall (premium sku) to inspect the egress traffic from an AKS cluster. The main purpose of this setup is to configure TLS inspection for specific outbound flows so that the firewall can examine the complete URL and other details in the body of the request which would not be available in a normal setup (without TLS inspection)

## Concepts Used
Note: You can use the "Standard Walkthrough" exercises available in Azure GitHub repo for some of the core AKS concepts 
1. Azure Firewall Premium (TLS, IDPS and WebCategories)
   - Reference: https://github.com/Azure/azure-quickstart-templates/tree/master/quickstarts/microsoft.network/azurefirewall-premium
2. Secrets Store CSI Driver (for azure keyvault)
   - Reference: https://github.com/gsriramit/aks-secrets-store-csi-kv/
3. Azure AD PodIdentity 
   -  Reference: https://github.com/gsriramit/aks-aad-pod-identity 
4. Azure Kubernetes Service (AKS) setup with Azure Firewall
   - Reference: https://github.com/gsriramit/aks-egress-azfirewall
5. Mount Azure File Share as Pod Volume (using CSI driver for azure files)
   - Reference: https://docs.microsoft.com/en-us/azure/aks/azure-files-volume#mount-file-share-as-an-inline-volume

## Architecture Diagram
![AKS-Firewall-TLS](https://user-images.githubusercontent.com/13979783/155938120-3377df9f-f762-4992-8e67-be6605d5a23b.png)

## Firewall Rules

### Network Rules

| Name      | Source Type | Source | Protocol  | Destination Ports | Destination Type | Destination        |
| --------- | ----------- | ------ | --------- | ----------------- | ---------------- | ------------------ |
| apiudp    | IP Address  | *     | UDP       | 1194              | IP Address       | AzureCloud.eastus2 |
| apitcp    | IP Address  | *     | TCP       | 9000              | IP Address       | AzureCloud.eastus2 |
| time      | IP Address  | *     | UDP       | 123               | FQFN             | ntp.ubuntu.com     |
| ssh       | IP Address  | *     | UDP & TCP | 22                | IP Address       | AzureCloud.eastus2 |
| fileshare | IP Address  | *     | TCP       | 445, 443          | Service Tag      | Storage.EastUS2    |

### Application Rules
| Name                             | Source Type | Source | Protocol          | TLS Inspection | Destination Type | Destination                                                                                                                                                                                                                                                 |
| -------------------------------- | ----------- | ------ | ----------------- | -------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AllowK8sOperationalServices      | IP Address  | \*     | Https:443,Http:80 | No             | FQDN             | \*.hcp.eastus2.azmk8s.io,mcr.microsoft.com,\*.data.mcr.microsoft.com,login.microsoftonline.com,packages.microsoft.com,acs-mirror.azureedge.net,\*.ods.opinsights.azure.com,\*.oms.opinsights.azure.com,\*.monitoring.azure.com,dc.services.visualstudio.com |
| AllowAzureKubernetesServicesFqdn | IP Address  | \*     | Https:443,Http:80 | No             | FQDN Tag         | AzureKubernetesService                                                                                                                                                                                                                                      |
| AllowSecureContainerRegistries   | IP Address  | \*     | Https:443         | No             | FQDN             | workloadcontainerregistry.azurecr.io,\*.blob.core.windows.net,registry.hub.docker.com,\*.docker.com,\*.docker.io,docker.io,\*.k8s.gcr.io,k8s.gcr.io,storage.googleapis.com                                                                                  |
| AllowWeatherService              | IP Address  | \*     | Https:443         | Yes            | FQDN             | \*.accuweather.com                                                                                                                                                                                                                                          |
| AllowUbuntuRequests              | IP Address  | \*     | Https:443,Http:80 | No             | FQDN             | \*.ubuntu.com                                                                                                                                                                                                                                               |
| AllowKeyVaultAccess              | IP Address  | \*     | Https:443,Http:80 | No             | FQDN             | vault.azure.net,\*vault.azure.net                                                                                                                                                                                                                           |
| AllowFileShareAccess             | IP Address  | \*     | Https:443,Http:80 | No             | FQDN             | stacacertshare.file.core.windows.net,\*file.core.windows.net                                                                                                                                                                                                |




