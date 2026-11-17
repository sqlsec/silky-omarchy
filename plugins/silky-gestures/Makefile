# Builds against the installed Hyprland headers. Rebuild after every Hyprland update:
# a plugin built for another version refuses to load.
PKGS     := hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon lua
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC --no-gnu-unique -std=c++26 -Wall -Wno-deprecated-declarations

silky-gestures.so: main.cpp
	$(CXX) $(CXXFLAGS) $$(pkg-config --cflags $(PKGS)) $< -o $@

clean:
	rm -f silky-gestures.so

.PHONY: clean
