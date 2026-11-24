CXX ?= g++
CXXFLAGS ?= -O2 -std=c++20 -Wall -Wextra -fno-exceptions
TARGET = silky-desktop-priority

all: $(TARGET)

$(TARGET): main.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean
