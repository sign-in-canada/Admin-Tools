#!/bin/bash
module=$1
user=$2
directory=$3

salt=$(azure/fetchsecret.sh ${module}Salt)
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
password_enc=$(azure/fetchsecret.sh ${module}gluuPW)
PASSWORD=$(echo ${password_enc} | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
export PASSWORD
file=${directory}/users-$(date +"%F")
query="SELECT t.Provider, COUNT(t.Provider) as Users
FROM
(
  SELECT CASE 
    WHEN (ARRAY v FOR v IN TOARRAY(gluu_user.oxExternalUid) WHEN v LIKE 'passport-saml:gckey%' END) THEN 'GCKEY'
    WHEN (ARRAY v FOR v IN TOARRAY(gluu_user.oxExternalUid) WHEN v LIKE 'passport-saml:cbs%' END) THEN 'CBS'
    ELSE 'OTHER'
  END AS Provider
  FROM gluu_user WHERE objectClass='gluuPerson'
) t
GROUP BY t.Provider"

/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "${query}" > ${file}.json
/opt/couchbase/bin/cbq -u $user -p $PASSWORD -s "SELECT oxSectorIdentifier, COUNT(doc) as users FROM gluu_user AS doc WHERE  objectClass = \"pairwiseIdentifier\" GROUP BY oxSectorIdentifier" >> ${file}.json
