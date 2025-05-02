#!/bin/bash

# Required open 80 port

set -e

# 0. 네임스페이스 준비
kubectl get ns network >/dev/null 2>&1 || kubectl create ns network

# 1. Nginx Ingress 설치
NGINX_REPO="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/cloud/deploy.yaml"
kubectl apply -f "$NGINX_REPO"
echo "✅ Nginx Ingress 설치 완료"
kubectl wait --namespace ingress-nginx \
  --for=condition=Available deployment/ingress-nginx-controller \
  --timeout=180s

# 2. cert-manager 설치
CERT_REPO="https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.yaml"
kubectl apply -f "$CERT_REPO"
echo "✅ cert-manager 설치 완료"
kubectl wait --namespace cert-manager \
  --for=condition=Available deployment/cert-manager-webhook \
  --timeout=180s

# 3. ClusterIssuer 생성
cat <<EOF > clusterissuer-letsencrypt-http.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: example@gmail.com
    privateKeySecretRef:
      name: letsencrypt-http-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

kubectl apply -f clusterissuer-letsencrypt-http.yaml
echo "✅ ClusterIssuer 생성 완료"

# 4. 테스트용 도메인 설정
DOMAIN="example.com"  # 실제 도메인으로 변경하세요

# 5. dummy gateway 서비스 및 nginx 배포
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: gateway
  namespace: network
spec:
  selector:
    app: dummy
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dummy
  namespace: network
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dummy
  template:
    metadata:
      labels:
        app: dummy
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
EOF

# 6. Ingress 생성
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gateway-ingress
  namespace: network
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-http
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${DOMAIN}
      secretName: gateway-tls
  rules:
    - host: ${DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gateway
                port:
                  number: 80
EOF

echo "⏳ 인증서 발급 대기 중... 최대 2분"

# 7. 인증서 상태 체크
for i in {1..24}; do
  READY=$(kubectl get certificate gateway-tls -n network -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$READY" == "True" ]]; then
    echo "🎉 인증서 발급 완료! ✅ https://$DOMAIN"
    exit 0
  fi
  echo "⌛ 인증서 상태: $READY (재시도 $i/24)"
  sleep 5
done

echo "❌ 인증서 발급 실패. 다음 명령어로 확인하세요:"
echo "kubectl describe certificate gateway-tls -n network"
exit 1