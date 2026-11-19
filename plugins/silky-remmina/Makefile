# GTK3 module for Remmina; built and installed by scripts/install-remmina-mac.sh.
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
PKGS = gtk+-3.0 librsvg-2.0

libsilky-remmina.so: silky-remmina.c
	$(CC) $(CFLAGS) -shared -fPIC -o $@ $< $$(pkg-config --cflags --libs $(PKGS))

.PHONY: all
all: libsilky-remmina.so
