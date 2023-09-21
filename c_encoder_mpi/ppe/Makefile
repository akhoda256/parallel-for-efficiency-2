#!/usr/bin/make -f

# Makefile for ppe
# Copyright (C) 2021  Xiaoyue Chen and Hannah Atmer
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

SHELL = /bin/sh

EXEC = ppe
SRCS = custom_types.cpp dct8x8_block.cpp main.cpp xml_aux.cpp
OBJS = $(SRCS:.cpp=.o)

DEBUG_FLAGS =
PERF_FLAGS = #-pg # comment this line out if not using gprof

CXX = g++
CXXFLAGS = $(DEBUG_FLAGS) $(PERF_FLAGS) -I /usr/include/libxml2/ -fopenmp \
	-msse4.1 -std=c++17 -foffload=nvptx-none -fcf-protection=none -foffload=-misa=sm_35 -fno-stack-protector
LDFLAGS = $(PERF_FLAGS)
LDLIBS = -lxml2 -ltiff -fopenmp -foffload=nvptx-none -fcf-protection=none -foffload=-misa=sm_35 -fno-stack-protector

.PHONY: all
all: $(EXEC)

$(EXEC): $(OBJS)
	$(CXX) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

custom_types.o: custom_types.h config.h
dct8x8_block.o: dct8x8_block.h
xml_aux.o: xml_aux.h config.h
main.o: config.h custom_types.h dct8x8_block.h xml_aux.h

.PHONY: clean
clean:
	rm $(EXEC) $(OBJS)
