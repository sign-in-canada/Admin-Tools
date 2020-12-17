#!/bin/bash
module=$1
user=$2
directory=$3

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
password=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
file=${directory}/clients-$(date +"%F").json

/opt/couchbase/bin/cbq -u $user -p $password -s "SELECT gluu.* FROM gluu WHERE objectClass='oxAuthClient' AND oxdId = ''" > $file
echo "Don't forget to save the client secret salt"
