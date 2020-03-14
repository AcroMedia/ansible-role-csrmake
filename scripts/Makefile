USCRIPTS    = csrmake_sha256.sh
USCRIPTS   += install-pending-cert.sh

UDEST  ?= /usr/local/ssl

# Checking for ADMIN_GROUP is only expected to work on red hat and debian.
# Wheel must be checked for first, since it only exists on red hat. The adm group exists on both.
ADMIN_GROUP = $(shell (getent group wheel || getent group adm || echo 'invalid_group:') | cut -f 1 -d':')


build:
	@echo There is nothing to configure or build. This is just a collection of shell-scripts.
	@echo Run \'sudo make install\' or \'sudo make uninstall\'.

install:
	# make sure dir exists
	install -o root -g root -m 755 -d $(DESTDIR)$(UDEST)

	# also make sure these 3 dirs exist - this would happen when first setting up a new server.
	install -v -o root -g $(ADMIN_GROUP) -m 750 -d $(DESTDIR)$(UDEST)/backups
	install -v -o root -g $(ADMIN_GROUP) -m 2750 -d $(DESTDIR)$(UDEST)/private
	install -v -o root -g root -m 755 -d $(DESTDIR)$(UDEST)/certs

	# put utils in place.
	$(foreach file,$(USCRIPTS), install -v -o root -g root -m 755 $(file) $(DESTDIR)$(UDEST);)

uninstall:
	# remove utils
	$(foreach file,$(USCRIPTS), rm -rfv $(DESTDIR)$(UDEST)/$(file) ;)
