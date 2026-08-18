#!/usr/bin/bash

ANSIBLE_HOME="$1"
if [ -z "${ANSIBLE_HOME}" ]; then
    echo "[ERROR] ANSIBLE_HOME is empty"
    exit 1
fi

log() {
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') - $1\n"
}

run_cmd() {
    log "[RUN] $1"
    eval "$1"
}

log "===== START kafka_prereq ansible start ====="

log "ANSIBLE_HOME: ${ANSIBLE_HOME}"

# ansible.cfg(inventory, remote_tmp 등) 적용을 위해 프로젝트 루트로 이동
run_cmd "cd ${ANSIBLE_HOME}"
run_cmd "ansible-playbook kafka_prereq_ansible.yml"

log "===== END kafka_prereq ansible end ====="
