# Builds against the installed fcitx5 headers. Rebuild after a major fcitx5 update.
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++20 -Wall -Wextra

libsilkywechatpreedit.so: silky-wechat-preedit.cpp
	$(CXX) $(CXXFLAGS) $$(pkg-config --cflags Fcitx5Core) $< -o $@ $$(pkg-config --libs Fcitx5Core)

.PHONY: all
all: libsilkywechatpreedit.so
