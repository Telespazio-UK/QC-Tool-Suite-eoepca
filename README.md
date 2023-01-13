# eoepca-flux

Simple deployment of EOEPCA using flux.

Defaults to a minikube cluster, but this can be adapted to any suitable Kubernetes cluster.

- [eoepca-flux](#eoepca-flux)
  - [Deployment](#deployment)
    - [Kubernetes Cluster](#kubernetes-cluster)
    - [Loadbalancer](#loadbalancer)
    - [Flux GitOps](#flux-gitops)
      - [Ingress Nginx](#ingress-nginx)
      - [Namespaces](#namespaces)
      - [Helm Repositories](#helm-repositories)
      - [NFS Provisioning](#nfs-provisioning)
      - [Storage Volumes](#storage-volumes)
      - [Resource Catalogue](#resource-catalogue)

## Deployment

The deployment is made by a sequence of steps, to be executed in order, that are described in the following sub-sections...

### Kubernetes Cluster

> NOTE<br>
> This step can be skipped if you already have a Kubernetes cluster prepared.

The script [`010-minikube`](./010-minikube) establishes a new minikube cluster as a starting point.

```bash
./010-minikube
```

### Loadbalancer

> NOTE<br>
> This step can be skipped if you already have a Loadbalancer - e.g. provided by your cloud environment - or you have a another means of establishing the 'access' IP to your cluster.

The script [`020-loadbalancer`](./020-loadbalancer) deploys the metallb loadbalancer into the cluster - configured with an address pool that comprises the single 'minikube' IP address - ref. `$ minikube ip`.

```bash
./020-loadbalancer
```

> NOTE<br>
> If you are not using minikube then the script must be edited to set your cluster access IP address...
> ```
> spec:
>   addresses:
>     - <cluster-access-ip>/32  # or <ip-range-start>-<ip-range-end>
> ```
>
> Alternatively the `LB_ADDRESSES` environment variable can be set to configure the script.

### Flux GitOps

The script [`030-flux`](./030-flux) bootstraps flux CI/CD into the Kubernetes cluster.

```bash
./030-flux
```

The script relies upon the following environment variables being set...

| Variable | Description | Default |
| - | - | - |
| GITHIB_USER | Owner of the Github repository | n/a<br>_(must be set)_ |
| GITHIB_TOKEN | Credential (PAT) for Github access | n/a<br>_(must be set)_ |
| GITHUB_REPO | Name of the Github repository | `eoepca-flux` |
| GITHUB_BRANCH | Github branch within the repository | `main` |
| GITHUB_PATH | Path within the repository for the flux root | `main` |

Once the script is executed then flux bootstraps the cluster from the `deploy` (by default) subdirectory.

The following subsections describe each element of the flux GitOps deployment.

#### Ingress Nginx

The file [`010-ingress-nginx.yaml`](./deploy/010-ingress-nginx.yaml) uses helm to deploy the `ingress-nginx` reverse proxy - which relies upon the loadbalancer to provide the IP address upon which the service listens. This represents the 'public' point of access to the deployed system.

The following elements are defined:
* **`Namespace`** - into which the `ingress-nginx` components are instantiated
* **`HelmRepository`** - from where the `ingress-nginx` helm chart is obtained
* **`HelmRelease`** - that uses helm to deploy the `ingress-ngin`x using the chart

In this deployment we are assuming a 'closed' deployment that is not externally accessible - and hence is not able to establish TLS certificates via letsencrypt. Therefore we disable the nginx default to always redirect http -> https...

```
  values:
    controller:
      config:
        ssl-redirect: false
```

#### Namespaces

The file [`020-namespaces.yaml`](./deploy/020-namespaces.yaml) predefines some namespaces into which the system is deployed.

#### Helm Repositories

The file [`030-helm-repositories.yaml`](./deploy/030-helm-repositories.yaml) defines some 'common' helm chart repositories to be used for the deployment of other components.

#### NFS Provisioning

The file [`040-nfs-provisioner.yaml`](./deploy/040-nfs-provisioner.yaml) establishes the capability for dynamic provisioning of NFS volumes.

Two `storage classes` are configured...
* `managed-nfs-storage` - with a reclaim policy of `Delete`
* `managed-nfs-storage-retain` - with a reclaim policy of `Retain`

The file `040-nfs-provisioner.yaml` must be edited to set the IP address of the NFS server and the path to the exported directory to host the dynamically created volumes.

> NOTE<br>
> Since the default 'minikube' deployment is not accompanied by an NFS server, this capability is 'suspended' by default.<br>
> Thus, to enable, the file must be edited to set...
> ```
> spec:
>   suspend: false
> ```

#### Storage Volumes

The file [`050-storage-volumes.yaml`](./deploy/050-storage-volumes.yaml) pre-creates persistent volume claims that can be used by other components.

> NOTE<br>
> By default the storage class `standard` is specfied - which relies upon the `k8s.io/minikube-hostpath` that is deployed with minikube. This must be adapted to a suitable storage class for your cluster - e.g. `managed-nfs-storage` is NFS provisioning has been configured.

#### Resource Catalogue

The file [`060-resource-catalogue.yaml`](./deploy/060-resource-catalogue.yaml) instantiates the EOEPCA Resource Catalogue.

In this deployment we are assuming a 'closed' deployment that is not externally accessible - and hence is not able to establish TLS certificates via letsencrypt. However, the resource-catalogue helm charts insist on configuring tls, which is not what we want in this case. Hence, we disable the helm chart ingress creation, and instead create our own ingress that is http only.

> NOTE<br>
> The file `060-resource-catalogue.yaml` must be edited to set the correct domain for your deployment within the service and ingress definition.
