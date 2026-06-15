export TARGET := iphone:clang:latest:12.0
export ARCHS := arm64

INSTALL_TARGET_PROCESSES = FreeFireMAX

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FFAimbot

FFAimbot_FILES = Tweak.xm
FFAimbot_CFLAGS = -fobjc-arc -I.
FFAimbot_LDFLAGS += -lsubstrate -lobjc -Wl,-segalign,0x4000
FFAimbot_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	@echo "=== Package built: packages/FFAimbot.deb ==="
