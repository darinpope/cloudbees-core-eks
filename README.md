# cloudbees-core-eksctl

This is a specific example of how to create an EKS cluster so that CloudBees Core will be completely internal (all private subnets and internal ELB).

## Prerequisites

* a VPC with 3 private subnets that have a large number of IPS addresses in each subnet

## Required Tooling

In order for these instructions to work, you will need a Linux distribution. This has not been tested on macOS or Windows. All of these steps were tested using a Vagrant based CentOS 7.6 image.

* AWS CLI version 1
  * https://docs.aws.amazon.com/cli/latest/userguide/install-linux.html
  * `aws --version`
* `kubectl` (be sure to download the correct version for the EKS version you plan to install)
  * https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html
  * `kubectl version --client`
* `aws-iam-authenticator`
  * https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
  * `aws-iam-authenticator version`
* `eksctl`
  * https://eksctl.io/introduction/installation/
  * `eksctl version` 
* `helm` and `tiller` (Use 2.x, not 3.x)
  * https://github.com/helm/helm/releases/tag/v2.16.1
    * NOTE: both the `helm` and `tiller` binaries are in the tarball 
  * `helm version --client`
* `cloudbees`
  * https://docs.cloudbees.com/docs/cloudbees-core/latest/cloud-admin-guide/cncf-tool
  * `cloudbees version`
  * NOTE: since we haven't installed EKS yet, the server calls will fail, but the client version will return.
* `kubens` and `kubectx`
  * https://kubectx.dev
  * since these are just scripts wrapping kubectl, there are no related versions.

## Installation

### Create Cluster

* `cd eksctl`
* Replace the contents of `bootstrap.sh` with your own bootstrap script
  * be sure to prepend 6 spaces to each line in your `bootstrap.sh` file like the example file has. This is to line up with the YAML in `config.template` when it is processed.
* Modify lines 3-20 of `configure.sh` with your data
  * `OUTPUT_FILENAME=config-71102d.yml`
  * `CLUSTER_NAME=my-cool-cluster`
  * `AMI_ID=ami-0cfce90d1d571102d`
  * `NODEGROUP_NAME_MASTERS=cloudbees-core-masters-71102d`
  * `NODEGROUP_NAME_REGULAR=cloudbees-core-regular-71102d`
  * `NODEGROUP_NAME_SPOT=cloudbees-core-spot-71102d`
* NOTE: You might want to set `OUTPUT_FILENAME` to a date instead of the last six characters of the AMI id. Chose whatever is best for you from a versioning perspective. Regardless of what you choose, you should keep all your configuration files (including others we are getting ready to get to) under version control.
* `./configure.sh`
* Review the changes to the output file (in this case `config-71102d.yml`) and make sure that everything looks correct
* NOTE: if you do not want to have SSH access to your worker nodes, remove the `ssh` blocks from your generated file.
* `eksctl create cluster -f config-71102d.yml`
* Get a coffee or two. This will take somewhere between 30-45 minutes.
* When complete...
  * `aws eks --region us-east-1 update-kubeconfig --name my-cool-cluster`
* `kubectl get nodes`
  * you should see 5 nodes

### Install Helm and Tiller

* `cd ../kubectl`
* `./install-helm-and-tiller.sh`

### Create EFS volume

Create the EFS volume in whatever way you want. Make sure that the Mount Targets are created in the same subnets as the worker nodes are created. When creating the Mount Targets, delete the `default` security group and associate the `*-ClusterSharedNodeSecurityGroup-*` security group from the worker node to all of the EFS subnets.

### Install efs-provisioner

* `cd ../helm`
* Edit the `efs-provisioner-config.yml` file:
  * set `efsFileSystemId` to the EFS volume's `fs-` id
  * set `awsRegion` to the AWS region the cluster is installed in
* `./install-efs-provisioner.sh`
* Review the output
  * Make sure all 4 Conditions are True from the `describe` output. If they aren't, you probably didn't set the correct security group the the EFS Mount Targets.
  * From the `sc` output, you should see two values. Leave `gp2` set as the default.
    * `efs`
    * `gp2 (default)`

### Install cluster-autoscaler

NOTE: The documentation for installing cluster-autoscaler for EKS is found at https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html

* `kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml`
* `kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"`
* `kubectl -n kube-system edit deployment.apps/cluster-autoscaler`
  * replace `<YOUR CLUSTER NAME>` with your cluster name
  * add the other 2 items to the bottom of the script call (refer to the documentation):
    * `--balance-similar-node-groups`
    * `--skip-nodes-with-system-pods=false`
* `kubectl -n kube-system set image deployment.apps/cluster-autoscaler cluster-autoscaler=k8s.gcr.io/cluster-autoscaler:v1.14.7`
  * refer to the documentation to select the correct version of the autoscaler. At the time of this writing, the latest for 1.14 is `v1.14.7`
* `kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler`
  * Give the process a couple of minutes to startup. You should see all the nodegroups listed in the log.

### Install ingress

NOTE: This installation process assumes you are *not* using SSL certificates. If you are, follow more detailed instructions at https://docs.cloudbees.com/docs/cloudbees-core/latest/eks-install-guide/installing-eks-using-installer#_setting_up_https  The key part below is downloading `service-l4.yaml` and adding the annotation in order for the ELB to be created in the private subnets.

* `kubectl create namespace ingress-nginx`
* `kubectl config set-context $(kubectl config current-context) --namespace=ingress-nginx`
* `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/mandatory.yaml`
* `wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/aws/service-l4.yaml`
* edit service-l4.yaml
  * add `service.beta.kubernetes.io/aws-load-balancer-internal: "0.0.0.0/0"` as an annotation in order to create the internal load balancer
* `kubectl -n ingress-nginx apply -f service-l4.yaml`
* `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/aws/patch-configmap-l4.yaml`
* `kubectl patch -n ingress-nginx service ingress-nginx -p '{"spec":{"externalTrafficPolicy":"Local"}}'`

### Create CNAME entry

* create a CNAME entry for your domain, i.e. `cloudbees.example.com`, to the ELB's address, i.e. `internal-abc-xyz.us-east-1.elb.amazonaws.com`

### Validate the cluster

* using the example from above `cloudbees check kubernetes --host-name cloudbees.example.com`
  * there should be an `[OK]` preceding each line of output. If not, resolve the problem until all the lines do have an `[OK]`

### Configure CloudBees Helm charts

* `cd ../helm`
* `./setup-cloudbees-charts.sh`

### Select the version of CloudBees Core to install

* `helm search cloudbees-core --versions`
  * select the value from the CHART_VERSION column. For example, 3.5.0 will install CloudBees Core 2.176.4.3. For the rest of this process, that will be the version that we install.

### Install Cloudbees Core

* `cd ../helm`
* Edit the `cloudbees-config.yml` file:
  * change `HostName` to your domain name
* `kubectl create namespace cloudbees-core`
* `kubectl config set-context $(kubectl config current-context) --namespace=cloudbees-core`
* `helm install --name cloudbees-core -f cloudbees-config.yml --namespace cloudbees-core cloudbees/cloudbees-core --version 3.5.0`
* wait about 30 seconds
* `kubectl describe pod cjoc-0`
  * You should see that the pod is Running
* `kubectl exec cjoc-0 cat /var/jenkins_home/secrets/initialAdminPassword`
  * You'll use this value once you start the configuration process

### Configure Cloudbees Core

* enter the initialAdminPassword
* request a license
* 

### Set the Master configurations so they are created correctly

On the Operations Center under `Manage Jenkins` -> `Configure System` -> `Kubernetes xxx` -> `Advanced`:

Global System Properties:
`cb.BeekeeperProp.noFullUpgrade=true`

For Managed Master, the annotation is added in the configuration page under the `Advanced Configuration - YAML` parameter. The YAML snippet to add would look like:

```
kind: StatefulSet
spec:
  template:
    metadata:
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
```          

### Create a Managed Master

### Test the regular agents

```
pipeline {
    options { 
        buildDiscarder(logRotator(numToKeepStr: "5"))
        //discard old builds to reduce disk usage
    }
    agent {
        kubernetes {
        label "regular-pod"
        yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: maven
      image: maven:3.6.3-jdk-8
      command:
      - cat
      tty: true
    - name: aws-cli
      image: infrastructureascode/aws-cli:1.16.301
      command:
      - cat
      tty: true
  nodeSelector:
    partition: regular-agents
  tolerations:
    - key: partition
      operator: Equal
      value: regular-agents
      effect: NoSchedule
"""
        }
    }
    stages {
        stage("Build and Test with Maven") {
            steps {
                container("maven") {
                    sh "mvn --version"
                }
            }
        }
        stage ("Deploy") {
            steps {
                container("aws-cli") {
                    sh "aws --version"
                }
            }
        }
    }
}
```

### Test the spot agents

```
pipeline {
    options { 
        buildDiscarder(logRotator(numToKeepStr: "5"))
    }
    agent {
        kubernetes {
        label "spot-pod"
        yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: maven
      image: maven:3.6.3-jdk-8
      command:
      - cat
      tty: true
    - name: aws-cli
      image: infrastructureascode/aws-cli:1.16.301
      command:
      - cat
      tty: true
  nodeSelector:
    partition: spot-agents
  tolerations:
    - key: partition
      operator: Equal
      value: spot-agents
      effect: NoSchedule
"""
        }
    }
    stages {
        stage("Build and Test with Maven") {
            steps {
                container("maven") {
                    sh "mvn --version"
                }
            }
        }
        stage ("Deploy") {
            steps {
                container("aws-cli") {
                    sh "aws --version"
                }
            }
        }
    }
}
```

## Upgrading CloudBees Core

To upgrade CloudBees Core, select the version that you want to upgrade to using `helm search cloudbees-core --versions`. Since we installed `3.5.0`, let's upgrade to `3.8.0`, which will give us CloudBees Core 2.204.1.3.

`helm upgrade cloudbees-core cloudbees/cloudbees-core -f cloudbees-config.yml --namespace cloudbees-core --version 3.8.0`

After the upgrade applies, login to the Operations Center and verify the version is correct.

## Update the EKS cluster to the latest version

* `eksctl update cluster -f config-71102d.yml`
  * NOTE: the `-f` file value should be your most current configuration file

## Upgrading EKS worker nodes

Let's assume that you need to replace your worker nodes every 30 days due to security requirements. Using the following process will create new worker node pools and drain off and destroy the old worker node pools.

NOTE: There will be short downtimes of the Operations Center and Masters when the drain process happens during the `delete nodegroup` as the pods are migrated to the new worker nodes. You will want to execute this process during low load times in order to minimize impact.

* `cd ../eksctl`
* Edit `configure.sh` and modify the variables to the new values that you want.
  * `OUTPUT_FILENAME`
  * `AMI_ID`
  * `NODEGROUP_NAME_MASTERS`
  * `NODEGROUP_NAME_REGULAR`
  * `NODEGROUP_NAME_SPOT`
* For our example, here's our new values:
  * `OUTPUT_FILENAME=config-a07557.yml`
  * `AMI_ID=ami-087a82f6b78a07557`
  * `NODEGROUP_NAME_MASTERS=cloudbees-core-masters-a07557`
  * `NODEGROUP_NAME_REGULAR=cloudbees-core-regular-a07557`
  * `NODEGROUP_NAME_SPOT=cloudbees-core-spot-a07557`
* `./configure.sh`
* `eksctl get nodegroups --cluster <your cluster name>`
  * review the existing node groups before starting
* `eksctl create nodegroup -f config-a07557.yml`
  * this will create the new node groups
* `eksctl get nodegroups --cluster <your cluster name>`
  * do not continue to the next step until all worker nodes are in a `Running` state
* `eksctl delete nodegroup -f config-a07557.yml --only-missing`
  * this is a dry run. it will tell you what will happen when you execute the next item.
* `eksctl delete nodegroup -f config-a07557.yml --only-missing --approve`
  * this is where the existing node groups will be cordoned, drained, and terminated.
  * this is the time where you will experience brief outages as the Operations Center and Master pods are restarted on the new worker nodes

## Destroying the Cluster

### Change the security groups on the EFS Mount Targets

### Delete the EKS cluster

`eksctl delete cluster -f config-a07557.yml --wait`

### Delete the EFS volume


