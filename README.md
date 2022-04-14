# ekstest

Provides terraform code to create a simple AWS EKS cluster using the official aws eks terraform module. Also provides a simple `nginx` kubernetes deployment. The terraform code is based off of the [EKS tutorial provided by HashiCorp](https://learn.hashicorp.com/tutorials/terraform/eks).

# Building An EKS Test Cluster With Terraform

This example requires a set of privileged AWS credentials that ensures the management of all resources created by terraform. In a production environment, a dedicated role with access to the explicit set of resources required for building EKS clusters should be used.
See [AWS EKS IAM role](https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html) for more details.

## Building The Docker Image

Build the `ekstest:latest` docker image.
```
bash% docker build -t ekstest:latest .
```
## Running The Docker Image

Once the container is built, we need run the container and configure our AWS credentials. There are several ways to accomplish this. I typically mount my local `~/.aws` directory containing credentials inside the working container.
```
bash% docker run -it -v ${HOME}/.aws:/root/.aws ekstest:latest /bin/bash
```
## Building EKS Cluster With Terraform

From the `/terraform` directory, run the following commands. 
```
root@95558170bbe5:/terraform# terraform init
root@95558170bbe5:/terraform# terraform plan
root@95558170bbe5:/terraform# terraform apply
```
## Locating The Resulting Kubeconfig File

The eks terraform module stands up the cluster, producing a kubeconfig file in the local directory upon completion. Once the kubeconfig is generated, export the `KUBECONFIG` environment variable. 
```
root@b6800197b12d:/# export KUBECONFIG=/terraform/kubeconfig_ekstest-asdf1243
```
## Installing kube-prometheus-stack With Helm

Using `helm`, install the `kube-prometheus-stack` chart, setting `prometheusSpec` values that allow `prometheus` to scrape metrics from pods and services in other namespaces. This is required in order to scrape metrics from the `ingress-nginx` controller pod which runs in `ingress-nginx` namespace.
```
root@95558170bbe5:/terraform# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
root@95558170bbe5:/terraform# helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
--set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
--set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```
## Retrieving The Grafana Password
```
root@95558170bbe5:/terraform# kubectl get secret --namespace default kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```
## Installing ingress-nginx With Helm

Using `helm`, install `ingress-nginx` ingress controller and enable the metrics endpoint. This allows prometheus to scrape the ingress controller for metrics. We need to set
`additionalLabels.release="[name-of-prometheus-helm-release]"` in order to instruct prometheus to scrape the ingress-nginx controller metrics endpoint.

See https://kubernetes.github.io/ingress-nginx/user-guide/monitoring
```
root@95558170bbe5:/terraform# helm upgrade --install ingress-nginx ingress-nginx \
--repo https://kubernetes.github.io/ingress-nginx \
--namespace ingress-nginx \
--create-namespace \
--set controller.metrics.enabled=true \
--set controller.metrics.serviceMonitor.enabled=true \
--set controller.metrics.serviceMonitor.additionalLabels.release="kube-prometheus-stack"
```
## Install cert-manager With Helm

Kubernetes ingresses can provide tls termination for backend services. We can leverage cert-manager and Let's Encrypt to easily manage TLS certificates for ingresses. 
```
root@95558170bbe5:/terraform# helm repo add jetstack https://charts.jetstack.io
root@95558170bbe5:/terraform# helm repo update
root@95558170bbe5:/terraform# helm upgrade --install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.8.0 \
--set installCRDs=true
```
## Create Let's Encrypt Staging And Prod Cluster Issuers

In order to use cert-manager with Let's Encrypt, we need to create `ClusterIssuer` resources. Create the following two yaml files, substituting a valid email address that is responsible for the domains that you manage.

`letsencrypt-prod.yaml`
```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    ## email address used for acme registration
    email: someone@foo.bar
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```
`letsencrypt-staging.yaml`
```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    ## email address used for acme registration
    email: someone@foo.bar
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
```
Create the `ClusterIssuer` resources using `kubectl`.
```
root@95558170bbe5:/terraform/scripts# kubectl create -f letsencrypt-prod.yml
root@95558170bbe5:/terraform/scripts# kubectl create -f letsencrypt-staging.yml
```
## Creating DNS CNAMEs For cert-manager And Let's Encrypt

In order to prove that you own the domain for which you are requesting a certificate, Let's Encrypt will send a challenge query to an HTTP endpoint with the requested hostname. If you request a certificate for `foo.bar.info`, Let's Encrypt will look for `http://foo.bar.info/.well-known/acme-challenge/<TOKEN>` before issuing the certificate.

When you create an ingress, the ingress-nginx controller (in a cloud environment) will create an externally facing load balancer. Each hostname that requires a certificate needs a CNAME that points to the CNAME of the load balancer created by the ingress. The hostnames must resolve to the load balancer CNAME.

When you create an tls-enabled ingress that uses cert-manager and Let's Encrypt, the ingress will automatically expose an HTTP endpoint with the challenge response. Let's Encrypt resolves the hostname(s) on the certificate request to the externally facing load balancer and validates the domain, allowing the certificate to be issued successfully.
```
root@95558170bbe5:/terraform# kubectl get ingress
NAME                        CLASS    HOSTS                                     ADDRESS                                                                  PORTS     AGE
cm-acme-http-solver-6vb4d   nginx    grafana.foo.bar                                                                                                    80        2s
cm-acme-http-solver-bg29p   nginx    hello-world.foo.bar                                                                                                80        2s
tls-ingress                 nginx    hello-world.foo.bar,grafana.foo.bar       a807b153dcbdc4dac837ca04e9c702fb-106581610.us-west-1.elb.amazonaws.com   80, 443   30m
```
## The helloworld Deployment

The `helloworld` deployment kubernetes manifests are located in the `deploy` subdirectory of the `terraform` directory. We use `kubectl` to manage these.
```
root@95558170bbe5:/terraform# kubectl apply -f deploy/helloworld
```
## Verify That Pods Are Running

Use `kubectl` to verify that the `nginx` pods are running and evenly distributed across the three worker nodes.
```
root@95558170bbe5:/terraform# kubectl get pods -owide
NAME                        READY   STATUS    RESTARTS   AGE     IP           NODE                                       NOMINATED NODE   READINESS GATES
helloworld-cdb9fc5b6-gg8qc  1/1     Running   0          5m12s   10.0.1.19    ip-10-0-1-90.us-west-1.compute.internal    <none>           <none>
helloworld-cdb9fc5b6-wgqjw  1/1     Running   0          5m12s   10.0.1.192   ip-10-0-1-198.us-west-1.compute.internal   <none>           <none>
helloworld-cdb9fc5b6-wpsfs  1/1     Running   0          5m12s   10.0.2.225   ip-10-0-2-137.us-west-1.compute.internal   <none>           <none>
```
## Creating The Ingress Without TLS Enabled

We can create a non tls-enabled ingress initially, allowing the ingress-nginx controller to allocate a load balancer. Once we have the name of the load balancer, we can create CNAMEs for the hostnames that resolve to the CNAME of the load balancer. Once the CNAMEs are in place, we can then modify the ingress to enable tls. cert-manager and Let's Encrypt will then be able to issue certificates successfully.
```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: hello-world.foo.bar
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: helloworld
            port:
              number: 80

  - host: grafana.foo.bar
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
```              
```
root@95558170bbe5:/terraform/deploy/nginx# kubectl create -f ingress.yaml
```
## Modifying The Ingress To Enable TLS
Here is an tls-enabled ingress that uses the `letsencrypt-prod` cert-manager issuer to create certificates signed by Let's Encrypt.
```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
      - grafana.foo.bar
      - hello-world.foo.bar
      secretName: foobartls

  rules:
  - host: hello-world.foo.bar
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80

  - host: grafana.foo.bar
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
```
```
root@95558170bbe5:/terraform/deploy/nginx# kubectl apply -f tls-ingress.yaml
```
# Cleaning Up The EKS Cluster

## Removing Ingresses

ingress-nginx will create load balancers and security groups that need to be removed before we can tear down the EKS cluster. We need to delete any ingresses that we have created, and also remove the ingress-nginx helm chart.
```
root@95558170bbe5:/terraform# kubectl delete ingress test-ingress
root@95558170bbe5:/terraform# helm uninstall -n ingress-nginx ingress-nginx
```
## Running Terraform Destroy

From the `/terraform` directory, use `terraform destroy` to tear down the cluster after 
```
root@95558170bbe5:/terraform# terraform destroy --auto-approve
```
## Protecting The Terraform Statefile

Inside the running container, the `/terraform/terraform.tfstate` file describes the AWS resources that the module creates. You will need this file in order to tear down the cluster.

In a production environment, a typical pattern followed to safeguard statefiles is to push them to an encrypted, versioned s3 bucket. This allows shared access to the statefiles across teams.

If you accidentally exit the running container before tearing down the cluster, you can easily restart the last running container in order to retrieve the statefile and run `terraform destroy`.
```
bash% docker start $(docker ps -q -l)
bash% docker attach $(docker ps -q -l)
```