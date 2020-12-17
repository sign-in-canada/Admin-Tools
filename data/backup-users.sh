#!/bin/bash
module=$1
user=$2
directory=$3

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
password=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
file=${directory}/users-$(date +"%F").json

/opt/couchbase/bin/cbexport json -c couchbase://localhost -u $user -p $password -b gluu_user -f lines --include-key cbkey -o $file
sed -i -e '/Gluu Manager Group/d' -e '/Default Admin User/d' $file
