#!/bin/ash

# Get currently connected MACs.
# Use this to initialise the current state of things immediately before we start watching for changes.
# NOTE: ash does not support arrays
# FIXME: Can we check this **after** we start watching for changes?
wifi_clients="$(for nic in $(iw dev | sed --quiet '/^\s\+Interface\s/ s///p') ; do
                    iw dev $nic station dump
                done | sed --quiet '/^Station\s\([[:xdigit:]:]\+\)\(\s(.*)\)\?$/ s//\1/p')"

# Is Muir (Mike's phone) in the list of connected clients
echo "$wifi_clients" | grep -qFx '2a:e0:9b:0d:0e:1e'
# Is Gaby's phone in list of connected clients
# FIXME: Is this Gaby's MAC?
echo "$wifi_clients" | grep -qFx '5e:0c:a4:36:ae:81'


# Muir's discovery info example
# NOTE: By ensuring all "device" dicts are identical, we can have all the entities grouped in the same device
# NOTE: I don't really like that I'm using the "NFC" icon, but the "wireless" one looks shit.
#       'mdi:router-wireless' is probably a decent default if not doing unique icons for each device.
#       I'm using 'mdi:cellphone-message' for Gaby
# ref: https://www.home-assistant.io/integrations/device_tracker.mqtt/#using-the-discovery-protocol
# topic: homeassistant/device_tracker/mijofa-iw2mqtt/2a-e0-9b-0d-0e-1e/config
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
#   "state_topic": "mijofa-iw2mqtt/tracker/2a-e0-9b-0d-0e-1e",
#   "unique_id": "mijofa-iw2mqtt.2a-e0-9b-0d-0e-1e",
#   "object_id": "mijofa-iw2mqtt.2a-e0-9b-0d-0e-1e",
#   "name": "2a:e0:9b:0d:0e:1e"
# }
# And for Gaby's
# topic: homeassistant/device_tracker/mijofa-iw2mqtt/5e-0c-a4-36-ae-81/config
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
#   "state_topic": "mijofa-iw2mqtt/5e-0c-a4-36-ae-81",
#   "unique_id": "mijofa-iw2mqtt.5e-0c-a4-36-ae-81",
#   "object_id": "mijofa-iw2mqtt.5e-0c-a4-36-ae-81",
#   "name": "5e:0c:a4:36:ae:81"
# }
