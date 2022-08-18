#!/bin/bash
COUNTRY="US"
STATE="Montana"
LOCALITY="Kalispell"
ORG="Development"
ORG_UNIT="Development Team"

function confirm() {
  local QUESTION=$1
  read -p "${QUESTION} [y/N] " yn
    case $yn in
        [Yy]* )
            return 1
            ;;
        [Nn]* )
            return 0
            ;;
        * )
            return 0
            ;;
    esac
    echo ""
}

function main() {
    
    if [[ "$#" -ne 1 ]]; then
      echo "Error: No domain name argument provided"
      echo "Usage: ./create-cert.sh local.example.com"
      exit 1
    fi

    DOMAIN=$1
    KEY=${DOMAIN}.key
    CSR=${DOMAIN}.csr
    CERT=${DOMAIN}.crt
    PEM=${DOMAIN}.pem

    generate_cert_and_key
    copy_cert_and_key
    cleanup

    echo ""
    echo "Finished certificate generation process:"
    echo "CSR=$CSR"
    echo "Private Key=$KEY"
    echo "Certificate=$CERT"

    install_as_CA_in_firefox
    install_as_CA_in_chrome
    
    export_pfx
}

function generate_cert_and_key() {
  
  # Generate Private key 
  openssl genrsa -out $KEY 4096

  # Create CSR config
  cat > csr.conf <<EOF
[ req ]
default_bits = 4096
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = $COUNTRY
ST = $STATE
L = $LOCALITY
O = $ORG
OU = $ORG_UNIT
CN = $DOMAIN

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $DOMAIN
IP.1 = 127.0.0.1
IP.2 = ::1

EOF

  # Create CSR request using private key
  echo "Creating CSR request..."
  openssl req -new -key $KEY -out $CSR -config csr.conf

  # Create a external config file for the certificate
  cat > cert.conf <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
IP.1 = 127.0.0.1
IP.2 = ::1

EOF

  # Create self-signed certificate
  echo "Completing the CSR and generating new certificate..."
  openssl x509 -req -in $CSR -signkey $KEY -out $CERT -days 3650 -sha256 -extfile cert.conf

  echo ""
  echo "Certificate Details:"
  openssl x509 -in $CERT -text -noout
}

function copy_cert_and_key() {

  echo ""
  echo "Copying certificate and key into correct locations..."

  # Copy the certificate as a trust source anchor
  sudo cp -v $CERT /usr/share/ca-certificates/trust-source/anchors/$PEM

  # Rebuild trust source anchors
  sudo update-ca-trust extract

  # Explicity copy the cert as a PEM file to /etc/ssl/certs
  sudo cp -v $CERT /etc/ssl/certs/$PEM

  # Copy the private key
  sudo cp -v $KEY /etc/ssl/
}

function cleanup() {

  # Clean up generated config files
  rm csr.conf
  rm cert.conf
}

function install_as_CA_in_firefox() {

  echo ""
  confirm "Do you wish to import the certificate as a CA into Firefox?"
  local YES=$?

  if [[ "$YES" -eq 1 ]]; then
    
    # Get the Firefox profile directory
    FF_PROFILE_DIR=$(grep "Default=.*\.default*" "$HOME/.mozilla/firefox/profiles.ini" | cut -d"=" -f2)
    echo "Firefox profile directory=$FF_PROFILE_DIR"
    
    echo "Deleting any old certificates registered for $DOMAIN..."
    certutil -d $HOME/.mozilla/firefox/$FF_PROFILE_DIR -D -n $DOMAIN

    echo "Adding $CERT as CA in Firefox..."
    echo "You can find it under: View Certificates -> Authorities -> $ORG -> $DOMAIN"
    certutil -d $HOME/.mozilla/firefox/$FF_PROFILE_DIR -A -t "C,," -n $DOMAIN -i $CERT
  fi
}

function install_as_CA_in_chrome() {

  echo ""
  confirm "Do you wish to import the certificate as a CA into Chrome?"
  local YES=$?

  if [[ "$YES" -eq 1 ]]; then

    echo "Deleting any old certificates registered for $DOMAIN..."
    certutil -d sql:$HOME/.pki/nssdb -D -n $DOMAIN

    echo "Adding $CERT as CA in Chrome..."
    echo "You can find it under: Manage Certificates -> Authorities -> org-$ORG -> $DOMAIN"

    certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n $DOMAIN -i $CERT
  fi
}

function export_pfx() {

  echo ""
  confirm "Do you wish to export certificate as a PFX file?"
  local YES=$?

  if [[ "$YES" -eq 1 ]]; then
    
    PFX=${DOMAIN}.pfx

    # Export as a PFX file
    echo "You must enter a password for PFX export..."
    openssl pkcs12 -export -in $CERT -inkey $KEY -out $PFX

    echo "PFX=$PFX"
  fi
}

main $@