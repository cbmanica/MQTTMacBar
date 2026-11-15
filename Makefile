SCHEME      = MQTTMacBar
PROJECT     = MQTTMacBar.xcodeproj
BUILD_DIR   = build
APP         = $(BUILD_DIR)/.derivedData/Build/Products/Debug/$(SCHEME).app
INSTALL_DIR = $(HOME)/Applications
INSTALLED   = $(INSTALL_DIR)/$(SCHEME).app

.PHONY: build run install clean kill test

build:
	@mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR)/.derivedData \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGN_STYLE=Manual \
		2>&1 | tee $(BUILD_DIR)/build.log; \
	BUILD_RESULT=$${PIPESTATUS[0]}; \
	if command -v xcbeautify >/dev/null 2>&1; then \
		xcbeautify < $(BUILD_DIR)/build.log; \
	else \
		grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" $(BUILD_DIR)/build.log; \
	fi; \
	exit $$BUILD_RESULT

run: build
	open $(APP)

install: build
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALLED)
	pkill -x $(SCHEME) || true
	open $(INSTALLED)

test:
	@mkdir -p $(BUILD_DIR)
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS,arch=arm64' \
		-derivedDataPath $(BUILD_DIR)/.derivedData \
		2>&1 | tee $(BUILD_DIR)/test.log; \
	TEST_RESULT=$${PIPESTATUS[0]}; \
	if command -v xcbeautify >/dev/null 2>&1; then \
		xcbeautify < $(BUILD_DIR)/test.log; \
	else \
		grep -E "error:|Test Suite|passed|failed" $(BUILD_DIR)/test.log; \
	fi; \
	exit $$TEST_RESULT

kill:
	pkill -x $(SCHEME) || true

restart: kill run

clean:
	rm -rf $(BUILD_DIR)
