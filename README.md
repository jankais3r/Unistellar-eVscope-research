# Unistellar eVscope research
Reverse engineering notes - **this is a work in progress**

[Product website](https://unistellaroptics.com/product/)

## End goals
The purpose of this research is to:
1. Understand the inner workings of the eVscope, and
2. Understand enough of it to be able to control the telescope and retrieve camera stream from a computer rather than the official mobile app

## Structure
* [Hardware](#hardware)
* [Software](#software)
  * [eVscope](#evscope)
    * [Filesystems](#filesystems)
    * [SSH](#enter-ssh)
    * [Enviroment](#environment)
    * [FBO Images](#fbo-images)
    * [Does it run Doom?](#does-it-run-doom)
  * Mobile app

## Hardware

- System platform: [Raspberry Pi 3 A+](https://www.raspberrypi.org/products/raspberry-pi-3-model-a-plus/)
- Custom board: Unistellar Unishield (Rev P)
- Camera sensor: [Sony IMX224](https://www.sony-semicon.co.jp/products/common/pdf/IMX224.pdf)
- Storage: 16GB SanDisk micro SD card

Here is what you see once you remove the side cover:
![eVscope without a cover](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/hardware/IMG_2289.jpg)

And a close-up on the Unishield:
![Unishield](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/hardware/IMG_2291.jpg)

When we disconnect Unishield from the Raspi, we can see the bottom side of the PCB with a [dsPIC33E microchip](https://www.microchip.com/wwwproducts/en/dsPIC33EP128GM304) responsible for control of the motors. The Unishield also contains a [LSM6DSM](https://www.st.com/resource/en/datasheet/lsm6dsm.pdf) gyroscope/accelerometer module.
![Unishield's underside](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/hardware/IMG_2343.jpg)

See more pictures (and a video) [here](https://github.com/jankais3r/Unistellar-eVscope-research/tree/master/images/hardware).

Here's a simple diagram of how are these things connected together:
![Diagram](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/hardware/diagram.png)

The Raspberry Pi does not use its DSI display interface, audio jack, or any of the USB ports. It gets power via GPIO pins from the Unishield, which is then directly soldered to a battery. The GPIO is also used for communication with the Unishield, e.g. to control the azimuth/altitude motors. The camera stream goes from the IMX224 sensor's board to the Unishield via an HDMI cable, and the data is then forwarded to the Raspberry Pi through the CSI camera interface. This is the same ribbon cable connector used by the official Raspberry Pi [camera module](https://www.raspberrypi.org/products/camera-module-v2/) (which uses IMX219, a different Sony sensor). Raspberry Pi then uses its own HDMI-out to display the starfield in the eye-piece, which is powered by an OLED display.


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

#### Environment

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

Speaking of `hostapd`, let's see what else is running on the telescope. (You can download full RAM dump [here](https://github.com/jankais3r/Unistellar-eVscope-research/releases/tag/memory-dump).)
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
Besides the already mentioned `evdaemon` that's a mere launcher daemon and `evsoft` that we'll look into shortly, there's just one interesting folder called `evsoft`. It doesn't contain much, just some more wifi configs and an [image](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/mire.rgba.png) and its [mask](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/mask_circle.rgba.png) that can be projected to the eye-piece during a focusing process:
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


Ok, let's see which binaries we have access to in general.
```
# ls -l /bin
total 1140
lrwxrwxrwx    1 root     root             7 Mar  3  2020 arch -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 ash -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 base64 -> busybox
-rwsr-xr-x    1 root     root        699352 Mar  3  2020 busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 cat -> busybox
-rwxr-xr-x    1 root     root          9660 Mar  3  2020 chattr
lrwxrwxrwx    1 root     root             7 Mar  3  2020 chgrp -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 chmod -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 chown -> busybox
-rwxr-xr-x    1 root     root          1342 Mar  3  2020 compile_et
lrwxrwxrwx    1 root     root             7 Mar  3  2020 cp -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 cpio -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 date -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 dd -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 df -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 dmesg -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 dnsdomainname -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 dumpkmap -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 echo -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 egrep -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 false -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 fdflush -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 fgrep -> busybox
-rwxr-xr-x    1 root     root         13744 Mar  3  2020 free
lrwxrwxrwx    1 root     root             7 Mar  3  2020 getopt -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 grep -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 gunzip -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 gzip -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 hostname -> busybox
-rwxr-xr-x    1 root     root         22056 Mar  3  2020 kill
lrwxrwxrwx    1 root     root             7 Mar  3  2020 link -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 linux32 -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 linux64 -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 ln -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 login -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 ls -> busybox
-rwxr-xr-x    1 root     root          9652 Mar  3  2020 lsattr
-rwxr-xr-x    1 root     root          1102 Mar  3  2020 mk_cmds
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mkdir -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mknod -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mktemp -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 more -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mount -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mountpoint -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mt -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 mv -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 netstat -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 nice -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 nuke -> busybox
-rwxr-xr-x    1 root     root         22068 Mar  3  2020 pgrep
-rwxr-xr-x    1 root     root         13776 Mar  3  2020 pidof
lrwxrwxrwx    1 root     root             7 Mar  3  2020 ping -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 pipe_progress -> busybox
-rwxr-xr-x    1 root     root         22068 Mar  3  2020 pkill
-rwxr-xr-x    1 root     root         22052 Mar  3  2020 pmap
lrwxrwxrwx    1 root     root             7 Mar  3  2020 printenv -> busybox
-rwxr-xr-x    1 root     root         79696 Mar  3  2020 ps
lrwxrwxrwx    1 root     root             7 Mar  3  2020 pwd -> busybox
-rwxr-xr-x    1 root     root          9644 Mar  3  2020 pwdx
lrwxrwxrwx    1 root     root             7 Mar  3  2020 resume -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 rm -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 rmdir -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 run-parts -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 sed -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 setarch -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 setpriv -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 setserial -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 sh -> busybox
-rwxr-xr-x    1 root     root         13800 Mar  3  2020 slabtop
lrwxrwxrwx    1 root     root             7 Mar  3  2020 sleep -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 stty -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 su -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 sync -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 tar -> busybox
-rwxr-xr-x    1 root     root          9692 Mar  3  2020 tload
-rwxr-xr-x    1 root     root         94700 Mar  3  2020 top
lrwxrwxrwx    1 root     root             7 Mar  3  2020 touch -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 true -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 umount -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 uname -> busybox
-rwxr-xr-x    1 root     root          9624 Mar  3  2020 uptime
lrwxrwxrwx    1 root     root             7 Mar  3  2020 usleep -> busybox
lrwxrwxrwx    1 root     root             7 Mar  3  2020 vi -> busybox
-rwxr-xr-x    1 root     root         26104 Mar  3  2020 vmstat
-rwxr-xr-x    1 root     root         17900 Mar  3  2020 w
-rwxr-xr-x    1 root     root         18208 Mar  3  2020 watch
lrwxrwxrwx    1 root     root             7 Mar  3  2020 zcat -> busybox


# ls -l /sbin
total 812
lrwxrwxrwx    1 root     root            14 Mar  3  2020 arp -> ../bin/busybox
-rwxr-xr-x    1 root     root         22072 Mar  3  2020 badblocks
lrwxrwxrwx    1 root     root            14 Mar  3  2020 blkid -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 devmem -> ../bin/busybox
lrwxrwxrwx    1 root     root             8 Mar  3  2020 dosfsck -> fsck.fat
-rwxr-xr-x    1 root     root         22224 Mar  3  2020 dumpe2fs
-rwxr-xr-x    1 root     root         13780 Mar  3  2020 e2freefrag
-rwxr-xr-x    1 root     root        264320 Mar  3  2020 e2fsck
lrwxrwxrwx    1 root     root             7 Mar  3  2020 e2label -> tune2fs
lrwxrwxrwx    1 root     root             8 Mar  3  2020 e2mmpstatus -> dumpe2fs
-rwxr-xr-x    1 root     root         13836 Mar  3  2020 e2undo
-rwxr-xr-x    1 root     root         17916 Mar  3  2020 e4crypt
lrwxrwxrwx    1 root     root            14 Mar  3  2020 fdisk -> ../bin/busybox
-rwxr-xr-x    1 root     root         13740 Mar  3  2020 filefrag
lrwxrwxrwx    1 root     root            14 Mar  3  2020 freeramdisk -> ../bin/busybox
-rwxr-xr-x    1 root     root         22132 Mar  3  2020 fsck
lrwxrwxrwx    1 root     root             6 Mar  3  2020 fsck.ext2 -> e2fsck
lrwxrwxrwx    1 root     root             6 Mar  3  2020 fsck.ext3 -> e2fsck
lrwxrwxrwx    1 root     root             6 Mar  3  2020 fsck.ext4 -> e2fsck
-rwxr-xr-x    1 root     root         50700 Mar  3  2020 fsck.fat
lrwxrwxrwx    1 root     root             8 Mar  3  2020 fsck.msdos -> fsck.fat
lrwxrwxrwx    1 root     root             8 Mar  3  2020 fsck.vfat -> fsck.fat
lrwxrwxrwx    1 root     root            14 Mar  3  2020 fstrim -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 getty -> ../bin/busybox
-rwxr-xr-x    1 root     root         13832 Mar  3  2020 halt
lrwxrwxrwx    1 root     root            14 Mar  3  2020 hdparm -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 hwclock -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 ifconfig -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 ifdown -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 ifup -> ../bin/busybox
-rwxr-xr-x    1 root     root         35076 Mar  3  2020 init
lrwxrwxrwx    1 root     root            14 Mar  3  2020 insmod -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 ip -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 ipaddr -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 iplink -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 ipneigh -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 iproute -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 iprule -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 iptunnel -> ../bin/busybox
-rwxr-xr-x    1 root     root         17972 Mar  3  2020 killall5
lrwxrwxrwx    1 root     root            14 Mar  3  2020 klogd -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 loadkmap -> ../bin/busybox
-rwxr-xr-x    1 root     root          9664 Mar  3  2020 logsave
lrwxrwxrwx    1 root     root            14 Mar  3  2020 losetup -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 lsmod -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 makedevs -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 mdev -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 mkdosfs -> ../bin/busybox
-rwxr-xr-x    1 root     root        108904 Mar  3  2020 mke2fs
lrwxrwxrwx    1 root     root             6 Mar  3  2020 mkfs.ext2 -> mke2fs
lrwxrwxrwx    1 root     root             6 Mar  3  2020 mkfs.ext3 -> mke2fs
lrwxrwxrwx    1 root     root             6 Mar  3  2020 mkfs.ext4 -> mke2fs
-rwxr-xr-x    1 root     root          5512 Mar  3  2020 mklost+found
lrwxrwxrwx    1 root     root            14 Mar  3  2020 mkswap -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 modprobe -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 nameif -> ../bin/busybox
lrwxrwxrwx    1 root     root             8 Mar  3  2020 pidof -> killall5
lrwxrwxrwx    1 root     root            14 Mar  3  2020 pivot_root -> ../bin/busybox
lrwxrwxrwx    1 root     root            10 Mar  3  2020 poweroff -> /sbin/halt
lrwxrwxrwx    1 root     root            10 Mar  3  2020 reboot -> /sbin/halt
lrwxrwxrwx    1 root     root            14 Mar  3  2020 rmmod -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 route -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 run-init -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 runlevel -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 setconsole -> ../bin/busybox
-rwxr-xr-x    1 root     root         18072 Mar  3  2020 shutdown
-rwxr-xr-x    1 root     root         26756 Mar  3  2020 start-stop-daemon
lrwxrwxrwx    1 root     root            14 Mar  3  2020 sulogin -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 swapoff -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 swapon -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 switch_root -> ../bin/busybox
-rwxr-xr-x    1 root     root         22044 Mar  3  2020 sysctl
lrwxrwxrwx    1 root     root            14 Mar  3  2020 syslogd -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 tc -> ../bin/busybox
-rwxr-xr-x    1 root     root         88280 Mar  3  2020 tune2fs
lrwxrwxrwx    1 root     root            14 Mar  3  2020 udhcpc -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 uevent -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 vconfig -> ../bin/busybox
lrwxrwxrwx    1 root     root            14 Mar  3  2020 watchdog -> ../bin/busybox


# ls -l /usr/bin
total 836
lrwxrwxrwx    1 root     root            17 Mar  3  2020 [ -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 [[ -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 ar -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 awk -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 basename -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 bunzip2 -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 bzcat -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 chrt -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 chvt -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 cksum -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 clear -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 cmp -> ../../bin/busybox
-rwxr-xr-x    1 root     root          9596 Mar  3  2020 containers_check_frame_int
-rwxr-xr-x    1 root     root          5488 Mar  3  2020 containers_datagram_receiver
-rwxr-xr-x    1 root     root          5492 Mar  3  2020 containers_datagram_sender
-rwxr-xr-x    1 root     root          5488 Mar  3  2020 containers_dump_pktfile
-rwxr-xr-x    1 root     root          9612 Mar  3  2020 containers_rtp_decoder
-rwxr-xr-x    1 root     root          5504 Mar  3  2020 containers_stream_client
-rwxr-xr-x    1 root     root          5504 Mar  3  2020 containers_stream_server
-rwxr-xr-x    1 root     root         17876 Mar  3  2020 containers_test
-rwxr-xr-x    1 root     root         13752 Mar  3  2020 containers_test_bits
-rwxr-xr-x    1 root     root         20748 Mar  3  2020 containers_test_uri
-rwxr-xr-x    1 root     root          5496 Mar  3  2020 containers_uri_pipe
lrwxrwxrwx    1 root     root            17 Mar  3  2020 crontab -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 cut -> ../../bin/busybox
lrwxrwxrwx    1 root     root            16 Mar  3  2020 dbclient -> ../sbin/dropbear
lrwxrwxrwx    1 root     root            17 Mar  3  2020 dc -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 deallocvt -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 diff -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 dirname -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 dos2unix -> ../../bin/busybox
lrwxrwxrwx    1 root     root            16 Mar  3  2020 dropbearconvert -> ../sbin/dropbear
lrwxrwxrwx    1 root     root            16 Mar  3  2020 dropbearkey -> ../sbin/dropbear
-rwxr-xr-x    1 root     root          9604 Mar  3  2020 dtmerge
-rwxr-xr-x    1 root     root         22188 Mar  3  2020 dtoverlay
-rwxr-xr-x    1 root     root           331 Jan 15  2019 dtoverlay-post
-rwxr-xr-x    1 root     root           330 Jan 15  2019 dtoverlay-pre
lrwxrwxrwx    1 root     root             9 Mar  3  2020 dtparam -> dtoverlay
lrwxrwxrwx    1 root     root            17 Mar  3  2020 du -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 eject -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 env -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 expr -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 factor -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 fallocate -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 find -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 flock -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 fold -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 free -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 fuser -> ../../bin/busybox
-rwxr-xr-x    1 root     root          9608 Mar  3  2020 gpio-event-mon
-rwxr-xr-x    1 root     root          9608 Mar  3  2020 gpio-hammer
lrwxrwxrwx    1 root     root            17 Mar  3  2020 head -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 hexdump -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 hexedit -> ../../bin/busybox
-rwxr-xr-x    1 root     root         50828 Mar  3  2020 hostapd_cli
lrwxrwxrwx    1 root     root            17 Mar  3  2020 hostid -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 id -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 install -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 ipcrm -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 ipcs -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 killall -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 last -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 less -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 logger -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 logname -> ../../bin/busybox
-rwxr-xr-x    1 root     root          9664 Mar  3  2020 lsgpio
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lsof -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lspci -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lsscsi -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lsusb -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lzcat -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lzma -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 lzopcat -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 md5sum -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 mesg -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 microcom -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 mkfifo -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 mkpasswd -> ../../bin/busybox
-rwxr-xr-x    1 root     root         17944 Mar  3  2020 mmal_vc_diag
lrwxrwxrwx    1 root     root            17 Mar  3  2020 nl -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 nohup -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 nproc -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 nslookup -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 od -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 openvt -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 passwd -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 paste -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 patch -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 printf -> ../../bin/busybox
-rwxr-xr-x    1 root     root         91488 Mar  3  2020 raspistill
-rwxr-xr-x    1 root     root         65260 Mar  3  2020 raspivid
-rwxr-xr-x    1 root     root         52484 Mar  3  2020 raspividyuv
-rwxr-xr-x    1 root     root         48344 Mar  3  2020 raspiyuv
lrwxrwxrwx    1 root     root            17 Mar  3  2020 readlink -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 realpath -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 renice -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 reset -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 resize -> ../../bin/busybox
-rwxr-xr-x    1 root     root         14212 Mar  3  2020 rngtest
lrwxrwxrwx    1 root     root            16 Mar  3  2020 scp -> ../sbin/dropbear
lrwxrwxrwx    1 root     root            17 Mar  3  2020 seq -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 setfattr -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 setkeycodes -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 setsid -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 sha1sum -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 sha256sum -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 sha3sum -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 sha512sum -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 shred -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 sort -> ../../bin/busybox
-rwxr-xr-x    1 root     root        178756 Mar  3  2020 sqlite3
lrwxrwxrwx    1 root     root            16 Mar  3  2020 ssh -> ../sbin/dropbear
lrwxrwxrwx    1 root     root            17 Mar  3  2020 strings -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 svc -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 svok -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 tail -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 tee -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 telnet -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 test -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 tftp -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 time -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 top -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 tr -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 traceroute -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 truncate -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 tty -> ../../bin/busybox
-rwxr-xr-x    1 root     root         22380 Mar  3  2020 tvservice
lrwxrwxrwx    1 root     root            17 Mar  3  2020 uniq -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 unix2dos -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 unlink -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 unlzma -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 unlzop -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 unxz -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 unzip -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 uptime -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 uudecode -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 uuencode -> ../../bin/busybox
-rwxr-xr-x    1 root     root          5516 Mar  3  2020 vcgencmd
-rwxr-xr-x    1 root     root         46704 Mar  3  2020 vchiq_test
-rwxr-xr-x    1 root     root          5480 Mar  3  2020 vcmailbox
-rwxr-xr-x    1 root     root         13864 Mar  3  2020 vcsmem
lrwxrwxrwx    1 root     root            17 Mar  3  2020 vlock -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 w -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 wc -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 wget -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 which -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 who -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 whoami -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 xargs -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 xxd -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 xz -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 xzcat -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 yes -> ../../bin/busybox


# ls -l /usr/sbin
total 2376
lrwxrwxrwx    1 root     root            17 Mar  3  2020 addgroup -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 adduser -> ../../bin/busybox
-rwxr-xr-x    1 root     root         30544 Mar  3  2020 aphelper
lrwxrwxrwx    1 root     root            17 Mar  3  2020 arping -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 chroot -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 crond -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 delgroup -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 deluser -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 dnsd -> ../../bin/busybox
-rwxr-xr-x    1 root     root        259440 Mar  3  2020 dnsmasq
-rwxr-xr-x    1 root     root        211432 Mar  3  2020 dropbear
lrwxrwxrwx    1 root     root            17 Mar  3  2020 ether-wake -> ../../bin/busybox
-rwxr-xr-x    1 root     root          9924 Mar  3  2020 evdaemon
-rwxr-xr-x    1 root     root       1026284 Mar  3  2020 evsoft
lrwxrwxrwx    1 root     root            17 Mar  3  2020 fbset -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 fdformat -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 fsfreeze -> ../../bin/busybox
-rwxr-xr-x    1 root     root        618692 Mar  3  2020 hostapd
lrwxrwxrwx    1 root     root            17 Mar  3  2020 i2cdetect -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 i2cdump -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 i2cget -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 i2cset -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 inetd -> ../../bin/busybox
-rwxr-xr-x    1 root     root        147292 Mar  3  2020 iw
lrwxrwxrwx    1 root     root            17 Mar  3  2020 killall5 -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 loadfont -> ../../bin/busybox
-rwxr-xr-x    1 root     root         63288 Mar  3  2020 logrotate
-rwxr-xr-x    1 root     root           290 Nov  8  2019 mount-wait.sh
lrwxrwxrwx    1 root     root            17 Mar  3  2020 partprobe -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 rdate -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 readprofile -> ../../bin/busybox
-rwxr-xr-x    1 root     root         14328 Mar  3  2020 rngd
lrwxrwxrwx    1 root     root            17 Mar  3  2020 setlogcons -> ../../bin/busybox
lrwxrwxrwx    1 root     root            17 Mar  3  2020 ubirename -> ../../bin/busybox
-rwxr-xr-x    1 root     root          5500 Mar  3  2020 unishield_cmd
-rwxr-xr-x    1 root     root          9732 Mar  3  2020 vcfiled
-rwxr-xr-x    1 root     root          5472 Mar  3  2020 wrod
```

No package manager and a volatile filesystem means that we'll have to scp in any binary that's not currently available, e.g. `tcpdump` for dumping network traffic between the telescope and a mobile app, and we'll have to do to do it again after every reboot.


#### FBO Images

So, the user-data partition mounted under `/media/rw/` contains a folder called `files` with bunch of files in it. But what are those?

```
# ls -l /media/rw/files
total 256764
-rw-r--r--    1 root     root       2545672 Mar 27  2020 1585345073856.fbo
-rw-r--r--    1 root     root       2545672 Mar 27  2020 1585345083667.fbo
-rw-r--r--    1 root     root       2545672 Mar 27  2020 1585345486703.fbo
-rw-r--r--    1 root     root       1936648 Mar 27  2020 1585345501614.fbo
-rw-r--r--    1 root     root       1936656 Mar 27  2020 1585345505586.fbo
-rw-r--r--    1 root     root       1936656 Mar 27  2020 1585345686158.fbo
-rw-r--r--    1 root     root       1936656 Mar 27  2020 1585345741764.fbo
-rw-r--r--    1 root     root       1936656 Mar 27  2020 1585345745736.fbo
-rw-r--r--    1 root     root       1936656 Mar 27  2020 1585345749708.fbo
-rw-r--r--    1 root     root       1936656 Mar 27  2020 1585345753680.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585596778908.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585596789080.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585596815757.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585596902862.fbo
-rw-r--r--    1 root     root       1936648 Mar 30  2020 1585596973802.fbo
-rw-r--r--    1 root     root       1936648 Mar 30  2020 1585597115831.fbo
-rw-r--r--    1 root     root       1936656 Mar 30  2020 1585597119803.fbo
-rw-r--r--    1 root     root       1936656 Mar 30  2020 1585597143634.fbo
-rw-r--r--    1 root     root       1936656 Mar 30  2020 1585597147606.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585597303947.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585597336216.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585597346183.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585597413752.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585597447854.fbo
-rw-r--r--    1 root     root       2545672 Mar 30  2020 1585597497822.fbo
-rw-r--r--    1 root     root       1936648 Mar 30  2020 1585598323476.fbo
-rw-r--r--    1 root     root       1936656 Mar 30  2020 1585598327448.fbo
-rw-r--r--    1 root     root       1936656 Mar 30  2020 1585598331420.fbo
```

Let's see what we can deduce just from the file listing. You can tell that the filenames are timestamps in the Unix epoch format. So, could these actually be images? But in which format? If you look closely, you can see that there are only 3 unique file sizes - `2,545,672`, `1,936,656` and `1,936,648`. Different images having the exact same file size automatically exclude any conventinal image format, as those (even the lossless ones) work with compression. Time to look under the lid (you can download 6 sample fbo images [here](https://github.com/jankais3r/Unistellar-eVscope-research/tree/master/images/software/fbo)).

![2.5MB fbo](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/highres_fbo.png)

If we look at multiple 2.5MB fbo files, we'll start to see a pattern - a 262-byte long header containing the telescope's serial number, and then just bunch of data. 

The constant file size and the `.fbo` extension (framebuffer?) suggests we might be looking at raw picture data. Let's throw it at [RAW Pixels](http://rawpixels.net) to see what we get. The most important variable when rendering raw bytes as an image is the picture resolution (more specifically, the width). Luckily we know that eVscope uses Sony IMX224 sensor with resolution of 1304x976. We put those values into RAW Pixels and we watch what happens.

![Bingo!](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/pixelraw.png)

Ok, this worked. If you're wondering what's the black vertical line, it is a side effect of not removing the header bytes. Set Offset to 262 to render the image properly.

Let's see some of them fully rendered.
![Stars](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585596902862.png)
![Moon](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585597336216.png)
![More stars](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1586379967316.png)
Keep in mind that these pictures were taken automatically by the telescope for research purposes and they were not meant to be viewed by the telescope's owner. Also I had the telescope on my balcony right next to a street light, so excuse the light polution in the first picture.

But what about the 1.9MB files? Try to load them, you'll see just a mess of pixels. Clearly they are taken at a lower resolution (hence the lower file size), but what resolution is that? If you open them in a hex editor, you'll also notice that 1) they have no header, and 2) they have a footer of varying size, hence giving us files of either `1,936,656` or `1,936,648` bytes in size.
![1.9MB fbo](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/lowres_fbo.png)

When we know that `2,545,672` images are 1,304 pixels wide, how wide are `1,936,656` images? Cross-multiplication, I knew I would use you one day. `992.0364540286`, let's make it 992 px.

![Where](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585345559058.png)
![you](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585345563030.png)
![going](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585345567002.png)

I have not figured out why these lower resolution pictures have so much noise in them (and a different type of noise than the light polution in the first big picture), but they also seem to be taken much more frequently, which means we can make an animation out of them.

![Wheee](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/star_glider.gif)

We can also batch-process all of our fbo pictures with ImageMagick. Use the provided [process_fbo.sh](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/process_fbo.sh) script.


#### Does it run Doom?

[Yes](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/doom.m4v)*



&ast; eVscope == Raspberry Pi, so of course it does run Doom. However, as compiling [Chocolate Doom](https://www.chocolate-doom.org/wiki/index.php/Building_Chocolate_Doom_on_Linux) on a box without a package manager would be a very frustrating experience, this demo simply shows a static image.
