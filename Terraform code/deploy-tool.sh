#!/bin/bash
# ==========================================
# 0. INSTALL HELM & CONNECT TO EKS
# ==========================================
echo "⚙️ Checking and installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

echo "🔥 Connecting to EKS-Cluster-DatNguyen..."
aws eks update-kubeconfig --region ap-southeast-1 --name EKS-Cluster-DatNguyen

# ==========================================
# NODE ALLOCATION ALGORITHM (10 NODES ARCHITECTURE)
# ==========================================
echo "🏷️ Planning infrastructure: Allocating 7 dedicated Nodes for Logging..."
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))

if [ ${#NODES[@]} -ge 10 ]; then
  echo "✅ Found ${#NODES[@]} Nodes. Starting to apply labels..."
  kubectl label node ${NODES[@]:3:7} role=logging --overwrite
else
  echo "⚠️ WARNING: Current cluster only has ${#NODES[@]} Nodes (Less than 10)."
  kubectl label node ${NODES[0]} role=logging --overwrite
fi

# ==========================================
# 1. INSTALL ARGOCD
# ==========================================
echo "🐙 Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.0/manifests/crds/applicationset-crd.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# ==========================================
# 2. INSTALL PROMETHEUS & GRAFANA
# ==========================================
echo "📊 Installing kube-prometheus-stack..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.storageClassName=gp2 \
  --set grafana.persistence.size=10Gi
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'

# ==========================================
# 3. INSTALL EFK STACK (ELASTICSEARCH - FILEBEAT - KIBANA)
# ==========================================
echo "🗄️ Initializing comprehensive Logging system (EFK Stack)..."
kubectl create namespace elastic-system
helm repo add elastic https://helm.elastic.co
helm repo update

echo "Deploying Elasticsearch (3 Nodes) into the 7-Node Logging zone..."
helm install elasticsearch elastic/elasticsearch -n elastic-system \
  --set replicas=3 \
  --set minimumMasterNodes=2 \
  --set volumeClaimTemplate.resources.requests.storage=15Gi \
  --set volumeClaimTemplate.storageClassName=gp2 \
  --set nodeSelector.role=logging

echo "⏳ Waiting for Elasticsearch to start and attach volumes (3-5 minutes)..."
kubectl rollout status statefulset/elasticsearch-master -n elastic-system --timeout=400s

echo "Deploying Filebeat to collect logs across all 10 Nodes..."
# a. Auto-generate standardized Filebeat configuration
cat << 'EOF' > filebeat-values.yaml
daemonset:
  enabled: true
filebeatConfig:
  filebeat.yml: |
    filebeat.inputs:
    - type: container
      paths:
        - /var/log/containers/*.log
      processors:
      - add_kubernetes_metadata:
          host: ${NODE_NAME}
          matchers:
          - logs_path:
              logs_path: "/var/log/containers/"
    output.elasticsearch:
      host: '${NODE_NAME}'
      hosts: '${ELASTICSEARCH_HOSTS:elasticsearch-master:9200}'
      username: '${ELASTICSEARCH_USERNAME}'
      password: '${ELASTICSEARCH_PASSWORD}'
      protocol: https
      ssl.verification_mode: none
EOF

# b. Install Filebeat using the generated configuration file
helm install filebeat elastic/filebeat -n elastic-system -f filebeat-values.yaml

echo "Installing Kibana UI (Internet-Facing, Port 80)..."
helm install kibana elastic/kibana -n elastic-system \
  --set service.type=LoadBalancer \
  --set service.port=80 \
  --set 'service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme=internet-facing' \
  --set nodeSelector.role=logging

# ==========================================
# 4. AUTOMATE ELASTICACHE (REDIS) FOR GOOGLE BOUTIQUE
# ==========================================
echo "🔄 Fetching ElastiCache endpoint from AWS (Terraform)..."
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)

if [ -n "$REDIS_ENDPOINT" ]; then
  echo "=========================================================="
  echo "🔥 CRITICAL MANUAL STEP (FOR GITLAB EC2) 🔥"
  echo "=========================================================="
  echo "AWS ElastiCache system is ready!"
  echo "Please copy the exact link below:"
  echo ""
  echo "👉 $REDIS_ENDPOINT 👈"
  echo ""
  echo "1. Log into GitLab: http://52.74.7.113"
  echo "2. Open the file kubernetes-manifests/cartservice.yaml"
  echo "3. Change REDIS_ADDR to: \"$REDIS_ENDPOINT:6379\""
  echo "4. Click Commit. ArgoCD will automatically handle the rest!"
  echo "=========================================================="
else
  echo "⚠️ WARNING: Could not fetch redis_endpoint from Terraform."
fi

# ==========================================
# 5. WAIT FOR SYSTEM INITIALIZATION AND FETCH CREDENTIALS
# ==========================================
echo "⏳ Waiting 60 seconds for AWS to provision the LoadBalancer..."
sleep 60

echo "==========================================="
echo "✅ INSTALLATION COMPLETE! HERE ARE YOUR CREDENTIALS:"
echo "==========================================="

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "🐙 ArgoCD Password (User: admin) : $ARGOCD_PASS"

GRAFANA_PASS=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
echo "📊 Grafana Password (User: admin) : $GRAFANA_PASS"

KIBANA_PASS=$(kubectl get secret elasticsearch-master-credentials -n elastic-system -o jsonpath="{.data.password}" | base64 --decode)
echo "🗄️ Kibana Password (User: elastic) : $KIBANA_PASS"

echo "==========================================="
echo "🌐 ACCESS URL BOARD (REMEMBER TO ADD http:// PREFIX):"
kubectl get svc -A | grep LoadBalancer | awk '{print $2, "->", $5}'