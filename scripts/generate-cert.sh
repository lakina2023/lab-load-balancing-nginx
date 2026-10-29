#!/bin/sh
# Génère un certificat auto-signé pour le lab (valable 1 an)
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/lab.key -out certs/lab.crt -subj "/CN=lab-lb"
echo "Certificat créé dans certs/"
