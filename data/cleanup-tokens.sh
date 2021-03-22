#!/bin/bash
module=AP
user=Administrator
API_VER='7.0'

source /etc/default/azure

# Obtain an access token
TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true | jq -r '.access_token')

fetchSecret () {
   curl -s -H "Authorization: Bearer ${TOKEN}" ${KEYVAULT}/secrets/${1}?api-version=${API_VER} \
      | jq -r '.value'
}

salt=$(fetchSecret ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(fetchSecret ${module}gluuPW)
password=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)

/opt/couchbase/bin/cbq -u $user -p $password -s "update gluu set META().expiration = 3600 where objectClass = 'oxUmaResourcePermission'"
/opt/couchbase/bin/cbq -u $user -p $password -s "update gluu_token set META().expiration = 3600 where objectClass = 'oxAuthUmaRPT'"