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

## Certificate Import Requirements
1. The intermediate CA Certicate needs to be imported into the keyvault as a secret. The secret can then mapped to the TLS property of the Azure Firewall in the deployment template. If this fails then the Intermediate CA certificate has to be imported as a valid PKCS#12 file into the vault and then mapped to the TLS Certificate field of Az-Firewall in the portal
```
 "properties": {
                "sku": {
                    "tier": "Premium"
                },
                "dnsSettings": {
                    "enableProxy": "true"
                },
                "transportSecurity": {
                    "certificateAuthority": {
                        "name": "[variables('keyVaultCASecretName')]",
                        "keyVaultSecretId": "[concat(reference(resourceId('Microsoft.KeyVault/vaults', variables('keyVaultName')), '2019-09-01').vaultUri, 'secrets/', variables('keyVaultCASecretName'), '/')]"
                    }
                },
```
2. The Root-CA certificate has to be imported into the keyvault in the PEM format even though only the public portion needs to be installed in the workload pods. The pods will read this certificate using the Secrets store CSI driver for Keyvault, convert into .CRT file and then add to the CA Certificates list
```
# Import the root-CA certificate to the keyvault - this will be referred to by the SecretProviderClass
# Note: Import operation in a keyvault accepts only .pem and .pfx files
cat rootCA.crt rootCA.key > rootCA.pem
az keyvault certificate import --vault-name $AZKEYVAULT_NAME -f rootCA.pem --name 'SelfSignedRootCACert'
```

## Integration with the Azure Container Registry
It is is optional to integrate the ACR with the AKS cluster for this baseline implementation (as we will only be deploying a minimal ubuntu image and use curl to test the working of TLS inspection). If you are buuilding actual applications that do internet-bound egress calls, then the ACR should be where the docker images should be staged. 
Note: I have added a sample .net app that reads the weather information from accuweather server. In this case the image needs to be built and pushed to ACR
```
az acr login --name workloadcontainerregistry
# Tag the image 
docker tag dotnetapp:testv1 workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1.2
# Push to ACR
docker push workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1.2
# run the container locally to test the validity of the URL
docker run --rm workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1.2
```
## Test Workload 
1.  Base image (Ubuntu Minimal image. Can be other distros too)
2.  Has a pod identity, certificate mounted as a volume either from the keyvault or the file share
3.  List of packages installed (curl for testing, openssl for certificate conversion from .pem to .crt, dpkg to configure the ssl certificate import from the newly added cert list )
    
## Commands to install the TLS Certificate in a Workload Pod
```
# Testing of the AAD-Pod-Identity & KeyVault Secret Store
## show secrets held in secrets-store
kubectl exec workload-egresstest -- ls /mnt/secrets-store/

# Check if the mounted share/directory lists the rootCA.pem file
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- ls /mnt/azure/
# Update the package lists and install curl- this is needed to test the egress from the app pod with TLS inspection enabled
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- apt-get update
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- apt-get -y install curl
# The certificates will have to be converted to .crt. This is a prerequisite. Only .crt files will be considered for installation
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- openssl x509 -in /mnt/azure/rootCA.pem -inform PEM -out /usr/share/ca-certificates/rootCA.crt
# The certificate is copied to an additonal location. The commands seem to not produce the same result everytime when using the path suggested in the documentation
# i.e. /usr/share/ca-certificates/
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- cp /usr/share/ca-certificates/rootCA.crt /usr/local/share/ca-certificates/rootCA.crt
# check for all the newly added CA certificates in /etc/ca-certificates.conf
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- dpkg-reconfigure ca-certificates
# this will use the /etc/ca-certificates.conf and install the valid certs and update the same in /etc/ssl/cert
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- update-ca-certificates
```
**Note**: 
1. In real time scenarios, these steps should be implemented as "commands" in the container after the container creation completes. The manual process provided here is just to illustrate and explain the individual steps 
2. It is also important to note that these steps (in majority of the cases) cannot be included as a part of the image building process in the dockerfile as the certificate has to be read securely from the keyvault 

## Powershell Commands to setup the AzureFileShare for Certificate Access
Note: This method was used because, the keyvault access from the pods failed with a connection refused error. This is captured in the "Issues&Troubleshooting" section. These were extracted from this [blog post](https://zimmergren.net/mount-an-azure-storage-file-share-to-deployments-in-azure-kubernetes-services-aks/) by Tobias
```
$accountName = "stacacertshare"        
$accountNameBytes = [System.Text.Encoding]::UTF8.GetBytes($accountName)
$accountNameBase64 = [Convert]::ToBase64String($accountNameBytes)
Write-Host "Account Name Base 64: " $accountNameBase64
  
$accountKey ="MiC7ql0Xycix7Tmk1CB0vLJPlHmWJWAnl48kZ59xynifKLULS4x59l6ZdqmUr1SchpWjAQgelvESfsFKmH+k7w=="
$accountKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($accountKey)
$accountKeyBase64 = [Convert]::ToBase64String($accountKeyBytes)
Write-Host "Account Name Key 64: " $accountKeyBase64

```

## SSH into the pods for troubleshooting
Reference: https://docs.microsoft.com/en-us/azure/aks/ssh
```
srvadmin@DESKTOP-LP3ON48:/mnt/c/DevApplications/KubernetesPlayground/aks-azfirewall-tls$ kubectl debug node/aks-nodepool1-30698835-vmss000000 -it --image=mcr.microsoft.com/a
ks/fundamental/base-ubuntu:v0.0.11
Creating debugging pod node-debugger-aks-nodepool1-30698835-vmss000000-trdzm with container debugger on node aks-nodepool1-30698835-vmss000000.
If you don't see a command prompt, try pressing enter.
root@aks-nodepool1-30698835-vmss000000:/# hostname --fqdn
aks-nodepool1-30698835-vmss000000.ulldf05wqgzuxd3hrtwrzok3xf.cx.internal.cloudapp.net
```

## Output Dump
Logs from the execution of commands during the setup of this solution - [Outputdump-documented](Outputdump.md)

## Testing
1. Use kubectl to execute a command on the pod. This can be as simple as a curl to an allowed or a blocked url
   - The tests can be futher be expanded to allow specific resources in a website, assuming the necessary allow and deny rule preferences are configured in the firewall
     - Allow data.service.accuweather.com/search but deny dataservice.accuweather.com/forecasts
2. Application rule logs & Azure Diagnostics logs queries in Log-Analytics
   - Note: Diagnostics logs has to be enabled for Azure Firewall and Log-Analytics has to be chosen as a target sink before the tests are run
   - Log Analytics has built-in queries to query the Application and Network rule logs
   ```
   # quick Log Analytics query to get the requests that are TLS inspected by the firewall- https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/firewall/premium-deploy-certificates-enterprise-ca.md#validate-tls-inspection
   AzureDiagnostics 
   | where ResourceType == "AZUREFIREWALLS" 
   | where Category == "AzureFirewallApplicationRule" 
   | where msg_s contains "Url:" 
   | sort by TimeGenerated desc)
   ```
## Issues & Troubleshooting
This section references the issues faced during the implementation of the solution
1. [Access to secrets store fails- Connection refused](Issues&Troubleshooting/KeyvaultAccess.md)
   - Issue opened in Azure-AKS Github page - https://github.com/Azure/AKS/issues/2812#issuecomment-1053532726
2. [Liveness Probes of NMI pods fail- Connection refused ](Issues&troubleshooting/NMILivenessProbeFailure.md)


   
   
