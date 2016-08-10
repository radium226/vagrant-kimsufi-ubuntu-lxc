#!/bin/bash

mode="${1}"
ipv6="${2}"
ipv4="${3}"
host="${4}"

case "${mode}" in
  add|old)
    echo "address=/.${host}.lxc/${ipv4}" >"/etc/dnsmasq.d/wildcard-${host}.conf"
    ;;
  del)
    rm "/etc/dnsmasq.d/wildcard-${name}.conf"
    ;;
esac
systemctl restart "dnsmasq"
