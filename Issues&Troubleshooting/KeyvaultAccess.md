# Get "http://localhost:2579/host/token/?resource=https://vault.azure.net": dial tcp 127.0.0.1:2579: connect: connection refused

## Error Log from the target pods
Events:
  Type     Reason       Age                   From               Message
  ----     ------       ----                  ----               -------
  Normal   Scheduled    6m19s                 default-scheduler  Successfully assigned default/ubuntu-deployment-55f6774b-4lpr6 to aks-nodepool1-15872125-vmss000000
  Warning  FailedMount  2m2s (x2 over 4m16s)  kubelet            Unable to attach or mount volumes: unmounted volumes=[secrets-store01-inline], unattached volumes=[secrets-store01-inline kube-api-access-6mkk4]: timed out waiting for the condition
  Warning  FailedMount  7s (x11 over 6m19s)   kubelet            MountVolume.SetUp failed for volume "secrets-store01-inline" : rpc error: code = Unknown desc = failed to mount secrets store objects for pod default/ubuntu-deployment-55f6774b-4lpr6, err: rpc error: code = Unknown desc = failed to mount objects, error: failed to get keyvault client: failed to get authorizer for keyvault client: Get "http://localhost:2579/host/token/?resource=https://vault.azure.net": dial tcp 127.0.0.1:2579: connect: connection refused
