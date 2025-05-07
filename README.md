# 🛠️ Infra Setup for K3s

K3s 기반의 경량 쿠버네티스 환경에서 Redis, MongoDB, MySQL을 Argo CD로 선언적으로 배포하고, Traefik을 통해 TCP/TLS 통신을 구성하며, Tailscale VPN으로 안전한 접근을 지원하는 **테스트 서버용 MSA 인프라 템플릿**입니다.

---

## 🎯 목표

- 로컬/개인 서버 환경에서도 **클라우드 수준의 MSA 인프라** 구현
- NodePort + TLS + VPN을 통해 **외부 노출 없이 안전한 통신** 확보
- GitOps 기반의 Argo CD로 **자동화된 배포 관리** 실현
- 구성 요소를 템플릿화하여 **다양한 환경에 재사용 가능**하도록 설계

---

## 📚 Tech Stack

| 기술                         | 선택 이유                                                                 |
|----------------------------|--------------------------------------------------------------------------|
| **K3s**                    | 경량화된 Kubernetes 배포판. 단일 노드 테스트나 소형 인스턴스에 적합                          |
| **Helm**                   | values.yaml 기반 파라미터화 및 설치 자동화를 통해 관리 편의성 제공                         |
| **Argo CD**                | Git 저장소 기반의 선언적 배포. GitOps 방식으로 운영 효율 극대화                          |
| **Traefik (내장 Ingress)** | K3s에 기본 포함된 경량 Ingress Controller. TCP/TLS 지원, IngressRoute 구성 지원 |
| **cert-manager**           | 인증서 발급 및 자동 갱신 관리. self-signed 설정으로 외부 의존도 제거                       |
| **Tailscale**              | WireGuard 기반의 VPN. 포트 포워딩 없이 안전하게 내부 리소스 접근 가능                    |
| **draw.io**                | 시각적 다이어그램 작성. 인프라 구조 이해 및 협업 효율성 향상                             |
---

## 🖼️ 인프라 구조 다이어그램 (`infra.drawio`)

전체 인프라 구성의 네트워크 및 배치 관계를 시각적으로 표현한 파일입니다.

- 파일 위치: `/infra/infra.drawio`
- 포맷: [draw.io](https://draw.io) 호환
- 각 구성 요소의 연결 흐름, 네임스페이스, TLS, VPN, 라우팅 구조 등을 표현

![img.png](img.png)

---

## 📦 Database 구성 (`/db`)

각 데이터베이스는 Helm 차트 기반으로 구성되며, Argo CD를 통해 선언적으로 배포됩니다.

### MongoDB
- `mongodb-argocd.yaml`: Argo CD `Application` 리소스
- `mongodb-values.yaml`: Helm chart 설정값

### MySQL
- `mysql-argocd.yaml`: Argo CD `Application` 리소스
- `mysql-values.yaml`: Helm chart 설정값

### Redis
- `redis-argocd.yaml`: Argo CD `Application` 리소스
- `redis-values.yaml`: Helm chart 설정값

---

## 🌐 Traefik 설정 (`/traefik`)

Traefik을 통한 TCP 포트 노출 및 TLS 암호화를 구성합니다.

- `traefik-service-patch.yaml`: NodePort 노출을 위한 Traefik Service 수정
- `traefik-patch.sh`: 위 패치를 자동 적용하는 스크립트
- `setup-traefik-cert-selfsigned.sh`: 인증서와 TLS 관련 리소스 생성 자동화

---

## 📑 인증서 관리 (cert-manager)

**cert-manager**를 통해 내부 서비스 간 TLS 통신을 위한 인증서를 자동으로 관리합니다.

### 구성 요소
- `ClusterIssuer`: self-signed 인증서 발급을 위한 전역 발급자
- `Certificate`: Traefik TCP 서비스에 적용할 인증서 리소스
- `TLSStore` / `TLSOption`: Traefik에 적용될 TLS 정책
- `Secret`: 발급된 인증서 및 키 저장 (예: `tcp-tls-secret`)

### 자동 갱신
- 기본 설정으로 **만료 15일 전 자동 갱신**
- self-signed 인증서도 cert-manager의 controller가 감시 및 갱신 수행

### 예시 리소스
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tcp-cert
spec:
  secretName: tcp-tls-secret
  duration: 2160h        # 90일
  renewBefore: 360h      # 15일 전
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
  dnsNames:
    - "example.domain.com"
```
---

## 🔧 운영 팁 및 Troubleshooting
### 📌 인증서 (cert-manager)

- 인증서 목록 및 상태 확인
  ```bash
  kubectl get certificate -A
  kubectl describe certificate <이름> -n <네임스페이스>
  ```
- 자동 갱신 로그 확인
  ```bash
  kubectl logs -l app.kubernetes.io/name=cert-manager -n cert-manager --tail=100
  ```

---

### 🌐 Traefik

- IngressRouteTCP 리소스 상태 확인
  ```bash
  kubectl get ingressroutetcp -A
  kubectl describe ingressroutetcp <이름> -n <네임스페이스>
  ```
- Traefik 로그 확인
  ```bash
  kubectl logs -l app.kubernetes.io/name=traefik -n kube-system --tail=100
  ```

---

### 🔐 Tailscale

- 현재 연결된 노드 확인
  ```bash
  tailscale status
  ```
- MagicDNS 및 TLS 경로 테스트
  ```bash
  curl -v https://<tailscale-domain>:<port>
  ```

---

### 🚀 Argo CD

- Application 목록 및 상태 확인
  ```bash
  argocd app list
  argocd app get <앱 이름>
  ```
- 수동 동기화
  ```bash
  argocd app sync <앱 이름>
  ```

---

### 📎 참고 링크

- [cert-manager 공식 문서](https://cert-manager.io/docs/)
- [Traefik TCP Routing](https://doc.traefik.io/traefik/routing/overview/)
- [Argo CD CLI Reference](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/)
