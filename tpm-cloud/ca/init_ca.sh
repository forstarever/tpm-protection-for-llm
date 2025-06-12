#!/bin/bash
CLIENT_IP="vmware-ubuntu"

EK_HANDLE=0x81010001
NV_INDEX=0x01C00002
# 1. 生成自建 CA
openssl req -new -x509 -days 3650 -newkey rsa:2048 -nodes \
  -subj "/CN=Simulated EK CA" \
  -keyout ek_ca.key -out ek_ca.pem

# 2. 创建临时证书配置文件
cat > ek_cert.conf <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
prompt             = no
x509_extensions    = v3_req

[ req_distinguished_name ]
CN = TPM EK

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
EOF

# 3. 创建伪造私钥（只为生成 CSR，不用真的用它）
openssl genrsa -out dummy.key 2048

# 4. 使用这个 dummy.key 生成一个 CSR（我们不用其实际 key，只取证书壳）
openssl req -new -key dummy.key -out ek.csr -config ek_cert.conf

# 5. 用 CA 签发该 CSR，但将其公钥替换为 TPM 的 ek_pub.pem
# ⚠️ 注意：我们不能用 CSR 中的公钥，需要替换为 TPM EK 的公钥

# 6. 最佳方法：使用 openssl x509 -force_pubkey
tpm2_readpublic -c $EK_HANDLE -f PEM -o ek_pub.pem
openssl x509 -req -in ek.csr \
  -CA ek_ca.pem -CAkey ek_ca.key -CAcreateserial \
  -out ekcert.pem -days 365 \
  -extfile ek_cert.conf -extensions v3_req \
  -force_pubkey ek_pub.pem

# 写入 NVRAM 为 DER 格式
openssl x509 -in ekcert.pem -outform DER -out ekcert.der
# 写入 TPM NVRAM 固定区域
tpm2_nvundefine $NV_INDEX -C o 2>/dev/null || true
tpm2_nvdefine $NV_INDEX -C o -s 1024 -a "ownerread|ownerwrite"
tpm2_nvwrite $NV_INDEX -C o -i ekcert.der
echo "[Cloud] EK 证书已写入 NVRAM $NV_INDEX。"

scp ek_ca.pem $CLIENT_IP:/home/star/tpm/ca/
