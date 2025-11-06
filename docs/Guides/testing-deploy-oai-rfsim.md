# Guide: GNB+rfSIM Deployment on O-Cloud

> [!NOTE]
> This User Guide is for deployment of OAI RFSim on O-Cloud.

![Notes](assets/sys-isolation.svg)

## Table of Contents

<!-- vim-markdown-toc GitLab -->

* [Prerequisites](#prerequisites)
* [User Setup](#user-setup)
* [Deployment Guide](#deployment-guide)
    * [Deply GNB](#deply-gnb)
    * [Deploy UE Sim](#deploy-ue-sim)
* [Test and Validation](#test-and-validation)
    * [Health Check Procedure](#health-check-procedure)
    * [Execute Diagnostics on Pods](#execute-diagnostics-on-pods)
    * [Check Network Statistic](#check-network-statistic)

<!-- vim-markdown-toc -->



## Prerequisites

1. Obtain Kubeconfig from cluster admin

> [!WARNING]
> User of O-Cloud cluster will be given access based on their needs (not superuser). Giving user superuser access had the potential of disturbing other deployed VNFs on the cluster, hence isolation should be performed.

2. [**Official**] Install essentials tools for deployment


    Install `kubectl` according to this gudie:
    - [Install and Set Up kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-binary-with-curl-on-linux)

    Install Helm follow this gude
    - [Installing Helm](https://helm.sh/docs/intro/install/)

3. [**Quick**] Install essentials tools for deployment Helm & K9s

    - Install `homebrew` App installer that **DOES NOT REQUIRE SUDO**

        > Ubuntu/Debian
        > ```bash
        > sudo apt install jq curl unzip git -y
        > /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        > test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        > test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        > echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
        > ```
        >
        > Fedora/RHEL/Rocky/Alma
        > ```bash
        > sudo dnf install jq curl -y
        > test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        > test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        > echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
        > ```
        > *MacOS*
        > ```bash
        > Homebrew is installed by default on MAC?
        > ```
        >
    - Install Kubectl and Helm using Homebrew (Works for Linux and MacOS)
        ```bash
        brew install helm kubectl
        ```


4. [Optional] `k9s`, easy monitoring and log reading. Ref: [User Gudie](https://k9scli.io/)

    ```bash
    brew install k9s
    ```


## User Setup

1. Obtain Kubeconfig from Admin

    - One time utilization
        ```
        cd <WHERE_KUBECONFIG_DIRECTORY_IS>
        export KUBECONFIG=$(pwd)/kubeconfig.yaml
        kubectl get pods
        kubectl get ns
        ```

    - Set kubeconfig as default for current user

        ```bash
        mkdir ~/.kube/ || true
        cp <WHERE_KUBECONFIG_FILE_IS> ~/.kube/config

        # Test the connection
        kubectl get pods
        kubectl get ns
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

## Deployment Guide

Define KUBECONFIG and git clone
```bash
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

    > Output Example
    > ```log
    > Release "oai-gnb" has been upgraded. Happy Helming!
    > NAME: oai-gnb
    > LAST DEPLOYED: Wed Oct 15 21:24:09 2025
    > NAMESPACE: john-ns
    > STATUS: deployed
    > REVISION: 3
    > TEST SUITE: None
    > NOTES:
    > 1. Get the application name by running these commands:
    >   export GNB_POD_NAME=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-gnb,app.kubernetes.io/instance=oai-gnb" -o jsonpath="{.items[0].metadata.name}")
    >   export GNB_eth0_IP=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-gnb,app.kubernetes.io/instance=oai-gnb" -o jsonpath="{.items[*].status.podIP}")
    > 2. Dockerhub images of OpenAirInterface requires avx2 capabilities in the cpu and they are built for x86 architecture, tested on UBUNTU OS only.
    > 3. Note: This helm chart of OAI-gNB is only tested in RF-simulator mode and is not tested with USRPs/RUs on Openshift/Kubernetes Cluster
    > 4. In case you want to test these charts with USRP/RU then make sure your underlying kernel is realtime and CPU sleep states are off.
    >    Also for good performance it is better to use MTU 9000 for Fronthaul interface.
    > 5. If you want to configure for a particular band then copy the configuration file in templates/configmap.yaml from here https://gitlab.eurecom.fr/oai/openairinterface5g/-/tree/develop/targets/PROJECTS/GENERIC-NR-5GC/CONF
    > ```
    >
    > Execute the recommended command provided by success message to defined your pod name. This pod name will be used on healthcheck procedure.
    >
    > Example, for deployment named `oai-gnb` on namespace named `john-ns`
    > ```bash
    > export GNB_POD_NAME=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-gnb,app.kubernetes.io/instance=oai-gnb" -o jsonpath="{.items[0].metadata.name}")
    > ```


### Deploy UE Sim

1. Go to the gnb chart location
    ```bash
    cd oai-cn5gs-fed/charts/oai-5g-ran/oai-gnb/
    ```
2. Update necessary configuration, for example I want to update the subscribe data to match my CoreNetwork database

```yaml
...
config:
    ...
    fullImsi: "001010000062650"       # make sure all the below entries are present in the subscriber database
    fullKey: "8baf473f2f8fd09487cccbd7097c6862"
    opc: "8e27b6af0e692e750f32667a3b14605d"
    dnn: "internet"
    ...
...
```

2. Deploy NR-UE
    ```bash
    helm install oai-ue .
    ```

    > Succeed Output
    > ```log
    > Release "oai-nr-ue" has been upgraded. Happy Helming!
    > NAME: oai-nr-ue
    > LAST DEPLOYED: Wed Oct 15 21:25:05 2025
    > NAMESPACE: john-ns
    > STATUS: deployed
    > REVISION: 2
    > TEST SUITE: None
    > NOTES:
    > 1. Get the application name by running these commands:
    >   export nr_ue_pod_name=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-nr-ue,app.kubernetes.io/instance=oai-nr-ue" -o jsonpath="{.items[0].metadata.name}")
    > 2. Dockerhub images of OpenAirInterface requires avx2 capabilities in the cpu and they are built for x86 architecture, tested on UBUNTU OS only.
    > 3. Note: This helm chart of OAI-NR-UE is only tested in RF-simulator mode not tested with hardware on Openshift/Kubernetes Cluster
    > 4. In case you want to test these charts with USRP then make sure your CPU sleep states are off
    > ```
    >
    > RUN the recommended provided by success message to defined your pod name. This pod name will be used on healthcheck procedure.
    > Example, for deployment named `oai-nr-ue` on namespace named `john-ns`
    >
    > ```bash
    > export nr_ue_pod_name=$(kubectl get pods --namespace john-ns -l "app.kubernetes.io/name=oai-nr-ue,app.kubernetes.io/instance=oai-nr-ue" -o jsonpath="{.items[0].metadata.name}")
    > ```

## Test and Validation

### Health Check Procedure

List and make sure deployed pod are running
```bash
kubectl get pods -n <Your Namespace>
```

> Example Output Succeed
> ```log
> NAME                         READY   STATUS    RESTARTS   AGE
> oai-gnb-777456887b-kcz75     1/1     Running   0          22m
> oai-nr-ue-75689c497b-89g67   1/1     Running   0          4s
> ```
> If STATUS shows PENDING it means deployment problem; CrashLoopBack software problem;

### Execute Diagnostics on Pods

> [!WARNING]
> This step can only be fully completed if all the pods from [Pod Life](#pod-life) is `running`.


1. GNB
```bash
# Get Full Log
kubectl logs -f -n john-ns $GNB_POD_NAME

# Get Full and follow log
kubectl logs -n john-ns $GNB_POD_NAME
```
2. UE
```bash
# Get Full Log
kubectl logs -f -n john-ns $nr_ue_pod_name

# Get Full and follow log
kubectl logs -n john-ns $nr_ue_pod_name
```

### Check Network Statistic

> [!WARNING]
> This step can only be fully completed if all the pods from [Pod Life](#pod-life) is `running`.

1. GNB Check SCTP socket

    ```bash
    kubectl exec -n <namespace> $GNB_POD_NAME -- netstat -Spn4
    ```

    > Expected Output
    > ```log
    > Active Internet connections (w/o servers)
    > Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
    > sctp       0      0 10.0.3.210:44206        10.98.175.243:38412     ESTABLISHED 1/nr-softmodem
    > ```
    > Make sure State shows ESTABLISHED, any other state means your N2 connection failed either because of network misconfiguration or N2 parameters missconfiguration.

2. GNB Check traffic on SCTP Socket

    ```bash
    kubectl exec -n john-ns $GNB_POD_NAME -- cat /proc/net/sctp/assocs
    ```

    > Output Example:
    > ```bash
    > ASSOC     SOCK   STY SST ST HBKT ASSOC-ID TX_QUEUE RX_QUEUE UID INODE LPORT RPORT LADDRS <-> RADDRS HBINT INS OUTS MAXRT T1X T2X RTXC wmema wmemq sndbuf rcvbuf
    >    0        0 2   1   3  0      58        0        0       0 39945153 44206 38412  10.0.3.210 <-> *10.98.175.243 	   30000     2     2   10    0    0        0        1        0   212992   212992
    > ```
    > Focus on `rcvbuf` and `sndbuf`, if the value is empty on either one of them check your connection or N2 config and compare them with the core network

3. UE Check GTP Tunnel socket

    ```bash
    ```

4. UE Check `oaitun_ue1` interface (Data Plane interface)
    ```bash
    kubectl exec -n john-ns $nr_ue_pod_name  -- ip addr show oaitun_ue1
    ```

    > Output Example:
    > ```log
    > 2: oaitun_ue1: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN group default qlen 500
    > link/none
    > inet 10.45.0.8/24 scope global oaitun_ue1
    >    valid_lft forever preferred_lft forever
    > inet6 fe80::b9ea:e57d:b43d:193a/64 scope link stable-privacy
    >    valid_lft forever preferred_lft forever
    > ```
    > Make sure the interface oaitun_ue1 have an IP. If its empty your PDU setup failed

4. UE Ping test via Data Plane

    Send ICMP packet to UPF node for Open5GS its `10.45.0.1`
    ```bash
    kubectl exec -n john-ns $nr_ue_pod_name  -- ping -I oaitun_ue1 10.45.0.1
    ```

Output Example
```bash
```
