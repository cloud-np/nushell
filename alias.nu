export def xrandr-fix [] {
    xrandr --output HDMI-0 --mode 1920x1080 --pos 0x360 --output DP-2 --mode 3440x1440 --pos 1920x0
}

export def webstorm [] {
    /home/cloud/JetBrains/WebStorm/bin/webstorm.sh
}

export def rustrover [] {
    /home/cloud/JetBrains/RustRover/bin/rustrover.sh
}
