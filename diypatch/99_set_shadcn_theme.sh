#!/bin/sh

uci set luci.main=core
uci set luci.main.mediaurlbase='/luci-static/shadcn'
uci commit luci

exit 0
