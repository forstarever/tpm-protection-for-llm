#!/bin/bash
set -e

# 配置路径
CLIENT_DIR="/home/star/tpm/tpm-test"
CLOUD_DIR="/home/ubuntu/tpm/tpm-test"  # 云端目录
CLOUD_IP="sifive"        # 云端IP或域名

# 创建清理函数
cleanup() {
    echo "[清理] 正在清除临时文件..."
    shred -u "$CLIENT_DIR"/* 2>/dev/null || true
    echo "[清理] 完成"
}

# 设置trap捕获EXIT信号
trap cleanup EXIT

mkdir -p $CLIENT_DIR
cd $CLIENT_DIR

# 步骤1: 接收云端的EK/AIK公钥
echo "[Client] 等待云端公钥..."
until [ -f $CLIENT_DIR/ek.pub ] && [ -f $CLIENT_DIR/ak.pub ] && [ -f $CLIENT_DIR/ak.name ]; do sleep 2; done

# 步骤2: 生成随机Nonce并发送到云端
echo "[Client] 生成Nonce..."
# openssl rand -hex 16 > $CLIENT_DIR/nonce.bin
tpm2_getrandom 16 | xxd -p -c 16 > $CLIENT_DIR/nonce.bin
scp $CLIENT_DIR/nonce.bin ubuntu@$CLOUD_IP:$CLOUD_DIR/

# 步骤3: 验证云端的Quote
echo "[Client] 等待云端Quote..."
until [ -f $CLIENT_DIR/quote.msg ] && [ -f $CLIENT_DIR/quote.sig ] && [ -f $CLIENT_DIR/quote.pcrs ]; do sleep 2; done

echo "[Client] 验证Quote签名和PCR..."
if ! tpm2_checkquote -Q -u $CLIENT_DIR/ak.pub -m $CLIENT_DIR/quote.msg -s $CLIENT_DIR/quote.sig -f $CLIENT_DIR/quote.pcrs -q $(cat $CLIENT_DIR/nonce.bin) -g sha256; then
  echo "[ERROR] Quote验证失败！"
  exit 1
fi

# 提取PCR摘要并对比Golden值（需预先准备pcr.bin）
echo "[Client] 验证PCR值..."
QUOTED_PCR=$(tpm2_print -t TPMS_ATTEST $CLIENT_DIR/quote.msg | grep "pcrDigest" | awk '{print $2}')
GOLDEN_PCR=$(cat $CLIENT_DIR/../backup/pcr.bin | openssl dgst -sha256 -binary | xxd -p -c 32)
if [ "$QUOTED_PCR" != "$GOLDEN_PCR" ]; then
  echo "[ERROR] PCR值不匹配！终止远程证明"
  touch $CLIENT_DIR/auth_failed.flag
  echo "AUTH_FAIL at $(date): PCR mismatch" > $CLIENT_DIR/auth_failed.log
  scp $CLIENT_DIR/auth_failed.log ubuntu@$CLOUD_IP:$CLOUD_DIR/
  exit 1

fi

# 步骤4: 创建凭证
echo "[Client] 创建凭证..."
#echo "invalid" > $CLIENT_DIR/ak.name
file_size=$(ls -l $CLIENT_DIR/ak.name | awk {'print $5'})
loaded_key_name=$(cat $CLIENT_DIR/ak.name | xxd -p -c $file_size)
tpm2_makecredential -Q -u $CLIENT_DIR/ek.pub -s $CLIENT_DIR/../backup/aes.bin -n $loaded_key_name -o $CLIENT_DIR/aescred.out

# 发送凭证到云端
scp $CLIENT_DIR/aescred.out ubuntu@$CLOUD_IP:$CLOUD_DIR/


echo "[Client] 远程认证成功！密钥已安全传输。"
