#!/bin/bash
kubectl create namespace cloudbees-core
kubectl config set-context "$(kubectl config current-context)" --namespace=cloudbees-core
helm install cloudbees-core -f cloudbees-config-efs.yml --namespace cloudbees-core cloudbees/cloudbees-core --version $1
echo "******************************************************************"
echo "sleeping for 120 seconds to give the cjoc pod a chance to start up"
echo "******************************************************************"
sleep 120
kubectl describe pod cjoc-0
kubectl exec cjoc-0 cat /var/jenkins_home/secrets/initialAdminPassword