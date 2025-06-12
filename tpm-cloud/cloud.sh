#!/bin/bash
set -e
CLOUD_DIR="/home/star/tpm/tpm-test"
CA_TEST="/home/star/tpm/ca-test"
CA_DIR="/home/star/tpm/ca"

CLIENT_DIR="/home/star/tpm/tpm-test"
CLIENT_IP="vmware-ubuntu"

NV_INDEX=0x01C00002
EK_HANDLE=0x81010001
AK_HANDLE=0x81010002
mkdir -p $CLOUD_DIR $CA_TEST
cd $CLOUD_DIR

cleanup() {
  echo "[Cloud] 清理临时文件..."
  shred -u $CA_TEST/* $CLOUD_DIR/* 2>/dev/null || true
}
trap cleanup EXIT

# 创建或读取EK
if ! tpm2_getcap handles-persistent | grep -q $EK_HANDLE; then
  echo "[Cloud] EK (句柄 $EK_HANDLE) 未找到，开始创建并持久化..."
  tpm2_createek -Q -c ek_temp.ctx -G rsa -u ek.pub
  tpm2_evictcontrol -C o -c ek_temp.ctx $EK_HANDLE
  rm ek_temp.ctx
  echo "[Cloud] EK已持久化到句柄 $EK_HANDLE"
else
  echo "[Cloud] EK 已存在"
  tpm2_readpublic -Q -c $EK_HANDLE -o ek.pub
fi

# 从 TPM NV 区域读取 EK 证书
if tpm2_nvread $NV_INDEX -C o -o $CA_TEST/ekcert.der 2>/dev/null; then
  echo "[Cloud] 从 TPM 读取 EK 证书成功"
else
  echo "[ERROR] EK 证书不存在，请先创建 EK 证书"
fi
openssl x509 -provider tpm2 -provider default -in $CA_TEST/ekcert.der -inform DER -out $CA_TEST/ekcert.pem

# 创建AIK并签发AK证书
echo "[Cloud] 创建 AIK..."
tpm2_createak -Q -C $EK_HANDLE -c ak.ctx -G rsa -g sha256 -s rsassa -u ak.pub -n ak.name
# 使用 openssl 生成 CSR
if tpm2_getcap handles-persistent | grep -q $AK_HANDLE; then
  echo "[Cloud] 句柄 $AK_HANDLE 已存在，清除旧内容..."
  tpm2_evictcontrol -Q  -c $AK_HANDLE
fi
tpm2_evictcontrol -c ak.ctx $AK_HANDLE
openssl req -provider tpm2 -provider default \
	-new -key handle:$AK_HANDLE -subj "/CN=TPM-AK" -out $CA_TEST/ak.csr
# tpm2_evictcontrol -Q -c $AK_HANDLE
# 准备向第三方 CA（客户端）请求签发 AK 证书
echo "[Cloud] 向第三方 CA 请求签发 AK 证书..."
scp -q ek.pub $CA_TEST/ekcert.pem ak.name $CA_TEST/ak.csr $CLIENT_IP:$CA_TEST/

# 等待 CA 返回激活凭证 challenge（aescred.out）
echo "[Cloud] 等待第三方 CA 发起 AK 验证挑战..."
until [ -f $CA_TEST/aescred.out ]; do sleep 2; done

# 使用 TPM 激活凭证（验证 AK 是否由本 TPM 拥有）
echo "[Cloud] 执行 activatecredential 解封挑战..."
tpm2_startauthsession --policy-session -S session.ctx
tpm2_policysecret -S session.ctx -c e
if tpm2_activatecredential -Q -c $AK_HANDLE  -C $EK_HANDLE -i $CA_TEST/aescred.out -o $CA_TEST/aes.bin -P"session:session.ctx"; then
  echo "[Cloud] activatecredential 成功，AK 属于 TPM 内部"
  scp -q $CA_TEST/aes.bin $CLIENT_IP:$CA_TEST
else
  echo "[ERROR] activatecredential 失败，远程证明终止"
  exit 1
fi

# 等待 CA 签发的 AK 证书
echo "[Cloud] 等待第三方 CA 签发 AK 证书..."
until [ -f $CA_TEST/akcert.pem ]; do sleep 2; done
cp $CA_TEST/akcert.pem .  # 将 AK 证书保存到当前目录
cp $CA_TEST/ekcert.pem .
# 等待客户端发来 Nonce
echo "[Cloud] 等待客户端发送 Nonce..."
until [ -f nonce.bin ]; do sleep 2; done

# 生成 Quote（使用 TPM AK 签名）
echo "[Cloud] 生成 Quote..."
tpm2_quote -Q -c  $AK_HANDLE  -l sha256:0,1,2,3,4,5,6,7 -q $(cat nonce.bin) -m quote.msg -s quote.sig -o quote.pcrs -g sha256
# 将 Quote 和证书发给客户端验证
echo "[Cloud] 发送 Quote 和证书给客户端..."
scp -q quote.msg quote.sig quote.pcrs akcert.pem ak.pub ak.name ek.pub ekcert.pem $CLIENT_IP:$CLIENT_DIR/

# 等待客户端验证通过并发回模型密钥
echo "[Cloud] 等待用户验证Quote..."
while true; do
    if [ -f $CLOUD_DIR/aes.bin ]; then
        echo "[Cloud] 验证成功，接收模型密钥"
        break
    fi
    if [ -f $CLOUD_DIR/pcr_failed.log ]; then
        echo "[ERROR] 用户端验证失败，远程证明终止！"
        exit 1
    fi
    sleep 2
done

# 使用 AES 密钥解密模型文件
echo "[Cloud] 解密模型..."
time openssl enc -d -aes-256-cbc -pbkdf2 -salt -in ../backup/model.enc -out ../models/model.gguf -pass file:aes.bin
echo "[Cloud] 模型解密完成：models/model.gguf"

