#!/bin/bash

#-------------------------------------------------------------------------------
# Copyright (c) 2019, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#--------------------------------------------------------------------------------

set -e; set -o xtrace

#installation of database differs accoring to the type of database resource found.
#This function is to deploy the database correctly as found in the test plan.

# ---debug--- deploymentRepositoryLocation="/Users/nishika_de_silva/github_NishikaDeSilva/kubernetes/testgrid/kubernetes-is-support"
# ---debug---  namespace="postgres-test"

HELM_VALUES="$deploymentRepositoryLocation/advanced/helm/is-pattern-1/values.yaml"
mysql=("wso2is-rdbms-service-mysql" "3306" "com.mysql.jdbc.Driver" "SELECT 1" "false")
postgres=("wso2is-rdbms-service-postgresql" "5432" "org.postgresql.Driver" "SELECT 1; COMMIT" "true")
#TODO: add mssql and oracle

function helm_deploy(){

  create_value_yaml
  create_gcr_secret
  change_k8sContext
  #install resources using helm
  resources_deployment

}

# Read a property file to a given associative array
#
# $1 - Property file
# $2 - associative array
# How to call
# declare -A somearray
# read_property_file testplan-props.properties somearray
read_property_file() {
    local property_file_path=$1
    # Read configuration into an associative array
    # IFS is the 'internal field separator'. In this case, your file uses '='
    local -n configArray=$2
    IFS="="
    while read -r key value
    do
      [[ -n ${key} ]] && configArray[$key]=$value
    done < ${property_file_path}
    unset IFS
}

function addConnectorInfo(){

port="${DB}[1]"; host="${DB}[0]"; drivercls="${DB}[2]"; validQ="${DB}[3]"; defAutoCom="${DB}[4]"

if [[ ${DB} != "mysql" ]];then
cat > ${HELM_VALUES} << EOF
wso2:
  connector:
    mysql:
      enabled: false
    $DB:
      enabled: true
    host: ${!host}
    port: "${!port}"
    username: wso2carbon
    password: wso2carbon
    driverClass: ${!drivercls}
    validationQuery: "${!validQ}"
    defaultAutoCommit: "${!defAutoCom}"
EOF
else
cat > ${HELM_VALUES} << EOF
wso2:
  connector:
    mysql:
      enabled: true
    host: ${!host}
    port: "${!port}"
    username: wso2carbon
    password: wso2carbon
    driverClass: ${!drivercls}
    validationQuery: "${!validQ}"
    defaultAutoCommit: "${!defAutoCom}"
EOF
fi

}

function addSubscriptionInfo(){
cat >> ${HELM_VALUES} << EOF
  subscription:
    username: ""
    password: ""
EOF
}

function addDeploymentInfo(){
cat >> ${HELM_VALUES} << EOF
  deployment:
    wso2is:
     dockerRegistry: "asia.gcr.io"
     imageName: "testgrid/wso2-docker/wso2is"
     imageTag: "5.8.0-$OS-$JDK-$DB"
     replicas: 1
     minReadySeconds: 30
     strategy:
       rollingUpdate:
         maxSurge: 1
         maxUnavailable: 0
     livenessProbe:
       initialDelaySeconds: 250
       periodSeconds: 10
     readinessProbe:
       initialDelaySeconds: 250
       periodSeconds: 10
     resources:
       # These are the minimum resource recommendations for running WSO2 Identity server profiles
       # as per official documentation (https://docs.wso2.com/display/IS580/Installation+Prerequisites).
       requests:
         memory: "2Gi"
         cpu: "2000m"
       limits:
         memory: "4Gi"
         cpu: "4000m"
     imagePullPolicy: Always
EOF
}

function addLoggingInfo(){
cat >> ${HELM_VALUES} << EOF
  centralizedLogging:
    enabled: false
    logstash:
      imageTag: 7.2.0
      elasticsearch:
        host: wso2-elasticsearch-master
        username: "elastic"
        password: "changeme"
      indexNodeID:
        wso2ISNode: "wso2is-node"
EOF
}

function addK8sInfo(){
cat >> ${HELM_VALUES} << EOF

kubernetes:
  svcaccount: "wso2svc-account"
EOF
}

function create_value_yaml(){

  file=$INPUT_DIR/infrastructure.properties
  declare -g -A infra_props
  read_property_file "${INPUT_DIR}/infrastructure.properties" infra_props
  dockerAccessUserName=${infra_props["dockerAccessUserName"]}
  dockerAccessPassword=${infra_props["dockerAccessPassword"]}
  namespace=${infra_props["namespace"]}

  DBEngine=${infra_props["DBEngine"]}
  OS=${infra_props["OS"]}
  JDK=${infra_props["JDK"]}

  DB=$(echo $DBEngine | cut -d'-' -f 1  | tr '[:upper:]' '[:lower:]')
  OS=$(echo $OS | cut -d'-' -f 1  | tr '[:upper:]' '[:lower:]')
  JDK=$(echo $JDK | cut -d'-' -f 1  | tr '[:upper:]' '[:lower:]')

  # ---debug---  OS="centos"
  # ---debug---  DB="mysql"
  # ---debug---  JDK="adopt_open_jdk8"

  echo "creating values.yaml file for wso2is-5.8.0 $OS-$JDK-$DB combination"

  addConnectorInfo
  addSubscriptionInfo
  addDeploymentInfo
  addLoggingInfo
  addK8sInfo

}

function create_gcr_secret(){
  #create secret with gcr authentication
  kubectl create secret docker-registry gcr-wso2creds \
    --docker-server=asia.gcr.io \
    --docker-username=_json_key \
    --docker-password="$(cat $INPUT_DIR/key.json)" \
    --docker-email=$dockerAccessUserName --namespace $namespace
}

function change_k8sContext(){
  if [[ ! -d ${HOME}/.kube/configfiles ]]; then
    mkdir ${HOME}/.kube/configfiles
  fi
  mkdir -p ${HOME}/.kube/configfiles/dir-${namespace}
  # copying the original config (.kube/config)
  cp ${HOME}/.kube/config ${HOME}/.kube/configfiles/dir-${namespace}/
  # Modifying namespace of new config-file
  kubectl config set-context $(kubectl config current-context) --kubeconfig ${HOME}/.kube/configfiles/dir-${namespace}/config --namespace ${namespace}
  # Modifying $KUBECONFIG environment variable
  export KUBECONFIG=${HOME}/.kube/configfiles/dir-${namespace}/config

  #  TO DO: remove created directory for kubeconfig ($HOME/.kube/configfiles/dir-$namespace)
}

function resources_deployment(){

    helmDeployment="wso2product$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 5 | head -n 1)"

    if  [ "$DB" == "mysql" ]
    then
        helm install --dep-up $helmDeployment $deploymentRepositoryLocation/advanced/helm/is-pattern-1
    fi

    if [ "$DB" == "postgres" ]
    then
        helm install wso2is-rdbms-service -f $deploymentRepositoryLocation/advanced/helm/databases/postgres-is/values.yaml stable/postgresql --version 2.6.1
        helm install $helmDeployment $deploymentRepositoryLocation/advanced/helm/is-pattern-1
    fi

    #TODO: helm intall for MSSQL/ Oracle

}


helm_deploy
