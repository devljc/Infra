
#!/bin/bash

set -e

DOMAIN="ubuntu-server.tail395392.ts.net"
NETWORK_NS="network"
DB_NS="db"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Cleanup any old IngressRouteTCP resources to avoid conflict
echo "\n🧹 이전 IngressRouteTCP 리소스 제거..."
kubectl delete ingressroutetcp redis-tcp -n $DB_NS --ignore-not-found
kubectl delete ingressroutetcp mongo-tcp -n $DB_NS --ignore-not-found
kubectl delete ingressroutetcp mysql-tcp -n $DB_NS --ignore-not-found

# Ensure namespaces exist
kubectl get ns "$NETWORK_NS" >/dev/null 2>&1 || kubectl create ns "$NETWORK_NS"
kubectl get ns "$DB_NS" >/dev/null 2>&1 || kubectl create ns "$DB_NS"

# 0. Traefik CRDs 설치 (v2.11 기준)
echo "\n📦 Traefik CRD 설치..."
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.11/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

# 1. cert-manager 설치 및 self-signed ClusterIssuer
echo "\n📥 cert-manager CRDs 적용..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml

echo "\n🚀 cert-manager 설치..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=false

# 2. ClusterIssuer 생성
echo "\n📝 self-signed ClusterIssuer 생성..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
EOF

# 3. Certificate 리소스 생성
echo "\n🔐 TLS 인증서 요청..."
cat <<EOF | kubectl apply -n $NETWORK_NS -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-cert
spec:
  secretName: app-tls-secret
  commonName: $DOMAIN
  dnsNames:
  - $DOMAIN
  duration: 2160h
  renewBefore: 360h
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
EOF

# 4. Dummy Gateway 배포 (Spring Gateway 대체 전용)
echo "\n🚀 Dummy Gateway 배포..."
cat <<EOF | kubectl apply -n $NETWORK_NS -f -
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spring-gateway
  template:
    metadata:
      labels:
        app: spring-gateway
    spec:
      containers:
      - name: echo
        image: ealen/echo-server
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: spring-gateway
spec:
  selector:
    app: spring-gateway
  ports:
  - port: 80
    targetPort: 80
EOF

# 5. Ingress 설정 (HTTPS, WS)
echo "\n🌐 Ingress 생성..."
cat <<EOF | kubectl apply -n $NETWORK_NS -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gateway-ingress
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-cluster-issuer
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - $DOMAIN
    secretName: app-tls-secret
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spring-gateway
            port:
              number: 80
      - path: /ws
        pathType: Prefix
        backend:
          service:
            name: spring-gateway
            port:
              number: 80
EOF

## 6. IngressRouteTCP for Redis, Mongo, MySQL
#echo "\n🔌 IngressRouteTCP 생성..."
#cat <<EOF | kubectl apply -n $DB_NS -f -
#---
#apiVersion: traefik.containo.us/v1alpha1
#kind: IngressRouteTCP
#metadata:
#  name: redis-tcp
#spec:
#  entryPoints:
#    - redis
#  routes:
#  - match: HostSNI("*")
#    services:
#    - name: redis-master
#      port: 6379
#  tls:
#    passthrough: true
#---
#apiVersion: traefik.containo.us/v1alpha1
#kind: IngressRouteTCP
#metadata:
#  name: mongo-tcp
#spec:
#  entryPoints:
#    - mongo
#  routes:
#  - match: HostSNI("*")
#    services:
#    - name: mongodb
#      port: 27017
#  tls:
#    passthrough: true
#---
#apiVersion: traefik.containo.us/v1alpha1
#kind: IngressRouteTCP
#metadata:
#  name: mysql-tcp
#spec:
#  entryPoints:
#    - mysql
#  routes:
#  - match: HostSNI("*")
#    services:
#    - name: mysql
#      port: 3306
#  tls:
#    passthrough: true
#EOF

# 7. 안내 출력
echo -e "\n✅ 구성 완료!"
echo "🌐 HTTPS → https://$DOMAIN/"
echo "🔗 WS   → ws://$DOMAIN/ws"
echo "🔗 WSS  → wss://$DOMAIN/ws (TLS proxy via Gateway)"

