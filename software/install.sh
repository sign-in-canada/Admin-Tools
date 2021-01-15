#/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Please specify the package to be installed. Eg:"
    echo "./install.sh SIC-AP-X.X.X"
    exit
fi

PRODUCT=$(echo ${1} | cut -c5-6)

umask 0

# Check for local parameters file
if [ -f install.params ] ; then
   source install.params
fi

# Obtain keyvault access token

TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true | jq -r '.access_token')

fetchSecret () {
   curl -s -H "Authorization: Bearer ${TOKEN}" ${KEYVAULT_URL}/secrets/${1}?api-version=7.1 | jq -r '.value'
}

# Verify keyvault connectivity before going any further
if fetchSecret 'x' > /dev/null 2>&1 ; then
   echo "Connected to Keyvault ${KEYVAULT_URL}"
else
   echo "Connection to Keyvault ${KEYVAULT_URL} failed. Aborting."
   exit 1
fi

# Get the admin password from Keyvault
GLUU_PASSWORD=$(fetchSecret ${PRODUCT}GluuPW)
if [ -z "$GLUU_PASSWORD" ] ; then
   read -p "Please enter the configuration decryption passaword => " -e -s GLUU_PASSWORD
fi
export GLUU_PASSWORD

# Get the Shibboleth password from Keyvault
SHIB_PASSWORD=$(fetchSecret ${PRODUCT}ShibPW)

# Get the couchbase cluster host name(s)
if [ -z "$CB_HOSTS" ] ; then
   read -p "Please enter the couchbase cluster hostname or IP => " -e -s CB_HOSTS
fi

# Get the encoding salt from Keyvault
SALT=$(fetchSecret ${PRODUCT}salt)

# Remove any old downloads
rm -f ${1}.tgz ${1}.tgz.sha

# Download the product tarball 
echo Downloading ${1}...
wget ${STAGING_URL}/${1}.tgz
wget ${STAGING_URL}/${1}.tgz.sha
echo -n "Checking download integrity..."
if [ "$(cut -d ' ' -f 2 ${1}.tgz.sha)" = "$(openssl sha256 ${1}.tgz | cut -d ' ' -f 2)" ] ; then
   echo "Passed."
else
   echo "Failed!. Aborting installation."
   exit 1
fi

echo "Stopping Gluu..."
if [ -f /sbin/gluu-serverd ] ; then
/sbin/gluu-serverd stop
fi

if [ -f /opt/gluu-server/install/community-edition-setup/setup.properties.last.enc ] ; then
   echo "Update detected. Backing up setup.properties..."
   cp /opt/gluu-server/install/community-edition-setup/setup.properties.last.enc .

   # Check to see if loadData is turned off
   if openssl enc -d -aes-256-cbc -pass env:GLUU_PASSWORD -in setup.properties.last.enc | grep -q "loadData=True" ; then
      echo "Disabling database initialization"
      openssl enc -d -aes-256-cbc -pass env:GLUU_PASSWORD -in setup.properties.last.enc |
         sed -e "/^loadData=True/ s/.*/loadData=False/g" |
         openssl enc -aes-256-cbc -pass env:GLUU_PASSWORD -out setup.properties.last.enc
   fi
else
   echo "New install. Creating setup.properties..."
   {
   cat <<-EOF
		#$(date)
		hostname=$(hostname)
		ip=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text")
		persistence_type=couchbase
		cb_install=2
		wrends_install=0
		couchbase_hostname=${CB_HOSTS}
		couchebaseClusterAdmin=gluu
		cb_password=${GLUU_PASSWORD}
		isCouchbaseUserAdmin=True
		mappingLocations={"default"\: "couchbase", "user"\: "couchbase", "site"\: "couchbase", "cache"\: "couchbase", "token"\: "couchbase", "session"\: "couchbase"}
		installPassport=True
		installSaml=True
		orgName=TBS-SCT
		city=Ottawa
		state=ON
		countryCode=CA
		admin_email=signin-authenticanada@tbs-sct.gc.ca
		oxtrust_admin_password=${GLUU_PASSWORD}
		$([ -n "${SALT}" ] && echo "encode_salt=${SALT}")
		$([ -n "${SHIB_PASSWORD}" ] && echo "couchbaseShibUserPassword=${SHIB_PASSWORD}")
	EOF
   } |
   openssl enc -aes-256-cbc -pass env:GLUU_PASSWORD -out setup.properties.last.enc
fi

if [ -f /opt/gluu-server/etc/certs/oxauth-keys.jks ] ; then
   echo "Backing up the oxAuth keystore"
   cp /opt/gluu-server/etc/certs/oxauth-keys.jks .
fi

if [ -f /opt/gluu-server/opt/gluu/jetty/oxauth/logs/oxauth.log ] ; then
   echo "Backing up the Gluu logs..."
   tar czf logs.tgz -C /opt/gluu-server \
                       opt/gluu/jetty/oxauth/logs \
                       opt/gluu/jetty/identity/logs \
                       opt/shibboleth-idp/logs \
                       opt/gluu/node/passport/server/logs \
                       var/log/httpd
fi

echo "Uninstalling Gluu..."
yum remove -y gluu-server
rm -rf /opt/gluu-server*

echo "Checking integrity of the Gluu RPM..."
rpm -K ./gluu-server-4.2.2-*.x86_64.rpm
if [ $? -eq 0 ] ; then
   echo "Passed."
else
   echo "Failed. Aborting!"
   exit
fi

echo "Reinstalling Gluu..."
yum localinstall -y ./gluu-server-4.2.2-*.x86_64.rpm

if [ ! -f /opt/gluu-server/install/community-edition-setup/setup.py ] ; then
   echo "Gluu setup install failed. Aborting!"
   exit
fi

echo "Adding Sign In Canada customizations..."
tar xvzf ${1}.tgz -C /opt/gluu-server/

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

if [ -n "$METADATA_URL" ] ; then
   echo "Configuring SAML metadata URL..."
   sed -i "s|\[URL\]|${METADATA_URL}|g" \
      /opt/gluu-server/opt/dist/signincanada/shibboleth-idp/conf/metadata-providers.xml
fi

if [ -f ./passport-central-config.json ] ; then
   echo "Restoring CSP and IDP configurations"
   cat ./passport-central-config.json > /opt/gluu-server/install/community-edition-setup/templates/passport-central-config.json
fi

echo "Configuring Gluu..."
cp setup.properties.last.enc /opt/gluu-server/install/community-edition-setup/setup.properties.enc
ssh  -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o PubkeyAuthentication=yes root@localhost \
   "/install/community-edition-setup/setup.py -cnf /install/community-edition-setup/setup.properties.enc -properties-password '$GLUU_PASSWORD' --import-ldif=/opt/dist/signincanada/ldif ; \
    /opt/dist/signincanada/postinstall.sh"

if [ -f ./oxauth-keys.jks ] ; then
   echo "Restoring the oxAuth keystore."
   cat ./oxauth-keys.jks > /opt/gluu-server/etc/certs/oxauth-keys.jks
fi

if [ -d ./local ] ; then
   echo "Applying local configuration..."
   cp -R ./local/* /opt/gluu-server
fi

if [ -f logs.tgz ] ; then
   echo "Restoring the logs..."
   tar xzf logs.tgz -C /opt/gluu-server
fi

echo "Restarting Gluu..."
/sbin/gluu-serverd restart

echo "Cleaning up..."
rm -f ${1}.tgz ${1}.tgz.sha

echo "${1} has been installed."
