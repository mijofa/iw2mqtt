#!/bin/ash

# FIXME: This should be unique to each AP
AVAILABILITY_TOPIC="mijofa-iw2mqtt/availability/mike.abrahall.id.au"
STATE_TOPIC="mijofa-iw2mqtt/state/mike.abrahall.id.au"
# FIXME: This should be configurable
ZONE_NAME=${ZONE_NAME:-home}
# FIXME: Grab MQTT_USER/PW/HOST from config as well

# FIXME: This should somehow include other AP's unique availability topics
discovery_template='{"device":{
                         "configuration_url":"https://github.com/mijofa/iw2mqtt",
                         "manufacturer":"mijofa",
                         "model":"iw2mqtt",
                         "name":"OpenWRT WiFi Devices",
                         "identifiers":["mijofa-iw2mqtt"]
                    },
                    "source_type":"#SOURCETYPE#",
                    "icon":"mdi:router-wireless",
                    "availability":[{"topic":"'"$AVAILABILITY_TOPIC"'"}],

                    "state_topic":"'"$STATE_TOPIC"'",
                    "value_template":"{{\"#MAC#\" in value_json.connected_devices or \"#MAC#\" in value_json.previous_devices}}",
                    "value_home":true,
                    "value_not_home":false,
                    "unique_id":"mijofa-iw2mqtt.#ID#",
                    "object_id":"mijofa-iw2mqtt.#ID#",
                    "name":"#MAC#"}'
# FIXME: source_type should be 'router' not 'gps', but routers don't seem to be able to specify any zone other than "home"
if [[ "$ZONE_NAME" == "home" ]] ; then
    discovery_template=${discovery_template/#SOURCETYPE#/router}
else
    echo "ERROR: Sorry, non 'home' zone names are not currently supported."
    exit 2
    discovery_template=${discovery_template/#SOURCETYPE#/gps}
fi

if [[ "$1" != "--verbose" ]] ; then
    VERBOSE="no"
fi
maybe_log() {
    test "$VERBOSE" == "no" || printf '%s\n' "$@" >&2
}

mqtt_pub() {
    topic=$1
    shift
    message=$1
    shift
    maybe_log "MQTT: $topic \"$message\""

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
    # We keep the previous list around so that HA can do some delayed device expiry for intermittent WiFi outages
    previous_devices_list="${connected_devices_list:-[]}"
    connected_devices_list="$(list_connected_MACs | sed 's/^/ "/;1s/^ /[/;s/$/",/;$s/,$/]/')"
    mqtt_pub "$STATE_TOPIC" "{\"last_update\":$(date +'%s'),
                              \"connected_devices\":$connected_devices_list,
                              \"previous_devices\":$previous_devices_list}"
}

# Set up the mqtt "last will and testament".
# This way when the script exits (cleanly or not) it tells HA that the entities are unavailable,
# rather than letting it continue to trust the outdated info.
# FIXME: Why OpenWRT doesn't have '/dev/fd' by default? OpenWRT's ash requires it for this?
test -L /dev/fd || ln -s /proc/self/fd /dev/fd
exec 3> >(exec mosquitto_pub --username $MQTT_USER --pw $MQTT_PW --host $MQTT_HOST --will-topic "$AVAILABILITY_TOPIC" --will-payload "offline" --topic "$AVAILABILITY_TOPIC" --stdin-line)
echo >&3 "online"

list_connected_MACs | while read mac ; do
    configure_discovery_for_mac "$mac"
done
configure_discovery_for_mac "5e:0c:a4:36:ae:81"
update_connections

{
    # FIXME: The only reason for this interval is so that we can update disconnects only a minute later.
    #        How can we do this better?
    while sleep 6 ; do
        printf '[%s]: n/a: ping station ALL\n' "$(date +'%Y-%m-%d %T.000000')"
    done &

    iw event -T
} | while read date time nic event station mac ; do
    echo >&3 "online"

    # Ignore the "unknown event" lines we get from `iw event`
    [[ "$station" == "station" ]] || continue

    # Do discovery for new connections (not disconnects)
    [[ "$event" == "new" ]] && configure_discovery_for_mac "$mac"

    # Update active connections with new connections and every interval
    update_connections
done

# Discovery info example/template
# NOTE: By ensuring all "device" dicts are identical, we can have all the entities grouped in the same device
# ref: https://www.home-assistant.io/integrations/device_tracker.mqtt/#using-the-discovery-protocol
# topic: homeassistant/device_tracker/mijofa-iw2mqtt/#ID#/config
# { "device": {
#     "configuration_url": "https://github.com/mijofa/iw2mqtt",
#     "manufacturer": "mijofa",
#     "model": "iw2mqtt",
#     "name": "OpenWRT WiFi Devices",
#     "identifiers": ["mijofa-iw2mqtt"]
#     # FIXME: This would need to be identical for all trackers in order to combine them properly.
#     #        Is this even supposed to have these MACs?
#     # "connections": [
#     #     ["mac", "2a:e0:9b:0d:0e:1e"],
#     #     ["mac", "5e:0c:a4:36:ae:81"]
#     # ],
#   },
#   "source_type": "router",
#   "icon": "mdi:router-wireless",
#   "availability": [
#     # This is unique to each AP so we can set a will-topic & will-payload properly.
#     # However every AP needs to know about each other for this to work properly.
#     {"topic": "mijofa-iw2mqtt/availability/mike.abrahall.id.au"}
#   ],
#   # Entity specific
#   "state_topic": "mijofa-iw2mqtt/tracker/#ID#",
#   "unique_id": "mijofa-iw2mqtt.#ID#",
#   "object_id": "mijofa-iw2mqtt.#ID#",
#   "name": "#MAC#"
# }
