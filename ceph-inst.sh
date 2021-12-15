#!/bin/bash -ex

list_logs () {
  ls -lah /var/log/ceph
}

create_install_vars () {
  echo -ne "###  Setting Basic Params"
  IFS='-' read -ra ARR <<< $HOSTNAME
  echo ${ARR}
  CEPH_CLUSTER_NAME=${ARR[0]}
  echo "Using cluster : ${CEPH_CLUSTER_NAME}"
  CEPH_ROLE=${ARR[1]}
  echo "Using role : ${CEPH_ROLE}"
  CEPH_NODE_ID=${ARR[2]}
  echo "Using node_id : ${CEPH_NODE_ID}"

  CEPH_NODE_IP=`ifconfig eth0| grep 'inet addr' | awk '{ print $2 }' | awk -F ':' '{ print $2}'`

  FSID=ca4643f1-c5d6-4eb7-a16e-49f2d5b35b90
  echo " - Done"
}

install_os_repos () {
  echo -ne "###  Bootstrapping APK Repos"
  sudo cat << EOF > /etc/apk/repositories
http://ewr.edge.kernel.org/alpine/v3.14/main
http://ewr.edge.kernel.org/alpine/v3.14/community
@edge http://ewr.edge.kernel.org/alpine/edge/main
#http://ewr.edge.kernel.org/alpine/edge/community
#http://ewr.edge.kernel.org/alpine/edge/testing
EOF
  echo  " - Done"
}

install_os_deps () {
  echo -ne "###  Installing Deps"
  sudo apk add python3==3.8.10-r0 py3-pip==20.3.4-r0 ceph@edge ceph-mgr@edge eudev@edge
  sudo pip install pyyaml
  echo  " - Done"
}

check_data_folders () {
  echo "Check data dir"
  sudo ls /var/lib/ceph/*
  echo " "
  echo "Check conf dif"
  ls /etc/ceph
}

set_perms () {
    sudo mkdir -p /etc/ceph
    sudo chown -R ceph /etc/ceph

    sudo mkdir -p /var/lib/ceph
    sudo chown -R ceph /var/lib/ceph

    sudo mkdir -p /var/run/ceph
    sudo chown -R ceph /var/run/ceph
}

heredoc_ceph-conf () {
  echo -ne "###  heredoc ceph.conf"
sudo -u ceph  cat << EOF > /etc/ceph/ceph.conf
[global]
fsid = ${FSID}
mon host = v2:${CEPH_NODE_IP}:3300/0,v1:${CEPH_NODE_IP}:6789/0
mon initial members = ${HOSTNAME}

public network = 10.0.0.0/24
cluster network = 10.5.0.0/24

auth cluster required = cephx
auth service required = cephx
auth client required = cephx

osd journal size = 1024
osd pool default size = 3
osd pool default min size = 2
osd pool default pg num = 333
osd pool default pgp num = 333
osd crush chooseleaf type = 1
EOF

echo  " - Done"
}

create_mon_keyring () {
  echo -ne "###  Creating Mon keyring"
  sudo -u ceph ceph-authtool \
    --create-keyring /etc/ceph/ceph.mon.keyring \
    --gen-key -n mon. \
    --cap mon 'allow *'
  echo  " - Done"
}

create_admin_keyring () {
  echo -ne "###  Creating Admin keyring"
  sudo -u ceph ceph-authtool \
    --create-keyring /etc/ceph/ceph.client.admin.keyring \
    --gen-key \
    -n client.admin \
    --cap mon 'allow *' \
    --cap osd 'allow *' \
    --cap mds 'allow *' \
    --cap mgr 'allow *'
  echo  " - Done"
}


create_osd_keyring () {
  echo -ne "###  Creating OSD keyring"
  mkdir -p /var/lib/ceph/bootstrap-osd
  sudo chown ceph /var/lib/ceph/bootstrap-osd

  sudo -u ceph ceph-authtool \
    --create-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring \
    --gen-key \
    -n client.bootstrap-osd \
    --cap mon 'profile bootstrap-osd' \
    --cap mgr 'allow r'
  echo  " - Done"
}

#create_admin_keyring
import_admin_keys () {
  echo -ne "###  Importing Admin Keys to Mon keyring"
  sudo -u ceph ceph-authtool /etc/ceph/ceph.mon.keyring \
    --import-keyring /etc/ceph/ceph.client.admin.keyring
  echo  " - Done"
}

import_osd_keys () {
  echo "###  Importing OSD Keys to Mon keyring"
  sudo -u ceph ceph-authtool /etc/ceph/ceph.mon.keyring \
    --import-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
  echo  " - Done"
}

create_mon_initmonmap () {
  echo "###  Create initial monmap"
  sudo -u ceph monmaptool \
    --create \
    --addv ${HOSTNAME} [v2:${CEPH_NODE_IP}:3300,v1:${CEPH_NODE_IP}:6789] \
    --fsid ${FSID} \
    /etc/ceph/monmap
  echo  " - Done"
}

create_mon () {
echo -ne "###  Ensure Mon data home"
sudo -u ceph mkdir -p /var/lib/ceph/mon/${HOSTNAME}
echo " - Done"

echo -ne "###  Create Monmap from initial"
sudo -u ceph ceph-mon \
  --cluster ${CEPH_CLUSTER_NAME} \
  --mkfs \
  -i ${CEPH_ROLE}-${CEPH_NODE_ID}-A \
  --monmap /etc/ceph/monmap \
  --keyring /etc/ceph/ceph.mon.keyring
echo  " - Done"
}

run_mon () {
echo -ne "### Run ceph-mon"
sudo -u ceph ceph-mon \
  --cluster ${CEPH_CLUSTER_NAME} \
  -c /etc/ceph/ceph.conf \
  -i ${CEPH_ROLE}-${CEPH_NODE_ID}-A \
  -d &&
# OR
#rc-service ceph-mon.0 start
echo  " - Done"
}

set_mon_params () {
  echo -ne "###  Set misc params"
  ceph -s
  ceph config set mon auth_allow_insecure_global_id_reclaim false
  ceph mon enable-msgr2
  ceph -s
echo  " - Done"
}
#set_mon_params
## Setup MGR/var/lib/ceph/mgr/ceph-ceph-00

#sudo -u ceph mkdir -p /var/lib/ceph/mgr/ceph-ceph-00
#ceph auth get-or-create mgr.$name mon 'allow profile mgr' osd 'allow *' mds 'allow *' > /var/lib/ceph/mgr/ceph-ceph-00/keyring

check_data_folders
list_logs
create_install_vars
#install_os_repos
#install_os_deps
# set_perms
# check_data_folders
# heredoc_ceph-conf
#
# ## Keyring
# create_mon_keyring
# create_admin_keyring
# create_osd_keyring
# check_data_folders
# create_admin_keyring
# import_admin_keys
# import_osd_keys
#
# ## MonMap
# create_mon_initmonmap
# create_mon
# check_data_folders
# run_mon
# set_mon_params
