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
    * [evsoft](#evsoft)
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

For your reference:
* [Decompiled device tree](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/other/evscope.dtb.txt)
* [/dev/](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/other/dev.txt)
* [/sys/bus/](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/other/sys_bus.txt)

## Software

### eVscope

#### Filesystems

As discussed in the hardware section, eVscope is powered by a Raspberry Pi board and that means one thing - filesystem on an SD card. We start our adventures by cloning the SD card. All future research will be done on the clone of the original card, just so we can revert to stock if we need to.

![File system](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/filesystem.png)

We see 4 partitions. Partition 1 and 2 are identical, and one of them likely acts as a fallback in case of a failed firmware update. Partition 3 contains a fairly large (3.4GB) SQLite database called `afdstarmap.db`, which holds information about objects in the sky. This database is used by the telescope to figure out where it should point itself. The 4th and largest partition is also the only one that is used for storing user data, e.g. observations that can be later uploaded to Unistellar for research purposes.

Partitions 1 & 2 are the ones we'll focus on first. We see a fairly standard setup for a Raspberry-based device. `cmdline.txt` and `config.txt` are used for interfacing with the firmware and it's where you set low level hardware preferences for different system buses and/or features of the SoC. `evscope.dtb` contains a device tree, describing all the different hardware features of the board(s). I've linked to the decompiled device tree in the hardware section. Then we have `evscope.fw`, which is the most important file of all - it contains the whole Linux system that powers the machine. Because the system is booted from a firmware file rather than a regular filesystem, runtime changes are not written back and the system is restored to its previous configuration on every reboot.

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

If you're curious which binaries we have access to in general, the full listing is available [here](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/other/binaries.txt) - it's mostly just busybox and some rpi-specific programs.

No package manager and a volatile filesystem means that we'll have to scp in any binary that's not currently available, e.g. `tcpdump` for dumping network traffic between the telescope and a mobile app, and we'll have to do to do it again after every reboot.

Let's have a look at what info do the standard Raspberry Pi binaries provide about the camera:
```
# mmal_vc_diag camerainfo
cameras  : 0
flashes  : 2
flash 0  : flash type LED
flash 1  : flash type LED

# mmal_vc_diag mmal-stats
component		port		buffers		fps	delay
ril.resize          	0 [in ]rx	5606      	30.0	39977
ril.resize          	0 [in ]tx	5606      	30.0	41214
ril.resize          	0 [out]rx	5607      	29.9	787336
ril.resize          	0 [out]tx	5606      	30.0	41212
ril.video_encode    	0 [in ]rx	5606      	30.0	35930
ril.video_encode    	0 [in ]tx	5606      	30.0	38675
ril.video_encode    	0 [out]rx	5700      	30.4	783872
ril.video_encode    	0 [out]tx	5700      	30.4	783883
ril.video_render    	0 [in ]rx	5606      	30.0	45526
ril.video_render    	0 [in ]tx	5604      	30.0	50018
ril.hvs             	0 [in ]rx	5606      	30.0	45171
ril.hvs             	0 [in ]tx	5606      	30.0	45526
ril.hvs             	1 [in ]rx	0         	 0.0	0
ril.hvs             	1 [in ]tx	0         	 0.0	0
ril.hvs             	2 [in ]rx	0         	 0.0	0
ril.hvs             	2 [in ]tx	0         	 0.0	0
ril.hvs             	3 [in ]rx	0         	 0.0	0
ril.hvs             	3 [in ]tx	0         	 0.0	0
ril.hvs             	4 [in ]rx	1         	 0.0	0
ril.hvs             	4 [in ]tx	0         	 0.0	0
ril.hvs             	0 [out]rx	5606      	29.9	877887
ril.hvs             	0 [out]tx	5606      	30.0	45543
ril.video_splitter  	0 [in ]rx	841       	 5.0	209922
ril.video_splitter  	0 [in ]tx	841       	 5.0	209922
ril.video_splitter  	0 [out]rx	842       	 5.0	1013016
ril.video_splitter  	0 [out]tx	841       	 5.0	209111
ril.video_splitter  	1 [out]rx	842       	 5.0	1017756
ril.video_splitter  	1 [out]tx	841       	 5.0	209921
ril.video_splitter  	2 [out]rx	0         	 0.0	0
ril.video_splitter  	2 [out]tx	0         	 0.0	0
ril.video_splitter  	3 [out]rx	0         	 0.0	0
ril.video_splitter  	3 [out]tx	0         	 0.0	0
ril.image_fx        	0 [in ]rx	841       	 5.0	207727
ril.image_fx        	0 [in ]tx	841       	 5.0	208498
ril.image_fx        	0 [out]rx	842       	 5.0	811206
ril.image_fx        	0 [out]tx	841       	 5.0	208500
ril.isp             	0 [in ]rx	841       	 5.0	207830
ril.isp             	0 [in ]tx	841       	 5.0	207860
ril.isp             	0 [out]rx	843       	 5.0	208401
ril.isp             	0 [out]tx	841       	 5.0	207858
ril.isp             	1 [out]rx	843       	 5.0	214934
ril.isp             	1 [out]tx	841       	 5.0	207857
ril.rawcam          	0 [out]rx	1704      	10.1	200298
ril.rawcam          	0 [out]tx	1700      	10.1	200101


# raspistill -f
mmal: Cannot read camera info, keeping the defaults for OV5647
mmal: mmal_vc_component_create: failed to create component 'vc.ril.camera' (1:ENOMEM)
mmal: mmal_component_create_core: could not create component 'vc.ril.camera' (1)
mmal: Failed to create camera component
mmal: main: Failed to create camera component
mmal: Camera is not detected. Please check carefully the camera module is installed correctly
```

Too bad, it seems that we won't be able to use standard tooling to access the camera. Not surprising though, working with other than official camera modules has always been a problem on Raspberries. [libcamera](https://www.raspberrypi.org/blog/an-open-source-camera-stack-for-raspberry-pi-using-libcamera/) is here to change that, but that does not apply for our use case.

What about the display in the eye piece?
```
# tvservice -s
state 0x12000a [HDMI DMT (16) RGB full 4:3], 1024x768 @ 60.00Hz, progressive


# tvservice -n
[E] No device present
```

The reported HDMI mode is 1024x768, however the [sight image](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/mire.rgba.png) used for focusing of the display has a resolution of 1280x960. When looked in the eye-pieace, the display has a circular shape. So far I haven't spent time investigating how many pixels are actually visible.

i2c bus:
```
# i2cdetect -y 0
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- 1a -- -- -- 1e --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- 36 -- -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
50: -- -- -- -- -- -- -- UU -- -- -- -- -- -- -- --
60: -- -- -- -- -- -- -- -- -- -- UU -- -- -- -- --
70: -- -- -- -- -- -- -- --


# i2cdetect -y 1
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
60: 60 -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
70: -- -- -- -- -- -- -- --
```

Network connections:
```
# netstat -tuln | grep LISTEN
netstat: /proc/net/tcp6: No such file or directory
tcp        0      0 0.0.0.0:13007           0.0.0.0:*               LISTEN
tcp        0      0 0.0.0.0:13009           0.0.0.0:*               LISTEN
tcp        0      0 0.0.0.0:13012           0.0.0.0:*               LISTEN
tcp        0      0 127.0.0.1:53            0.0.0.0:*               LISTEN
tcp        0      0 192.168.100.1:53        0.0.0.0:*               LISTEN
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN
```

Port `13007` is used by the telescope to announce its status. Port `13009` is used for the camera data stream. Port `13012` is used for controlling the telescope. More on those later.


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

Let's see what we can deduce just from the file listing. You can tell that the filenames are timestamps in the Unix epoch format. So, could these actually be images? But in which format? If you look closely, you can see that there are only 3 unique file sizes - `2,545,672`, `1,936,656` and `1,936,648`. Different images having the exact same file size automatically exclude any conventinal image format, as those (even the lossless ones) work with compression. Time to look under the lid (you can download 7 sample fbo images [here](https://github.com/jankais3r/Unistellar-eVscope-research/tree/master/images/software/fbo)).

![2.5MB fbo](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/highres_fbo.png)

If we look at multiple 2.5MB fbo files, we'll start to see a pattern - a 262-byte long header containing the telescope's serial number, and then just bunch of data. 

The constant file size and the `.fbo` extension (framebuffer?) suggests we might be looking at raw picture data. Let's throw it at [RAW Pixels](http://rawpixels.net) to see what we get. The most important variable when rendering raw bytes as an image is the picture resolution (more specifically, the width). Luckily we know that eVscope uses Sony IMX224 sensor with resolution of 1304x976. We put those values into RAW Pixels and we watch what happens.

![Bingo!](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/pixelraw.png)

Ok, this worked. If you're wondering what's the black vertical line, it is a side effect of not removing the header bytes. Set Offset to 262 to render the image properly.

Let's see some of them fully rendered.
![Stars](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585596902862.png)
![Moon](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585597336216.png)
![More stars](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1586379967316.png)
Keep in mind that these pictures were taken automatically by the telescope for research purposes and they were not meant to be viewed by the telescope's owner. What you see in the last picture is a "dark frame", showing pixels that light up on the camera's sensor even when the telescope cover is on. The telescope is smart enough to account for them when rendering the photos meant for consumption.

But what about the 1.9MB files? Try to load them, you'll see just a mess of pixels. Clearly they are taken at a lower resolution (hence the lower file size), but what resolution is that? If you open them in a hex editor, you'll also notice that 1) they have no header, and 2) they have a footer of varying size, hence giving us files of either `1,936,656` or `1,936,648` bytes in size.
![1.9MB fbo](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/lowres_fbo.png)

When we know that `2,545,672` images are 1,304 pixels wide, how wide are `1,936,656` images? Cross-multiplication, I knew I would use you one day. `992.0364540286`, let's make it 992 px.

![Lowres star](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1585345559058.png)

I have not figured out why these lower resolution pictures have so much noise in them (and a different type of noise than the light polution in the first big picture), but they also seem to be taken much more frequently, which means we can make an animation out of them.

![Wheee](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/star_glider.gif)

We can also batch-process all of our fbo pictures with ImageMagick. Use the provided [process_fbo.sh](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/process_fbo.sh) script.

ImageMagick doesn't have seem to have a built-in support for decoding color information encoded in the Bayer format, but we can use [bayer2rgb](https://github.com/jdthomas/bayer2rgb) to get color versions of those pictures. However, there's not that much to be gained by introducing color. See for yourself.
![Stars with colorful noise](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/fbo/1588798962319.fbo.tiff)
You can use the provided script [process_fbo_rgb.sh](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/process_fbo_rgb.sh) to render the pictures in color.

#### evsoft

As we've discussed earlier, evsoft is the main binary running on the telescope.

It is responsible for (non-exhaustive list):
* Establishing connection with the mobile clients
* Controlling the hardware (camera, motors, display)
* Figuring out what part of the sky the telescope is looking at
* Processing the camera data and sending it to the mobile clients


The Unistellar team chose [ZeroMQ](https://zeromq.org) library for 1) routing the camera data within the evsoft process, and 2) communication between the telescope and the mobile apps. It seems to be a good choice for a multiplatform application. The only downside I found so far is that I've never used it before, so my research is going a bit slower than I would like.

I've ran the evsoft binary through strings, and I've found these relevant [inproc://](http://api.zeromq.org/2-1:zmq-inproc) zmq endpoints:
```
inproc://deinterlacing_frame
inproc://background_frame
inproc://stack_frame
inproc://raw_frame
inproc://src_frame
inproc://bayer_frame
inproc://isp_frame0 in_frame0
inproc://isp_frame1 out_frame1
inproc://fx_frame in_frame
inproc://split_frame0
inproc://split_frame1
inproc://resized_frame
inproc://comp_frame
inproc://sink_frame out_sink
inproc://deinterlacing_frame
inproc://background_frame
inproc://out_rgb_frame out_rgb_frame
inproc://out_yuv_frame out_yuv_frame
```
They all seem to be holding camera data in different states, however the inproc scheme makes them unreachable unless we would inject ourselves into the evsoft process. It's an option, but my primary goal is to reverse engineer the API used by the mobile apps, not to hack the telescope. zmq also supports tcp:// sockets, so we'll look at those next.


#### Does it run Doom?

[Yes](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/doom.m4v)*

![Doom](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/images/software/evscope/doom.gif)

&ast; eVscope == Raspberry Pi, so of course it does run Doom. However, as compiling [Chocolate Doom](https://www.chocolate-doom.org/wiki/index.php/Building_Chocolate_Doom_on_Linux) on a box without a package manager would be a very frustrating experience, this demo simply shows a static image.
