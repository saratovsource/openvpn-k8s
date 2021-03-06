#!/bin/bash

if [ "$DEBUG" == "1" ]; then
  set -x
fi

set -e

OVPN_NETWORK="${OVPN_NETWORK:-10.140.0.0}"
OVPN_SUBNET="${OVPN_SUBNET:-255.255.0.0}"
OVPN_PROTO="${OVPN_PROTO:-udp}"
OVPN_NATDEVICE="${OVPN_NATDEVICE:-eth0}"
#OVPN_K8S_ROUTES
OVPN_K8S_DOMAIN="${OVPN_KUBE_DOMAIN:-cluster.local}"
#OVPN_K8S_DNS
OVPN_DH="${OVPN_DH:-/etc/openvpn/pki/dh.pem}"
OVPN_CERTS="${OVPN_CERTS:-/etc/openvpn/pki/certs.p12}"
OVPN_MULTIPLE_CERTS="${OVPN_MULTIPLE_CERTS:-}"

sed 's|{{OVPN_NETWORK}}|'"${OVPN_NETWORK}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_SUBNET}}|'"${OVPN_SUBNET}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_PROTO}}|'"${OVPN_PROTO}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_DH}}|'"${OVPN_DH}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_CERTS}}|'"${OVPN_CERTS}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_K8S_SERVICE_NETWORK}}|'"${OVPN_K8S_SERVICE_NETWORK}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_K8S_SERVICE_SUBNET}}|'"${OVPN_K8S_SERVICE_SUBNET}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_K8S_DOMAIN}}|'"${OVPN_K8S_DOMAIN}"'|' -i "${OVPN_CONFIG}"
sed 's|{{OVPN_K8S_DNS}}|'"${OVPN_K8S_DNS}"'|' -i "${OVPN_CONFIG}"

if [ "${OVPN_MULTIPLE_CERTS}" ]; then
    echo "duplicate-cn" >> "${OVPN_CONFIG}"
fi

if [ "${OVPN_K8S_ROUTES}" ]; then
    sed 's%,%\n%g' <<< "${OVPN_K8S_ROUTES}" | sort | while read ROUTE; do
        IFS="/:" read SUBNET CIDR PORT PROTO <<< "${ROUTE}"
        NETMASK=$(ipcalc -m ${SUBNET}/${CIDR} | cut -d'=' -f2)

        if [ "${SUBNET}/${CIDR}" != "$PREV_ROUTE" ]; then
            echo "push \"route ${SUBNET} ${NETMASK}\"" >> "${OVPN_CONFIG}"
        fi

        if [ "${PORT}" ]; then
            PROTO="${PROTO:-tcp}"
            iptables -t nat -A POSTROUTING -s ${OVPN_NETWORK}/${OVPN_SUBNET} -d ${SUBNET}/${CIDR} -o ${OVPN_NATDEVICE} -p ${PROTO} --dport ${PORT} -j MASQUERADE
        else
            iptables -t nat -A POSTROUTING -s ${OVPN_NETWORK}/${OVPN_SUBNET} -d ${SUBNET}/${CIDR} -o ${OVPN_NATDEVICE} -j MASQUERADE
        fi
        PREV_ROUTE="${SUBNET}/${CIDR}"
    done
fi

if [ "${OVPN_K8S_DNS}" ]; then
    echo "push \"dhcp-option DOMAIN ${OVPN_K8S_DOMAIN}\"" >> "${OVPN_CONFIG}"
    echo "push \"dhcp-option DNS ${OVPN_K8S_DNS}\"" >> "${OVPN_CONFIG}"
fi

chown nobody:nobody "${OVPN_CERTS}" "${OVPN_DH}"
chmod 400 "${OVPN_CERTS}" "${OVPN_DH}"

mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

exec openvpn --config ${OVPN_CONFIG}
