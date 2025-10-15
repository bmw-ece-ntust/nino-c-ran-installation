# GNB+rfSIM Deployment on O-Cloud

> [!NOTE]
> This User Guide is based on the [O-RAN O-DU High project](https://github.com/o-ran-sc/o-du-l2/tree/master) and provides step-by-step instructions for deployment and testing.

![XX](../assets/sys-isolation.svg)

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Basic Execution](#basic-execution)
- [Intel L1 Integration](#intel-l1-integration)
- [O1 Interface Configuration](#o1-interface-configuration)
- [Health Check Procedures](#health-check-procedures)
- [Containerization Deployment](#containerization-deployment)
- [Troubleshooting](#troubleshooting)



## Prerequisites

1. Set Kubeconfig

    > [!WARNING]
    > User of O-Cloud cluster will be given access based on their needs (not superuser). Giving user superuser access had the potential of disturbing other deployed VNFs on the cluster, hence isolation should be performed.

    - Admin will generate individual kubeconfig based on what the user needs

2. Install essentials tools for deployment purpooses

    ```bash
    dnf install helm kubectl yq
    ```

4. [Optional] `k9s`

    ```bash
    curl ***
    ```


## Basic Execution

1. Request Kubeconfig from Admin

Define used kubeconfig
```
export KUBECONFIG=$(pwd)/kubeconfig.yaml
```

2. Verify Access
```bash
# Success Command <Allowed to View>
kubectl get nodes
kubectl get pods
kubectl get ns

# Will Fail <User only allowed to ceratin namespace>
kubectl get pods -A
```

## User Guide

Define KUBECONFIG and git clone
```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml
git clone https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed.git
```

### Deply GNB
1. Go to the gnb chart location
    ```bash
    cd oai-cn5gs-fed/charts/oai-5g-ran/oai-gnb/
    ```
2. Config GNB
- Update values.yaml and change `amfHost` value into the name of core-network's servicename i.e. `oai-

    ```yaml
    ...
    config:
        ...
        amfhost: "open5gs-amf-ngap.5gs-cn" # Open5GS service runs at a namespace named 5gs-cn
        ...
    ...
    ```

3. Deploy GNB+rfSIM
    ```bash
    helm install oai-gnb .
    ```

    Output Example
    ```log
    Release "oai-gnb" has been upgraded. Happy Helming!
    NAME: oai-gnb
    LAST DEPLOYED: Wed Oct 15 21:24:09 2025
    NAMESPACE: john-ns
    STATUS: deployed
    REVISION: 3
    TEST SUITE: None
    NOTES:
    1. Get the application name by running these commands:
      export GNB_POD_NAME=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-gnb,app.kubernetes.io/instance=oai-gnb" -o jsonpath="{.items[0].metadata.name}")
      export GNB_eth0_IP=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-gnb,app.kubernetes.io/instance=oai-gnb" -o jsonpath="{.items[*].status.podIP}")
    2. Dockerhub images of OpenAirInterface requires avx2 capabilities in the cpu and they are built for x86 architecture, tested on UBUNTU OS only.
    3. Note: This helm chart of OAI-gNB is only tested in RF-simulator mode and is not tested with USRPs/RUs on Openshift/Kubernetes Cluster
    4. In case you want to test these charts with USRP/RU then make sure your underlying kernel is realtime and CPU sleep states are off.
       Also for good performance it is better to use MTU 9000 for Fronthaul interface.
    5. If you want to configure for a particular band then copy the configuration file in templates/configmap.yaml from here https://gitlab.eurecom.fr/oai/openairinterface5g/-/tree/develop/targets/PROJECTS/GENERIC-NR-5GC/CONF
    ```

### Deploy UE Sim

1. Go to the gnb chart location
    ```bash
    cd oai-cn5gs-fed/charts/oai-5g-ran/oai-gnb/
    ```

2. Deploy NR-UE
    ```bash
    helm install oai-ue .
    ```

    Succeed Output
    ```log
    Release "oai-nr-ue" has been upgraded. Happy Helming!
    NAME: oai-nr-ue
    LAST DEPLOYED: Wed Oct 15 21:25:05 2025
    NAMESPACE: john-ns
    STATUS: deployed
    REVISION: 2
    TEST SUITE: None
    NOTES:
    1. Get the application name by running these commands:
      export NR_UE_POD_NAME=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-nr-ue,app.kubernetes.io/instance=oai-nr-ue" -o jsonpath="{.items[0].metadata.name}")
    2. Dockerhub images of OpenAirInterface requires avx2 capabilities in the cpu and they are built for x86 architecture, tested on UBUNTU OS only.
    3. Note: This helm chart of OAI-NR-UE is only tested in RF-simulator mode not tested with hardware on Openshift/Kubernetes Cluster
    4. In case you want to test these charts with USRP then make sure your CPU sleep states are off
    ```
## Health Check Procedure

List and make sure deployed pod are running
```bash
kubectl get pods
```

Example Output Succeed
```log
NAME                         READY   STATUS    RESTARTS   AGE
oai-gnb-777456887b-kcz75     1/1     Running   0          22m
oai-nr-ue-75689c497b-89g67   1/1     Running   0          4s
```





