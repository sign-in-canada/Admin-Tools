# Install Gluu on a new VM

echo "Downloading Gluu GPG Key"
# TODO: We should have outr own copy of the GPG key in an S3 bucket we control, to mitigate MITM
wget -nv https://repo.gluu.org/rhel/RPM-GPG-KEY-GLUU -O /etc/pki/rpm-gpg/RPM-GPG-KEY-GLUU
if [ $? -ne 0 ] ; then
   echo "Gluu GPG Key Download Failed. Aborting!"
   exit 1
fi

echo "Importing the Gluu GPG Key"
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-GLUU

echo "Downloading Gluu Server"
if grep Red /etc/redhat-release ; then
   wget -nv https://repo.gluu.org/rhel/7/gluu-server-4.4.0-rhel7.x86_64.rpm
else
   wget -nv https://repo.gluu.org/centos/7/gluu-server-4.4.0-centos7.x86_64.rpm
fi

echo "Checking integrity of the Gluu RPM..."
rpm -K ./gluu-server-4.4.0-*.x86_64.rpm
if [ $? -eq 0 ] ; then
   echo "Passed."
else
   echo "Failed. Aborting!"
   exit 1
fi

echo "Installing Gluu..."
yum install -y ./gluu-server-4.4.0-*.x86_64.rpm

while [ ! -f /opt/gluu-server/install/community-edition-setup/setup.py ] ; do
   echo "Gluu Setup was not extracted. Trying again..."
   # RPM is supposed to do this but sometimes doesn't. I think becasue the containter is not ready yet.
   sleep 5
   ssh -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                  -o PubkeyAuthentication=yes root@localhost '/opt/gluu/bin/install.py'
done

if grep Red /etc/redhat-release ; then
   echo "Configuring RedHat package repositories..."
   rm -rf /opt/gluu-server/etc/yum.repos.d/*
   cp -R /etc/yum.repos.d/epel-custom.repo /opt/gluu-server/etc/yum.repos.d
   cp -R /etc/yum.repos.d/redhat.repo /opt/gluu-server/etc/yum.repos.d
   cp -R /etc/yum.repos.d/rh-cloud.repo /opt/gluu-server/etc/yum.repos.d
   cp -R /etc/pki/rhui /opt/gluu-server/etc/pki
fi

echo "Patching Gluu setup..."
sed -i 's/key_expiration=2,/key_expiration=730,/' /opt/gluu-server/install/community-edition-setup/setup_app/installers/oxauth.py
sed -i 's/enc with password {1}/enc with password/' /opt/gluu-server/install/community-edition-setup/setup_app/utils/properties_utils.py
sed -i 's|/usr/java/latest/jre/lib/security/cacerts|%(default_trust_store_fn)s|' /opt/gluu-server/install/community-edition-setup/templates/oxtrust/oxtrust-config.json
sed -i 's|\"caCertsPassphrase\":\"\"|\"caCertsPassphrase\":\"%(defaultTrustStorePW)s\"|' /opt/gluu-server/install/community-edition-setup/templates/oxtrust/oxtrust-config.json
sed -i '/^\s*start_services()$/d' /opt/gluu-server/install/community-edition-setup/setup.py

echo "Updating Conbtainer packages..."
ssh  -t -o IdentityFile=/etc/gluu/keys/gluu-console -o Port=60022 -o LogLevel=QUIET \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o PubkeyAuthentication=yes root@localhost \
   "yum clean all ; yum update -y"

; TODO: Install the AWS CLI within the contianer

echo "Updating server packages..."
yum clean all
yum update -y
