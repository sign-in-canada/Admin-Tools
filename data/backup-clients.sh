#!/bin/bash
module=$1
user=$2
directory=$3

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
PASSWORD=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
export PASSWORD
file=${directory}/clients-$(date +"%F")

/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "SELECT gluu.* FROM gluu WHERE objectClass='oxAuthClient' AND oxdId = ''" |
    sed -n '/^{/,$p' | jq '.results'> ${file}.json
openssl enc -aes-256-cbc -pass env:PASSWORD -in ${file}.json -out ${file}.enc
