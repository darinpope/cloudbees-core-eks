#!/bin/bash
kubectl create namespace cloudbees-core
kubectl config set-context "$(kubectl config current-context)" --namespace=cloudbees-core
helm install --name cloudbees-core -f cloudbees-config.yml --namespace cloudbees-core cloudbees/cloudbees-core --version $1
echo "***************************"
echo "sleeping for 60 seconds to give the cjoc pod a chance to start up"
echo "***************************"
sleep 60
kubectl describe pod cjoc-0
kubectl exec cjoc-0 cat /var/jenkins_home/secrets/initialAdminPassword