#!/bin/bash -x

##
## Installs prometheus and ingress-nginx with metrics enabled.
## Also installs cert-manager to use letsencrypt certificates with ingress.
##
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

install_ingress() {
  ## install ingress-nginx and enable metrics for prometheus
  ## additionalLabels.release should match the name of the helm release for kube-prometheus-stack

  ## controller runs in a separate namespace 
  kubectl create namespace ingress-nginx

  helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.additionalLabels.release="kube-prometheus-stack"
}

install_prometheus() {
  ## add prometheus repo
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

  ## install kube-prometheus-stack, instructing it to scrape pods and services in other namespaces
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
}

install_cert_manager() {
  local cert_manager_version=v1.8.0

  ## install cert-manager helm chart
  [[ $(helm repo list | grep jetstack) ]] || helm repo add jetstack https://charts.jetstack.io
  helm repo update 

  helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version ${cert_manager_version} \
  --set installCRDs=true
}

## main
install_ingress
install_prometheus
install_cert_manager

