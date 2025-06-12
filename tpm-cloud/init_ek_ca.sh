#!/bin/bash
CLIENT_IP="vmware-ubuntu"
mkdir -p /home/star/tpm/ca
cd /home/star/tpm/ca
openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
  -subj "/CN=Simulated EK CA" \
  -keyout ek_ca.key -out ek_ca.pem
scp ek_ca.pem $CLIENT_IP:/home/star/tpm/ca/
