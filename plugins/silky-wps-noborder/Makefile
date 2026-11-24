# Builds a small LD_PRELOAD helper for WPS Office (Linux/XWayland) that drops
# KPromeMainWindow's outer frame margins on floating windows.
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++20 -Wall -Wextra

libsilkywpsnoborder.so: silky-wps-noborder.cpp version.map
	$(CXX) $(CXXFLAGS) $< -Wl,--version-script=version.map -ldl -o $@

.PHONY: all clean
all: libsilkywpsnoborder.so
clean:
	rm -f libsilkywpsnoborder.so
