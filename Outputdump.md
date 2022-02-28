## Output Dump of commands
The dump information will help you understand the working of the important commands along the way when building this solution

1. SSL error from the .Net Application (happens when the Azure Firewall Certificate is missing or not valid (sub-cases))
```
.NET 6.0.2
Unhandled exception. System.Net.WebException: The SSL connection could not be established, see inner exception.
 ---> System.Net.Http.HttpRequestException: The SSL connection could not be established, see inner exception.
 ---> System.Security.Authentication.AuthenticationException: The remote certificate is invalid because of errors in the certificate chain: UntrustedRoot
 ```
 2. SSL error from the workload pod when the server certificate validation fails
 ```
srvadmin@DESKTOP-LP3ON48:/mnt/c/DevApplications/KubernetesPlayground/aks-azfirewall-tls$ kubectl exec curl-deployment-b98f7cc4b-5qjwz -- curl https://accuweather.com
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
curl: (35) Unknown SSL protocol error in connection to accuweather.com:443
command terminated with exit code 35
```

3. Failing to whitelist port 445 for SMB access to the File-share in the firewall rules
```
#### Error: Unable to mount the requested volume- occured before port 445 was opened in the network rules ################
Volumes:
  azurefileshare:
    Type:        AzureFile (an Azure File Service mount on the host and bind mount to the pod)
    SecretName:  storage-secret
    ShareName:   fwtlscertshare
    ReadOnly:    false
  kube-api-access-fcb9b:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason       Age               From               Message
  ----     ------       ----              ----               -------
  Normal   Scheduled    53s               default-scheduler  Successfully assigned default/ubuntu-deployment-6fdb9cb5f4-ln4bm to aks-nodepool1-26797051-vmss000001
  Warning  FailedMount  8s (x4 over 43s)  kubelet            MountVolume.SetUp failed for volume "azurefileshare" : mount failed: exit status 32
Mounting command: mount
Mounting arguments: -t cifs -o file_mode=0777,dir_mode=0777,vers=3.0,actimeo=30,mfsymlinks,<masked> //stacacertshare.file.core.windows.net/fwtlscertshare /var/lib/kubelet/pods/6c1c81c9-4f7e-4d72-9426-75f948e50f98/volumes/kubernetes.io~azure-file/azurefileshare
Output: mount error(2): No such file or directory
Refer to the mount.cifs(8) manual page (e.g. man mount.cifs)
```

4. Verbose output of a curl initiated by a workload pod (and configured for TLS inspection in the firewall application rules)
```

srvadmin@DESKTOP-LP3ON48:/mnt/c/DevApplications/KubernetesPlayground/aks-azfirewall-tls$ kubectl exec ubuntu-deployment-858dd67f58-c5r8t -- curl -v https://dataservice.accuweather.com/locations/v1/cities/search?apikey=lOpevOZZZyazIsPaGb32UEDMLRTHxy0T&q=Chennai&language=en-us&details=false
[1] 2384
[2] 2385
[3] 2386
[2]   Done                    q=Chennai
[3]+  Done                    language=en-us
srvadmin@DESKTOP-LP3ON48:/mnt/c/DevApplications/KubernetesPlayground/aks-azfirewall-tls$   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0*   Trying 34.237.118.114:443...
* TCP_NODELAY set
* Connected to dataservice.accuweather.com (34.237.118.114) port 443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*   CAfile: /etc/ssl/certs/ca-certificates.crt
  CApath: /etc/ssl/certs
} [5 bytes data]
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
} [512 bytes data]
* TLSv1.3 (IN), TLS handshake, Server hello (2):
{ [97 bytes data]
* TLSv1.2 (IN), TLS handshake, Certificate (11):
{ [3871 bytes data]
* TLSv1.2 (IN), TLS handshake, Server key exchange (12):
{ [556 bytes data]
* TLSv1.2 (IN), TLS handshake, Server finished (14):
{ [4 bytes data]
* TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
} [37 bytes data]
* TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
} [1 bytes data]
* TLSv1.2 (OUT), TLS handshake, Finished (20):
} [16 bytes data]
* TLSv1.2 (IN), TLS handshake, Finished (20):
{ [16 bytes data]
* SSL connection using TLSv1.2 / ECDHE-RSA-AES256-GCM-SHA384
* ALPN, server did not agree to a protocol
* Server certificate:
*  subject: CN=Azure Firewall Manager CA; CN=dataservice.accuweather.com
*  start date: Feb 24 15:50:42 2022 GMT
*  expire date: Feb 25 15:50:42 2023 GMT
*  subjectAltName: host "dataservice.accuweather.com" matched cert's "dataservice.accuweather.com"
*  issuer: CN=Azure Firewall Manager CA
*  SSL certificate verify ok.
} [5 bytes data]
> GET /locations/v1/cities/search?apikey=lOpevOZZZyazIsPaGb32UEDMLRTHxy0T HTTP/1.1
> Host: dataservice.accuweather.com
> User-Agent: curl/7.68.0
> Accept: */*

```
