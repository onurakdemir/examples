#!/bin/bash

# Call it with the namespace to monitor
namespace=${1:-default}

# API URL setup. Requires an ambassador API proxy running side-by-side
base=http://localhost:8001
ns=namespaces/$namespace
k8s_service_url=$base/api/v1/$ns/services
k8s_ingress_url=$base/apis/extensions/v1beta1/$ns/ingresses

# Watch the K8s API on events on service objects
echo "::: Starting to wait for events"
curl -N -s -k $k8s_service_url?watch=true | while read event
do
  # Event type
  type=$(echo $event | jq -r '.type')
  # Annotation "expose" on service
  expose=$(echo $event | jq -r '.object.metadata.annotations.expose?')
  # Firt service port
  port=$(echo $event | jq -r '.object.spec.ports[0]?.port')
  # Service
  service=$(echo $event | jq -r .object.metadata.name)

  echo "::: $type -- $service [$port] expose = $expose"

  # If a new service has been added and when its labeled with "expose", then
  # create an ingress object for it
  if [ $type = "ADDED" ] && [ $expose != 'null' ]; then
    # Check for Ingress with the same name
    http_code=$(curl -s -o /dev/null -w "%{http_code}" $k8s_ingress_url/$service)
    if [ $http_code != 200 ]; then
      echo "::: Creating Ingress backend for service '$service'"
      cat - << EOT | curl -s -H "Content-Type: application/json" -X "POST" -d @- $k8s_ingress_url
{
    "apiVersion": "extensions/v1beta1",
    "kind": "Ingress",
    "metadata": {
        "name": "$service",
        "namespace": "$namespace"
    },
    "spec": {
        "rules": [{
            "http": {
                "paths": [{
                    "backend": {
                        "serviceName": "$service",
                        "servicePort": $port
                    },
                    "path": "$expose"
                }]
            }
        }]
    }
}
EOT
      echo
    else
      echo "::: Ingress '$service' already exists. Skipping ..."
    fi
  fi
done
