#
# Files and directories
#
WORKDIR ?= $(CURDIR)
RESULTS ?= $(if $(wildcard $(WORKDIR)/results/merged.csv),$(WORKDIR)/results/merged.csv,$(WORKDIR)/paperresults/merged.csv)
PLOT_FORMAT ?= svg
PLOT ?= $(WORKDIR)/$(notdir $(WORKDIR)).svg

#
# Tools
#
SNAKE ?= python3

#
# Targets
#
.PHONY: all
all: prepare run plot

.PHONY: prepare
prepare:
	$(WORKDIR)/build.sh

.PHONY: run
run:
	$(WORKDIR)/udp_echo.sh

.PHONY: plot
plot:
	$(SNAKE) $(WORKDIR)/plot.py --data $(RESULTS) --output $(PLOT)

.PHONY: clean
clean:
	$(WORKDIR)/clean.sh
