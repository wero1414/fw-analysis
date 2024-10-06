#!/bin/sh
#****************************************************************
#
#		         dhcp-hook.sh
#
#		Copyright 2017 Rivet Networks LLC
#
#****************************************************************

add_macprio () {
	local macaddr=$1

	uci -q add_list "krouter.krouter.macprio=$macaddr;2"
	uci -q add_list "krouter.krouter.xbox_macaddr=$macaddr"
	logger -t krouter "adding ${macaddr} as an xbox"
}

# called from DNS hook, let's scan the IPs for xbox
[ "$(uci -q get krouter.krouter.xbox_detection)" = "1" -a -n "$DNSMASQ_LEASE_EXPIRES" ] && {
	while read -r expires macaddr ipaddr hostname; do
		if [ "$DNSMASQ_LEASE_EXPIRES" = "$expires" ]; then
			# scan to see if we already are present
			present="false"
			for elem in $(uci -q get krouter.krouter.macprio); do
				if echo $elem | grep -qi $macaddr; then
					present="true"
					break
				fi
			done
			# if an xbox has already been seen/detected don't re-prio it
			for elem in $(uci -q get krouter.krouter.xbox_macaddr); do
				if echo $elem | grep -qi $macaddr; then
					present="true"
					break
				fi
			done

			# not present so add at default prio
			if [ "$present" = "false" ]; then
				if echo $hostname | grep -qi xbox; then
					add_macprio $macaddr
					continue
				fi

				sleep 5
				if ! kdetect $ipaddr 2>&1 | grep -q Unknown; then
					add_macprio $macaddr
					continue
				fi
			fi
		fi
	done < /var/dhcp.leases
}

reload_config
