#!/bin/bash
echo "Create gluu user"
/opt/couchbase/bin/couchbase-cli user-manage -c couchbase://localhost \
--set \
--rbac-username gluu \
--roles 'query_update[*], query_select[*], query_insert[*], query_delete[*], data_writer[*], data_reader[*]' \
--auth-domain local

if [ "$product" == "AP" ] ; then
  echo "Create Shibboleth user"
  /opt/couchbase/bin/couchbase-cli user-manage -c couchbase://localhost \
    --set \
    --rbac-username couchbaseShibUser \
    --roles 'query_select[gluu_user]' \
    --auth-domain local
fi