NAME := cwin
SDK  ?= ../../..
SRCS := window.c
RUNMODE := desktop
TESTFLAGS := --expect 'CWIN: click 1 at' --expect 'CWIN: click 2 at' --expect 'CWIN: closed after 2 clicks'
include $(SDK)/c/c.mk
