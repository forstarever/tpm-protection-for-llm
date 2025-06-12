#!/bin/bash
mkdir -p /home/star/tpm/ca
cd /home/star/tpm/ca
openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
  -subj "/CN=ThirdParty AK CA" \
  -keyout ak_ca.key -out ak_ca.pem

