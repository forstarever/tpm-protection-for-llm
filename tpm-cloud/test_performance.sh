#!/bin/bash
# 文件名: test_performance.sh
# 描述: 依次测试 attestation、保护初始化与推理启动的耗时性能

CLOUD_ATTEST_SCRIPT="/home/star/tpm/cloud.sh"
PROTECT_SCRIPT="/home/star/tpm/runtime_protect.sh"
LOG_FILE="/home/star/tpm/log/secure_audit.log"
RUNTIME_LOG="/home/star/tpm/log/runtime.log"
touch $LOG_FILE
touch $RUNTIME_LOG
echo "==== 性能测试开始 ===="
GLOBAL_START=$(date +%s%3N)
# 1. 启动 cloud_attestation.sh 并计时
echo "[TEST] 启动 cloud.sh ..."
START_ATTEST=$(date +%s%3N)
# bash "$CLOUD_ATTEST_SCRIPT"
./cloud.sh
END_ATTEST=$(date +%s%3N)
echo "[RESULT] cloud.sh 耗时：$((END_ATTEST - START_ATTEST)) ms"
echo

# 2. 启动 runtime_protect.sh 并等待“初始度量完成”日志
echo "[TEST] 启动 runtime_protect.sh 并等待初始度量完成..."
START_PROTECT=$(date +%s%3N)
# 使用文件描述符+tee 捕获初始输出
bash "$PROTECT_SCRIPT" 2>&1 | tee "$RUNTIME_LOG" &
PROTECT_PID=$!

# 等待“初始度量完成”标志
while true; do
    if grep -q "初始度量完成" "$RUNTIME_LOG"; then
        break
    fi
    sleep 1
done

END_PROTECT=$(date +%s%3N)
echo "[RESULT] 初始度量耗时：$((END_PROTECT - START_PROTECT)) ms"
echo

# 修改日志方式：关闭 tee，后续输出进入日志文件
# echo "[INFO] 重定向 runtime_protect 输出到 runtime.log..."
kill $PROTECT_PID
# 重新以纯日志模式运行
bash "$PROTECT_SCRIPT" >> "$RUNTIME_LOG" 2>&1 &
PROTECT_PID=$!

GLOBAL_NOW=$(date +%s%3N)
TOTAL_ELAPSED=$((GLOBAL_NOW - GLOBAL_START))
echo "[RESULT] 启动前总耗时：${TOTAL_ELAPSED} ms"
echo

# 3. 启动 llama-cli 推理（前台输出）
echo "[TEST] 启动 llama-cli 模型推理..."
# $LLAMA_CMD
llama-cli -m ~/tpm/models/model.gguf

# 脚本执行结束
echo "==== 性能测试完成 ===="

