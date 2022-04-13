# ekstest

Provides terraform code to create a simple AWS EKS cluster using the official aws eks terraform module. Also provides a simple `nginx` kubernetes deployment. The terraform code is based off of the [EKS tutorial provided by HashiCorp](https://learn.hashicorp.com/tutorials/terraform/eks).

# Building An EKS Test Cluster With Terraform

This example requires a set of privileged AWS credentials that ensures the management of all resources created by terraform. 

In a production environment, a dedicated role with access to the explicit set of resources required for building EKS clusters should be used.
See [AWS EKS IAM role](https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html) for more details.

## Building The Docker Image

Build the `ekstest:latest` docker image.
```
bash% docker build -t ekstest:latest .
```
## Run The Docker Image

Once the container is built, we need run the container and configure our AWS credentials. There are several ways to accomplish this. These can be passed as environment variables to docker.

Make sure you remove these from your history file, if needed, when finished.
```
bash% docker run -it \
  -e AWS_ACCESS_KEY_ID=******************** \
  -e AWS_SECRET_ACCESS_KEY=**************************************** \
  ekstest:latest -- /bin/bash
```
## Building EKS Cluster With Terraform

From the `terraform` directory, run the following commands. 
```
root@29e6c98cf177:/terraform# terraform init
root@29e6c98cf177:/terraform# terraform plan
root@29e6c98cf177:/terraform# terraform apply --auto-approve
```
## Locating The Resulting Kubeconfig File

The eks module builds the cluster and produces a kubeconfig file in the local directory. With the kubeconfig, we can deploy a simple `nginx` application. From the running container, export the `KUBECONFIG` environment variable. 
```
root@b6800197b12d:/# export KUBECONFIG=/terraform/kubeconfig_ekstest-asdf1243
```
In a production environment, access to the control plane must be secured, typically through the use of a VPN.

## The Nginx Deployment

The `nginx` deployment kubernetes manifests are located in the `deploy` subdirectory of the `terraform` directory. We use `kubectl` to manage these.
```
bash% kubectl apply -f deploy/nginx
```
## Verify That Pods Are Running

Use `kubectl` to verify that the `nginx` pods are running and evenly distributed across the three worker nodes.
```
root@95558170bbe5:/terraform# kubectl get pods -owide
NAME                    READY   STATUS    RESTARTS   AGE     IP           NODE                                       NOMINATED NODE   READINESS GATES
nginx-cdb9fc5b6-gg8qc   1/1     Running   0          5m12s   10.0.1.19    ip-10-0-1-90.us-west-1.compute.internal    <none>           <none>
nginx-cdb9fc5b6-wgqjw   1/1     Running   0          5m12s   10.0.1.192   ip-10-0-1-198.us-west-1.compute.internal   <none>           <none>
nginx-cdb9fc5b6-wpsfs   1/1     Running   0          5m12s   10.0.2.225   ip-10-0-2-137.us-west-1.compute.internal   <none>           <none>
```
## Accessing The Nginx Deployment

A `LoadBalancer` service is created when we deploy the `nginx` service. You can retrieve the elb address using `kubectl`.
```
root@95558170bbe5:/terraform# kubectl get service nginx --no-headers | awk {'print $4'}
a3b022452b445405783e2e61895c8642-1108080924.us-west-1.elb.amazonaws.com
```
The `nginx` application can be accessed by opening a browser and pointing it to the elb address.
```
http://a3b022452b445405783e2e61895c8642-1108080924.us-west-1.elb.amazonaws.com
```
In a production environment, the use of an SSL certificate and https is obviously preferred.

# Cleaning Up The EKS Cluster

## Removing The Nginx Service

Before we tear down the cluster, we need to remove the `nginx` kubernetes service that we created earlier. This service creates an AWS ELB and security group that are attached to the VPC that is created when we build the cluster. `terraform` will not be able to tear down the cluster until we remove these components.

It's not strictly necessary to remove the deployment and the configmap, but this is good housekeeping.
```
bash% kubectl delete service nginx
bash% kubectl delete deployment nginx
bash% kubectl delete configmap nginx-scripts
```
## Running Terraform Destroy

We can use `terraform destroy` to tear down the cluster that we have created.
```
bash% terraform destroy --auto-approve
```
## Protecting The Terraform Statefile

Inside the running container, the `/terraform/terraform.tfstate` file describes the AWS resources that the module creates. You will need this file in order to tear down the cluster.

In a production environment, a typical pattern followed to safeguard statefiles is to push them to an encrypted, versioned s3 bucket. This allows shared access to the statefiles across teams.

If you accidentally exit the running container before tearing down the cluster, you can easily restart the last running container in order to retrieve the statefile and run `terraform destroy`.
```
bash% docker start $(docker ps -q -l)
bash% docker attach $(docker ps -q -l)
```
## Install ingress-nginx

Using `helm`, install `ingress-nginx` ingress controller, enabling metrics endpoint.
See https://kubernetes.github.io/ingress-nginx/user-guide/monitoring
```
bash% kubectl create namespace ingress-nginx
bash% helm install ingress-nginx ingress-nginx \
--repo https://kubernetes.github.io/ingress-nginx \
--namespace ingress-nginx \
--set controller.metrics.enabled=true \
--set controller.metrics.serviceMonitor.enabled=true \
--set controller.metrics.serviceMonitor.additionalLabels.release="kube-prometheus-stack"
```
## Installing kube-prometheus-stack

Using `helm`, install the `kube-prometheus-stack` chart, setting `prometheusSpec` values that allow `prometheus` to scrape metrics from pods and services in other namespaces. This is required in order to scrape metrics from the `ingress-nginx` controller pod which runs in `ingress-nginx` namespace.
```
bash% helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
bash% helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack
--set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
--set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```
## Get Grafana Password
```
bash% kubectl get secret --namespace default kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```
## Create Ingress
