#/bin/bash

cd /opt/staging
umask 0
set -o pipefail

# Check for local parameters file
if [ -f install.params ] ; then
   source ./install.params
fi

if [ "$#" -eq 1 ]; then
   PACKAGE=${1}
elif [ -z "${PACKAGE}" ]; then
   echo "Please specify the package to be installed. Eg:"
   echo "./install.sh SIC-AP-X.X.X"
   exit
fi

product=$(echo ${PACKAGE} | cut -d - -f2)

# Obtain the internal IP address
ip_addr=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text")
if [ $? -ne 0 ] ; then
   echo "Failed to obtain IP address from the metadata service. Aborting!"
   exit 1
fi

# Obtain keyvault access token
token_json=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true)
if [ $? -ne 0 ] ; then
   echo "Failed to obtain an acces token from the metadata service. Aborting!"
   exit 1
else
   access_token=$(echo -n ${token_json} | jq -r '.access_token')
fi

fetchSecret () {
   json=$(curl -s -H "Authorization: Bearer ${access_token}" "${KEYVAULT_URL}/secrets/${1}?api-version=7.1")
   if [ $? -ne 0 ] ; then # Error
      return 1
   else
      echo -n ${json} | jq -r '.value'
   fi
}

# Get the encoding salt from Keyvault
salt=$(fetchSecret ${product}salt)
if [ $? -ne 0 ] || [ ${#salt} -ne 24 ] ; then
   echo $salt
   echo "Failed to get the encoding salt from Key Vault. Aborting!"
   exit 1
fi

# Get the admin password from Keyvault
pw_encoded=$(fetchSecret ${product}GluuPW)
if [ $? -ne 0 ] || [ -z "${pw_encoded}" ] ; then
   echo "Failed to get the master password from Key Vault. Aborting!"
   exit 1
fi

#Decode the password
key=$(echo -n $salt | hexdump -ve '1/1 "%.2x"')
GLUU_PASSWORD=$(echo $pw_encoded | openssl enc -d -des-ede3 -K ${key} -nosalt -a)
if [ $? -ne 0 ] || [ -z "${GLUU_PASSWORD}" ] ; then
   echo "Failed to decode the master password. Aborting!"
   exit 1
else
   export GLUU_PASSWORD
fi

# If the SAML METADATA_URL is configured, then we will install Shibboleth
if [ -n "${METADATA_URL}" ] ; then
   # Get the Shibboleth password from Keyvault
   shib_password=$(fetchSecret ${product}ShibPW)
   if [ $? -ne 0 ] || [ -z "${shib_password}" ] ; then
      echo "Failed to fetch the shibboleth password. Aborting!"
      exit 1
   fi
fi

if [ -f /opt/gluu-server/install/community-edition-setup/setup.properties.last.enc ] ; then
   echo "Existing container detected. Backing up setup.properties..."
   cp /opt/gluu-server/install/community-edition-setup/setup.properties.last.enc .
fi

if [ -f /opt/gluu-server/etc/certs/oxauth-keys.jks ] ; then
   echo "Backing up the oxAuth and Passport keystores..."
   if [ ! -d backups ] ; then
      mkdir backups
   fi
   cp /opt/gluu-server/etc/certs/oxauth-keys.jks backups
   cp /opt/gluu-server/etc/certs/passport-rs.jks backups
   cp /opt/gluu-server/etc/certs/passport-rp.jks backups
   cp /opt/gluu-server/etc/certs/passport-rp.pem backups
   cp /opt/gluu-server/etc/gluu/conf/passport-config.json backups
fi

if [ -f setup.properties.last.enc ] ; then
   echo "Found setup.properties.last.enc. An update will be performed."

   # Check to see if loadData is turned off
   if openssl enc -d -aes-256-cbc -pass env:GLUU_PASSWORD -in setup.properties.last.enc | grep -q "loadData=True" ; then
      echo "Disabling database initialization"
      openssl enc -d -aes-256-cbc -pass env:GLUU_PASSWORD -in setup.properties.last.enc |
         sed -e "/^loadData=True/ s/.*/loadData=False/g" |
         openssl enc -aes-256-cbc -pass env:GLUU_PASSWORD -out setup.properties.last.new
      if [ $? -ne 0 ] ; then
         echo "Could not disable database initialization. Aborting!"
         exit 1
      else
         mv --backup setup.properties.last.new setup.properties.last.enc
      fi
   fi
else
   echo "New install. Creating setup.properties..."
   # Get the couchbase cluster host name(s)
   if [ -z "$CB_HOSTS" ] ; then
      read -p "Please enter the couchbase cluster hostname or IP => " -e -s CB_HOSTS
   fi
   if [ -z "$HOSTNAME" ] ; then
      HOSTNAME=$(hostname)
   fi
   {
   cat <<-EOF
		#$(date)
		hostname=$HOSTNAME
		encode_salt=${salt}
      ip=${ip_addr}
		persistence_type=couchbase
		cb_install=2
		wrends_install=0
		couchbase_hostname=${CB_HOSTS}
		couchebaseClusterAdmin=gluu
		cb_password=${GLUU_PASSWORD}
		isCouchbaseUserAdmin=True
		mappingLocations={"default"\: "couchbase", "user"\: "couchbase", "site"\: "couchbase", "cache"\: "couchbase", "token"\: "couchbase", "session"\: "couchbase"}
		oxauth_legacyIdTokenClaims=true
		orgName=TBS-SCT
		city=Ottawa
		state=ON
		countryCode=CA
		admin_email=signin-authenticanada@tbs-sct.gc.ca
		oxtrust_admin_password=${GLUU_PASSWORD}
		$([ "$product" = "AP" ] && echo "installPassport=True")
		$([ "$product" = "MFA" ] && echo "installFido2=True")
		$([ -n "${shib_password}" ] && echo "installSaml=True")
		$([ -n "${shib_password}" ] && echo "couchbaseShibUserPassword=${shib_password}")
	EOF
   } |
   openssl enc -aes-256-cbc -pass env:GLUU_PASSWORD -out setup.properties.last.enc
fi

# Download the product tarball 
echo Downloading ${PACKAGE}...
wget -nv ${STAGING_URL}/${PACKAGE}.tgz -O ${PACKAGE}.tgz
if [ $? -ne 0 ] ; then
   echo "Package download failed. Aborting!"
   exit 1
fi

wget -nv ${STAGING_URL}/${PACKAGE}.tgz.sha -O ${PACKAGE}.tgz.sha
if [ $? -ne 0 ] ; then
   echo "Package hash download failed. Aborting!"
   exit 1
fi

echo -n "Checking download integrity..."
if [ "$(cut -d ' ' -f 2 ${PACKAGE}.tgz.sha)" = "$(openssl sha256 ${PACKAGE}.tgz | cut -d ' ' -f 2)" ] ; then
   echo "Passed."
else
   echo "Failed!. Aborting installation."
   exit 1
fi

# Check for the Gluu package. Attempt to download if necessary

if [ ! -f /etc/pki/rpm-gpg/RPM-GPG-KEY-GLUU ] ; then
   echo "Attepmting to Download Gluu GPG Key"
   wget -nv https://repo.gluu.org/rhel/RPM-GPG-KEY-GLUU -O /etc/pki/rpm-gpg/RPM-GPG-KEY-GLUU
   if [ $? -ne 0 ] ; then
      echo "Gluu GPG Key Download Failed. Aborting!"
      exit 1
   fi
fi
echo "Importing the Gluu GPG Key"
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-GLUU

if [ ! -f ./gluu-server-4.2.3-*.x86_64.rpm ] ; then
   echo "Downloading Gluu Server"
   if grep Red /etc/redhat-release ; then
      wget -nv https://repo.gluu.org/rhel/7/gluu-server-4.2.3-rhel7.x86_64.rpm
   else
      wget -nv https://repo.gluu.org/centos/7/gluu-server-4.2.3-centos7.x86_64.rpm
   fi
fi

echo "Checking integrity of the Gluu RPM..."
rpm -K ./gluu-server-4.2.3-*.x86_64.rpm
if [ $? -eq 0 ] ; then
   echo "Passed."
else
   echo "Failed. Aborting!"
   exit 1
fi

echo "Uninstalling Gluu..."
yum remove -y gluu-server > /dev/null 2>&1
rm -rf /opt/gluu-server*

echo "Reinstalling Gluu..."
yum localinstall -y ./gluu-server-4.2.3-*.x86_64.rpm

while [ ! -f /opt/gluu-server/install/community-edition-setup/setup.py ] ; do
   echo "Gluu Setup was not extracted. Trying again..."
   # RPM is supposed to do this but sometimes doesn't. I think becasue the containter is not ready yet.
   sleep 5
   ssh -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                  -o PubkeyAuthentication=yes root@localhost '/opt/gluu/bin/install.py'  
done

echo "Adding Sign In Canada customizations..."
tar xvzf ${PACKAGE}.tgz -C /opt/gluu-server/

if grep Red /etc/redhat-release ; then
   echo "Configuring RedHat package repositories..."
   rm -rf /opt/gluu-server/etc/yum.repos.d/*
   cp -R /etc/yum.repos.d/epel-custom.repo /opt/gluu-server/etc/yum.repos.d
   cp -R /etc/yum.repos.d/redhat.repo /opt/gluu-server/etc/yum.repos.d
   cp -R /etc/yum.repos.d/rh-cloud.repo /opt/gluu-server/etc/yum.repos.d
   cp -R /etc/pki/rhui /opt/gluu-server/etc/pki
fi

echo "Configuring Keyvault URL..."
echo "KEYVAULT=${KEYVAULT_URL}" > /opt/gluu-server/etc/default/azure

if [ -n "${METADATA_URL}" ] ; then
   echo "Configuring SAML metadata URL..."
   sed -i "s|\[URL\]|${METADATA_URL}|g" \
      /opt/gluu-server/opt/dist/signincanada/shibboleth-idp/conf/metadata-providers.xml
fi

echo "Configuring Gluu..."
cp setup.properties.last.enc /opt/gluu-server/install/community-edition-setup/setup.properties.enc
ssh  -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o PubkeyAuthentication=yes root@localhost \
   "/install/community-edition-setup/setup.py -cnf /install/community-edition-setup/setup.properties.enc -properties-password '$GLUU_PASSWORD' --import-ldif=/opt/dist/signincanada/ldif"

echo "Completing Sign In Canada installation..."
ssh  -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o PubkeyAuthentication=yes root@localhost \
   "/opt/dist/signincanada/postinstall.sh"

if [ -d backups ] ; then
   echo "Restoring the oxAuth keystore..."
   cat backups/oxauth-keys.jks > /opt/gluu-server/etc/certs/oxauth-keys.jks
   echo "Restoring the Passport RS keystore..."
   cat backups/passport-rs.jks > /opt/gluu-server/etc/certs/passport-rs.jks
   echo "Restoring the Passport RP keystore and config..."
   cat backups/passport-rp.jks > /opt/gluu-server/etc/certs/passport-rp.jks
   cat backups/passport-rp.pem > /opt/gluu-server/etc/certs/passport-rp.pem
   cat backups/passport-config.json > /opt/gluu-server/etc/gluu/conf/passport-config.json
fi

if [ -d ./local ] ; then
   echo "Applying local configuration..."
   cp -R ./local/* /opt/gluu-server
fi

echo "Restarting Gluu..."
/sbin/gluu-serverd restart

echo "Cleaning up..."
rm -f ${PACKAGE}.tgz ${PACKAGE}.tgz.sha

echo "${PACKAGE} has been installed."
