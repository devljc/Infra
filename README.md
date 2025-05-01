# 🧩 GitOps 인프라 구조

Argo CD를 통한 Helm 기반 GitOps 배포 구조입니다.

## 디렉터리 구성

- `db/` : db 구성 (ex. Redis, MongoDB)
- `argocd/` : Argo CD 자체 설정 (선택)

## 사용 방법

1. Argo CD 설치 후 `bootstrap.yaml` 적용
2. Argo CD UI 또는 CLI를 통해 앱 상태 확인
3. Git 변경 → Argo CD 자동 동기화

## 네임스페이스

- Redis, MongoDB는 `db` 네임스페이스에 배포