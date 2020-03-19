#!/bin/bash
helm repo add cloudbees https://charts.cloudbees.com/public/cloudbees 
helm repo update
helm search repo cloudbees-core --versions
