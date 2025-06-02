#!/bin/bash

# Reload input devices
udevadm trigger

# Run oem-install if OEM is set
/usr/sbin/oem-install

# Force Qt apps to use GTK3
export QT_QPA_PLATFORMTHEME=gtk3

# Start X11 if not running
if [ -z "$DISPLAY" ] && ! pidof X; then
  startx /usr/bin/jwm
fi

# Print message when no jwm
clear

cat /etc/bliss/message.txt
