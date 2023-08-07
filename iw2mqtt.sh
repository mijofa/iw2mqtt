#!/bin/ash

# FIXME: This should be unique to each AP
AVAILABILITY_TOPIC="mijofa-iw2mqtt/availability/mike.abrahall.id.au"
# FIXME: This should be configurable
ZONE_NAME=${ZONE_NAME:-home}
# FIXME: Grab MQTT_USER/PW/HOST from config as well

# FIXME: This should somehow include other AP's unique availability topics
discovery_template='{"device":{"configuration_url":"https://github.com/mijofa/iw2mqtt","manufacturer":"mijofa","model":"iw2mqtt","name":"OpenWRT WiFi Devices","identifiers":["mijofa-iw2mqtt"]},"source_type":"#SOURCETYPE#","icon":"mdi:router-wireless","availability":[{"topic":"'"$AVAILABILITY_TOPIC"'"}],"state_topic":"#STATE_TOPIC#","unique_id":"mijofa-iw2mqtt.#ID#","object_id":"mijofa-iw2mqtt.#ID#","name":"#MAC#"}'
# FIXME: source_type should be 'router' not 'gps', but routers don't seem to be able to specify any zone other than "home"
if [[ "$ZONE_NAME" == "home" ]] ; then
    discovery_template=${discovery_template/#SOURCETYPE#/rorouterr}
else
    discovery_template=${discovery_template/#SOURCETYPE#/gps}
fi

# Get currently connected MACs.
list_connected_MACs() {
    for nic in $(iw dev | sed --quiet '/^\s\+Interface\s/ s///p') ; do
        iw dev $nic station dump
    done | sed --quiet '/^Station\s\([[:xdigit:]:]\+\)\(\s(.*)\)\?$/ s//\1/p'
}

# Set up the mqtt "last will and testament".
# This way when the script exits (cleanly or not) it tells HA that the entities are unavailable,
# rather than letting it continue to trust the outdated info.
# FIXME: OpenWRT doesn't have '/dev/fd' by default? OpenWRT's ash requires it for this?
test -L /dev/fd || ln -s /proc/self/fd /dev/fd
exec 3> >(exec mosquitto_pub --username $MQTT_USER --pw $MQTT_PW --host $MQTT_HOST --will-topic "$AVAILABILITY_TOPIC" --will-payload "offline" --topic "$AVAILABILITY_TOPIC" --stdin-line)
echo >&3 "online"

{
    # FIXME: Can we check this **after** we start watching for changes?
    start_time="$(date +'%Y-%m-%d %T.000000')"  # Intentionally matches the date format of `iw event -T`
    list_connected_MACs| while read mac ; do
        echo "[$start_time]: $nic: new station $mac"
    done

    # Monitor connection changes
#    iw_regexp="^\[([[:digit:]-]{10} [[:digit:]:.]{15})\]: ([[:alnum:]]+): (new|del) station ([[:xdigit:]:]{17})$"
#    iw event -T | tee /dev/stderr | sed --quiet --regexp-extended "/$iw_regexp/{s//\3 \4 \1/;p}p" | tee /dev/stderr
    iw event -T
} | while read date time nic event station mac ; do
    date=${date#[}
    time=${time%]:}
    # Consider this a hearbeat
    echo "online" >&3

    # Ignore the "unknown event" lines we get from `iw event`
    # NOTE: neither grep or sed support unbuffered output in busybox
    test "$station" == "station" || continue

    state_topic="mijofa-iw2mqtt/tracker/${mac//:/-}"

    discovery_topic="homeassistant/device_tracker/mijofa-iw2mqtt/${mac//:/-}/config"
    # FIXME: Use a json parser: https://openwrt.org/docs/guide-developer/jshn
    discovery_data=${discovery_template//#STATE_TOPIC#/$state_topic}
    discovery_data=${discovery_data//#MAC#/$mac}
    discovery_data=${discovery_data//#ID#/${mac//:/-}}
    # FIXME: Should this have --retain?
    mosquitto_pub --username $MQTT_USER --pw $MQTT_PW --host $MQTT_HOST --topic "$discovery_topic" --message "$discovery_data"

    if [ "$event" = "del" ] ; then
        # There seems to be some cases where a "del" event goes while the device is still connected.
        # I'm not sure what's going on, but I suspect this is when things try to connect to both 5ghz & 2.4ghz at the same time,
        # then disconnect 2.4ghz once the 5ghz succeeds
        if list_connected_MACs | grep -qFx "$mac" ; then
            continue
        else
            state="not_home"
        fi
    else
        state="$ZONE_NAME"
    fi
    echo "${date}T${time} $mac $state"
    mosquitto_pub --username $MQTT_USER --pw $MQTT_PW --host $MQTT_HOST --topic "$state_topic" --message "$state" --retain
    # FIXME: Use json_attributes topic and set some things like "connection time" and maybe even GPS co-ords

    # We need to send this **after** HA notices the discovery config and starts listening.
    # FIXME: This is still generally too early
    echo "online" >&3
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
