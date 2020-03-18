#!/bin/bash
kubectl create namespace efs-provisioner
kubectl config set-context "$(kubectl config current-context)" --namespace=efs-provisioner
helm install -f efs-provisioner-config.yml stable/efs-provisioner
echo "*******************************************"
echo "sleeping for 30 seconds before pulling data"
echo "*******************************************"
sleep 30
kubectl describe pod
kubectl get sc
helm ls