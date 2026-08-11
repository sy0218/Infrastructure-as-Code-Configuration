#!/usr/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <ANSIBLE_HOME> <TARGET>"
    echo "TARGET: all | helm"
    exit 1
fi

ANSIBLE_HOME="${1}"
TARGET="${2}"

log() {
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') - $1\n"
}

run_cmd() {
    log "[RUN] $1"
    eval "$1"
}

log "===== START helm ansible start ====="

log "ANSIBLE_HOME: ${ANSIBLE_HOME}"
log "TARGET: ${TARGET}"

# ansible.cfg(inventory, remote_tmp 등) 적용을 위해 프로젝트 루트로 이동
run_cmd "cd ${ANSIBLE_HOME}"

# ansible 플레이북 실행
if [ "${TARGET}" = "all" ]; then
    run_cmd "ansible-playbook helm_ansible.yml"
else
    run_cmd "ansible-playbook helm_ansible.yml --tags ${TARGET}"
fi

log "===== END helm ansible end ====="
