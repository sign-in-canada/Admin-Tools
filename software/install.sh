#/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Please specify the package to be installed. Eg:"
    echo "./install.sh SIC-AP-X.X.X"
    exit
fi

umask 0
source install.params
read -p "Please enter the configuration decryption passaword => " -e -s PASSWORD

rm -f ${1}.tgz ${1}.tgz.sha

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

if [ ! -f ./oxauth-keys.jks ] ; then
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
rpm -K ./gluu-server-4.1.0-*.x86_64.rpm
if [ $? -eq 0 ] ; then
   echo "Passed."
else
   echo "Failed. Aborting!"
   exit
fi

echo "Reinstalling Gluu..."
yum localinstall -y ./gluu-server-4.1.0-*.x86_64.rpm

if [ ! -f /opt/gluu-server/install/community-edition-setup/setup.py ] ; then
   echo "Gluu setup install failed. Aborting!"
   exit
fi

echo "Adding Sign In Canada customizations..."
tar xvzf ${1}.tgz -C /opt/gluu-server/

echo "Configuring Keyvault URL..."
echo "KEYVAULT=${KEYVAULT_URL}" > /opt/gluu-server/etc/default/azure

if [ ! -z "$METADATA_URL" ] ; then
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
   "/install/community-edition-setup/setup.py -n -f /install/community-edition-setup/setup.properties.enc -properties-password '$PASSWORD' --import-ldif=/opt/dist/signincanada/ldif ; \
    /opt/dist/signincanada/postinstall.sh"

if [ -f ./oxauth-keys.jks ] ; then
   echo "Restoring the oxAuth keystore."
   cat ./oxauth-keys.jks > /opt/gluu-server/etc/certs/oxauth-keys.jks
fi

if [ -d ./local ] ; then
   echo "Applying local configuration..."
   cp -R ./local/* /opt/gluu-server
fi

echo "Restoring the logs..."
tar xzf logs.tgz -C /opt/gluu-server

echo "Restarting Gluu..."
/sbin/gluu-serverd restart

echo "Cleaning up..."
rm -f ${1}.tgz ${1}.tgz.sha

echo "${1} has been installed."
