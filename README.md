# eoepca-flux

Deployment of selected EOEPCA components to TPZ-UK internal cluster.

- [eoepca-flux](#eoepca-flux)
  - [Accessing from TPZ-UK Dev VM](#accessing-from-tpz-uk-dev-vm)
  - [Prerequisite Tooling](#prerequisite-tooling)
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
  - [Load Records into Resource Catalogue](#load-records-into-resource-catalogue)

## Accessing from TPZ-UK Dev VM

The cluster comprises 4 nodes - only one (`172.26.59.13`) is accessible from the TPZ-UK dev VM network - and only via SSH...

* `172.26.59.13`
  * Cluster access node
  * NFS server
  * Cluster roles: master, worker
* `172.26.59.10`
  * Accessible only from `172.26.59.13`
  * Cluster roles: worker
* `172.26.59.11`
  * Accessible only from `172.26.59.13`
  * Cluster roles: worker
* `172.26.59.12`
  * Accessible only from `172.26.59.13`
  * Cluster roles: worker

**Thus, all interactions with the cluster are made via node `172.26.59.13`. Specifically the steps described in this README are performed on the node `172.26.59.13`.**

Connection is via SSH...
```
ssh -X rke@172.26.59.13
```

Use of the option `-X` allows the browser to be invoked on this access VM, and displayed on the connecting dev VM. This is necessary to establish a browser session that is able to connect to the cluster services, _(since the VM `172.26.59.13` does not allow traffic on `http` ports)_.

For example... (from your dev VM)
```
ssh -X rke@172.26.59.13 google-chrome
```

This browser instance can then be used to interact with the web services of the cluster deployment.

## Prerequisite Tooling

_On the node `172.26.59.13`_

The deployment relies upon the following prerequisite tooling, with supporting scripts to facilitate their installation...

* **docker**<br>
  ```
  ./bin/install-docker
  ```

* **rke**<br>
  ```
  ./bin/install-rke
  ```

* **kubectl**<br>
  ```
  ./bin/install-kubectl
  ```

* **helm**<br>
  ```
  ./bin/install-helm
  ```

* **flux**<br>
  ```
  ./bin/install-flux
  ```

Use the scripts to install the tooling as required.

## Deployment

_On the node `172.26.59.13`_

The deployment is made by a sequence of steps, to be executed in order, that are described in the following sub-sections...

### Kubernetes Cluster

> NOTE<br>
> This step can be skipped if you already have a Kubernetes cluster prepared.

The script [`010-kubernetes`](./010-kubernetes) establishes a new Kubernetes cluster using [Rancher Kubernetes Engine (RKE)](https://www.rancher.com/products/rke) as a starting point.

```bash
./010-kubernetes
```

The kubeconfig for the new cluster is in the file `kube_config_cluster.yml`.

Set environment variable `KUBECONFIG` to point to the new cluster...
```
  export KUBECONFIG="<path-to-file>/kube_config_cluster.yml"
```
This can be placed in your `${HOME}/.bashrc` file.

### Loadbalancer

> NOTE<br>
> This step can be skipped if you already have a Loadbalancer - e.g. provided by your cloud environment - or you have a another means of establishing the 'access' IP to your cluster.

The script [`020-loadbalancer`](./020-loadbalancer) deploys the metallb loadbalancer into the cluster - configured with an address pool that comprises the IP address of the node `172.26.59.13` in the cluster - this node, importantly, being the only one that is accessible from the TPZ-UK dev VM network.

This IP will be assigned to the `ingress-nginx` component within the cluster, through which all published cluster services will be exposed. Thus, a 'public' IP is presented by the cluster that is, at least, accessible from the dev VMs that can run a browser.

```bash
./020-loadbalancer
```

The resultant domain through which the cluster public services are accessed is `172-26-59-13.nip.io` which resolves to the 'accessible' VM of the TPZ-UK cluster - e.g. `my-service.172-26-59-13.nip.io`.

> NOTE<br>
> For a custom configuration, the script must be edited to set your cluster access IP address...
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

The file `040-nfs-provisioner.yaml` must be edited to set the IP address of the NFS server and the path to the exported directory to host the dynamically created volumes. This has been preconfigured with the address and path of the NFS server VM...

```
    nfs:
      server: "172.26.59.13"
      path: /data/dynamic
```

> NOTE<br>
> If NFS support is not required then this capability can be suspended by editing...
> ```
> spec:
>   suspend: true
> ```

#### Storage Volumes

The file [`050-storage-volumes.yaml`](./deploy/050-storage-volumes.yaml) pre-creates persistent volume claims that can be used by other components.

> NOTE<br>
> By default the storage class `managed-nfs-storage-retain` is specfied - which relies upon the NFS provisioner above.

#### Resource Catalogue

The file [`070-resource-catalogue.yaml`](./deploy/070-resource-catalogue.yaml) instantiates the EOEPCA Resource Catalogue.

In this deployment we are assuming a 'closed' deployment that is not externally accessible - and hence is not able to establish TLS certificates via letsencrypt. However, the resource-catalogue helm charts insist on configuring tls, which is not what we want in this case. Hence, we disable the helm chart ingress creation, and instead create our own ingress that is http only.

> NOTE<br>
> The file `070-resource-catalogue.yaml` must be edited to set the correct domain for your deployment within the service and ingress definition. In this case it has been initialised with the value `172-26-59-13.nip.io` that resolves to the IP address of the 'accessible' node within the TPZ-UK cluster.

## Load Records into Resource Catalogue

_On the node `172.26.59.13`_

Records can be loaded into the Resource Catalogue from STAC Item inputs files.

The helper script [`./bin/load-records`](./bin/load-records) has been included to facilitate this.

The following included example illustrates...

```
./bin/load-records ./records/absolute-sea-level-heights-baltics-sar-hsu.json
```

After the record is loaded it can be http://resource-catalogue.172-26-59-13.nip.io/collections/metadata:main/items/absolute-sea-level-heights-baltics-sar-hsu here - [http://resource-catalogue.172-26-59-13.nip.io/collections/metadata:main/items/absolute-sea-level-heights-baltics-sar-hsu](http://resource-catalogue.172-26-59-13.nip.io/collections/metadata:main/items/absolute-sea-level-heights-baltics-sar-hsu)
