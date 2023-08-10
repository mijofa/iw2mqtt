iw2mqtt
=======
Use OpenWRT's wireless connection state as MQTT device trackers
ref: https://www.home-assistant.io/integrations/device_tracker.mqtt/

The intended purpose is to have this running on the OpenWRT AP (doesn't need to
be OpenWRT, so long as it has ``iw event`` and ``mosquitto_pub``) sending
updates to Home Assistant via MQTT.

Building
========
Generally you shouldn't need to do this yourself since I'll try to to keep packages in the GitHub releases up-to-date.

Since .ipks are pretty similar to .debs, I've used the frameworks I already have in place and am familiar with for building .deb packages.
With a small amount of code in the debian/rules file to turn the resulting .deb into an .ipk file.

Packages can be built directly using debuild::

    debuild -us -uc
    ls -alp ../iw2mqtt_*_all.ipk

Installing
==========
Simply copy the .ipk file to your OpenWRT device, then install it using opkg::

    scp ../iw2mqtt_*_all.ipk OpenWRT:
    ssh OpenWRT opkg install iw2mqtt_*_all.ipk

I might set up an opkg repo eventually, but don't have one yet.

Configuring
===========
Config is managed in uci, however there is no luci module for it.
You can use ```uci``` the command line tools to configure it::

    uci import iw2mqtt </dev/null
    uci set iw2mqtt.mqtt_host="$MQTT_HOST"  # Required
    uci set iw2mqtt.mqtt_user="$MQTT_USER"  # Required
    uci set iw2mqtt.mqtt_pass="$MQTT_PASS"  # Required
    uci set iw2mqtt.hostname="example.net"  # Optional, defaults to $(uci get system.@system[0].hostname)
    uci set iw2mqtt.update_interval="1m"  # Optional, default: 1 minute
    uci set iw2mqtt.attributes_json='{"latitude":-0.0,"longitude":0.0,"gps_accuracy":100,"source_tracker_id":"[$HOSTNAME]"}'  # Optional, leave blank for 'home'

No config in Home Assistant is required, assuming you already have MQTT integration & discovery working.

Running
=======
There is an included initscript to so you can start/stop it using ```/etc/init.d/iw2mqtt```.

After configuring, you probably simply want to enable it to run on reboots, and start it immediately::

    /etc/init.d/iw2mqtt enable
    /etc/init.d/iw2mqtt start


You might also want to pre-configure some MAC addresses that are not currently connected to your network to set them up in HA before they connect.
You can do so by sourcing ```libiw2mqtt``` directly and running the relevant function::

    . libiw2mqtt
    configure_discovery_for_mac 11:22:33:aa:bb:cc

Dev notes
=========
Inspired largely by `awilliams/wifi-presence <https://github.com/awilliams/wifi-presence>`_ & `dersimn/owrtwifi2mqtt <https://github.com/dersimn/owrtwifi2mqtt>`_.
The former is written in Go, and doesn't fit in the flash storage on my AP,
the latter requires a lot of YAML config in HA instead of using MQTT discovery,
and I don't like that it's based on IPs and assumes they are static.

TODO
----
* Rework it to use zone names instead of GPS co-ords
  Or at least remove the GPS co-ords when the device is "not_home" because it still shows up on the map in that location


Zone names rework
-----------------
Frustratingly value_template can only set payload_{home,not_home,reset}, nothing else.
ref: https://github.com/home-assistant/core/blob/5d3d66e47d066c74d596a326631165dea8411081/homeassistant/components/mqtt/device_tracker.py#L138
Note the ```else:...``` sets location_name to the original msg.payload instead of just the templated payload.

So I can't do something as simple as ```{{$ZONE_NAME if #MAC# in value_json.connected_devices}}```.

I also don't want to have a unique state_topic per MAC address, because that causes complexities when the OpenWRT goes "unavailable" and comes back.
If that MAC isn't connected anymore, the OpenWRT won't send any updates, but HA will remember the last state.

Maybe I can use the json_attributes_topic for connected_devices, update that every min or so.
**Then** update the state_topic with the zone name with a template like ```{"not_home" if #MAC# not in state_attr(entity_id, "connected_devices")}```.

HA won't rerun the value_template when the json_attributes_topic updates, but I might be able to just repeat the state_topic update to get a similar effect.
Might that run into thread/concurrency issues with the value_template being run before the json_attributes are processed?

ref: "Temporal mismatches" here: https://www.home-assistant.io/integrations/sensor.mqtt/#json-attributes-template-configuration
