#!/bin/bash
# 文件名: tpm_runtime_protect.sh
# 描述: 基于TPM PCR度量的运行时文件保护与明文日志记录
# 依赖: tpm2-tools, inotify-tools

# 配置区
WORK_DIR="/home/star/tpm/log"
FILES=(
    "$WORK_DIR/../cloud.sh"
    "$WORK_DIR/../runtime_protect.sh"
    "/home/star/llama.cpp/build/bin/llama-cli"
    "/home/star/llama.cpp/build/bin/llama-server"
    "$WORK_DIR/../models/model.gguf"
    "$WORK_DIR/test.txt"
)
PCR=16                               # 使用的PCR寄存器
SERVICE_NAME="llama-*"             # 服务进程名
LOG_FILE="secure_audit.log"          # 明文日志文件
cd $WORK_DIR

# 安全日志记录
log_event() {
    local event="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local entry="${timestamp}: ${event}"
    echo "$entry" | tee -a "$LOG_FILE"

    # 获取当前PCR值作为审计锚点
    # echo "PCR[$PCR]:" | tee -a "$LOG_FILE"
    tpm2_pcrread sha256:$PCR | grep "$PCR" >> "$LOG_FILE"
}

# 终止服务并清理
terminate_service() {
    log_event "[ERROR] 终止服务..."
    sudo pkill -9 -f "$SERVICE_NAME"
    log_event "正在清除模型文件..."
    shred -u "$WORK_DIR/../models/model.guff" 2>/dev/null || true
    tpm2_flushcontext -t
    log_event "清理完成，服务已终止"
    exit 1
}
# trap terminate_service  EXIT
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
        hash=$(sha256sum "$file" | awk '{print $1}')
        BASELINE_HASHES["$file"]=$hash
        tpm2_pcrextend $PCR:sha256=$hash
        log_event "初始度量： $file ($hash)"
    done
    log_event "初始度量完成，持续监控中..."

    # 启动inotify监控
    inotifywait -mqr --format '%w%f' -e modify,attrib,close_write,move,delete "${FILES[@]}" | \
    while read -r changed_file; do
	log_event "WARNING: $changed_file changed!"
        current_hash=$(sha256sum "$changed_file" | awk '{print $1}')
        original_hash=${BASELINE_HASHES["$changed_file"]}

        if [ "$current_hash" != "$original_hash" ]; then
            log_event "ERROR: $changed_file hash mismatch! (Now: $current_hash)"
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

