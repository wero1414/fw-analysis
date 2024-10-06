#!/bin/sh
#*****************************************************************
#
#		         qdisc_control.sh
#
#		Copyright 2016 Rivet Networks LLC
#
#****************************************************************

#ARGS:
# $1 = interface name (lan or wan)
# $2 = optional state (on or off)

. /usr/share/libubox/jshn.sh
. /lib/functions.sh

trap "lock -u /tmp/krouter.qos.lock" 0
trap "exit 1" SIGTERM SIGHUP

lock /tmp/krouter.qos.lock

err_exit() {
	echo "Invalid device specificed, specified. Use wan or lan"
	exit 1
}

dev=$1
[ "$dev" != "lan" -a "$dev" != "wan" ] && err_exit;

STATUS=$(ubus call network.interface.$dev status)
json_load "$STATUS"
json_get_var DEVICE l3_device

config_load krouter
config_get_bool enabled "krouter" enabled 1

tc qdisc del dev $DEVICE root
[ 1 -eq "$enabled" ] || return 0

STATE=ON
[ -n "$2" ] && STATE=$2

case $dev in
lan)
	BW=$(config_get krouter download)
	;;
wan)
	BW=$(config_get krouter upload)
	;;
*)
	err_exit
esac

ROOT_MAJOR=1
ROOT_MINOR=1
PRIO_ROOT=100
PRIO1=10
PRIO2=20
PRIO3=30
PRIO4=40
PRIO5=50
PRIO6=60

case $STATE in
on|ON)
	tc qdisc del dev $DEVICE root
	tc qdisc add dev $DEVICE root handle ${ROOT_MAJOR}: prio bands 3 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	tc qdisc add dev $DEVICE parent ${ROOT_MAJOR}:2 handle ${PRIO_ROOT}:1 htb default ${PRIO4}
	tc class add dev $DEVICE parent ${PRIO_ROOT}: classid ${PRIO_ROOT}:1 htb rate $BW
	tc class add dev $DEVICE parent ${PRIO_ROOT}:1 classid ${PRIO_ROOT}:${PRIO1} htb rate 128kbit ceil $BW prio 1
	tc class add dev $DEVICE parent ${PRIO_ROOT}:1 classid ${PRIO_ROOT}:${PRIO2} htb rate 128kbit ceil $BW prio 2
	tc class add dev $DEVICE parent ${PRIO_ROOT}:1 classid ${PRIO_ROOT}:${PRIO3} htb rate 128kbit ceil $BW prio 3
	tc class add dev $DEVICE parent ${PRIO_ROOT}:1 classid ${PRIO_ROOT}:${PRIO4} htb rate 128kbit ceil $BW prio 4
	tc class add dev $DEVICE parent ${PRIO_ROOT}:1 classid ${PRIO_ROOT}:${PRIO5} htb rate 128kbit ceil $BW prio 5
	tc class add dev $DEVICE parent ${PRIO_ROOT}:1 classid ${PRIO_ROOT}:${PRIO6} htb rate 128kbit ceil $BW prio 6
	tc qdisc add dev $DEVICE parent ${PRIO_ROOT}:${PRIO1} fq_codel
	tc qdisc add dev $DEVICE parent ${PRIO_ROOT}:${PRIO2} fq_codel
	tc qdisc add dev $DEVICE parent ${PRIO_ROOT}:${PRIO3} fq_codel
	tc qdisc add dev $DEVICE parent ${PRIO_ROOT}:${PRIO4} fq_codel
	tc qdisc add dev $DEVICE parent ${PRIO_ROOT}:${PRIO5} fq_codel
	tc qdisc add dev $DEVICE parent ${PRIO_ROOT}:${PRIO6} fq_codel
	tc filter add dev $DEVICE protocol ip parent ${PRIO_ROOT}:0 prio 1 handle 0x10010 fw flowid ${PRIO_ROOT}:${PRIO1}
	tc filter add dev $DEVICE protocol ip parent ${PRIO_ROOT}:0 prio 1 handle 0x10020 fw flowid ${PRIO_ROOT}:${PRIO2}
	tc filter add dev $DEVICE protocol ip parent ${PRIO_ROOT}:0 prio 1 handle 0x10030 fw flowid ${PRIO_ROOT}:${PRIO3}
	tc filter add dev $DEVICE protocol ip parent ${PRIO_ROOT}:0 prio 1 handle 0x10050 fw flowid ${PRIO_ROOT}:${PRIO5}
	tc filter add dev $DEVICE protocol ip parent ${PRIO_ROOT}:0 prio 1 handle 0x10060 fw flowid ${PRIO_ROOT}:${PRIO6}
	tc filter add dev $DEVICE protocol ip parent ${ROOT_MAJOR}:0 prio 1 handle 0x10099 fw flowid ${ROOT_MAJOR}:1
	;;
off|OFF)
	echo "Turning off qdisc not implmented yet"
	exit 1
	;;
*)
	echo "Invalid state selected"
	exit 1
	;;
esac

