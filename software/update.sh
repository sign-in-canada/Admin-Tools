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

echo "Extracting Sign In Canada customizations..."
tar xvzf ${PACKAGE}.tgz opt/dist/signincanada/custom.tgz opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz opt/dist/gluu/passport.tgz opt/azure/applicationinsights-agent-*.jar

if ! cmp --silent opt/dist/signincanada/custom.tgz /opt/gluu-server/opt/dist/signincanada/custom.tgz ; then
   echo "Updating oxAuth customizations"
   cp /opt/gluu-server/opt/dist/signincanada/custom.tgz /opt/gluu-server/opt/dist/signincanada/custom.tgz.bak
   cat opt/dist/signincanada/custom.tgz > /opt/gluu-server/opt/dist/signincanada/custom.tgz
   ssh  -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o PubkeyAuthentication=yes root@localhost \
   "mkdir /opt/gluu/jetty/oxauth/custom.new ; \
    tar xzf /opt/dist/signincanada/custom.tgz -C /opt/gluu/jetty/oxauth/custom.new ; \
    chown -R jetty:jetty /opt/gluu/jetty/oxauth/custom.new ; \
    rm -rf /opt/gluu/jetty/oxauth/custom.old ; \
    mv /opt/gluu/jetty/oxauth/custom /opt/gluu/jetty/oxauth/custom.old ; \
    mv /opt/gluu/jetty/oxauth/custom.new /opt/gluu/jetty/oxauth/custom ; \
    touch /opt/gluu/jetty/oxauth/custom/scripts/*/*.py"
fi

if ! cmp --silent opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz /opt/gluu-server/opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz \
    || ! cmp --silent opt/dist/gluu/passport.tgz /opt/gluu-server/opt/dist/gluu/passport.tgz ; then
   echo "Updating Passport"
   cp /opt/gluu-server/opt/dist/gluu/passport.tgz /opt/gluu-server/opt/dist/gluu/passport.tgz.bak
   cp /opt/gluu-server/opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz /opt/gluu-server/opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz.bak
   cat opt/dist/gluu/passport.tgz > /opt/gluu-server/opt/dist/gluu/passport.tgz
   cat opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz > /opt/gluu-server/opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz
   ssh  -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o PubkeyAuthentication=yes root@localhost \
   "umask 7 ; \
    mkdir -p /opt/gluu/node/passport.new/logs ; \
    tar xzf /opt/dist/gluu/passport.tgz --strip 1 -C /opt/gluu/node/passport.new --no-xattrs --no-same-owner --no-same-permissions ; \
    tar xzf /opt/dist/gluu/passport-version_4.4.0-node_modules.tar.gz -C /opt/gluu/node/passport.new --no-xattrs --no-same-owner --no-same-permissions ; \
    chown -R node:gluu /opt/gluu/node/passport.new ; \
    chmod -R g+w /opt/gluu/node/passport.new ; \
    systemctl stop passport ; \
    rm -rf /opt/gluu/node/passport.old ; \
    mv /opt/gluu/node/passport /opt/gluu/node/passport.old ; \
    mv /opt/gluu/node/passport.new /opt/gluu/node/passport ; \
    systemctl start passport"
fi

newagent=$(find opt/azure/ -name applicationinsights-agent-*.jar -printf '%f\n')
oldagent=$(find /opt/gluu-server/opt/azure/ -name applicationinsights-agent-*.jar -printf '%f\n')
if [ "$newagent" != "$oldagent" ] ; then
   echo "Updating Application Insights Java agent"
   cp opt/azure/$newagent /opt/gluu-server/opt/azure
   mv /opt/gluu-server/opt/azure/$oldagent /opt/gluu-server/opt/azure/$oldagent.old
   sed -i "s/$oldagent/$newagent/" /opt/gluu-server/etc/default/oxauth
   sed -i "s/$oldagent/$newagent/" /opt/gluu-server/etc/default/identity
   if [ -f /opt/gluu-server/etc/default/fido ] ; then
      sed -i "s/$oldagent/$newagent/" /opt/gluu-server/etc/default/fido2
   fi
   if [ -f /opt/gluu-server/etc/default/idp ] ; then
      sed -i "s/$oldagent/$newagent/" /opt/gluu-server/etc/default/idp
   fi
fi

echo "Cleaning up..."
rm -f ${PACKAGE}.tgz ${PACKAGE}.tgz.sha
rm -rf opt

echo "${PACKAGE} has been installed."

