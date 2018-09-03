#!/bin/bash

# Prerequsites: A record set (for the domain below), bash shell (not zsh), chmod +x ./install.sh
# Run as ROOT for example in /tmp directory and follow the instructions on the screen
# Tested on ubuntu 18.04 LTS

# Usage ./install.sh [DOMAIN NAME]
# ./install.sh canoed.cryptware.de

# CONSTANTS
# Do not use / sign and " sign in passwords
POSTGRES_PASSWORD="secretpassword123"
RATE_SERVICE_PASSWORD="secretpassword321"
RAI_NODE_REPO="https://github.com/nanocurrency/raiblocks.git"
CANOED_REPO="https://github.com/getcanoe/canoed"
RATE_SERVICE_REPO="https://github.com/getcanoe/rateservice.git"
MAILSERVER="mail.getcanoe.io"
MAILALERT="alert@getcanoe.io"

# Make sure only root can continue
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Check number of params
if (( $# != 1 )); then
    echo "Illegal number of parameters"
    echo "./install.sh [DOMAIN NAME]"
    exit 1
fi

apt-get update && apt-get -y upgrade
apt-get -y install git

# Set passwords to config files
git checkout ./canoed.conf
sed -i "s/secretpasswordmqtt/$RATE_SERVICE_PASSWORD/" ./canoed.conf
sed -i "s/secretpassworddb/$POSTGRES_PASSWORD/" ./canoed.conf
git checkout ./rateservice.conf
sed -i "s/secretpasswordmqtt/$RATE_SERVICE_PASSWORD/" ./rateservice.conf
git checkout ./vernemq
sed -i "s/secretpassworddb/$POSTGRES_PASSWORD/" ./vernemq
git checkout ./monit/monitrc
sed -i "s/mail.getcanoe.io/$MAILSERVER/" ./monit/monitrc
sed -i "s/alert@getcanoe.io/$MAILALERT/" ./monit/monitrc

echo "net.ipv4.tcp_fin_timeout = 20" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf
/sbin/sysctl -p

echo "# Raise for both canoed and vernemq users. If another user is running the rai_node add a line for it aswell." >> /etc/security/limits.conf
echo "canoed    -    nofile      65536" >> /etc/security/limits.conf
echo "vernemq   -    nofile      65536" >> /etc/security/limits.conf

apt-get -y install nginx redis-server git

sed -i 's^# server_tokens off;^server_tokens off;^' /etc/nginx/nginx.conf
git checkout ./default
sed -i "s/server_name _;/server_name $1;/" ./default
cp ./default /etc/nginx/sites-available/default
service nginx restart

apt-get -y install software-properties-common
add-apt-repository ppa:certbot/certbot
apt-get update
sudo apt-get -y install python-certbot-nginx 

echo "Please choose whether or not to redirect HTTP traffic to HTTPS, removing HTTP access: DO NOT REDIRECT"
certbot --nginx

crontab -l | grep 'certbot renew' || (crontab -l 2>/dev/null; echo '43 6 * * * certbot renew --post-hook "systemctl reload nginx"') | crontab -

wget https://bintray.com/artifact/download/erlio/vernemq/deb/xenial/vernemq_1.3.1-1_amd64.deb
dpkg -i vernemq_1.3.1-1_amd64.deb
cat ./vernemq >> /etc/vernemq/vernemq.conf
cp ./vernemq.service /etc/systemd/system/vernemq.service
systemctl daemon-reload
systemctl enable vernemq.service
systemctl start vernemq.service
systemctl --no-pager status vernemq

curl -sL https://deb.nodesource.com/setup_8.x -o nodesource_setup.sh
bash nodesource_setup.sh
apt-get -y install nodejs

sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt xenial-pgdg main" >> /etc/apt/sources.list'
wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get -y install postgresql-9.6 postgresql-contrib-9.6

sudo -u postgres createuser canoe
sudo -u postgres createdb canoe

echo
echo
echo "Please now execute those commands, copy them, this window will disappear and you will be able to continue"
echo
echo "alter user canoe with encrypted password '$POSTGRES_PASSWORD';"
echo "grant all privileges on database canoe to canoe;"
echo "\list"
echo "\connect canoe"
echo "CREATE EXTENSION pgcrypto;"
echo "\q"
echo
echo
sleep 10
read -p "Press enter to continue"

sudo -u postgres psql

apt-get -y install cmake g++ curl wget make

wget -O boost_1_66_0.tar.gz https://netix.dl.sourceforge.net/project/boost/boost/1.66.0/boost_1_66_0.tar.gz   
tar xzvf boost_1_66_0.tar.gz   
cd boost_1_66_0   
./bootstrap.sh --with-libraries=filesystem,iostreams,log,program_options,thread   
./b2 --prefix=../[boost] link=static install   
cd ..

git clone --recursive https://github.com/NOS-Cash/NOSnode2 rai_build   
cd rai_build   
cmake -DBOOST_ROOT=../[boost]/ -G "Unix Makefiles"   
make rai_node   
cp rai_node ../rai_node && cd .. && ./rai_node --diagnostics

useradd -m canoed
cp ./rai_node /home/canoed/
su - canoed -c './rai_node --daemon &'
sleep 5
pkill -f "rai_node"

sed -i 's/"callback_address": "",/"callback_address": "[::1]",/' /home/canoed/RaiBlocks/config.json
sed -i 's/"callback_port": "0",/"callback_port": "8180",/' /home/canoed/RaiBlocks/config.json
sed -i 's/"callback_target": "",/"callback_target": "\/callback",/' /home/canoed/RaiBlocks/config.json
sed -i 's/"rpc_enable": "false",/"rpc_enable": "true",/' /home/canoed/RaiBlocks/config.json
sed -i 's/"enable_control": "false",/"enable_control": "true",/' /home/canoed/RaiBlocks/config.json

cp ./rai_node.service /etc/systemd/system/rai_node.service

PREV_PATH=$(pwd)

cd /home/canoed
sudo -u canoed git clone https://github.com/getcanoe/canoed /home/canoed/canoed
cp "$PREV_PATH/canoed.conf" /home/canoed/canoed/canoed.conf
chown canoed:canoed /home/canoed/canoed/canoed.conf
cp "$PREV_PATH/canoed.service" /etc/systemd/system/canoed.service
cd /home/canoed/canoed

npm install
chown -R canoed:canoed .
/home/canoed/canoed/canoed --initialize

systemctl daemon-reload
systemctl enable canoed.service
systemctl start canoed.service

su - canoed -c 'git clone https://github.com/getcanoe/rateservice.git /home/canoed/rateservice'
cp "$PREV_PATH/rateservice.conf" /home/canoed/rateservice/rateservice.conf
chown canoed:canoed /home/canoed/rateservice/rateservice.conf

cd /home/canoed/rateservice
npm install
chown -R canoed:canoed .

sed -i "s/secretpassword/$POSTGRES_PASSWORD/" /home/canoed/canoed/addmqttuser
su - canoed -c "/home/canoed/canoed/addmqttuser rateservice $RATE_SERVICE_PASSWORD rateservice"

cp "$PREV_PATH/rateservice.service" /etc/systemd/system/rateservice.service
systemctl daemon-reload
systemctl enable rateservice.service
systemctl start rateservice.service

apt-get -y install monit

cp "$PREV_PATH/monit/nginx" /etc/monit/conf-available/nginx
cp "$PREV_PATH/monit/postgresql" /etc/monit/conf-available/postgresql
cp "$PREV_PATH/monit/rai_node"  /etc/monit/conf-available/rai_node
ln -s /etc/monit/conf-available/postgresql /etc/monit/conf-enabled/
ln -s /etc/monit/conf-available/nginx /etc/monit/conf-enabled/
ln -s /etc/monit/conf-available/rai_node /etc/monit/conf-enabled/

cp "$PREV_PATH/check-rai.sh" /home/canoed/check-rai.sh
cp "$PREV_PATH/start-rai.sh" /home/canoed/start-rai.sh
chmod +x /home/canoed/*.sh

cp "$PREV_PATH/monit/monitrc" /etc/monit/monitrc
systemctl reload monit
sudo monit status
sudo monit summary

systemctl enable rai_node
systemctl start rai_node

echo
echo
echo "Checking logs:  sudo journalctl -f -u canoed.service"
echo "To search for errors run:  sudo journalctl -u canoed.service | grep error"
echo
echo
echo "Following command shows the amount of accounts that were used with your canoe backend:"
echo "redis-cli scan | wc"
echo "Sometimes it might be needed to reset the sessions stored in redis. You can do that with this command:"
echo "redis-cli flushall"
echo "Keep in mind that currently running canoes need to be restarted after this."
echo
echo
echo "Script finished"
