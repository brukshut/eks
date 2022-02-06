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
bash% terraform init
bash% terraform plan
bash% terraform apply --auto-approve
```
## Locating The Resulting Kubeconfig File

The eks module builds the cluster and produces a kubeconfig file in the local directory. With the kubeconfig, we can deploy a simple `nginx` application. From the running container, export the `KUBECONFIG` environment variable.
```
root@b6800197b12d:/# export KUBECONFIG=/terraform/kubeconfig_ekstest-asdf1243
```
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

A `LoadBalancer` service is created when we deploy the `nginx` service. You can retrieve the endpoint using `kubectl`.
```
root@95558170bbe5:/terraform# kubectl get service nginx --no-headers | awk {'print $4'}
a3b022452b445405783e2e61895c8642-1108080924.us-west-1.elb.amazonaws.com
```
The `nginx` application can be accessed by opening a browser and pointing it to the following `http` endpoint.
```
http://a3b022452b445405783e2e61895c8642-1108080924.us-west-1.elb.amazonaws.com
```
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

We can use `terraform destroy` to tear down the cluster that we have created. Before we need to do this, we must delete the `nginx` service, which creates a Load Balancer and security group that is attached to the VPC.
```
bash% terraform destroy --auto-approve
```
## Restarting An Exited Container

Inside the running container, the `/terraform/terraform.tfstate` file describes the AWS resources that the module creates. If you accidentally exit the running container after standing up the cluster, you can restart the last running container in order to run `terraform destroy`.
```
bash% docker start $(docker ps -q -l)
bash% docker attach $(docker ps -q -l)
```
