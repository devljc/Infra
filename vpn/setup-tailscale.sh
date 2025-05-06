#!/bin/bash

set -e

echo "📦 Tailscale 설치 중..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "Tailscale 데몬 시작 중 (이미 등록되어 있을 수 있음)"
sudo systemctl enable --now tailscaled || true

echo "🌐 브라우저 인증 링크를 통해 로그인하세요:"
sudo tailscale up

echo "연결 상태:"
tailscale status

echo "🔍 현재 Tailscale IP:"
tailscale ip -4