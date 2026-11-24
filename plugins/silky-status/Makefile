CXX ?= g++
CXXFLAGS ?= -O2 -std=c++20 -Wall -Wextra
TARGET = silky-status

all: $(TARGET)

$(TARGET): main.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean
