# Install Couchbase on a clean VM

# TODO: Download the Couchbase GPG key and RPM. Verify the latter.

echo "Configuring the O/S for Couchbase..."  

if [ ! -d /etc/tuned/no-thp ] ; then
  mkdir /etc/tuned/no-thp
  cat > /etc/tuned/no-thp/tuned.conf <<-EOF
	[main]
	include=virtual-guest

	[vm]
	transparent_hugepages=never
EOF

  tuned-adm profile no-thp

  echo 0 > /proc/sys/vm/swappiness
  cp -p /etc/sysctl.conf /etc/sysctl.conf.`date +%Y%m%d-%H:%M`
  echo >> /etc/sysctl.conf
  echo "#Set swappiness to 0 to avoid swapping" >> /etc/sysctl.conf
  echo "vm.swappiness = 0" >> /etc/sysctl.conf
fi

# TODO: Download the Couchbase GPG key and RPM. Verify the latter.

echo "Installing Couchbase..."  
sudo yum install -y https://packages.couchbase.com/releases/6.6.5/couchbase-server-enterprise-6.6.5-centos7.x86_64.rpm

echo "Updating O/S packages"
yum clean all
yum update -y
