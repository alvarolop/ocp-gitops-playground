# Red Hat Openshift GitOps Playground

## Introduction

GitOps is an increasingly popular set of practices for managing the complexities of running hybrid multicluster Kubernetes infrastructure. GitOps centers on treating Git repositories as the single source of truth and applying Git workflows that have been consistently used for application development to infrastructure and application operators. 

https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.16/html/understanding_openshift_gitops/about-redhat-openshift-gitops[Red Hat OpenShift GitOps] Red Hat OpenShift GitOps uses https://argo-cd.readthedocs.io/en/stable[Argo CD] to manage cluster-scoped resources. Argo CD is a popular Cloud Native Computing Foundation (CNCF) open-source GitOps Kubernetes Operator for declarative configuration on Kubernetes clusters. 

## Installing Openshift GitOps Operator

First, let's install the OpenShift GitOps Operator on OCP and log in to the Argo CD instance.

```bash
oc apply -f argocd-operator-install.yaml
```

NOTE: After the installation is completed, the operator pods will be running in the `openshift-gitops-operator` project.

By default, the GitOps operator deploys an ArgoCD instance in the `openshift-gitops` project. To have full control of the installation, the https://access.redhat.com/solutions/6097231[following configuration] has been set in the previous OCP template.

```yaml
    spec:
      config:
        env:
          - name: DISABLE_DEFAULT_ARGOCD_INSTANCE
            value: "true"
          - name: DISABLE_DEFAULT_ARGOCD_CONSOLELINK
            value: "true"
```

## Create an instance

Second, we are going to deploy our ArgoCD instance manually using the following template:

```bash
helm repo add alvarolop-gitops https://alvarolop.github.io/ocp-gitops-playground/
helm upgrade --install argocd alvarolop-gitops/argocd-config --namespace openshift-gitops \
  --set global.namespace=openshift-gitops \
  --set global.clusterName=argocd \
  --set global.clusterDomain=$(oc get dns.config/cluster -o jsonpath='{.spec.baseDomain}') \
  --set argoRoll
```

Access the installed ArgoCD cluster using the following route:

```bash
oc get routes argocd-server -n openshift-gitops --template="https://{{.spec.host}}"
```

## Update the Helm repository

This GitHub repository also acts as a Helm Repository that only serves the `argocd-config` Helm Package. If I generate a new version of the chart, I just run the following commands:

```bash
rm argocd-config-*.tgz
helm lint argocd-config/
helm package argocd-config/
helm repo index --url https://alvarolop.github.io/ocp-gitops-playground/ .
```

And then push the changes to the repo.



## Argo Rollouts

**Argo Rollouts** is a Kubernetes controller and set of CRDs that provide advanced deployment capabilities such as blue-green, canary, and progressive delivery. It integrates with Argo CD to manage the lifecycle of applications. Here is an overview of all the components that take part in a deployment managed by Argo Rollouts.

![Argo Rollouts Architecture](https://argo-rollouts.readthedocs.io/en/stable/architecture-assets/argo-rollout-architecture.png)


For a satisfying experience with Argo Rollouts, you need to install three components:

1. **Argo Rollouts Controller**: This is the main controller that manages the rollout of applications. You can find the rollout manager configuration file in the [`argocd-config/templates/rolloutManager-argo-rollout.yaml`](argocd-config/templates/rolloutManager-argo-rollout.yaml) file of this repository.
2. **Argo Rollouts CLI**: This is a command-line interface that allows you to interact with the Argo Rollouts controller. Install the CLI using the commands from the following [link](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.16/html-single/argo_rollouts/index#gitops-installing-argo-rollouts-cli-on-linux_using-argo-rollouts-for-progressive-deployment-delivery).
3. **Argo Rollouts UI**: This is a web-based user interface that provides a visual representation of the rollouts in the Argo CD dashboard. You can enable the UI by setting the `enableRolloutsUI` parameter to `true` in the ArgoCD instance configuration. 




## Things you should know!

### Configuring Authentication

After the Red Hat OpenShift GitOps Operator is installed, Argo CD automatically creates a user with admin permissions. However, we have disabled Admin access in the ArgoCD RBAC using the property `.spec.disableAdmin`. 

Dex is installed by default for all the Argo CD instances created by the Operator. You can configure Red Hat OpenShift GitOps to use Dex as the SSO authentication provider by setting the .spec.sso parameter. This is the current configuration:

```yaml
spec:
  sso:
    dex:
      openShiftOAuth: true
    provider: dex
```

Dex uses the users and groups defined within the OpenShift Container Platform by checking the OAuth server provided by the platform. Use the following configuration so that every OCP `cluster-admin` is an ArgoCD admin:

```yaml
spec:
  rbac:
    defaultPolicy: 'role:admin'
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
    scopes: '[groups]'
```





### Configuring authorization

Authorization in ArgoCD is a combination of configuring permissions at different levels. Here we present all three levels that you have to take care of to set proper authorization configuration. Please, read the three following sections carefully. 


#### Managing cluster-wide resources

Cluster resources are not bound to a namespace, and, therefore, are not affected by the previous label. For that reason, non-default ArgoCD instances cannot control them. If you want to do so, you need to instruct the GitOps operator to allow it for your cluster like in the following example:

```yaml
    spec:
      config:
        env:
          - name: ARGOCD_CLUSTER_CONFIG_NAMESPACES
            value: openshift-gitops, gitops
```




#### Using namespace Isolation at Service Account level

The ArgoCD instance only has privileges in its namespace which is `openshift-gitops`. For creating/updating/listing resources in other namespaces, it's mandatory to update the RBAC for its Service Account.

This section can be as complex as the security requirements that your organization demands for the ArgoCD deployment. The easiest solution for non-productive environments would be to grant `cluster-admin` rights to the service account that interacts with the k8s API.

```bash
oc adm policy add-cluster-role-to-user admin system:serviceaccount:openshift-gitops:argocd-argocd-application-controller
```


If you prefer to have a per-project tunning, you can use the configuration set in the template `openshift/11-application-app.yaml`, where we provide project admin rights to the SA. This is also oriented to get a proper multi-tenancy configuration, like in the previous section. Check the template mentioned or use the following command:

```bash
oc adm policy add-role-to-user admin system:serviceaccount:openshift-gitops:argocd-argocd-application-controller -n $APP_NAMESPACE
```


Obviously, you can even set a finer tunning by creating a custom `Role` and `RoleBinding` to specify the resources that each ArgoCD will be allowed to manage per namespace. This https://access.redhat.com/solutions/5875661[KCS] gives you an example of how to configure one of these `RoleBindings`.



Extra documentation:

* https://blog.andyserver.com/2020/12/argocd-namespace-isolation[Deep-dive blog post] about namespace isolation using the SA `RoleBindings`.
* https://github.com/redhat-developer/gitops-operator/issues/116[Upstream issue] regarding permissions for the ArgoCD instance.











## Annex: Installing Nexus


> [!CAUTION]
> TL;DR: Execute the following script to auto-install a Nexus instance in your cluster:
> `./nexus-auto-install.sh`


Nexus Repository OSS is an open-source repository that supports many artifact formats, including Docker, Java™, and npm. With the Nexus tool integration, pipelines in your toolchain can publish and retrieve versioned apps and their dependencies by using central repositories that are accessible from other environments.

If you are planning to deploy your applications using Helm charts, most of the architectures you will need a Helm repository to host packaged Helm charts. Install a Nexus repository manager using the following commands:


```bash
# Define common variables
OPERATOR_NAMESPACE="nexus"

# Deploy operator
oc process -f openshift/nexus/01-operator.yaml \
  -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE | oc apply -f -

# Deploy application instance
oc process -f openshift/nexus/02-server.yaml \
  -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE \
  -p SERVER_NAME="nexus-server" | oc apply -f -
```

### Creating  a Helm repository

Create a Helm repository with the following steps:

* Access the Nexus route: `oc get routes nexus-server --template="https://{{.spec.host}}"`.
* Log in using the admin credentials: `admin` / `admin123`.
* Server Administration > Repositories > Create Repositories > "Helm(hosted)":
  - name: `helm-charts`.
  - DeploymentPolicy: `Allow redeploy`.
* Click on `Create repository`.

NOTE: If you don't want to use the console, you can use the `curl` command to create this repository. Check an example in the `auto-install-nexus.sh` script.
