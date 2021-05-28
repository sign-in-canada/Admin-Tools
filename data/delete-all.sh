#!/bin/bash
module=$1

export CB_REST_USERNAME=Administrator
salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
CB_REST_PASSWORD=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
export CB_REST_PASSWORD

/opt/couchbase/bin/couchbase-cli  bucket-delete -c localhost:8091 \
    --bucket gluu

/opt/couchbase/bin/couchbase-cli  bucket-delete -c localhost:8091 \
    --bucket gluu_user

/opt/couchbase/bin/couchbase-cli  bucket-delete -c localhost:8091 \
    --bucket gluu_session

/opt/couchbase/bin/couchbase-cli  bucket-delete -c localhost:8091 \
    --bucket gluu_cache

/opt/couchbase/bin/couchbase-cli  bucket-delete -c localhost:8091 \
    --bucket gluu_token

/opt/couchbase/bin/couchbase-cli  bucket-delete -c localhost:8091 \
    --bucket gluu_site

/opt/couchbase/bin/couchbase-cli  user-manage -c localhost:8091 \
    --delete --rbac-username couchbaseShibUser --auth-domain local