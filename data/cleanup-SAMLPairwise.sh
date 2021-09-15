#!/bin/bash
module=$1
user=$2
rpEntityId=$3
action=$4

if [ $# -lt 3 ] ; then
    echo "Usage: $0 <module> <gluuUsername> <rpEntityId> [<action>]"
    echo "       <action>: 'view' | 'update'. Default option is 'view' when the action is not specified"
    exit
fi

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
PASSWORD=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
export PASSWORD

# Count identified records subject to update
recordsCount=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "SELECT count(*) FROM gluu_user WHERE objectClass='gluuPerson' AND ANY pId IN persistentId SATISFIES pId LIKE '$rpEntityId|%' END" | sed -n '/^{/,$p' | jq '.results[] | ."$1"')
echo "Number of identified records subject to this cleanup operation is $recordsCount"

# Update the CB records if update action is specified
shopt -s nocasematch; 
if [[ ! -z "$action" && "update" =~ "$action" && $recordsCount -gt 0 ]]; then 
    echo "Database update in progress ..."

    # update
    updateAction=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "UPDATE gluu_user SET persistentId = ARRAY v FOR v IN persistentId WHEN v NOT LIKE '$rpEntityId|%' END WHERE objectClass='gluuPerson' AND ANY pId IN persistentId SATISFIES pId LIKE '$rpEntityId|%' END" | sed -n '/^{/,$p')
    status=$(echo $updateAction | jq -r '.status')
    mutationCount=$(echo $updateAction | jq '.metrics' | jq '.mutationCount')

    # Check the operation status and the number of updated records 
    if [[ $status == 'success' && $mutationCount -eq $recordsCount ]] ; then
        echo "Cleaning up successfully completed"
    else
        echo "Cleaning up completed with errors"
    fi
fi
