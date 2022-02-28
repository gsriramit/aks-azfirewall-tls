# Liveness probe failed: Get "http://10.42.1.4:8086/healthz": dial tcp 10.42.1.4:8086: connect: connection refused

## Error Log from the target pods
Events:
  Type     Reason     Age                   From               Message
  ----     ------     ----                  ----               -------
  Normal   Scheduled  2m57s                 default-scheduler  Successfully assigned default/nmi-hb9fx to aks-nodepool1-30698835-vmss000000
  Normal   Pulled     108s (x4 over 2m57s)  kubelet            Container image "mcr.microsoft.com/oss/azure/aad-pod-identity/nmi:v1.8.7" already present on machine
  Normal   Created    108s (x4 over 2m57s)  kubelet            Created container nmi
  Normal   Killing    108s (x3 over 2m33s)  kubelet            Container nmi failed liveness probe, will be restarted
  Normal   Started    107s (x4 over 2m57s)  kubelet            Started container nmi
  Warning  Unhealthy  93s (x10 over 2m43s)  kubelet            Liveness probe failed: Get "http://10.42.1.4:8086/healthz": dial tcp 10.42.1.4:8086: connect: connection refused