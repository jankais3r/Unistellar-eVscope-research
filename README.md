# Unistellar eVscope research
Research notes

[Product website](https://unistellaroptics.com/product/)

## End goals
The purpose of this research is to:
1. Understand the inner workings of the eVscope, and
2. Understand enough of it to be able to control the telescope and retrieve camera stream from a computer rather than the official mobile app

## Structure
* Hardware
* Software
  * eVscope
  * Mobile app

## Hardware

## Software

### eVscope

#### Filesystems

As discussed in the hardware section, eVscope is powered by a Raspberry Pi board and that means one thing - filesystem on an SD card. We start our adventures by cloning the SD card. All future research will be done on the clone of the original card, just so we can revert to stock if we need to.

![File system](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/filesystem.png)

We see 4 partitions. Partition 1 and 2 are identical, and one of them likely acts as a fallback in case of a failed firmware update. Partition 3 contains a fairly large (3.4GB) SQLite database called `afdstarmap.db`, which holds information about objects in the sky. This database is used by the telescope to figure out where it should point itself. The 4th and largest partition is also the only one that is used for storing user data, e.g. observations that can be later uploaded to Unistellar for research purposes.

Partitions 1 & 2 are the ones we'll focus on first. We see a fairly standard setup for a Raspberry-based device. `cmdline.txt` and `config.txt` are used for interfacing with the firmware and it's where you set low level hardware preferences for different system buses and/or features of the SoC. `evscope.dtb` contains a device tree, describing all the different hardware features of the board(s). Then we have `evscope.fw`, which is the most important file of all - it contains the whole Linux system that powers the machine. Because the system is booted from a firmware file rather than a regular filesystem, runtime changes are not written back and the system is restored to its previous configuration on every reboot.

Upon boot, Partition 3 gets mounted as `/media/ro`, while the user-data Partition 4 gets mounted as `/media/rw`. How do we know that?

```
df -h
Filesystem                Size      Used Available Use% Mounted on
devtmpfs                178.5M         0    178.5M   0% /dev
tmpfs                   187.0M         0    187.0M   0% /dev/shm
tmpfs                   187.0M      8.0K    186.9M   0% /tmp
tmpfs                   187.0M     28.0K    186.9M   0% /run
/dev/mmcblk0p3            3.2G      3.2G         0 100% /media/ro
/dev/mmcblk0p4           10.8G    503.7M     10.3G   5% /media/rw
```

#### Enter SSH

Before we can start poking around the live system, we need a way in. The easiest way is to modify the system image (`evscope.fw`) to contain our own SSH public key. We'll need a 4096-bit RSA key, because that's what Unistellar used. Search the image file for `ssh-rsa` and you'll land at the right place. Then just replace the original key with one of your own, and you're good. For good measure, modify the image file in both Partition 1 & 2.

![SSH key replacement](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/ssh_key.png)

With these changes in place, put the SD card back into the scope, boot it up, and SSH in.

![We're in](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/ssh.png)


Now we can do some basic probing...
```
# uname -a
Linux evscope 4.19.7 #2 SMP Tue Mar 3 11:41:00 CET 2020 armv7l GNU/Linux


# cat /init 
#!/bin/sh
# devtmpfs does not get automounted for initramfs
/bin/mount -t devtmpfs devtmpfs /dev
exec 0</dev/console
exec 1>/dev/console
exec 2>/dev/console
exec /sbin/init "$@"


# cat /etc/shadow
root:$6$.E3d94szeQMLo$9ZIIDlYkDXHWp.3MyK2zCkQSzqwwsuycAH/tzledx4pgWhfK2I4lYD.PEpCxv4tKnwp1Cw..IEtAEJHXfTz1f0:10933:0:99999:7:::
daemon:*:10933:0:99999:7:::
bin:*:10933:0:99999:7:::
sys:*:10933:0:99999:7:::
sync:*:10933:0:99999:7:::
mail:*:10933:0:99999:7:::
www-data:*:10933:0:99999:7:::
operator:*:10933:0:99999:7:::
nobody:*:10933:0:99999:7:::


# cat /etc/passwd
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/bin/false
bin:x:2:2:bin:/bin:/bin/false
sys:x:3:3:sys:/dev:/bin/false
sync:x:4:100:sync:/bin:/bin/sync
mail:x:8:8:mail:/var/spool/mail:/bin/false
www-data:x:33:33:www-data:/var/www:/bin/false
operator:x:37:37:Operator:/var:/bin/false
nobody:x:65534:65534:nobody:/home:/bin/false
```

My first instict was to fire up an http proxy on my Mac in an attempt to monitor communication between the telescope and the mobile app. However, my phone could not see the Mac, even though they were both connected to the eVscope's AP.

That's because the AP is configured in that way. You can have multiple phones connected at the same time, and it's actually a good idea to have the wifi setup this way. All you have to do to revert this, is to change a config file and restart `hostapd` that takes care of the AP.

```
# cat /etc/hostapd.conf
interface=wlan0
driver=nl80211
max_num_sta=10
hw_mode=g
ieee80211n=1
ignore_broadcast_ssid=0
wpa=0
ssid=eVscope-zuv8m5
channel=11


# cat /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.100.2,192.168.100.100,255.255.255.0,24h
bind-interfaces
bogus-priv
dhcp-authoritative

# disable gateway
dhcp-option=3
```

Speaking of `hostapd`, let's see what else is running on the telescope.
![top](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/top.png)

Ok, we see that `dropbear` is used as an ssh server, and then we have an `evdaemon` that runs `evsoft`, the main binary that makes it all work. We'll look at those a bit later.

We've seen that the main executable is called `evsoft`, so let's see if there are any other interesting files relating to eVscope or Unistellar.

```
# find / -name "ev*"
/media/rw/evsoft.log
/etc/logrotate.d/evsoft
/sys/kernel/slab/eventpoll_pwq
/sys/kernel/slab/eventpoll_epi
/sys/module/block/parameters/events_dfl_poll_msecs
/usr/share/evsoft
/usr/sbin/evsoft
/usr/sbin/evdaemon
```
Besides the already mentioned `evdaemon` that's a mere launcher daemon and `evsoft` that we'll look into shortly, there's just one interesting folder called `evsoft`. It doesn't contain much, just some more wifi configs and two images that can be projected to the eye-piece during a mirror-alignment and focusing process:
```
# ls /usr/share/evsoft
hostapd-open.conf  hostapd-wpa.conf   mask.rgba.gz       sight.rgba.gz
```

What about Unistellar?

```
# find / -name "unis*"
/sys/firmware/devicetree/base/__symbols__/unishield_cryptochip
/usr/share/unishield
/usr/share/unishield/unishield-app.ver
/usr/share/unishield/unishield-app.hex
/usr/sbin/unishield_cmd
```

The `unishield_cmd` binary handles communication with the Unishield Pi-Hat that sits on top of the Raspberry and doesn't offer much more than than basic power functions.
```
# /usr/sbin/unishield_cmd
usage: /usr/sbin/unishield_cmd cmd
- cmd: "poweroff" or "reboot"
```

The `unishield-app.hex` file is a firmware for the daughter board, but 1) it's not high on my priority list of things to reverse engineer, and 2) it's way above my skillset, so we'll ignore it for now.
