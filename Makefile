ODIN_ANDROID_NDK=${ANDROID_NDK_HOME}
ANDROID_OUT_DIR=out/AndroidProject/app/src/main/jniLibs/arm64-v8a

ANDROID_FILES := \
	android_files/AndroidManifest.xml \
	android_files/build.gradle \
	android_files/settings.gradle

all: android
	# odin build src -out:main

android: ${ANDROID_FILES}
	mkdir -p ${ANDROID_OUT_DIR}
	cp android_files/AndroidManifest.xml out/AndroidProject/app/src/main/
	cp android_files/build.gradle        out/AndroidProject/app/
	cp android_files/settings.gradle     out/AndroidProject
	ODIN_ANDROID_NDK=${ANDROID_NDK_HOME} \
	odin build src -out:${ANDROID_OUT_DIR}/libandroid_odin.so \
		-debug \
		-collection:my_vendor=./my_vendor/ \
		-target:linux_arm64 -subtarget:android -build-mode:shared

pc:
	@mkdir -p out
	odin build src -out:out/pc_odin -collection:my_vendor=./my_vendor/ -debug

