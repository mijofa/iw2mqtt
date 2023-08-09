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
