# Makefile for sqlite-plsql (Odin Implementation)
ODIN = odin
ODIN_SRC = src
BUILD_DIR = build
SQLITE_BIN = sqlite-bin
CC = gcc
CFLAGS = -g
WIN_LIBS = $(PWD)/win-libs

ABS_SRC    = $(abspath src)
ABS_BUILD  = $(abspath build)
ABS_SQLITE = $(abspath sqlite-bin)

# Optimization Levels:
ODIN_OPT  = -o:speed
# Clang: -O3 (Speed), -Oz (Smallest size)
CLANG_OPT = -O3 -flto

all:
	@echo "Usage:"
	@echo "  make linux"
	@echo "  make macos"
	@echo "  make windows"
	@echo "  make test"
	@echo "  make leak-check"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

linux: $(BUILD_DIR)
	$(ODIN) build $(ODIN_SRC) -build-mode:shared $(ODIN_OPT) -out:$(BUILD_DIR)/plsqlite.so

macos: $(BUILD_DIR)
	$(ODIN) build $(ODIN_SRC) -build-mode:shared $(ODIN_OPT) -out:$(BUILD_DIR)/plsqlite.dylib -target:darwin_amd64

LIB_CMT        = $(WIN_LIBS)/crt/lib/x86_64/libcmt.lib
LIB_OLDNAMES   = $(WIN_LIBS)/crt/lib/x86_64/oldnames.lib
LIB_VCRUNTIME  = $(WIN_LIBS)/crt/lib/x86_64/libvcruntime.lib
LIB_UCRT       = $(WIN_LIBS)/sdk/lib/ucrt/x86_64/libucrt.lib
LIB_KERNEL32   = $(WIN_LIBS)/sdk/lib/um/x86_64/kernel32.lib
LIB_USER32     = $(WIN_LIBS)/sdk/lib/um/x86_64/user32.lib
LIB_SHELL32    = $(WIN_LIBS)/sdk/lib/um/x86_64/shell32.lib
LIB_SQLITE     = $(ABS_SQLITE)/sqlite3.lib

windows: $(BUILD_DIR) download-sqlite-win
	# 1. Clear and create the IR directory
	rm -rf $(ABS_BUILD)/ir && mkdir -p $(ABS_BUILD)/ir

	# 2. Run Odin from inside the IR directory using the absolute source path
	cd $(ABS_BUILD)/ir && odin build $(ABS_SRC) \
		-target:windows_amd64 \
		-build-mode:llvm \
		$(ODIN_OPT) \
		-out:plsqlite.ll

	# 3. Link all generated .ll files (your code + core libs)
	clang -target x86_64-pc-windows-msvc -shared -fuse-ld=lld \
		-Wno-override-module \
		$(CLANG_OPT) \
		-o $(ABS_BUILD)/plsqlite.dll \
		$(ABS_BUILD)/ir/*.ll \
		-Wl,/nodefaultlib \
		"$(LIB_SQLITE)" \
		"$(LIB_CMT)" \
		"$(LIB_OLDNAMES)" \
		"$(LIB_VCRUNTIME)" \
		"$(LIB_UCRT)" \
		"$(LIB_KERNEL32)" \
		"$(LIB_USER32)" \
		"$(LIB_SHELL32)" \
		-Wl,/export:sqlite3_plsqlite_init

debug: $(BUILD_DIR)
	$(ODIN) build $(ODIN_SRC) -build-mode:shared -out:$(BUILD_DIR)/plsqlite.so -debug

test: linux
	python3 -m unittest tests.test_plsqlite -v

# Valgrind leak check (requires C runner)
leak-check: linux
	$(CC) $(CFLAGS) tests/leak_check.c -o $(BUILD_DIR)/leak_check -lsqlite3
	valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 --main-stacksize=16777216 ./$(BUILD_DIR)/leak_check
	rm -f $(BUILD_DIR)/leak_check

# Coverage using python kcov
coverage: debug
	mkdir -p coverage
	kcov --include-pattern=src coverage python3 tests/test_plsqlite.py

clean:
	rm -rf $(BUILD_DIR) coverage

download-headers:
	@if [ -f headers/sqlite3.h ] && [ -f headers/sqlite3ext.h ]; then \
		echo "SQLite headers already exist, skipping download."; \
	else \
		echo "Downloading SQLite headers..."; \
		mkdir -p headers; \
		curl -L https://www.sqlite.org/2023/sqlite-amalgamation-3420000.zip -o sqlite.zip; \
		unzip -o sqlite.zip; \
		mv sqlite-amalgamation-3420000/sqlite3.h sqlite-amalgamation-3420000/sqlite3ext.h headers/; \
		rm -rf sqlite-amalgamation-3420000 sqlite.zip; \
		echo "SQLite headers downloaded."; \
	fi

# --- Windows / Wine Development Workflow ---

# 1. Setup Windows SDK libraries (requires xwin)
setup-win-libs:
	xwin splat --output ./win-libs

# 2. Download Windows SQLite binaries and tools
download-sqlite-win:
	@if [ -f $(SQLITE_BIN)/sqlite3.dll ] && [ -f $(SQLITE_BIN)/sqlite3.lib ] && [ -f $(SQLITE_BIN)/sqlite3.exe ]; then \
		echo "Windows SQLite tools already exist in $(SQLITE_BIN), skipping download."; \
	else \
		echo "Downloading Windows SQLite DLL..."; \
		mkdir -p $(SQLITE_BIN); \
		curl -L -o /tmp/sqlite-dll.zip "https://www.sqlite.org/2024/sqlite-dll-win-x64-3470200.zip"; \
		unzip -o -j /tmp/sqlite-dll.zip -d $(SQLITE_BIN)/; \
		rm -f /tmp/sqlite-dll.zip; \
		llvm-dlltool -m i386:x86-64 -d $(SQLITE_BIN)/sqlite3.def -l $(SQLITE_BIN)/sqlite3.lib -D $(SQLITE_BIN)/sqlite3.dll; \
		echo "Created $(SQLITE_BIN)/sqlite3.lib"; \
		echo "Windows SQLite DLL installed!"; \
		curl -L -o /tmp/sqlite-tools.zip "https://www.sqlite.org/2024/sqlite-tools-win-x64-3470200.zip"; \
		unzip -o -j /tmp/sqlite-tools.zip sqlite3.exe -d $(SQLITE_BIN)/; \
		rm -f /tmp/sqlite-tools.zip; \
		echo "Windows SQLite tools installed!"; \
	fi

# 3. Build Windows DLL (cross-compiles using LLVM/Clang)
windows: $(BUILD_DIR) download-sqlite-win
	# 1. Clear and create the IR directory
	rm -rf $(ABS_BUILD)/ir && mkdir -p $(ABS_BUILD)/ir

	# 2. Run Odin from inside the IR directory using the absolute source path
	cd $(ABS_BUILD)/ir && odin build $(ABS_SRC) \
		-target:windows_amd64 \
		-build-mode:llvm \
		$(ODIN_OPT) \
		-out:plsqlite.ll

	# 3. Link all generated .ll files (your code + core libs)
	clang -target x86_64-pc-windows-msvc -shared -fuse-ld=lld \
		-Wno-override-module \
		$(CLANG_OPT) \
		-o $(ABS_BUILD)/plsqlite.dll \
		$(ABS_BUILD)/ir/*.ll \
		-Wl,/nodefaultlib \
		"$(LIB_SQLITE)" \
		"$(LIB_CMT)" \
		"$(LIB_OLDNAMES)" \
		"$(LIB_VCRUNTIME)" \
		"$(LIB_UCRT)" \
		"$(LIB_KERNEL32)" \
		"$(LIB_USER32)" \
		"$(LIB_SHELL32)" \
		-Wl,/export:sqlite3_plsqlite_init

# 4. Install Windows Python in Wine (one-time setup)
PYTHON_WIN_URL = https://www.python.org/ftp/python/3.14.3/python-3.14.3-amd64.exe
install-wine-python:
	@if wine python --version 2>/dev/null | grep -q "Python 3.14"; then \
		echo "Python 3.14 is already installed in Wine:"; \
		wine python --version; \
		echo "Run 'make uninstall-wine-python' first to reinstall."; \
	else \
		echo "Downloading Windows Python 3.14..."; \
		curl -L -o /tmp/python-win.exe $(PYTHON_WIN_URL); \
		echo "Installing Python in Wine (this may take a few minutes)..."; \
		wine /tmp/python-win.exe /quiet InstallAllUsers=1 PrependPath=1; \
		echo "Verifying Python installation..."; \
		wine python --version; \
		echo "Windows Python installed successfully!"; \
	fi

# 5. Full Python test suite under Wine
test-wine: windows
	@echo "Running full Python test suite under Wine..."
	@if wine python --version 2>/dev/null | grep -q Python; then \
		WINEDEBUG=-all wine python -m unittest tests.test_plsqlite -v; \
	else \
		echo "ERROR: Windows Python not installed. Run 'make install-wine-python' first."; \
		exit 1; \
	fi

.PHONY: all linux macos windows debug test leak-check coverage clean test-wine install-wine-python setup-win-libs
