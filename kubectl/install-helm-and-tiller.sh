#!/bin/bash
kubectl --namespace kube-system create serviceaccount tiller
kubectl --namespace kube-system create clusterrolebinding tiller-cluster-rule  --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller
echo "************************************"
echo "sleeping for 15 seconds"
echo "************************************"
sleep 15
helm version