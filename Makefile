##
# SDK build
##

.SECONDARY:

# HELPERS

# Check is variable defined helper
check_defined = $(strip $(foreach 1,$1, $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = $(if $(value $1),, $(error Undefined $1$(if $2, ($2))$(if $(value @), required by target '$@')))

# params: scheme, platform, logfile
define xctest
	$(if $(filter $2,macOS),$(eval SDK=macosx)$(eval DEST='platform=macOS'),)
	$(if $(filter $2,MacCatalyst),$(eval SDK=macosx)$(eval DEST='platform=macOS,variant=Mac Catalyst'),)
	$(if $(filter $2,iOSsim),$(eval SDK=iphonesimulator)$(eval DEST='platform=iOS Simulator,name=iPhone 15'),)
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

build: build/xcframework/CodeCoverage.zip build/symbols/CodeCoverage.zip

clean:
	rm -rf ./build

test:
	$(call xctest,CodeCoverage,macOS,$(XC_LOG))
	$(call xctest,CodeCoverage,iOSsim,$(XC_LOG))
	$(call xctest,CodeCoverage,tvOSsim,$(XC_LOG))
	$(call xctest,CodeCoverage,MacCatalyst,$(XC_LOG))

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
	@$(MAKE) build
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
