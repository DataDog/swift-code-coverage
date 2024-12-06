.SECONDARY:

export MACOSX_DEPLOYMENT_TARGET := 10.13
export IPHONEOS_DEPLOYMENT_TARGET := 11.0
export TVOS_DEPLOYMENT_TARGET := 11.0
export PATH := $(PWD)/llvm/build/tools/bin:$(PATH)

CMAKE_ARGS := -G "Ninja" \
		-DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
		-DLLVM_BUILD_TOOLS=OFF \
		-DCLANG_BUILD_TOOLS=OFF \
		-DBUILD_SHARED_LIBS=OFF \
		-DLLVM_ENABLE_ZLIB=ON \
		-DLLVM_ENABLE_THREADS=ON \
		-DLLVM_ENABLE_UNWIND_TABLES=OFF \
		-DLLVM_ENABLE_EH=OFF \
		-DLLVM_ENABLE_RTTI=OFF \
		-DLLVM_ENABLE_ZSTD=OFF \
		-DLLVM_ENABLE_FFI=OFF \
		-DLLVM_ENABLE_TERMINFO=OFF \
		-DLLVM_DISABLE_ASSEMBLY_FILES=ON \
		-DCMAKE_BUILD_TYPE=Release

# Check is variable defined helper
check_defined = $(strip $(foreach 1,$1, $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = $(if $(value $1),, $(error Undefined $1$(if $2, ($2))$(if $(value @), required by target '$@')))

# params: scheme, platform, logfile
define xctest
	$(if $(filter $2,macOS),$(eval SDK=macosx)$(eval DEST='platform=macOS,arch=x86_64'),)
	$(if $(filter $2,iOSsim),$(eval SDK=iphonesimulator)$(eval DEST='platform=iOS Simulator,name=iPhone 14'),)
	$(if $(filter $2,tvOSsim),$(eval SDK=appletvsimulator)$(eval DEST='platform=tvOS Simulator,name=Apple TV'),)
	$(if $3,\
		set -o pipefail; xcodebuild -scheme $1 -sdk $(SDK) -destination $(DEST) test | tee $1-$2-$3.log | xcbeautify,\
		xcodebuild -scheme $1 -sdk $(SDK) -destination $(DEST) test)
endef

## params: scheme, sdk, destination, name, logfile
define xcarchive
	$(if $5,\
		set -o pipefail; xcodebuild archive -scheme $1 -sdk $2 -destination $3 -archivePath \
			build/$1/$4.xcarchive SKIP_INSTALL=NO | tee $1-$4-$5.log | xcbeautify,\
		xcodebuild archive -scheme $1 -sdk $2 -destination $3 -archivePath build/$1/$4.xcarchive SKIP_INSTALL=NO)
endef

####
# LLVM build
####

llvm/build/tools/bin/cmake:
	@curl -L -o cmake.tar.gz https://github.com/Kitware/CMake/releases/download/v3.31.0/cmake-3.31.0-macos-universal.tar.gz
	@tar xzf cmake.tar.gz
	@mkdir -p llvm/build/tools/bin llvm/build/tools/doc llvm/build/tools/man llvm/build/tools/share
	@cd cmake-* && \
	 mv CMake.app/Contents/bin/* ../llvm/build/tools/bin/ && \
	 mv CMake.app/Contents/doc/* ../llvm/build/tools/doc/ && \
	 mv CMake.app/Contents/man/* ../llvm/build/tools/man/ && \
	 mv CMake.app/Contents/share/* ../llvm/build/tools/share/
	@rm -rf cmake*
	
llvm/build/tools/bin/ninja:
	@mkdir -p llvm/build/tools/bin
	@curl -OL https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-mac.zip
	@unzip ninja-mac.zip
	@mv ninja llvm/build/tools/bin/
	@rm ninja-mac.zip

llvm_tools: llvm/build/tools/bin/cmake llvm/build/tools/bin/ninja

clean_llvm_tools:
	@rm -rf llvm/build/tools
	@mkdir -p llvm/build/tools

llvm/build/src/llvm-%.tar.xz:
	@mkdir -p llvm/build/src
	@curl -L -o "$@" https://github.com/llvm/llvm-project/releases/download/llvmorg-$*/llvm-project-$*.src.tar.xz
	
clean_llvm_sources:
	@rm -rf llvm/build/src
	@mkdir -p llvm/build/src

llvm/build/src/llvm-%: llvm/build/src/llvm-%.tar.xz
	@rm -f "llvm/build/src/llvm$*"
	@tar xzf $<
	@cd llvm-project-$*.src ;\
	 for patch in "$(PWD)/llvm/patches/$*"/*; do \
		if [[ "$$patch" == *.diff ]]; then \
			echo "Applying patch: $$patch" ;\
			git apply --ignore-space-change --ignore-whitespace "$$patch" ;\
		fi \
	 done
	@cp llvm-project-$*.src/llvm/cmake/platforms/iOS.cmake llvm-project-$*.src/llvm/cmake/platforms/tvOS.cmake
	@sed -i.bak 's/iphoneos/appletvos/' llvm-project-$*.src/llvm/cmake/platforms/tvOS.cmake
	@cp llvm-project-$*.src/llvm/cmake/platforms/iOS.cmake llvm-project-$*.src/llvm/cmake/platforms/macOS.cmake
	@sed -i.bak 's/iphoneos/macosx/' llvm-project-$*.src/llvm/cmake/platforms/macOS.cmake
	@mv llvm-project-$*.src $@
	@touch -am $@
	@xcrun SetFile -d "$$(xcrun GetFileInfo -m $@)" $@

llvm/build/src/llvm15: llvm/build/src/llvm-15.0.0 llvm_tools
	@cd $(dir $@) && ln -s $(notdir $<) $(notdir $@)

llvm/build/src/llvm17: llvm/build/src/llvm-17.0.6 llvm_tools
	@cd $(dir $@) && ln -s $(notdir $<) $(notdir $@)

llvm/build/libs/llvm%/macosx: llvm/build/src/llvm%
	$(eval CMAKE_ARGS_PL = $(CMAKE_ARGS) \
				-DCMAKE_INSTALL_PREFIX="$(PWD)/$@" \
				-DLLVM_TARGET_ARCH="arm64;x86_64" \
				-DCMAKE_TOOLCHAIN_FILE="$(PWD)/$</llvm/cmake/platforms/macOS.cmake" \
				-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64")
	@mkdir -p llvm/build/build llvm/build/libs
	@cd llvm/build/build && cmake $(CMAKE_ARGS_PL) "$(PWD)/$</llvm"
	@env cmake --build llvm/build/build
	@env cmake --install llvm/build/build
	@mv "$@/include/llvm" "$@/include/llvm$*"
	@mv "$@/include/llvm-c" "$@/include/llvm$*-c"
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm/|#include \"llvm$*/|" {} \;
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm-c/|#include \"llvm$*-c/|" {} \;
	@libtool -static -o $@/llvm$*.a $@/lib/*.a
	@rm -rf llvm/build/build $@/bin $@/share $@/lib

llvm/build/libs/llvm%/iphoneos: llvm/build/src/llvm%
	$(eval CMAKE_ARGS_PL = $(CMAKE_ARGS) \
				-DCMAKE_INSTALL_PREFIX="$(PWD)/$@" \
				-DLLVM_TARGET_ARCH="arm64" \
				-DCMAKE_TOOLCHAIN_FILE="$(PWD)/$</llvm/cmake/platforms/iOS.cmake" \
				-DCMAKE_OSX_ARCHITECTURES="arm64")
	@mkdir -p llvm/build/build llvm/build/libs
	@cd llvm/build/build && cmake $(CMAKE_ARGS_PL) "$(PWD)/$</llvm"
	@env cmake --build llvm/build/build
	@env cmake --install llvm/build/build
	@mv "$@/include/llvm" "$@/include/llvm$*"
	@mv "$@/include/llvm-c" "$@/include/llvm$*-c"
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm/|#include \"llvm$*/|" {} \;
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm-c/|#include \"llvm$*-c/|" {} \;
	@libtool -static -o $@/llvm$*.a $@/lib/*.a
	@rm -rf llvm/build/build $@/bin $@/share $@/lib

llvm/build/libs/llvm%/iphonesimulator: llvm/build/src/llvm%
	$(eval SYSROOT = $(shell xcodebuild -version -sdk iphonesimulator Path))
	$(eval CMAKE_ARGS_PL = $(CMAKE_ARGS) \
				-DCMAKE_INSTALL_PREFIX="$(PWD)/$@" \
				-DLLVM_TARGET_ARCH="arm64;x86_64" \
				-DCMAKE_TOOLCHAIN_FILE="$(PWD)/$</llvm/cmake/platforms/iOS.cmake" \
				-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
				-DCMAKE_OSX_SYSROOT="$(SYSROOT)")
	@mkdir -p llvm/build/build llvm/build/libs
	@cd llvm/build/build && cmake $(CMAKE_ARGS_PL) "$(PWD)/$</llvm"
	@env cmake --build llvm/build/build
	@env cmake --install llvm/build/build
	@mv "$@/include/llvm" "$@/include/llvm$*"
	@mv "$@/include/llvm-c" "$@/include/llvm$*-c"
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm/|#include \"llvm$*/|" {} \;
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm-c/|#include \"llvm$*-c/|" {} \;
	@libtool -static -o $@/llvm$*.a $@/lib/*.a
	@rm -rf llvm/build/build $@/bin $@/share $@/lib

llvm/build/libs/llvm%/appletvos: llvm/build/src/llvm%
	$(eval CMAKE_ARGS_PL = $(CMAKE_ARGS) \
				-DCMAKE_INSTALL_PREFIX="$(PWD)/$@" \
				-DLLVM_TARGET_ARCH="arm64" \
				-DCMAKE_TOOLCHAIN_FILE="$(PWD)/$</llvm/cmake/platforms/tvOS.cmake" \
				-DCMAKE_OSX_ARCHITECTURES="arm64")
	@mkdir -p llvm/build/build llvm/build/libs
	@cd llvm/build/build && cmake $(CMAKE_ARGS_PL) "$(PWD)/$</llvm"
	@env cmake --build llvm/build/build
	@env cmake --install llvm/build/build
	@mv "$@/include/llvm" "$@/include/llvm$*"
	@mv "$@/include/llvm-c" "$@/include/llvm$*-c"
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm/|#include \"llvm$*/|" {} \;
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm-c/|#include \"llvm$*-c/|" {} \;
	@libtool -static -o $@/llvm$*.a $@/lib/*.a
	@rm -rf llvm/build/build $@/bin $@/share $@/lib
	
llvm/build/libs/llvm%/appletvsimulator: llvm/build/src/llvm%
	$(eval SYSROOT = $(shell xcodebuild -version -sdk appletvsimulator Path))
	$(eval CMAKE_ARGS_PL = $(CMAKE_ARGS) \
				-DCMAKE_INSTALL_PREFIX="$(PWD)/$@" \
				-DLLVM_TARGET_ARCH="arm64;x86_64" \
				-DCMAKE_TOOLCHAIN_FILE="$(PWD)/$</llvm/cmake/platforms/tvOS.cmake" \
				-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
				-DCMAKE_OSX_SYSROOT="$(SYSROOT)")
	@mkdir -p llvm/build/build llvm/build/libs
	@cd llvm/build/build && cmake $(CMAKE_ARGS_PL) "$(PWD)/$</llvm"
	@env cmake --build llvm/build/build
	@env cmake --install llvm/build/build
	@mv "$@/include/llvm" "$@/include/llvm$*"
	@mv "$@/include/llvm-c" "$@/include/llvm$*-c"
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm/|#include \"llvm$*/|" {} \;
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm-c/|#include \"llvm$*-c/|" {} \;
	@libtool -static -o $@/llvm$*.a $@/lib/*.a
	@rm -rf llvm/build/build $@/bin $@/share $@/lib
	
llvm/build/libs/llvm%/maccatalyst: llvm/build/src/llvm%
	$(eval SYSROOT = $(shell xcodebuild -version -sdk macosx Path))
	$(eval CMAKE_ARGS_PL = $(CMAKE_ARGS) \
				-DCMAKE_INSTALL_PREFIX="$(PWD)/$@" \
				-DLLVM_TARGET_ARCH="arm64;x86_64" \
				-DCMAKE_TOOLCHAIN_FILE="$(PWD)/$</llvm/cmake/platforms/iOS.cmake" \
				-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
				-DCMAKE_OSX_SYSROOT="$(SYSROOT)" \
				-DCMAKE_OSX_DEPLOYMENT_TARGET="" \
				-DCMAKE_C_FLAGS="-target arm64-apple-ios14.0-macabi" \
				-DCMAKE_CXX_FLAGS="-target arm64-apple-ios14.0-macabi")
	@mkdir -p llvm/build/build llvm/build/libs
	@cd llvm/build/build && cmake $(CMAKE_ARGS_PL) "$(PWD)/$</llvm"
	@env cmake --build llvm/build/build
	@env cmake --install llvm/build/build
	@mv "$@/include/llvm" "$@/include/llvm$*"
	@mv "$@/include/llvm-c" "$@/include/llvm$*-c"
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm/|#include \"llvm$*/|" {} \;
	@find "$@/include" -type f -exec sed -i "" "s|#include \"llvm-c/|#include \"llvm$*-c/|" {} \;
	@libtool -static -o $@/llvm$*.a $@/lib/*.a
	@rm -rf llvm/build/build $@/bin $@/share $@/lib

llvm/xcframeworks/LLVM%.xcframework: llvm/build/libs/llvm%/macosx llvm/build/libs/llvm%/maccatalyst \
									 llvm/build/libs/llvm%/iphoneos llvm/build/libs/llvm%/iphonesimulator \
									 llvm/build/libs/llvm%/appletvos llvm/build/libs/llvm%/appletvsimulator
	$(eval LIBS = $(foreach plfm,$^,-library "$(plfm)/llvm$*.a" -headers "$(plfm)/include"))
	@mkdir -p llvm/xcframeworks
	@xcodebuild -create-xcframework $(LIBS) -output $@

build_llvm: llvm/xcframeworks/LLVM15.xcframework llvm/xcframeworks/LLVM17.xcframework

llvm%_prebuilt_xcframework:
	$(eval PLATFORMS = $(wildcard llvm/build/libs/llvm$*/*))
	$(eval LIBS = $(foreach plfm,$(PLATFORMS),-library "$(plfm)/llvm$*.a" -headers "$(plfm)/include"))
	@mkdir -p llvm/xcframeworks
	@xcodebuild -create-xcframework $(LIBS) -output llvm/xcframeworks/LLVM$*.xcframework

llvm_prebuilt: llvm15_prebuilt_xcframework llvm17_prebuilt_xcframework

clean_llvm_libs:
	@rm -rf llvm/build/libs llvm/xcframeworks
	@mkdir -p llvm/build/libs llvm/xcframeworks

clean_llvm: clean_llvm_sources clean_llvm_tools clean_llvm_libs

##
# SDK build
##

build/%/iphoneos.xcarchive:
	$(call xcarchive,$*,iphoneos,'generic/platform=iOS',iphoneos,$(XC_LOG))

build/%/iphonesimulator.xcarchive:
	$(call xcarchive,$*,iphonesimulator,'generic/platform=iOS Simulator',iphonesimulator,$(XC_LOG))
	
build/%/macos.xcarchive:
	$(call xcarchive,$*,macosx,'generic/platform=macOS',macos,$(XC_LOG))

build/%/maccatalyst.xcarchive:
	$(eval platform = 'generic/platform=macOS,variant=Mac Catalyst')
	$(call xcarchive,$*,macosx,$(platform),maccatalyst,$(XC_LOG))

build/%/appletvos.xcarchive:
	$(call xcarchive,$*,appletvos,'generic/platform=tvOS',appletvos,$(XC_LOG))

build/%/appletvsimulator.xcarchive:
	$(call xcarchive,$*,appletvsimulator,'generic/platform=tvOS Simulator',appletvsimulator,$(XC_LOG))

build/xcframework/%.xcframework: build/%/iphoneos.xcarchive build/%/iphonesimulator.xcarchive \
								 build/%/macos.xcarchive build/%/maccatalyst.xcarchive \
								 build/%/appletvos.xcarchive build/%/appletvsimulator.xcarchive
	@mkdir -p $(PWD)/build/xcframework
	@xargs xcodebuild -create-xcframework -output $@ <<<"$(foreach archive,$^,-framework $(archive)/Products/Library/Frameworks/$*.framework)"

build/xcframework/%.zip: build/xcframework/%.xcframework
	cd ./build/xcframework/; zip -ry ./$*.zip ./$*.xcframework

build/symbols/%.zip: build/%/iphoneos.xcarchive build/%/iphonesimulator.xcarchive \
					 build/%/macos.xcarchive build/%/maccatalyst.xcarchive \
					 build/%/appletvos.xcarchive build/%/appletvsimulator.xcarchive
	@for archive in $^ ; do \
		name=$$(basename $$archive | cut -d'.' -f1) ;\
		mkdir -p $(PWD)/build/symbols/$*/$$name ;\
		cp -R $$archive/dSYMs/*.dSYM $(PWD)/build/symbols/$*/$$name/ ;\
	done
	@cd $(PWD)/build/symbols/$*; zip -ry ../$*.zip ./*

build_sdk: build/xcframework/CodeCoverage.zip build/symbols/CodeCoverage.zip

clean_sdk:
	rm -rf ./build

test:
	$(call xctest,CodeCoverage,macOS,$(XC_LOG))
	$(call xctest,CodeCoverage,iOSsim,$(XC_LOG))
	$(call xctest,CodeCoverage,tvOSsim,$(XC_LOG))

# RELEASE LOGIC

set_version:
	@:$(call check_defined, version, release version)
	sed -i "" "s|MARKETING_VERSION =.*|MARKETING_VERSION = \"$(version)\";|g" CodeCoverage.xcodeproj/project.pbxproj
	sed -i "" "s|let[[:blank:]]*releaseVersion.*|let releaseVersion = \"$(version)\"|g" Package.swift

set_hash:
	$(eval HASH := $(shell swift package compute-checksum ./build/xcframework/CodeCoverage.zip))
	sed -i "" "s|let[[:blank:]]*relaseChecksum.*|let relaseChecksum = \"$(HASH)\"|g" Package.swift

build_release:
	@$(MAKE) set_version
	@$(MAKE) build_sdk
	@$(MAKE) set_hash

github_release: build_release	
	@:$(call check_defined, GH_TOKEN, GitHub token)
	# Update gh tool if needed
	@brew list gh &>/dev/null || brew install gh
	# Commit updated xcodeproj and Package.swift
	@git add Package.swift CodeCoverage.xcodeproj/project.pbxproj
	@git checkout -b release-$(version)
	@git commit -m "Updated binary package version to $(version)"
	@git tag -f $(version)
	@git push -f --tags origin release-$(version)
	# rename symbols file
	@mv build/symbols/CodeCoverage.zip build/symbols/CodeCoverage.symbols.zip
	#make github release
	@gh release create $(version) --draft --verify-tag --generate-notes \
		build/xcframework/CodeCoverage.zip build/symbols/CodeCoverage.symbols.zip
