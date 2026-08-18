#!/usr/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <ANSIBLE_HOME>"
    echo "  구 MinIO 로컬(systemd) 설치 제거 — K8s(304-minio) 컷오버 전 단계"
    exit 1
fi

ANSIBLE_HOME="${1}"

log() {
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') - $1\n"
}

run_cmd() {
    log "[RUN] $1"
    eval "$1"
}

log "===== START minio remove ansible start ====="

log "ANSIBLE_HOME: ${ANSIBLE_HOME}"

# ansible.cfg(inventory, remote_tmp 등) 적용을 위해 프로젝트 루트로 이동
run_cmd "cd ${ANSIBLE_HOME}"

# ansible 플레이북 실행
run_cmd "ansible-playbook minio_remove_ansible.yml"

log "===== END minio remove ansible end ====="
