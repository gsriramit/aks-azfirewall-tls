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
