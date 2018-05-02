#!/bin/sh

genpasswd() {
        local l=$1
        [ "$l" == "" ] && l=16
        tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${l} | xargs
}



# ec2 parameter set
INSTANCE_TYPE=`curl http://169.254.169.254/latest/meta-data/instance-type`
INSTACE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
PUBLIC_DOMAIN=`curl http://169.254.169.254/latest/meta-data/public-ipv4`

RAND8=`genpasswd 8`
RAND16=`genpasswd 16`
DATABASE_NAME=$INSTACE_ID
DATABASE_USER="ec_${RAND8}" 
DATABASE_PASS=`mkpasswd -l 16 | tr -c A-Za-z0-9 _`
DATABASE_ROOT_PASS=`mkpasswd -l 16 | tr -c A-Za-z0-9 _`
TABLE_PREFIX="${RAND8}_"
FTP_PASS="${RAND16}"

echo "DATABASE NAME $DATABASE_NAME" >> /root/fastpress.txt 2>&1
echo "DATABASE USER $DATABASE_USER" >> /root/fastpress.txt 2>&1
echo "DATABASE USER PASS $DATABASE_PASS" >> /root/fastpress.txt 2>&1
echo "DATABASE ROOT PASS $DATABASE_ROOT_PASS" >> /root/fastpress.txt 2>&1
echo "FTP PASS $FTP_PASS" >> /root/fastpress.txt 2>&1


# database alive check
mysqladmin ping -h127.0.0.1 -uroot >> /tmp/instance-initialize.log 2>&1
if [ ! $? -eq 0 ]; then
  systemctl restart mysqld
  mysqladmin ping -h127.0.0.1 -uroot >> /tmp/instance-initialize.log 2>&1
  if [ ! $? -eq 0 ]; then
    exit
  fi
fi

mysql -uroot -ps@mple_PW1 --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DATABASE_ROOT_PASS}';"
mysql -uroot -p${DATABASE_ROOT_PASS} -e "create database \`${DATABASE_NAME}\` default character set utf8mb4 collate utf8mb4_general_ci";
mysql -uroot -p${DATABASE_ROOT_PASS} -e "GRANT ALL ON \`${DATABASE_NAME}\`.* TO ${DATABASE_USER}@'localhost' IDENTIFIED BY '${DATABASE_PASS}';";
mysql -uroot -p${DATABASE_ROOT_PASS} -e "FLUSH PRIVILEGES";

METADATA=/var/www/html/public_html/wp-config.php

sed -i "s/___database_pass___/${DATABASE_PASS}/g" $METADATA
sed -i "s/___database_user___/${DATABASE_USER}/g" $METADATA
sed -i "s/___database_name___/${DATABASE_NAME}/g" $METADATA
sed -i "s/___table_prefix___/${TABLE_PREFIX}/g" $METADATA

LINE_NUMBER=`cat $METADATA | wc -l`
SALT_BEGIN_LINE_PRE=`grep -n "define('AUTH_KEY'" $METADATA | cut -f1 -d":"`
SALT_BEGIN_LINE=`expr ${SALT_BEGIN_LINE_PRE} - 1`
SALT_END_LINE_PRE=`grep -n "define('NONCE_SALT'" $METADATA | cut -f1 -d":"`
SALT_END_LINE=`expr ${LINE_NUMBER} - ${SALT_END_LINE_PRE}`

CONFIG_HEAD=`head -n ${SALT_BEGIN_LINE} $METADATA`
CONFIG_BODY=`curl https://api.wordpress.org/secret-key/1.1/salt/`
CONFIG_TAIL=`tail -n ${SALT_END_LINE} $METADATA`

if [ "${CONFIG_BODY}" != "" ]; then
    cp -p $METADATA $METADATA.bak
    echo "${CONFIG_HEAD}" > $METADATA
    echo "${CONFIG_BODY}" >> $METADATA
    echo "${CONFIG_TAIL}" >> $METADATA
fi

useradd fastpress
expect -c "
spawn passwd fastpress
expect \"New password:\"
send -- \"${FTP_PASS}\n\"
expect \"Retype new password:\"
send -- \"${FTP_PASS}\n\"
expect \"passwd: all authentication tokens updated successfully.\"
send -- \"exit\n\"
"
