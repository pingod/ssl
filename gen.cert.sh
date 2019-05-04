#!/usr/bin/env bash

# 扩展信任IP或域名
## 一般ssl证书只信任域名的访问请求，有时候需要使用ip去访问server，那么需要给ssl证书添加扩展IP，
## 多个IP用逗号隔开。如果想多个域名访问，则添加扩展域名（SSL_DNS）,多个SSL_DNS用逗号隔开
export SSL_IP='127.0.0.1,10.252.97.142' # 例如: 192.168.1.111
export SSL_DNS='boe.com.cn,*.boe.com.cn' # 例如: demo.rancher.com

export SSL_CONFIG=./openssl.cnf

if [ -z "$1" ];then
    echo
    echo 'Issue a wildcard SSL certificate with Fishdrowned ROOT CA'
    echo
    echo 'Usage: ./gen.cert.sh   <domain>'
    echo '    <domain>          The domain name of your site, like "example.dev",'
    echo '                      you will get a certificate for *.example.dev'
    echo '                      Multiple domains are acceptable'
    exit;
fi

if [[ -n ${SSL_DNS} || -n ${SSL_IP} ]]; then
    if [[ ! $(grep 'alt_names' ${SSL_CONFIG}) ]];then
        cat >> ${SSL_CONFIG} <<EOM
subjectAltName = @alt_names
[ alt_names ]
EOM
        IFS=","
        dns=(${SSL_DNS})
        for i in "${!dns[@]}"; do
        echo DNS.$((i+1)) = ${dns[$i]} >> ${SSL_CONFIG}
        done

        if [[ -n ${SSL_IP} ]]; then
            ip=(${SSL_IP})
            for i in "${!ip[@]}"; do
            echo IP.$((i+1)) = ${ip[$i]} >> ${SSL_CONFIG}
            done
        fi
    fi
fi

# Move to root directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Generate root certificate if not exists
if [ ! -f "out/root.crt" ]; then

    if [ ! -d "out" ]; then
        bash flush.sh
    fi

    # Generate root cert along with root key
    openssl req -config ${SSL_CONFIG} \
        -newkey rsa:2048 -nodes -keyout out/root.key.pem \
        -new -x509 -days 7300 -out out/root.crt \
        -subj "/C=CN/ST=Guangdong/L=Guangzhou/O=Fishdrowned/CN=Fishdrowned ROOT CA"

    # Generate cert key
    openssl genrsa -out "out/cert.key.pem" 2048

fi

# Create domain directory
BASE_DIR="out/$1"
TIME=`date +%Y%m%d-%H%M`
DIR="${BASE_DIR}/${TIME}"
mkdir -p ${DIR}

# Create CSR
openssl req -new -out "${DIR}/$1.csr.pem" \
    -key out/cert.key.pem \
    -config <(cat ${SSL_CONFIG} ) \
    -subj "/C=CN/ST=Guangdong/L=Guangzhou/O=Fishdrowned/OU=$1/CN=*.$1"

# Issue certificate
# openssl ca -batch -config .${SSL_CONFIG} -notext -in "${DIR}/$1.csr.pem" -out "${DIR}/$1.cert.pem"
openssl ca -config ${SSL_CONFIG} -batch -notext \
    -in "${DIR}/$1.csr.pem" \
    -out "${DIR}/$1.crt" \
    -cert ./out/root.crt \
    -keyfile ./out/root.key.pem

# Chain certificate with CA
cat "${DIR}/$1.crt" ./out/root.crt > "${DIR}/$1.bundle.crt"
ln -snf "./${TIME}/$1.bundle.crt" "${BASE_DIR}/$1.bundle.crt"
ln -snf "./${TIME}/$1.crt" "${BASE_DIR}/$1.crt"
ln -snf "../cert.key.pem" "${BASE_DIR}/$1.key.pem"
ln -snf "../root.crt" "${BASE_DIR}/root.crt"

# Output certificates
echo
echo "Certificates are located in:"

ls -la `pwd`/${BASE_DIR}/*.*