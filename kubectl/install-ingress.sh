#!/bin/bash
kubectl create namespace ingress-nginx
kubectl config set-context "$(kubectl config current-context)" --namespace=ingress-nginx
kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/mandatory.yaml
kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/aws/service-l4.yaml
kubectl annotate -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/aws/service-l4.yaml service.beta.kubernetes.io/aws-load-balancer-internal="0.0.0.0/0"
kubectl annotate -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/aws/service-l4.yaml --overwrite=true service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout="3600"
kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/aws/patch-configmap-l4.yaml
kubectl patch -n ingress-nginx service ingress-nginx -p '{"spec":{"externalTrafficPolicy":"Local"}}'
echo "************************************"
echo "sleeping for 90 seconds"
echo "************************************"
sleep 90
kubectl get -n ingress-nginx service