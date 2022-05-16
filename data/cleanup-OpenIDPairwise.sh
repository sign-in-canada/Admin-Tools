#!/bin/bash
module=$1
user=$2
clientInum=$3
action=$4

if [ $# -lt 3 ] ; then
    echo "Usage: $0 <module> <gluuUsername> <clientInum> [<action>]"
    echo "       <action>: 'view' | 'update'. Default option is 'view' when the action is not specified"
    exit
fi

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
PASSWORD=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
export PASSWORD

# Check the OIDC client existence
oxAuthClient=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "SELECT count(*) FROM gluu WHERE objectClass='oxAuthClient' and inum='$clientInum'" | sed -n '/^{/,$p' | jq -r '.results[] | ."$1"')

if [ $oxAuthClient -ne 1 ] ; then
    echo "Error: invalid OIDC <clientInum>"
    exit
fi

# Count identified gluuPerson documents subject to update: with any OIDC client pairwiseIdentifier in oxPPID array
gluuPersonDocsCount=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "SELECT count(*) FROM gluu_user WHERE objectClass='gluuPerson' AND ANY id IN oxPPID SATISFIES id IN (SELECT RAW u.oxId FROM gluu_user u WHERE u.objectClass='pairwiseIdentifier' and u.oxAuthClientId='$clientInum') END" | sed -n '/^{/,$p' | jq '.results[] | ."$1"')
echo "Number of identified gluuPerson documents subject to this cleanup operation is $gluuPersonDocsCount"

# Count identified pairwiseIdentifier documents subject to update: with the specified OIDC client inum
pwIdDocsCount=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "SELECT count(*) FROM gluu_user WHERE objectClass='pairwiseIdentifier' AND oxAuthClientId = '$clientInum'" | sed -n '/^{/,$p' | jq '.results[] | ."$1"')
echo "Number of identified pairwiseIdentifier documents subject to this cleanup operation is $pwIdDocsCount"

# Count total number of documents to update or to delete
totalDocToUpdate=$(($gluuPersonDocsCount + $pwIdDocsCount))

# Update the CB records if update action is specified
shopt -s nocasematch; 
if [[ ! -z "$action" && "update" =~ "$action" && totalDocToUpdate -gt 0 ]]; then 
    echo "Database update in progress ..."

    # Update
    # Action 1- Remove any members of the oxPPID array that match a pairwiseIdentifier document of the specified OIDC client   
    updateAction1=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "UPDATE gluu_user SET oxPPID = ARRAY v FOR v IN oxPPID WHEN v NOT IN (SELECT RAW u.oxId FROM gluu_user u WHERE u.objectClass='pairwiseIdentifier' and u.oxAuthClientId='$clientInum') END WHERE objectClass='gluuPerson' AND ANY id IN oxPPID SATISFIES id IN (SELECT RAW u.oxId FROM gluu_user u WHERE u.objectClass='pairwiseIdentifier' and u.oxAuthClientId='$clientInum') END" | sed -n '/^{/,$p')
    status1=$(echo $updateAction1 | jq -r '.status')
    mutationCount1=$(echo $updateAction1 | jq '.metrics' | jq '.mutationCount')

    # Action 2- Delete pairwiseIdentifier documents of the specified OIDC client   
    updateAction2=$(/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "DELETE FROM gluu_user WHERE objectClass='pairwiseIdentifier' AND oxAuthClientId = '$clientInum'" | sed -n '/^{/,$p')
    status2=$(echo $updateAction2 | jq -r '.status')
    mutationCount2=$(echo $updateAction2 | jq '.metrics' | jq '.mutationCount')

    # Check operations status and number of updated records 
    if [[ $status1 == 'success' && $status2 == 'success' && $mutationCount1 -eq $gluuPersonDocsCount && $mutationCount2 -eq $pwIdDocsCount ]] ; then
        echo "Cleaning up successfully completed"
    else
        echo "Cleaning up completed with errors"
    fi
fi
