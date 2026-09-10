NVIM ?= nvim

.PHONY: test benchmark format check
test:
	NVIM_LOG_FILE=/tmp/stardust-tests.log $(NVIM) --headless -u NONE -i NONE -l tests/run.lua

benchmark:
	NVIM_LOG_FILE=/tmp/stardust-benchmark.log $(NVIM) --headless -u NONE -i NONE -l tests/benchmark.lua

format:
	stylua lua plugin tests examples

check:
	stylua --check lua plugin tests examples
