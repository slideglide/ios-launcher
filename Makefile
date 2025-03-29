export ARCHS := arm64
PACKAGE_FORMAT = ipa
TARGET := iphone:clang:latest:14.0:13.5
#TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = Geode

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Geode

ifeq ($(TROLLSTORE),1)
Geode_CODESIGN_FLAGS = -Sts-entitlements.xml
THEOS_PACKAGE_NAME=trollstore
else
Geode_CODESIGN_FLAGS = -Sentitlements.xml
endif

Geode_FILES = $(wildcard src/*.m) $(wildcard src/views/*.m) $(wildcard src/components/*.m) $(wildcard src/LCUtils/*.m) $(wildcard src/LCUtils/AltStoreCore*.m) fishhook/fishhook.c $(wildcard MSColorPicker/MSColorPicker/*.m) $(wildcard GCDWebServer/GCDWebServer/*/*.m)
Geode_FRAMEWORKS = UIKit CoreGraphics Security
Geode_CFLAGS = -fobjc-arc -IGCDWebServer/GCDWebServer/Core -IGCDWebServer/GCDWebServer/Requests -IGCDWebServer/GCDWebServer/Responses
Geode_LIBRARIES = archive # thats dumb
$(APPLICATION_NAME)_LDFLAGS = -e _GeodeMain -rpath @loader_path/Frameworks

include $(THEOS_MAKE_PATH)/application.mk
SUBPROJECTS += ZSign TweakLoader TestJITLess AltStoreTweak
include $(THEOS_MAKE_PATH)/aggregate.mk


before-package::
	@mv $(THEOS_STAGING_DIR)/Applications/Geode.app/Geode $(THEOS_STAGING_DIR)/Applications/Geode.app/GeodeLauncher_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou

after-package::
ifeq ($(TROLLSTORE),1)
	@mv "$(THEOS_PACKAGE_DIR)/trollstore_$(THEOS_PACKAGE_BASE_VERSION).ipa" "$(THEOS_PACKAGE_DIR)/com.geode.launcher_$(THEOS_PACKAGE_BASE_VERSION).tipa"
endif

before-all::
	@sh ./download_openssl.sh

# make package FINALPACKAGE=1 STRIP=0 TROLLSTORE=1
