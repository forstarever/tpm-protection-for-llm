#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用sudo或以root用户运行此脚本"
    exit 1
fi

# 定义文件路径
IMA_FILE="/sys/kernel/security/ima/ascii_runtime_measurements"

# 检查文件是否存在
if [ ! -f "$IMA_FILE" ]; then
    echo "错误: 文件 $IMA_FILE 不存在"
    exit 1
fi

# 提取第二列的hash值
HASH=$(awk 'NR==1 {print $2}' "$IMA_FILE")

# 检查是否成功提取hash
if [ -z "$HASH" ]; then
    echo "错误: 无法从文件中提取hash值"
    exit 1
fi

# 将hash扩展至PCR10
echo "将hash $HASH 扩展至PCR10..."
tpm2_pcrextend 10:sha1="$HASH"

if [ $? -eq 0 ]; then
    echo "成功将hash扩展至PCR10"
else
    echo "错误: 扩展PCR10失败"
    exit 1
fi
