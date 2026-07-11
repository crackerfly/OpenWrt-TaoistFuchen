FAKESIP_DIR := fakesip
FAKESIP_VERSION := 0.9.4

.PHONY: clean compile install

clean:
	$(MAKE) -C $(FAKESIP_DIR) clean

compile:
	$(MAKE) -C $(FAKESIP_DIR) \
		PREFIX=/usr \
		VERSION="$(FAKESIP_VERSION)" \
		all

install:
	$(MAKE) -C $(FAKESIP_DIR) \
		PREFIX=/usr \
		VERSION="$(FAKESIP_VERSION)" \
		DESTDIR="$(DESTDIR)" \
		install
