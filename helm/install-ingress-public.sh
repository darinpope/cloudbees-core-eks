#!/bin/bash
kubectl create namespace ingress-nginx
kubectl config set-context "$(kubectl config current-context)" --namespace=ingress-nginx
helm install nginx-ingress stable/nginx-ingress --namespace ingress-nginx --values ingress-public-values.yaml --version 1.31.0
echo "************************************"
echo "sleeping for 90 seconds"
echo "************************************"
sleep 90
kubectl get -n ingress-nginx service
