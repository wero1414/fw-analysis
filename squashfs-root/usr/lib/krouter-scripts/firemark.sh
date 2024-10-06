#!/bin/sh
#****************************************************************
#
#		         firemark.sh
#
#		Copyright 2016 Rivet Networks LLC
#
#****************************************************************

. /usr/share/libubox/jshn.sh
. /lib/functions.sh

trap "lock -u /tmp/krouter.fm.lock" 0
trap "exit 1" SIGTERM SIGHUP

lock /tmp/krouter.fm.lock

uci set firewall.krouter=include
uci set firewall.krouter.path=/usr/lib/krouter-scripts/firemark.sh

iptables -N krouter-chain-local -t mangle
iptables -D OUTPUT -t mangle -j krouter-chain-local
iptables -A OUTPUT -t mangle -j krouter-chain-local
iptables -F krouter-chain-local -t mangle
iptables -A krouter-chain-local -t mangle --j MARK --set-mark 0x10099

iptables -N krouter-chain -t mangle
iptables -D FORWARD -t mangle -j krouter-chain
iptables -A FORWARD -t mangle -j krouter-chain
iptables -F krouter-chain -t mangle

config_load krouter

config_get_bool enabled "krouter" enabled 1
[ 1 -eq "$enabled" ] || return 0

config_get_bool debug "krouter" debug 0
[ 1 -eq "$debug" ] && logger -t krouter "prio debugging enabled"


LAN_STATUS=$(ubus call network.interface.lan status)
json_load "$LAN_STATUS"
json_get_var LAN_DEVICE l3_device

# configure DHCP clients for high priority
# iterate over DHCP leases
compare_and_add() {
	local maccmp=${1%;*}
	local prio=${1#*;}

	# if it's a fully formed MAC add it regardless of DHCP
	[ $(echo $maccmp | wc -c) = "18" ] && {
		logger -t krouter "found macprio entry for $maccmp (static)"
		iptables -A krouter-chain -t mangle -i ${LAN_DEVICE} -m mac --mac-source ${maccmp} --j MARK --set-mark 0x100${prio}0

		return
	}

	[ -e /var/dhcp.leases ] && {
		while read -r expires macaddr ipaddr hostname; do
			echo $macaddr | grep -q -i ^$maccmp && {
				logger -t krouter "found macprio entry for $macaddr"
				iptables -A krouter-chain -t mangle -i ${LAN_DEVICE} -m mac --mac-source ${macaddr} --j MARK --set-mark 0x100${prio}0
			}
		done < /var/dhcp.leases
	}
}

compare_and_add_prio3 () {
	logger -t krouter "add prio 3 for killer endpoint"
	compare_and_add "$1;3"
}

iptables -A krouter-chain -t mangle -j CONNMARK --restore-mark
# If this is uncommented, we will skip already-marked connections.  If connections can
# change marks over time, don't enable this optimization.
#iptables -A krouter-chain -t mangle -m mark ! --mark 0 -j ACCEPT

# mark packets for prioritization

add_prio_level () {
	local dscp=$1
	local prio=$2

	[ 1 -eq "$debug" ] && {
		iptables -N krouter-chain-log-p${prio} -t mangle
		iptables -F krouter-chain-log-p${prio} -t mangle

		iptables -A krouter-chain -t mangle -i ${LAN_DEVICE} -m dscp --dscp $dscp --j krouter-chain-log-p${prio}
		iptables -A krouter-chain-log-p${prio} -t mangle -i ${LAN_DEVICE} -m mark ! --mark 0x100${prio}0 -j LOG --log-prefix "krouter new prio: " --log-level 6
	}

	iptables -A krouter-chain -t mangle -i ${LAN_DEVICE} -m dscp --dscp $dscp --j MARK --set-mark 0x100${prio}0
}

# mark 4 first so it's always overridden if something else applies
add_prio_level 0x00 4

# mark macprio based prio
config_list_foreach krouter macprio compare_and_add

# mark endpoints as prio 3 (default prio)
config_list_foreach krouter endpoints compare_and_add_prio3

# finally, switch to any other prios we have set which will override the macprio
add_prio_level 0x0e 6
add_prio_level 0x08 5
add_prio_level 0x26 3
add_prio_level 0x20 2
add_prio_level 0x2e 1

iptables -A krouter-chain -t mangle -i ${LAN_DEVICE} -j CONNMARK --save-mark

