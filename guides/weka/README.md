# Well-lit Path: WEKA GPU Direct

This guide demonstrates how to deploy llm-d with WEKA storage using GPU
Direct Storage (GDS) for high-performance data transfer between GPUs and
storage. It covers both PVC and host-path storage configurations.

## Overview

The WEKA GDS integration includes:

1. InitContainer added to run `amgctl` to create the cufile.json on the node
   (only implemented for decode so far, will need to add this for prefill too)
2. Mount the cufile.json from ~/amg_stable/cufile.json on the host to
   /etc/cufile.json in the main container

## Prerequisites

- Have the [proper client tools installed on your local system](
  ../prereq/client-setup/README.md) to use this guide.
- Configure and deploy your [Gateway control plane](
  ../prereq/gateway-provider/README.md) to create resources
- Create Installation Namespace:

  ```bash
  export NAMESPACE=weka
  kubectl create namespace ${NAMESPACE}
  ```

- [Create the `llm-d-hf-token` secret in your target namespace with the key
  `HF_TOKEN` matching a valid HuggingFace token](
  ../prereq/client-setup/README.md#huggingface-token) to pull models.
- [Choose an llm-d version](../prereq/client-setup/README.md#llm-d-version)

## Installation

### Deploy Model Servers

#### PVC

Before deploying, update the PVC configuration:

1. In `./manifests/modelserver/overlays/pvc-storage/pvc.yaml` replace
`SOME_STORAGE_CLASS_NAME` to match your WEKA CSI storage class
   name (e.g., `weka-csi-sc`)

```bash
kubectl apply -k ./manifests/modelserver/overlays/pvc-storage -n ${NAMESPACE}
```

#### Host

Before deploying, must update the host path configuration:

1. In `./manifests/modelserver/overlays/host-storage/kustomization.yaml` replace
 `/SOME/PATH/GOES/HERE` with the valid host path where WEKA
   storage is mounted (e.g., `/mnt/weka`) or will cause main container fail to start.

```bash
kubectl apply -k ./manifests/modelserver/overlays/host-storage -n ${NAMESPACE}
```

### Deploy InferencePool

This will create the InferencePool resource and automatically create an Istio
DestinationRule.

```bash
export NAMESPACE=weka
helm install llama-3-3-70b-instruct-fp8-dynamic \
    -n ${NAMESPACE} \
    -f ./manifests/inferencepool.values.yaml \
    oci://us-central1-docker.pkg.dev/k8s-staging-images/\
gateway-api-inference-extension/charts/inferencepool \
    --version v1.2.0-rc.1
```

### Deploy Gateway

Deploy the Gateway and HTTPRoute resources:

```bash
kubectl apply -k ./manifests/gateway/overlays/istio -n ${NAMESPACE}
```

## Refactors in Progress

- needs to refactor this into the PD example with overlays but for dev work
  we are keeping it in its own directory (# TODO : double check this?)
