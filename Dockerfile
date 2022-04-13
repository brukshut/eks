FROM debian:latest

ARG kubectl_version=1.21.2

RUN apt-get update && apt-get install curl git lsb-release python3 python3-pip software-properties-common vim -y && pip3 install awscli

RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - && \
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && \
    apt-get update && \
    apt-get install terraform

RUN curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod +x /tmp/get_helm.sh && \
    /tmp/get_helm.sh

RUN curl -o /usr/local/bin/aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/$kubectl_version/2021-07-05/bin/linux/amd64/aws-iam-authenticator && chmod 0755 /usr/local/bin/aws-iam-authenticator
RUN curl -o usr/local/bin/kubectl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod 0755 /usr/local/bin/kubectl

ADD terraform /terraform
