#!/bin/bash

# Declare the variables
RG_LOCATION='eastus2'
RG_NAME='rg-aksegressfirewalltest-dev0001'
AZKEYVAULT_NAME='kv-azsecretstore-dev01'
export SUBSCRIPTION_ID=""
CLUSTER_NAME="aksworkload-dev-01"
export IDENTITY_NAME="podidentity"
export KEYVAULT_NAME="kv-aks-secretstore"
export TENANT_ID=""
FWPUBLICIP_NAME="FirewallPublicIP"
FWNAME="AKSFirewall"
FWROUTE_NAME_INTERNET="aks-egress-fwinternet"
FWROUTE_TABLE_NAME="aks-egress-fwrt"
VNET_NAME="aks-egress-vnet"
PLUGIN="azure"

az login
az account set -s "${SUBSCRIPTION_ID}"

# install the needed features
az provider register --namespace Microsoft.OperationsManagement
az provider register --namespace Microsoft.OperationalInsights
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService

# Create the networking hubs resource group.
az group create -n $RG_NAME -l $RG_LOCATION
# Create the base infrastructure components
# This deployment shd create the base virtual network, route table that creates a default egress route for 0/0 and a keyvault
az deployment group create -g $RG_NAME -f BaseInfrastructure/deployBaseInfrastructure.json -p BaseInfrastructure/deployBaseInfrastructure.parameters.json

# Create the TLS Certificates that will be used by the workload pods and azure firewall during the TLS inspection process
# Create root CA
openssl req -x509 -new -nodes -newkey rsa:4096 -keyout rootCA.key -sha256 -days 1024 -out rootCA.crt -subj "/C=US/ST=US/O=Self Signed/CN=Self Signed Root CA" -config openssl.cnf -extensions rootCA_ext

# Create intermediate CA request
openssl req -new -nodes -newkey rsa:4096 -keyout interCA.key -sha256 -out interCA.csr -subj "/C=US/ST=US/O=Self Signed/CN=Self Signed Intermediate CA"

# Sign on the intermediate CA
openssl x509 -req -in interCA.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out interCA.crt -days 1024 -sha256 -extfile openssl.cnf -extensions interCA_ext

# Export the intermediate CA into PFX
# format of the password should be "pass:<>". The part after the : delimeter has been left blank in the MS documentation for you to feed in
# References:
# https://www.openssl.org/docs/manmaster/man1/openssl-pkcs12.html
# https://www.ibm.com/docs/en/spectrum-conductor/2.3.0?topic=groups-setting-up-ssl-tier-3-notebooks
openssl pkcs12 -export -out interCA.pfx -inkey interCA.key -in interCA.crt -passout "pass:azfwintercapwd"
#pass-fw-akstls-02:

echo ""
echo "================"
echo "Successfully generated root and intermediate CA certificates"
echo "   - rootCA.crt/rootCA.key - Root CA public certificate and private key"
echo "   - interCA.crt/interCA.key - Intermediate CA public certificate and private key"
echo "   - interCA.pfx - Intermediate CA pkcs12 package which could be uploaded to Key Vault"
echo "================"

# Create a secret (base64 encoded data) from the PFX of the intermediate CA
export AZFIREWALL_TLS_INTERMEDIATECA_CERT_DATA=$(cat interCA.pfx | base64 | tr -d '\n')
# Note: If executing through WSL or Cloud Shell, the logged-in user account needs to be given the secret add permissions to be able to execute the next step
# If automation is used, the SP needs to be provided the appropriate permissions 
# Add the intermediateCA certificate as a secret to the keyvault- this will be referred to by the firewall policy
az keyvault secret set --name 'CACert' --vault-name $AZKEYVAULT_NAME --value $AZFIREWALL_TLS_INTERMEDIATECA_CERT_DATA
# Import the root-CA certificate to the keyvault - this will be referred to by the SecretProviderClass
# Note: Import operation in a keyvault accepts only .pem and .pfx files
cat rootCA.crt rootCA.key > rootCA.pem
az keyvault certificate import --vault-name $AZKEYVAULT_NAME -f rootCA.pem --name 'SelfSignedRootCACert'

# Deploy the Firewall that provides the egress security through TLS inspection
az deployment group create -g $RG_NAME -f Firewall/deployAzureFirewall.json -p Firewall/deployAzureFirewall.parameters.json

# Get the Public and Private IPs of the Firewall
FWPUBLIC_IP=$(az network public-ip show -g $RG_NAME -n $FWPUBLICIP_NAME --query "ipAddress" -o tsv)
FWPRIVATE_IP=$(az network firewall show -g $RG_NAME -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv)

# Add the additional route that is a requisite of asymmetric routing soln
az network route-table route create -g $RG_NAME --name $FWROUTE_NAME_INTERNET --route-table-name $FWROUTE_TABLE_NAME --address-prefix $FWPUBLIC_IP/32 --next-hop-type Internet

# Map the route table to the cluster node subnet (aks-subnet)
ROUTE_TABLE_ID=$(az network route-table show -g $RG_NAME -n $FWROUTE_TABLE_NAME --query id -o tsv)
az network vnet subnet update -n 'aks-subnet' --vnet-name $VNET_NAME -g $RG_NAME --route-table $ROUTE_TABLE_ID


# Deploy the AKS resource that will host the workload pods
SUBNETID=$(az network vnet subnet show -g $RG_NAME --vnet-name $VNET_NAME --name 'aks-subnet' --query id -o tsv)
# Create an RBAC enabled AKS cluster and deploy it to the preexisting virtual network subnet
# Service (ClusterIP) CIDR and the DNS Service IP need to be explicitly provided to the command to avoid the defaults of 10.0.0.0/16 & 10.0.0.10
# Deployment to an existing subnet also provides the option of bringing our own Identities for the Control-Plane and Kubelet (suggested)
# Suggestion Message : It is highly recommended to use USER assigned identity (option --assign-identity) when you want to bring your ownsubnet, which will have no latency for the role assignment to take effect. When using SYSTEM assigned identity, azure-cli will grant Network Contributor role to the system assigned identity after the cluster is created, and the role assignment will take some time to take effect, see https://docs.microsoft.com/azure/aks/use-managed-identity, proceed to create cluster with system assigned identity? (y/N)
# Reference: https://docs.microsoft.com/en-us/azure/aks/use-managed-identity#create-a-cluster-using-kubelet-identity 
# az aks create -g $RG_NAME -n $CLUSTER_NAME --vnet-subnet-id $aksworkload_subnet_id --enable-aad --enable-azure-rbac --network-plugin azure --node-count 1 --enable-addons monitoring --enable-managed-identity --service-cidr 10.0.10.0/23 --dns-service-ip 10.0.10.10

# set this to the name of your Azure Container Registry.  It must be globally unique
MYACR=workloadContainerRegistry
# Run the following line to create an Azure Container Registry if you do not already have one
az acr create -n $MYACR -g $RG_NAME --sku basic
REGISTRYID=$(az acr show --name $MYACR -g $RG_NAME --query id -o tsv)


# Retrieve your IP address
CURRENT_IP=$(dig @resolver1.opendns.com ANY myip.opendns.com +short)

# Create the AKS cluster
# OutboundType should be defined and strictly be UserDefinedRouting 
# As we are deploying to an existing subnet (this is a prerequisite for UDR outbound), the subnetId needs to be mentioned
az aks create -g $RG_NAME -n $CLUSTER_NAME -l $RG_LOCATION \
  --node-count 2 --generate-ssh-keys \
  --network-plugin $PLUGIN \
  --outbound-type userDefinedRouting \
  --service-cidr 10.41.0.0/16 \
  --dns-service-ip 10.41.0.10 \
  --docker-bridge-address 172.17.0.1/16 \
  --vnet-subnet-id $SUBNETID \
  --enable-managed-identity \
  --api-server-authorized-ip-ranges $FWPUBLIC_IP,$CURRENT_IP/32 \
  --enable-aad  \
  --enable-azure-rbac \
  --enable-addons monitoring \
  --attach-acr $REGISTRYID


# Add to AKS approved list
# az aks update -g $RG_NAME -n $CLUSTER_NAME --api-server-authorized-ip-ranges $CURRENT_IP/32

# Reference
# az aks create -g MyResourceGroup -n MyManagedCluster --api-server-authorized-ip-ranges 193.168.1.0/24,194.168.1.0/24,195.168.1.0

#############################################
# AAD-Pod_Identity & SecretsStoreCSIDriver Section
#############################################


# for this demo, we will be deploying a user-assigned identity to the AKS node resource group
export IDENTITY_RESOURCE_GROUP="$(az aks show -g ${RG_NAME} -n ${CLUSTER_NAME} --query nodeResourceGroup -otsv)"

#BASE_VNET_ID=$(az network vnet show -g $RG_NAME -n BaseVnet --query id -o tsv)

# get the client-Id of the managed identity assigned to the node pool
AGENTPOOL_IDENTITY_CLIENTID=$(az aks show -g $RG_NAME -n $CLUSTER_NAME --query identityProfile.kubeletidentity.clientId -o tsv)

# perform the necessary role assignments to the managed identity of the nodepool (used by the kubelet)
# Important Note: The roles Managed Identity Operator and Virtual Machine Contributor must be assigned to the cluster managed identity or service principal, identified by the ID obtained above, 
# ""before deploying AAD Pod Identity"" so that it can assign and un-assign identities from the underlying VM/VMSS.
az role assignment create --role "Managed Identity Operator" --assignee $AGENTPOOL_IDENTITY_CLIENTID --scope /subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${IDENTITY_RESOURCE_GROUP}
az role assignment create --role "Virtual Machine Contributor" --assignee $AGENTPOOL_IDENTITY_CLIENTID --scope /subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${IDENTITY_RESOURCE_GROUP}

# The --attach-acr switch in the cluster creation command takes care of this specific role assignment
# az role assignment create --role "AcrPull" --assignee $AGENTPOOL_IDENTITY_CLIENTID --scope /subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RG_NAME}/providers/Microsoft.ContainerRegistry/registries/$MYACR


# get the cluster access credentials before executing the K8s API commands
# Note: the --admin switch is optional and not adviced for production setups
az aks get-credentials -n $CLUSTER_NAME -g $RG_NAME --admin

# The manifests are downlaoded from the azure github repo
kubectl apply -f PodIdentityManifests/deployment-rbac.yaml
# For AKS clusters, deploy the MIC and AKS add-on exception by running -
kubectl apply -f PodIdentityManifests/mic-exception.yaml

#Deploy Azure Key Vault Provider for Secrets Store CSI Driver
# Todo- check if this repo URL is covered by the whitelisted FDQNs in Firewall Application Rules
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure

###################(OR)###############################
# Reference: https://secrets-store-csi-driver.sigs.k8s.io/getting-started/installation.html

kubectl apply -f SecretStoreCSIDriverManifests/rbac-secretproviderclass.yaml
kubectl apply -f SecretStoreCSIDriverManifests/csidriver.yaml
kubectl apply -f SecretStoreCSIDriverManifests/secrets-store.csi.x-k8s.io_secretproviderclasses.yaml
kubectl apply -f SecretStoreCSIDriverManifests/secrets-store.csi.x-k8s.io_secretproviderclasspodstatuses.yaml
kubectl apply -f SecretStoreCSIDriverManifests/secrets-store-csi-driver.yaml


# Create the managed (user-assigned) identity that will be assigned to the pods (in a specific namespace if required) to authenticate with AAD and access azure resources 
az identity create -g ${IDENTITY_RESOURCE_GROUP} -n ${IDENTITY_NAME}
export IDENTITY_CLIENT_ID="$(az identity show -g ${IDENTITY_RESOURCE_GROUP} -n ${IDENTITY_NAME} --query clientId -otsv)"
export IDENTITY_RESOURCE_ID="$(az identity show -g ${IDENTITY_RESOURCE_GROUP} -n ${IDENTITY_NAME} --query id -otsv)"

# set the access control policies that grant the necessary permissions to the MI to access the vault resources
# set policy to access keys in your keyvault
az keyvault set-policy -n $AZKEYVAULT_NAME --key-permissions get --spn $IDENTITY_CLIENT_ID
# set policy to access secrets in your keyvault
az keyvault set-policy -n $AZKEYVAULT_NAME --secret-permissions get --spn $IDENTITY_CLIENT_ID
# set policy to access certs in your keyvault
az keyvault set-policy -n $AZKEYVAULT_NAME --certificate-permissions get --spn $IDENTITY_CLIENT_ID

# Note: The following K8s manifests can be deployed to the cluster using the appropriate file as the i/p param after the needed values are updated
# The Yq tool can be used to achieve this - https://github.com/mikefarah/yq

# Create the needed "AzureIdentity" resource kind
cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: ${IDENTITY_NAME}
spec:
  type: 0
  resourceID: ${IDENTITY_RESOURCE_ID}
  clientID: ${IDENTITY_CLIENT_ID}
EOF

# Create the needed "AzureIdentityBinding" resource kind- this lets the NMI pods to communicate with the IMDS
cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: ${IDENTITY_NAME}-binding
spec:
  azureIdentity: ${IDENTITY_NAME}
  selector: ${IDENTITY_NAME}
EOF

# Deploy the Azure Secret Provider Class. This will be referenced by the workload pod in the next step
# Note: The class exposes limited number of objects. Modify this to add as many objects as needed by the workload
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: class-firewallrootca-cert
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"          # Set to true for using aad-pod-identity to access keyvault
    keyvaultName: $AZKEYVAULT_NAME
    objects:  |
      array:
        - |
          objectName: SelfSignedRootCACert
          objectType: cert        # object types: secret, key or cert
          objectVersion: ""         # [OPTIONAL] object versions, default to latest if empty
    tenantId: $TENANT_ID                # the tenant ID of the KeyVault
EOF





# login to the azure account to access the ACR
az acr login --name $MYACR

# tag the prebuilt image from Microsoft MCR
docker tag mcr.microsoft.com/dotnet/samples workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1
# push the container image to ACR
docker push workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1



#spotify/alpine - if you prefer alpine as the base image, then this image contains bash and curl built on top of alpine
# Deploy a sample workload that uses pod-identity and creates a secret volume mount request
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: workload-egresstest
  labels:
    aadpodidbinding: $IDENTITY_NAME    # Set the label value to the selector defined in AzureIdentityBinding
spec:
  containers:
    - name: workload-egress
      image: ubuntu:18.04              # This is is supposed to install the minimal version of ubuntu 
      command:
        - "/bin/sleep"
        - "10000"
      volumeMounts:
      - name: secrets-store01-inline
        mountPath: "/mnt/secrets-store"
        readOnly: true
  volumes:
    - name: secrets-store01-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "class-firewallrootca-cert"
EOF

# Testing of the AAD-Pod-Identity & KeyVault Secret Store
## show secrets held in secrets-store
kubectl exec workload-egresstest -- ls /mnt/secrets-store/

# Check if the mounted share/directory lists the rootCA.pem file
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- ls /mnt/azure/
# Update the package lists and install curl- this is needed to test the egress from the app pod with TLS inspection enabled
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- apt-get update
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- apt-get -y install curl
# The certificates will have to be converted to .crt. This is a prerequisite. Only .crt files will be considered for installation
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- openssl x509 -in /mnt/azure/rootCA.pem -inform PEM -
out /usr/share/ca-certificates/rootCA.crt
# The certificate is copied to an additonal location. The commands seem to not produce the same results everytime when using the path suggested in the documentation
# i.e. /usr/share/ca-certificates/
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- cp /usr/share/ca-certificates/rootCA.crt /usr/local/share/ca-certificates/rootCA.crt
# check for all the newly added CA certificates in /etc/ca-certificates.conf
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- dpkg-reconfigure ca-certificates
# this will use the /etc/ca-certificates.conf and install the valid certs and update the same in /etc/ssl/cert
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- update-ca-certificates

# final test to check the egress payload for the URL (TLS inspection at the firewall)
kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- curl -v https://dataservice.accuweather.com/locations/v1/cities/search?apikey=lOpevOZZZyazIsPaGb32UEDMLRTHxy0T&q=Chennai&language=en-us&details=false

# quick Log Analytics query to get the requests that are TLS inspected by the firewall- https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/firewall/premium-deploy-certificates-enterprise-ca.md#validate-tls-inspection
#AzureDiagnostics 
#| where ResourceType == "AZUREFIREWALLS" 
#| where Category == "AzureFirewallApplicationRule" 
#| where msg_s contains "Url:" 
#| sort by TimeGenerated desc


>az acr login --name workloadcontainerregistry
>docker tag dotnetapp:testv1 workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1.2
>docker push workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1.2
>docker run --rm workloadcontainerregistry.azurecr.io/dotnetconsoleapp:v1.2
