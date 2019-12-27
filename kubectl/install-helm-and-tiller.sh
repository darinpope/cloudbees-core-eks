#!/bin/bash
kubectl --namespace kube-system create serviceaccount tiller
kubectl --namespace kube-system create clusterrolebinding tiller-cluster-rule  --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller
echo sleeping for 15 seconds
sleep 15
helm version