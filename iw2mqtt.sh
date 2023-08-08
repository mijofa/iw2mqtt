#!/bin/ash

HOSTNAME="$(uci get system.@system[0].hostname)"

# FIXME: This should be unique to each AP
AVAIL_TOPIC="mijofa-iw2mqtt/availability/$HOSTNAME"
STATE_TOPIC="mijofa-iw2mqtt/state/$HOSTNAME"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-1m}"
# FIXME: Grab LOCATION & MQTT_USER/PW/HOST from config as well

# use payload_reset if location is set, otherwise payload_home
home_or_reset="${LOCATION:+reset}"
home_or_reset="${home_or_reset:-home}"

# FIXME: This should somehow include other AP's unique availability topics
# FIXME: source_type should be 'router' not 'gps', but routers don't seem to be able to specify any zone other than "home"
# FIXME: The configuration_url should be something like a Luci URL, not the upstream source/documentation
discovery_template='{"device":{
                         "configuration_url":"https://github.com/mijofa/iw2mqtt",
                         "manufacturer":"mijofa",
                         "model":"iw2mqtt",
                         "name":"OpenWRT WiFi Devices",
                         "identifiers":["mijofa-iw2mqtt"]
                    },
                    "source_type":"gps",
                    "icon":"mdi:router-wireless",
                    "availability":[{"topic":"'"$AVAIL_TOPIC"'",
                                     "value_template":"{{ True if (value_json is not boolean) else value_json }}",
                                     "payload_available":true,
                                     "payload_not_available":false
                    }],

                    "state_topic":"'"$STATE_TOPIC"'",
                    "value_template":"{{ \"#MAC#\" in value_json.connected_devices + value_json.previous_devices }}",
                    "payload_'"$home_or_reset"'":true,
                    "payload_not_home":false,

                    "json_attributes_topic":"'"$AVAIL_TOPIC"'",

                    "unique_id":"mijofa-iw2mqtt.#ID#",
                    "object_id":"mijofa-iw2mqtt.#ID#",
                    "name":"#MAC#"}'

if [[ "$1" != "--verbose" ]] ; then
    LOG_MQTT="no"
fi

mqtt_pub() {
    topic=$1
    shift
    message=$1
    shift
    # Would be nice to use '%q' here, but BusyBox/OpenWRT's printf doesn't support that
    test "$LOG_MQTT" == "no" || printf '%s: mqtt_pub(%s): %s\n' "$(date -Iseconds)" "$topic" "$message" >&2
    # test "$LOG_MQTT" == "no" || echo "$message" | sed "s|^|$(date -Iseconds) mqtt_pub($topic) |" >&2

    mosquitto_pub --username $MQTT_USER --pw $MQTT_PW --host $MQTT_HOST --topic "$topic" --message "$message" "$@"
}

# Get currently connected MACs.
list_connected_MACs() {
    for nic in $(iw dev | sed --quiet '/^\s\+Interface\s/ s///p') ; do
        iw dev $nic station dump
    done | sed --quiet '/^Station\s\([[:xdigit:]:]\+\)\(\s(.*)\)\?$/ s//\1/p'
}

# Update the discovery topic so that HA knows to monitor this device
# FIXME: This really should only be done once per device, not every single time there's a change
configure_discovery_for_mac() {
    discovery_topic="homeassistant/device_tracker/mijofa-iw2mqtt/${1//:/-}/config"
    device_id=${1//:/-}
    state_topic="mijofa-iw2mqtt/tracker/$device_id"
    # FIXME: Use a json parser: https://openwrt.org/docs/guide-developer/jshn
    discovery_data=${discovery_template//#STATE_TOPIC#/$state_topic}
    discovery_data=${discovery_data//#MAC#/$1}
    discovery_data=${discovery_data//#ID#/$device_id}
    # FIXME: Should this have --retain?
    mqtt_pub "$discovery_topic" "$discovery_data"
}

update_connections() {
    # We keep the previous list around for some delayed device expiry for intermittent WiFi outages.
    # This is implemented by having the value_template simply check both lists
    previous_devices_list="${connected_devices_list:-[]}"
    connected_devices_list="$(list_connected_MACs | sed 's/^/ "/;1s/^ /[/;s/$/",/;$s/,$/]/')"
    mqtt_pub "$STATE_TOPIC" "{\"last_update\":$(date +'%s'),
                              \"connected_devices\":$connected_devices_list,
                              \"previous_devices\":$previous_devices_list}"
}

new_connection() {
    configure_discovery_for_mac "$1"

    # We don't want to update the expiry of old previous connections when a single new connections arrives.
    # So just resend the old data, with this 1 MAC address appended,
    # since we also don't care if there's duplicate entries in the list.
    connected_devices_list="${connected_devices_list%]},\"$1\"]"
    mqtt_pub "$STATE_TOPIC" "{\"last_update\":$(date +'%s'),
                              \"connected_devices\":$connected_devices_list,
                              \"previous_devices\":$previous_devices_list}"
}

# Set up the mqtt "last will and testament".
# This way when the script exits (cleanly or not) it tells HA that the entities are unavailable,
# rather than letting it continue to trust the outdated info.
# FIXME: Why OpenWRT doesn't have '/dev/fd' by default? OpenWRT's ash requires it for this?
test -L /dev/fd || ln -s /proc/self/fd /dev/fd
exec 3> >(exec mosquitto_pub --username $MQTT_USER --pw $MQTT_PW --host $MQTT_HOST --will-topic "$AVAIL_TOPIC" --will-payload "false" --will-retain --topic "$AVAIL_TOPIC" --stdin-line --retain)

# Pre-load the currently connected devices before we start listening for new devices
list_connected_MACs | while read mac ; do
    configure_discovery_for_mac "$mac"
done
update_connections

# Tell HA that the current MQTT data is valid, and it can mark the entities as available now.
echo "${LOCATION:-true}" >&3

{
    # FIXME: The only reason for this interval is so that we can update disconnects only a minute later.
    #        Should we just run the 'update_connections' function in it's own background loop?
    while sleep $UPDATE_INTERVAL ; do
        printf '[%s]: n/a: ping station ALL\n' "$(date +'%Y-%m-%d %T.000000')"
    done &

    iw event -T
} | while read date time nic event station mac ; do
    # Ignore the "unknown event" lines we get from `iw event`
    [[ "$station" == "station" ]] || continue

    # Ignore disconnect events, because it might be a transient outage, so just let them expire out instead
    [[ "$event" == "del" ]] && continue

    # Update active connections with new connections and every interval
    [[ "$event" == "ping" ]] && update_connections

    # Update new connections immediately instead of waiting for the ping
    [[ "$event" == "new" ]] && new_connection "$mac"
done
