iw2mqtt
=======
Use OpenWRT's wireless connection state as MQTT device trackers
ref: https://www.home-assistant.io/integrations/device_tracker.mqtt/

Not yet ready for production, just a bunch of notes (for now).
The intended goal is to have this running on the OpenWRT AP (doesn't need to
be OpenWRT, so long as it has ``iw event`` and ``mosquitto_pub``) sending
updates to Home Assistant via MQTT.

Installing
==========
TODO

Currently just scping the script to ~ on the OpenWRT device

Running
=======
TODO

Set the MQTT_USER, MQTT_PW, & MQTT_HOST variables as need.
Then run `./iw2mqtt.sh &`

Dev notes
=========
Inspired largely by `awilliams/wifi-presence <https://github.com/awilliams/wifi-presence>`_ & `dersimn/owrtwifi2mqtt <https://github.com/dersimn/owrtwifi2mqtt>`_.
The former is written in Go, and doesn't fit in the flash storage on my AP,
the latter requires a lot of YAML config in HA,
and I don't like that it assumes IPs are static instead of just using MAC addresses.

I also figure it's likely less resource intensive if it's not checking the IP,
hostname, or any other info every time.

All this needs to do is:

* read a small amount of config (from uci?) for what MQTT server to talk to and what zone to update
* read config (from uci? or mqtt?) for a list of MACs to monitor
* send some basic discovery info on startup for the configured MACs
  This discovery info **could** include device name and such,
  but at most that should be set in the config beforehand.
  NOTE: Don't set node_id AP-specific because that would cause issues for a device_tracker across multiple APs at once
  NOTE: Maybe the discovery info is the config?
* send home/away/zone updates to the specific MAC topics
* set the topic state to "offline" when not running
  How does mqtt "last will" work?

The "zone" state is optional, but would be useful for running this in a separate building over the VPN.

TODO
----
* Hook into uci for MQTT server details & credentials
* Make things work a bit better if there's multiple APs running in separate zones
* Make a .ipk package
