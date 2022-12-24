#!/bin/bash

# Taken and edited from https://github.com/juanluisbaptiste/docker-postfix under GPLv3

[ "${DEBUG}" == "yes" ] && set -x

function add_config_value() {
  local key=${1}
  local value=${2}
  # local config_file=${3:-/etc/postfix/main.cf}
  [ "${key}" == "" ] && echo "ERROR: No key set !!" && exit 1
  [ "${value}" == "" ] && echo "ERROR: No value set !!" && exit 1

  echo "Setting configuration option ${key} with value: ${value}"
 postconf -e "${key} = ${value}"
}

[ -z "${SERVER_HOSTNAME}" ] && echo "SERVER_HOSTNAME is not set" && exit 1


#Get the domain from the server host name
DOMAIN=`echo ${SERVER_HOSTNAME} | awk 'BEGIN{FS=OFS="."}{print $(NF-1),$NF}'`

# Set needed config options
add_config_value "maillog_file" "/dev/stdout"
add_config_value "myhostname" ${SERVER_HOSTNAME}
add_config_value "mydestination" ${SERVER_HOSTNAME}
add_config_value "mydomain" ${DOMAIN}
add_config_value "myorigin" '$mydomain'
add_config_value "smtp_host_lookup" "native,dns"

# Bind to both IPv4 and IPv4
add_config_value "inet_protocols" "all"


#Enable logging of subject line
if [ "${LOG_SUBJECT}" == "yes" ]; then
  postconf -e "header_checks = regexp:/etc/postfix/header_checks"
  echo -e "/^Subject:/ WARN" >> /etc/postfix/header_checks
  echo "Enabling logging of subject line"
fi

#Check for subnet restrictions
nets='10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16'
if [ ! -z "${SMTP_NETWORKS}" ]; then
  declare ipv6re="^((([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|\
    ([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|\
    ([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|\
    ([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|\
    :((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}|\
    ::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|\
    (2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|\
    (2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))/[0-9]{1,3})$"

  for i in $(sed 's/,/\ /g' <<<$SMTP_NETWORKS); do
    if grep -Eq "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}" <<<$i ; then
      nets+=", $i"
    elif grep -Eq "$ipv6re" <<<$i ; then
      readarray -d \/ -t arr < <(printf '%s' "$i")
      nets+=", [${arr[0]}]/${arr[1]}"
    else
      echo "$i is not in proper IPv4 or IPv6 subnet format. Ignoring."
    fi
  done
fi
add_config_value "mynetworks" "${nets}"

# Set SMTPUTF8
if [ ! -z "${SMTPUTF8_ENABLE}" ]; then
  postconf -e "smtputf8_enable = ${SMTPUTF8_ENABLE}"
  echo "Setting configuration option smtputf8_enable with value: ${SMTPUTF8_ENABLE}"
fi

if [ ! -z "${OVERWRITE_FROM}" ]; then
  echo -e "/^From:.*$/ REPLACE From: $OVERWRITE_FROM" > /etc/postfix/smtp_header_checks
  postmap /etc/postfix/smtp_header_checks
  postconf -e 'smtp_header_checks = regexp:/etc/postfix/smtp_header_checks'
  echo "Setting configuration option OVERWRITE_FROM with value: ${OVERWRITE_FROM}"
fi

# Set message_size_limit
if [ ! -z "${MESSAGE_SIZE_LIMIT}" ]; then
  postconf -e "message_size_limit = ${MESSAGE_SIZE_LIMIT}"
  echo "Setting configuration option message_size_limit with value: ${MESSAGE_SIZE_LIMIT}"
fi


postconf -e "virtual_alias_maps = regexp:/etc/postfix/redirect"
postconf -e "luser_relay = rss@rss.transport"

# Create transport file
echo "Creating transport file"
echo "* rsstransport:" > /etc/postfix/transport

# Add transport file to postfix
#postconf -e "transport_maps = regexp:/etc/postfix/transport"

# Add transport to master.cf
echo "Adding transport to master.cf"
echo "rsstransport unix - n n - - pipe flags=R user=mailrcv argv=/recv.sh" >> /etc/postfix/master.cf

postconf -e "default_transport = rsstransport"

#Start services

# If host mounting /var/spool/postfix, we need to delete old pid file before
# starting services
rm -f /var/spool/postfix/pid/master.pid

exec /usr/sbin/postfix -c /etc/postfix start-fg