#!/bin/bash
# 解密日志文件
ENCRYPT_KEY_HANDLE=0x81000002
LOG_FILE="secure_audit.bin"
WORK_DIR="/home/ubuntu/tpm/log"
cd $WORK_DIR

# 按块解密（日志条目+PCR值）
block_size=256  # 根据实际日志长度调整
count=$(stat -c%s "$LOG_FILE")

for ((offset=0; offset<count; offset+=block_size)); do
    # 解密日志条目
    dd if="$LOG_FILE" bs=1 skip=$offset count=$((block_size-32)) 2>/dev/null | \
    tpm2_encryptdecrypt -c $ENCRYPT_KEY_HANDLE -d --iv iv.bin
    
    # 显示关联的PCR值
    echo -n " | PCR16: "
    dd if="$LOG_FILE" bs=1 skip=$((offset+block_size-32)) count=32 2>/dev/null | \
    xxd -p -c 32
done
