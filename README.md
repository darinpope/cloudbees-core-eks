# cloudbees-core-eksctl

This is a specific example of how to create an EKS cluster so that CloudBees Core will be completely internal (all private subnets and internal ELB).

## Prerequisites

* a VPC with 3 private subnets that have a large number of IP addresses in each subnet

## Required Tooling

You have two options for tooling. You can:

* build your own
* use a Docker image that already has all the tooling

### Build Your Own

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
  * https://eksctl.io/introduction/#installation
  * `eksctl version` 
* `helm`
  * use 3.x by installing just the `helm` binary
    * https://github.com/helm/helm/releases/tag/v3.2.1
    * `helm version`
  * if you want to use Helm 2.x, then install `helm` and `tiller`
    * https://github.com/helm/helm/releases/tag/v2.16.3
      * NOTE: both the `helm` and `tiller` binaries are in the tarball 
    * `helm version --client`
* `cloudbees`
  * https://docs.cloudbees.com/docs/cloudbees-core/latest/cloud-admin-guide/cncf-tool
  * `cloudbees version`
  * NOTE: since we haven't installed EKS yet, the server calls will fail, but the client version will return.
* `kubens` and `kubectx`
  * https://kubectx.dev

### Use a Docker image

* `docker pull darinpope/eks-tooling:latest`
* `docker run -it -v $HOME/.aws:/root/.aws -v $HOME/github/cloudbees-core-eks:/root/cloudbees-core-eks --env AWS_DEFAULT_PROFILE=default --env AWS_PROFILE=default darinpope/eks-tooling:latest /bin/bash`
  * `cd /root/cloudbees-core-eks`

## Installation

### Create Cluster

* `cd eksctl`
* Replace the contents of `bootstrap.sh` with your own bootstrap script
  * be sure to prepend 6 spaces (not tabs) to each line in your `bootstrap.sh` file like the example file has. This is to line up with the YAML in `config.template` when it is processed.
  * https://github.com/awslabs/amazon-eks-ami/blob/81ac166912ebbdb46c56549efe3d88331f524cad/amazon-eks-nodegroup.yaml#L484
* Modify lines 3-20 of `configure.sh` with your data. For example, here's a few of the values:
  * `OUTPUT_FILENAME=config-71102d.yml`
  * `CLUSTER_NAME=my-cool-cluster`
  * `AMI_ID=ami-0cfce90d1d571102d`
  * `NODEGROUP_NAME_MASTERS=cloudbees-core-masters-71102d`
  * `NODEGROUP_NAME_REGULAR=cloudbees-core-regular-71102d`
  * `NODEGROUP_NAME_SPOT=cloudbees-core-spot-71102d`
* NOTE: You might want to set `OUTPUT_FILENAME` to a date instead of the last six characters of the AMI id. Chose whatever is best for you from a versioning perspective. Regardless of what you choose, you should keep all your configuration files (including others we are getting ready to get to) under version control.
* NOTE: You can search for the official AMIs by looking for "Owner: Amazon Images" and "AMI Name: amazon-eks-node". From there, you'll see a list of the official EKS optimized AMIs for that region.
* `./configure.sh`
* Review the changes to the output file (in this case `config-71102d.yml`) and make sure that everything looks correct
  * if you do not want to have SSH access to your worker nodes, remove the `ssh` blocks from your generated file
  * if you do not want to have custom user data, remove the `overrideBootstrapCommand` block from your generated file
* `eksctl create cluster -f config-71102d.yml`
* Get a coffee or two. This will take somewhere between 30-45 minutes.
* When complete...
  * `aws eks --region us-east-1 update-kubeconfig --name my-cool-cluster`
* `kubectl get nodes`
  * you should see 5 nodes

### If using Helm 2.x, install Tiller into the cluster

* `cd ../kubectl`
* `./install-helm-and-tiller.sh`

### If using Helm 3.x, add the official Helm stable charts

* `helm repo add stable https://kubernetes-charts.storage.googleapis.com/`
* `helm repo update`

### Create EFS volume

Create the EFS volume in whatever way you want. Make sure that the Mount Targets are created in the same private subnets as the worker nodes are created. When creating the Mount Targets, delete the `default` security group and associate the `*-ClusterSharedNodeSecurityGroup-*` security group from the worker node to all of the EFS subnets.

NOTE: Wait about 5 minutes before moving on to the next step. It take a couple of minutes for the DNS entry for the EFS endpoint to propagate.

### Install efs-provisioner

* `cd ../helm`
* Edit the `efs-provisioner-config.yml` file:
  * set `efsFileSystemId` to the EFS volume's `fs-` id
  * set `awsRegion` to the AWS region the cluster is installed in
* `./install-efs-provisioner.sh`
* Review the output
  * Make sure all 4 Conditions are True from the `describe` output. If they aren't, you probably didn't set the correct security group the the EFS Mount Targets.
  * From the `sc` output, you should see two values. Leave `gp2` set as the default.
    * `aws-efs`
    * `gp2 (default)`

### Install cluster-autoscaler

NOTE: The documentation for installing cluster-autoscaler for EKS is found at https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html. Read this documentation prior to doing the following steps.

* `kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml`
* `kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"`
* `kubectl -n kube-system edit deployment.apps/cluster-autoscaler`
  * replace `<YOUR CLUSTER NAME>` with your cluster name
  * add the other 2 items to the bottom of the script call (refer to the documentation):
    * `--balance-similar-node-groups`
    * `--skip-nodes-with-system-pods=false`
* `kubectl -n kube-system set image deployment.apps/cluster-autoscaler cluster-autoscaler=k8s.gcr.io/cluster-autoscaler:v1.16.5`
  * refer to the documentation to select the correct version of the autoscaler. At the time of this writing, the latest for 1.16 is `v1.16.5` https://github.com/kubernetes/autoscaler/releases
* `kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler`
  * Give the process a couple of minutes to startup. You should see something like the following in the log. If you don't, that means cluster-autoscaler is not installed properly.

```
I1227 14:01:10.840732       1 static_autoscaler.go:147] Starting main loop
I1227 14:01:10.841184       1 utils.go:626] No pod using affinity / antiaffinity found in cluster, disabling affinity predicate for this loop
I1227 14:01:10.841206       1 static_autoscaler.go:303] Filtering out schedulables
I1227 14:01:10.841258       1 static_autoscaler.go:320] No schedulable pods
I1227 14:01:10.841279       1 static_autoscaler.go:328] No unschedulable pods
I1227 14:01:10.841295       1 static_autoscaler.go:375] Calculating unneeded nodes
I1227 14:01:10.841308       1 utils.go:583] Skipping ip-10-0-103-33.ec2.internal - node group min size reached
I1227 14:01:10.841320       1 utils.go:583] Skipping ip-10-0-101-243.ec2.internal - node group min size reached
I1227 14:01:10.841328       1 utils.go:583] Skipping ip-10-0-103-166.ec2.internal - node group min size reached
I1227 14:01:10.841335       1 utils.go:583] Skipping ip-10-0-103-134.ec2.internal - node group min size reached
I1227 14:01:10.841344       1 utils.go:583] Skipping ip-10-0-102-23.ec2.internal - node group min size reached
I1227 14:01:10.841423       1 static_autoscaler.go:402] Scale down status: unneededOnly=true lastScaleUpTime=2019-12-27 14:00:50.829406654 +0000 UTC m=+19.997223477 lastScaleDownDeleteTime=2019-12-27 14:00:50.82940675 +0000 UTC m=+19.997223575 lastScaleDownFailTime=2019-12-27 14:00:50.829406845 +0000 UTC m=+19.997223669 scaleDownForbidden=false isDeleteInProgress=false
```

### Install ingress

NOTE: This installation process assumes you are *not* using SSL certificates.

* `cd ../helm`

If you want a private ELB:

* `./install-ingress-private.sh`
  * save the "internal-..." value from the EXTERNAL-IP column. You'll use it in the CNAME step.

If you want a public ELB:

* `./install-ingress-public.sh`
  * save the value from the EXTERNAL-IP column. You'll use it in the CNAME step.

### Create CNAME entry

* create a CNAME entry for your domain, i.e. `cloudbees.example.com`, to the ELB's address, i.e. `internal-abc-xyz.us-east-1.elb.amazonaws.com`

NOTE: Wait until the DNS entry is resolving before moving on to the next step. If you are using Route53, it is usually pretty fast. Other DNS providers tend to be a bit slower.

### Validate the cluster

* using the example from above `cloudbees check kubernetes --host-name cloudbees.example.com`
  * there should be an `[OK]` preceding each line of output. If not, resolve the problem until all the lines do have an `[OK]`

### Configure CloudBees Helm charts

* `cd ../helm`
* `./setup-cloudbees-charts.sh`

### Select the version of CloudBees Core to install

* `helm search repo cloudbees-core --versions`
  * select the value from the CHART_VERSION column. For example, 3.9.0 will install CloudBees Core 2.204.2.2. For the rest of this process, that will be the version that we install.

### Create the SSL certificate

* You can generate a 90 day certificate from https://www.sslforfree.com/
* Once you get the zip file, merge certificate.crt and ca_bundle.crt
  * `cat certificate.crt ca_bundle.crt > merged.crt`
  * inside of merged.crt, you'll have to add a carriage return at the end of the certificate
    * `-----END CERTIFICATE-----`

### Create secret using the certificate you created

`kubectl create secret tls core-example-com-tls --key /root/cloudbees-core-eks/private.key --cert /root/cloudbees-core-eks/merged.crt --namespace cloudbees-core`

### Install Cloudbees Core

If you are using EFS as your storage:

* Edit the `cloudbees-config-efs.yml` file:
  * change `HostName` to your domain name
* `./install-cloudbees-core-efs.sh 3.9.0`
  * be sure to pass the chart version from the previous step to the script
* You should see that the pod is Running
* You'll see the output from initialAdminPassword. You'll use that value when you open the url in a browser.

If you are using EBS as your storage:

* Edit the `cloudbees-config.yml` file:
  * change `HostName` to your domain name
* `./install-cloudbees-core.sh 3.9.0`
  * be sure to pass the chart version from the previous step to the script
* You should see that the pod is Running
* You'll see the output from initialAdminPassword. You'll use that value when you open the url in a browser.

### Configure Cloudbees Core

* open your CNAME in a browser
  * for example http://cloudbees.example.com/cjoc/
* enter the initialAdminPassword
* apply your license
* click on `Install Suggested plugins`
* if you get an `Incremental Upgrade Available` screen, click on `Install`
* create user and click on `Save and Continue`
* if you received an `Incremental Upgrade Available` screen, you'll click on `Restart`
* if you did *not* receive an `Incremental Upgrade Available` screen, click on `Start using...`
  * in this case, as soon as the Operations Center starts, do a restart of the Operations Center by adding a `/restart` to the end of the url

### Set the Master Provisioning configuration

* On the Operations Center under `Manage Jenkins` -> `Configure System` -> `Kubernetes Master Provisioning` -> `Advanced`:
  * Global System Properties):
```
cb.BeekeeperProp.noFullUpgrade=true
com.cloudbees.masterprovisioning.kubernetes.KubernetesMasterProvisioning.storageClassName=aws-efs
```
  * YAML:
```
kind: StatefulSet
spec:
  template:
    metadata:
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
    spec:
      nodeSelector:
        partition: masters
      tolerations:
      - key: partition
        operator: Equal
        value: masters
        effect: NoSchedule
```
* Click `Save`

Your configuration should look similar to the image below:

![](/images/master-provisioning.png)

### Create a Managed Master

The purpose of this master is to test that the agents are working as expected in the upcoming steps. For our example, we are going to assume this master is just temporary and is going to be deleted once we finish our tests.

On the Operations Center:

* click on `New Item`
* Enter an item name: `mm1`
* Select `Managed Master`
* Click `OK`
* Review the settings, but do not make any changes
* Click `Save`
* Wait for 2-3 minutes for the master to start
* When you see both the `Approved` and `Connected` blue balls, click over to the master

On the Managed Master:

* click on `Install Suggested plugins`
* if you get an `Incremental Upgrade Available` screen, click on `Install`
* if you received an `Incremental Upgrade Available` screen, you'll click on `Restart`
* if you did *not* receive an `Incremental Upgrade Available` screen, click on `Start using CloudBees Core Managed Master`
  * do a restart of the Managed Master by adding a `/restart` to the end of the url

### Test the regular agents

* click on `New Item`
* Enter an item name: `regular`
* Select `Pipeline`
* Click `OK`
* Scroll down to the Pipeline section and paste in the following pipeline script:
```
pipeline {
    options { 
        buildDiscarder(logRotator(numToKeepStr: "5"))
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
        stage("Deploy") {
            steps {
                container("aws-cli") {
                    sh "aws --version"
                }
            }
        }
        stage("sleep") {
          steps {
            sleep 180
          }
        }
    }
}
```
* Click `Save`
* Click `Build Now`
* `kubectl get pods -o wide`
* look at the `regular-pod-...` pod and determine which `NODE` it is on. Verify that the pod is on the "regular" agent worker node instance. To find out what the regular agent instance is, look at the EC2 console and look at the name.

![](/images/regular-agents.png)

### Test the spot agents

* click on `New Item`
* Enter an item name: `spot`
* Select `Pipeline`
* Click `OK`
* Scroll down to the Pipeline section and paste in the following pipeline script:
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
        stage("Deploy") {
            steps {
                container("aws-cli") {
                    sh "aws --version"
                }
            }
        }
        stage("sleep") {
          steps {
            sleep 180
          }
        }
    }
}
```
* Click `Save`
* Click `Build Now`
* `kubectl get pods -o wide`
* look at the `spot-pod-...` pod and determine which `NODE` it is on. Verify that the pod is on the "spot" agent worker node instance. To find out what the spot agent instance is, look at the EC2 console and look at the name.

![](/images/spot-agents.png)

## Upgrading CloudBees Core

To upgrade CloudBees Core, select the version that you want to upgrade to using `helm search repo cloudbees-core --versions`. Since we installed `3.9.0`, let's upgrade to `3.11.0`, which will give us CloudBees Core 2.204.3.7.

If EFS:

`helm upgrade cloudbees-core cloudbees/cloudbees-core -f cloudbees-config-efs.yml --namespace cloudbees-core --version 3.11.0`

If EBS:

`helm upgrade cloudbees-core cloudbees/cloudbees-core -f cloudbees-config.yml --namespace cloudbees-core --version 3.11.0`

After the upgrade applies, wait a couple of minutes for the changes to apply. Then, login to the Operations Center and verify the version is correct.

NOTE: This upgrade only upgrades the Operations Center. It is your responsibilty to upgrade the Masters when you are ready to do so.

## Update the EKS cluster to the latest version

* `cd eksctl`
* `eksctl update cluster -f config-71102d.yml`
  * NOTE: the `-f` file value should be your most current configuration file

## Upgrading EKS worker nodes

Let's assume that you need to replace your worker nodes every 30 days due to security requirements. Using the following process will create new worker node pools and drain off and destroy the old worker node pools.

NOTE: There will be short (roughly 2-3 minutes, but could be longer) downtimes of the Operations Center and Masters when the drain process happens during the `delete nodegroup` as the pods are migrated to the new worker nodes. With this in mind, you will want to execute this process during low load times in order to minimize impact.

* `cd eksctl`
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
  * Diff your old config file against the new config file, i.e. config-71102d.yml vs config-a07557.yml, and make sure that the only changes are the AMI id and node group names
* `eksctl get nodegroups --cluster my-cool-cluster`
  * review the existing node groups before starting
```
CLUSTER		NODEGROUP			CREATED			MIN SIZE	MAX SIZE	DESIRED CAPACITY	INSTANCE TYPE	IMAGE ID
my-cool-cluster	cloudbees-core-masters-71102d	2019-12-27T13:32:34Z	3		9		0			r5.xlarge	ami-0cfce90d1d571102d
my-cool-cluster	cloudbees-core-regular-71102d	2019-12-27T13:32:34Z	1		3		0			m5.large	ami-0cfce90d1d571102d
my-cool-cluster	cloudbees-core-spot-71102d	2019-12-27T13:32:34Z	1		9		0			m4.large	ami-0cfce90d1d571102d
```
* `eksctl create nodegroup -f config-a07557.yml`
  * this will create the new node groups
  * it can take about 8-15 minutes for the new node groups to start up
```
CLUSTER		NODEGROUP			CREATED			MIN SIZE	MAX SIZE	DESIRED CAPACITY	INSTANCE TYPE	IMAGE ID
my-cool-cluster	cloudbees-core-masters-71102d	2019-12-27T13:32:34Z	3		9		0			r5.xlarge	ami-0cfce90d1d571102d
my-cool-cluster	cloudbees-core-masters-a07557	2019-12-27T15:26:17Z	3		9		0			r5.xlarge	ami-087a82f6b78a07557
my-cool-cluster	cloudbees-core-regular-71102d	2019-12-27T13:32:34Z	1		3		0			m5.large	ami-0cfce90d1d571102d
my-cool-cluster	cloudbees-core-regular-a07557	2019-12-27T15:26:17Z	1		3		0			m5.large	ami-087a82f6b78a07557
my-cool-cluster	cloudbees-core-spot-71102d	2019-12-27T13:32:34Z	1		9		0			m4.large	ami-0cfce90d1d571102d
my-cool-cluster	cloudbees-core-spot-a07557	2019-12-27T15:26:18Z	1		9		0			m4.large	ami-087a82f6b78a07557
```
* `eksctl get nodegroups --cluster my-cool-cluster`
  * do not continue to the next step until all worker nodes are in a `Running` state and fully initialized. You can check this in the EC2 console or however you check your EC2 instance states.
* `eksctl delete nodegroup -f config-a07557.yml --only-missing`
  * this is a dry run. it will tell you what will happen when you execute the next item.
  * review the `(plan)` items from the output before continuing to the next step to make sure it will delete the correct node groups
* `eksctl delete nodegroup -f config-a07557.yml --only-missing --approve`
  * this is where the existing node groups will be cordoned, drained, and terminated.
  * this is the time where you will experience brief outages as the Operations Center and Master pods are restarted on the new worker nodes
  * wait about 5 minutes before moving to the next step
* `eksctl get nodegroups --cluster my-cool-cluster`
  * there should only be 3 node groups remaining, all with the expected AMI id
```
CLUSTER		NODEGROUP			CREATED			MIN SIZE	MAX SIZE	DESIRED CAPACITY	INSTANCE TYPE	IMAGE ID
my-cool-cluster	cloudbees-core-masters-a07557	2019-12-27T15:26:17Z	3		9		0			r5.xlarge	ami-087a82f6b78a07557
my-cool-cluster	cloudbees-core-regular-a07557	2019-12-27T15:26:17Z	1		3		0			m5.large	ami-087a82f6b78a07557
my-cool-cluster	cloudbees-core-spot-a07557	2019-12-27T15:26:18Z	1		9		0			m4.large	ami-087a82f6b78a07557
```

## Destroying the Cluster

### Change the security groups on the EFS Mount Targets

* remove the `*-ClusterSharedNodeSecurityGroup-*` security group from each subnet
* add the `default` group back to each subnet

### Delete the EKS cluster

* `eksctl delete cluster -f config-a07557.yml --wait`
  * NOTE: the `-f` file value should be your most current configuration file

### Delete the EFS volume

* delete the EFS volume following your standard processes

### Delete any EBS volumes

* delete any EBS volumes that are showing as *available* that were associated with your cluster.
