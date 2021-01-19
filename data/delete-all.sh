#!/bin/bash
export CB_REST_USERNAME=$1
export CB_REST_PASSWORD=$2

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