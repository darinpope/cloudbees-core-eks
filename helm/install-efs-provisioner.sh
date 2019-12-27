#!/bin/bash
kubectl create namespace efs-provisioner
kubectl config set-context "$(kubectl config current-context)" --namespace=efs-provisioner
helm install --name efs-provisioner -f efs-provisioner-config.yml stable/efs-provisioner
sleep 30
kubectl describe pod
kubectl get sc