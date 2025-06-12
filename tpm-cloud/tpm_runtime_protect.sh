#!/bin/bash
# 基于TPM的运行时文件保护与日志记录

# 配置区
WORK_DIR="/home/ubuntu/tpm/log"
FILES=(
    "$WORK_DIR/../cloud_attestation.sh"
    "$WORK_DIR/../tpm_runtime_protect.sh"
    "/home/ubuntu/llama.cpp/vulkan_build/bin/llama-cli"
    "$WORK_DIR/../models/model.guff"
    "$WORK_DIR/test.txt"
)
PCR=16                                # 使用的PCR寄存器
SERVICE_NAME="llama-cli"             # 服务进程名
LOG_FILE="secure_audit.log"          # 日志文件
cd $WORK_DIR

# 安全日志记录（明文）
log_event() {
    local event="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local entry="${timestamp}: ${event}"
    echo "$entry" | tee -a "$LOG_FILE"

    # 获取当前PCR值作为审计锚点
    tpm2_pcrread sha256:$PCR | grep "$PCR" >> "$LOG_FILE"
}

# 使用TPM计算文件哈希
tpm_hash_file() {
    local file="$1"
    tpm2_hash --hierarchy=o --hash-algorithm=sha256 -o /dev/null -t /dev/null "$file" | awk '/^hash:/ {print $2}'
}

# 终止服务并清理
terminate_service() {
    log_event "Critical: File tamper detected! Terminating service..."
    sudo pkill -9 -f "$SERVICE_NAME"
    log_event "正在清除模型文件..."
    shred -u "$WORK_DIR/../models/model.guff" 2>/dev/null || true
    log_event "清理完成"
    tpm2_flushcontext -t
    log_event "Service terminated, TPM context cleared"
    exit 1
}

# 文件监控主逻辑
start_monitoring() {
    declare -A BASELINE_HASHES

    # 初始度量
    log_event "初始度量中..."
    for file in "${FILES[@]}"; do
        if [ ! -f "$file" ]; then
            log_event "Error: $file not exist!"
            exit 1
        fi
        hash=$(tpm_hash_file "$file")
        BASELINE_HASHES["$file"]=$hash
        tpm2_pcrextend $PCR:sha256=$hash
        log_event "Initial measured: $file ($hash)"
    done
    log_event "初始度量完成，持续监控中..."

    # 启动inotify监控
    inotifywait -mqr --format '%w%f' -e modify,attrib,close_write,move,delete "${FILES[@]}" | \
    while read -r changed_file; do
        if [ ! -f "$changed_file" ]; then
            log_event "Warning: $changed_file was deleted or moved!"
            terminate_service
        fi

        current_hash=$(tpm_hash_file "$changed_file")
        original_hash=${BASELINE_HASHES["$changed_file"]}

        if [ "$current_hash" != "$original_hash" ]; then
            log_event "Alert: $changed_file hash mismatch! (Now: $current_hash)"
            terminate_service
        else
            tpm2_pcrextend $PCR:sha256=$current_hash
            log_event "PCR updated: $changed_file valid change"
        fi
    done
}

# 主流程
log_event "===== Runtime Protection Start ====="
start_monitoring

