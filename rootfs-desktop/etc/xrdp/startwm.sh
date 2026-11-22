#!/bin/sh
# Start the Ubuntu GNOME session for xrdp (managed by sift-workstation-docker).
#
# Containers have no systemd/logind, so gnome-session runs its built-in
# session manager (used automatically when not started by systemd) on
# Xorg (xorgxrdp) with software rendering.
unset DBUS_SESSION_BUS_ADDRESS
if [ -r /etc/profile ]; then . /etc/profile; fi

export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_CONFIG_DIRS=/etc/xdg/xdg-ubuntu:/etc/xdg
export XDG_DATA_DIRS=/usr/share/ubuntu:/usr/local/share:/usr/share
XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
export XDG_RUNTIME_DIR
export NO_AT_BRIDGE=1
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# `sift` is the Ubuntu session minus gsd-power, which needs logind (see the
# Dockerfile). Session output goes to ~/.cache/sift-session.log.
mkdir -p "$HOME/.cache"
exec dbus-run-session -- gnome-session --session=sift --disable-acceleration-check \
  >"$HOME/.cache/sift-session.log" 2>&1
