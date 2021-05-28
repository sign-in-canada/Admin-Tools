#!/bin/bash
module=$1
user=$2
file=$3

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
password=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)

/opt/couchbase/bin/cbimport json -c couchbase://localhost -u $user -p $password -b gluu_user -f lines -g "%cbkey%" --ignore-fields cbkey -d file://${file}

