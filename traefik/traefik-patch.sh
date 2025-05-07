apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    additionalArguments:
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--providers.kubernetesIngress=true"    # ✅ 여기가 중요!
    ports:
      web:
        port: 80
        expose:
          enabled: true
        protocol: TCP
      websecure:
        port: 443
        expose:
          enabled: true
        protocol: TCP