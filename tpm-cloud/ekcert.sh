#!/bin/bash
# 初始化 EK 证书并写入 TPM NVRAM

openssl req -new -x509 -keyout ek.key -nodes -days 365 -subj "/CN=CloudTPM-EK" -out ekcert.pem
openssl x509 -in ekcert.pem -outform DER -out ekcert.der

tpm2_nvundefine 0x01C00002 -C o 2>/dev/null || true
tpm2_nvdefine 0x01C00002 -C o -s 1024 -a "ownerread|ownerwrite"
tpm2_nvwrite 0x01C00002 -C o -i ekcert.der

