#!/bin/bash
set -e
CLIENT_DIR="/home/star/tpm/tpm-test"
CA_DIR="/home/star/tpm/ca"
CA_TEST="/home/star/tpm/ca-test"
CLOUD_IP="milkv"
CLOUD_DIR="/home/star/tpm/tpm-test"

mkdir -p $CLIENT_DIR $CA_DIR $CA_TEST
cd $CLIENT_DIR

cleanup() {
  echo "[Client/CA] 清理临时文件..."
  shred -u $CA_TEST/* $CLIENT_DIR/* 2>/dev/null || true
}
trap cleanup EXIT

# 初始化 CA
if [ ! -f "$CA_DIR/ak_ca.pem" ]; then
  openssl req --provider tpm2 -provider default new -x509 -days 3650 -nodes -newkey rsa:2048 -subj "/CN=ThirdParty AK CA" \
    -keyout "$CA_DIR/ak_ca.key" -out "$CA_DIR/ak_ca.pem"
fi

# 验证 EK 证书
echo "[Client/CA] 等待 EK 证书..."
until [ -f "$CA_TEST/ekcert.pem" ] && \
      [ -f "$CA_TEST/ek.pub" ] && \
      [ -f "$CA_TEST/ak.name" ] && \
      [ -f "$CA_TEST/ak.csr" ]; do
    sleep 2
done
openssl verify -provider tpm2 -provider default -CAfile "$CA_DIR/ek_ca.pem" "$CA_TEST/ekcert.pem" || { echo "[ERROR] EK证书无效"; exit 1; }
echo "[Cleint/CA] EK 验证证书成功"

# 发起 makecredential
openssl rand -provider tpm2 -provider default 32 > secret.bin
AK_NAME_HEX=$(xxd -p "$CA_TEST/ak.name" | tr -d '\n')
tpm2_makecredential -Q -u "$CA_TEST/ek.pub" -n "$AK_NAME_HEX" -s secret.bin -o "$CA_TEST/aescred.out"

scp -q "$CA_TEST/aescred.out" $CLOUD_IP:$CA_TEST/

# 等待 activatecredential 返回
echo "[Client/CA] 等待云端响应..."
until [ -f "$CA_TEST/aes.bin" ]; do sleep 2; done
diff secret.bin "$CA_TEST/aes.bin" && echo "[Client/CA] TPM AK 验证通过" || { echo "[ERROR] TPM AK 验证失败"; exit 1; }

# 签发 AK 证书
openssl x509 -provider default -req -in "$CA_TEST/ak.csr" -CA "$CA_DIR/ak_ca.pem" -CAkey "$CA_DIR/ak_ca.key"  -CAcreateserial -out "$CA_TEST/akcert.pem" -days 365
scp -q "$CA_TEST/akcert.pem" $CLOUD_IP:$CA_TEST/

# 发起远程证明
openssl rand -provider tpm2 -provider default -hex 16 > nonce.bin
scp -q nonce.bin $CLOUD_IP:$CLOUD_DIR/

# 等待 EK,AK,Quote
echo "[Client] 等待Ek,Ak,Quote..."
until [ -f quote.msg ] && \
      [ -f quote.sig ] && \
      [ -f quote.pcrs ] && \
      [ -f akcert.pem ] && \
      [ -f ak.pub ] && \
      [ -f ak.name ] && \
      [ -f ek.pub ] && \
      [ -f ekcert.pem ]; do
    sleep 2
done

# 验证EK证书合法性
openssl verify -provider tpm2 -provider default -CAfile $CA_DIR/ek_ca.pem ekcert.pem || { echo "[ERROR] EK证书无效"; exit 1; }

# 验证AK证书合法性
openssl verify -provider tpm2 -provider default -CAfile $CA_DIR/ak_ca.pem akcert.pem || { echo "[ERROR] AK证书验证失败"; exit 1; }
echo "[Client] EK,AK证书验证成功"

# 验证Quote签名
echo "[Client] 验证Quote签名和PCR..."  
if ! tpm2_checkquote -Q -u $CLIENT_DIR/ak.pub -m $CLIENT_DIR/quote.msg \
  -s $CLIENT_DIR/quote.sig -f $CLIENT_DIR/quote.pcrs -q $(cat $CLIENT_DIR/nonce.bin) \
  -g sha256; then
  echo "[ERROR] Quote验证失败！"
  exit 1
fi

# 提取PCR摘要并对比Golden值
echo "[Client] 验证PCR值..."
QUOTED_PCR=$(tpm2_print -t TPMS_ATTEST $CLIENT_DIR/quote.msg | grep "pcrDigest" | awk '{print $2}')
GOLDEN_PCR=$(cat $CLIENT_DIR/../backup/pcr.bin | openssl dgst -sha256 -binary | xxd -p -c 32)
if [ "$QUOTED_PCR" != "$GOLDEN_PCR" ]; then
  echo "[ERROR] PCR值不匹配！终止远程证明"
  touch $CLIENT_DIR/pcr_failed.flag
  echo "AUTH_FAIL at $(date): PCR mismatch" > $CLIENT_DIR/pcr_failed.log
  scp -q $CLIENT_DIR/pcr_failed.log $CLOUD_IP:$CLOUD_DIR/
  exit 1
fi
echo "[CLlient] Quote签名和PCR验证成功"
scp -q $CLIENT_DIR/../backup/aes.bin $CLOUD_IP:$CLOUD_DIR/
echo "[Cliennt] 密钥发送完成，远程证明结束"
