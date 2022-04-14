#!/bin/bash -x

##
## install_charts.sh
## Installs prometheus and grafana with a bunch of useful addons.
## Installs ingress-nginx with support for prometheus metrics.
## Installs cert-manager to use letsencrypt certificates with ingress.
## Ordering is important. Install prometheus first.
##
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export KUBECONFIG=$(ls /terraform/kubeconfig_ekstest*)

add_repo() {
  local name=$1
  local url=$2
  [[ $(helm repo list | grep $name) ]] || helm repo add $name $url
  helm repo update
}

install_prometheus() {
  ## We need to install prometheus before we install ingress-nginx.
  add_repo prometheus-community https://prometheus-community.github.io/helm-charts

  ## Install kube-prometheus-stack, instructing it to scrape pods and services in other namespaces.
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
}

install_ingress() {
  ## Install ingress-nginx and enable metrics for prometheus (after installing prometheus).
  ## additionalLabels.release should match the name of the helm release for prometheus.
  local prometheus_release=kube-prometheus-stack

  ## ingress-nginx runs in a separate namespace.
  helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.additionalLabels.release="${prometheus_release}"
}

install_cert_manager() {
  ## install cert-manager helm chart
  local cert_manager_version=v1.8.0
  add_repo jetstack https://charts.jetstack.io

  ## cert-manager runs in a separate namespace.
  helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version ${cert_manager_version} \
  --set installCRDs=true
}

## main
install_prometheus
install_ingress
install_cert_manager
