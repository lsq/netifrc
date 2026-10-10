# Original copyright (c) 2007-2009 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

iwd_depend()
{
	after macnet plug
	before interface
	provide wireless
	after iwconfig
	program /usr/libexec/iwd
}

_config_vars="$_config_vars iwd"

iwd_pre_start()
{
	local iwds=/usr/libexec/iwd
	local args= opt= opts=
	eval opts=\$iwd_${IFVAR}

	#set a "safe" default in case phy was not defined
	PHY="phy0"

	for opt in ${opts}; do
		case "${opt}" in
			phy* )	PHY="${opt}"
				einfo "Assigned PHY to be ${PHY}"
				;;
			*    )	;;
		esac
	done

    # --- Diagnostic block 1: does the PHY exist at all? ---
    # https://deepwiki.com/search/-bringing-up-interface-wlan0-c_5648193d-e04e-4ea9-a99a-946bf6548bd7
	if [ ! -d "/sys/class/ieee80211/${PHY}" ]; then
		if [ -d /sys/class/ieee80211 ] && [ -n "$(ls -A /sys/class/ieee80211 2>/dev/null)" ]; then
			ewarn "PHY '${PHY}' not found in /sys/class/ieee80211/"
			ewarn "Available PHYs: $(ls /sys/class/ieee80211 2>/dev/null | tr '\n' ' ')"
			ewarn "Check iwd_${IFVAR} setting - it may be pointing at the wrong phy"
		else
			ewarn "No wireless PHY detected in /sys/class/ieee80211/ at all"
			ewarn "The wireless driver kernel module is probably not loaded (check 'lsmod' / 'dmesg')"
		fi
	else
		# PHY exists - try to show which driver/device it's bound to
		if [ -e "/sys/class/ieee80211/${PHY}/device/driver" ]; then
			veinfo "PHY ${PHY} is bound to driver: $(basename "$(readlink -f "/sys/class/ieee80211/${PHY}/device/driver")")"
		fi
	fi

	# --- Diagnostic block 2: has an interface for this PHY already been
	# claimed/renamed (e.g. by udev/.link rules) under a different name? ---
	if [ -d "/sys/class/ieee80211/${PHY}/device/net" ]; then
		local existing_if=
		for existing_if in "/sys/class/ieee80211/${PHY}/device/net"/*; do
			[ -e "${existing_if}" ] || continue
			existing_if=$(basename "${existing_if}")
			if [ "${existing_if}" != "${IFVAR}" ]; then
				ewarn "PHY ${PHY} already has interface '${existing_if}' instead of expected '${IFVAR}'"
				ewarn "This interface may have been renamed by udev/.link rules"
			fi
		done
	fi
	
	if [ -d "/sys/class/net/${IFACE}" ]; then
		einfo "${IFACE} exists in sysfs"
	else
		ewarn "${IFACE} does NOT exist in sysfs yet"
	fi

	if command -v iw >/dev/null 2>&1; then
		einfo "iw dev output:"
		iw dev | while IFS= read -r line; do einfo "  $line"; done
	fi

	ip link show "${IFACE}" >/dev/null 2>&1 \
		&& einfo "ip link: ${IFACE} present" \
		|| ewarn "ip link: ${IFACE} missing"

	ebegin "Starting iwd on ${PHY} and ${IFVAR}"
	pidfile="/run/iwd-${IFVAR}.pid"
	# https://deepwiki.com/search/78110d33-e512-41ea-9ac7-cc78afc3b768
	# fixed
	start-stop-daemon --start --exec "${iwds}" --pidfile "${pidfile}" --background --make-pidfile --stdout /var/log/iwd.log --stderr /var/log/iwd.log -- -p ${PHY} -i "${IFVAR}" -d
	# start-stop-daemon --start --exec "${iwds}" --pidfile "${pidfile}" --background --make-pidfile --stdout /var/log/iwd.log --stderr /var/log/iwd.log -- -p ${PHY} -i "${IFVAR}"
	# -i参数有可能出现bug
	# 传了 -i wlan0，所以 iwd 不会自己创建接口，而是要求启动那一刻 phy0 上已经存在名为 wlan0 的 nl80211 接口
	# https://deepwiki.com/search/78110d33-e512-41ea-9ac7-cc78afc3b768
	# start-stop-daemon --start --exec "${iwds}" --pidfile "${pidfile}" --background --make-pidfile --stdout /var/log/iwd.log --stderr /var/log/iwd.log -- -p ${PHY} -d
	local ret=$?

	# --- Diagnostic block 3: did iwd actually start, or exit immediately? ---
	if [ ${ret} -eq 0 ]; then
		sleep 1
		if [ -f "${pidfile}" ]; then
			local iwd_pid="$(cat "${pidfile}" 2>/dev/null)"
			einfo "iwd_pid: ${iwd_pid}."
			if [ -n "${iwd_pid}" ] && ! kill -0 "${iwd_pid}" 2>/dev/null; then
				eerror "iwd was started but the process (pid ${iwd_pid}) is no longer running"
				eerror "Check iwd's own logs (journalctl -u iwd, or syslog) for why it exited"
				eerror "Common causes: D-Bus not running, rfkill blocking the radio, phy already in use"
				ret=1
			fi
		else
			eerror "iwd pidfile ${pidfile} was not created - iwd may have failed to start"
			ret=1
		fi
	fi

	return ${ret}
	# return $?
}


iwd_post_stop()
{
	local iwds=/usr/libexec/iwd
	pidfile="/run/iwd-${IFVAR}.pid"
	if [ -f ${pidfile} ]; then
		ebegin "Stopping iwd on ${IFACE}"
		start-stop-daemon --stop --exec "${iwds}" --pidfile "${pidfile}"
		eend $?
	fi

	# If iwd exits uncleanly, we need to remove the stale dir
	[ -S "/run/iwd/${IFACE}" ] \
		&& rm -f "/run/iwd/${IFACE}"
}

