#
# Files and directories
#
WORKDIR ?= $(CURDIR)
MEM ?= 1024M
RESULTS ?= $(if $(wildcard $(WORKDIR)/results/$(MEM)/*),$(WORKDIR)/results/$(MEM),$(WORKDIR)/paperresults/$(MEM))
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
	$(WORKDIR)/genimages.sh

.PHONY: run
run:
	$(WORKDIR)/benchmark.sh

.PHONY: plot
plot:
	$(SNAKE) $(WORKDIR)/plot.py --data $(RESULTS) --output $(PLOT)

.PHONY: clean
clean:
	@-
