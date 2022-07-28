
COREVER=$(shell curl 'http://www.tinycorelinux.net/downloads.html' | grep 'Version ' | awk -F'Version ' '{print $$2}' | awk '{print $$1}')
EXTRA_PKGS="\
	avahi.tcz\
	dbus.tcz\
	expat2.tcz\
	gcc_libs.tcz\
	glib2.tcz\
	libavahi.tcz\
	libdaemon.tcz\
	libffi.tcz\
	liblvm2.tcz\
	libpci.tcz\
	ncursesw.tcz\
	nss-mdns.tcz\
	openssh.tcz\
	openssl-1.1.1.tcz\
	parted.tcz\
	pci-utils.tcz\
	readline.tcz\
	sc101-nbd.tcz\
	udev-lib.tcz\
"

UID=$(shell id -u)
GID=$(shell id -g)

ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

all:
	if [ "$$(grep Debian /etc/os-release)" == "" ] ; then \
		docker build . -t netbootcd-ipxe-bootchain-build ;\
		docker run --rm --privileged=true -v $(ROOT_DIR):$(ROOT_DIR) netbootcd-ipxe-bootchain-build /bin/bash -c 'cd $(ROOT_DIR) && make UID=$(UID) GID=$(GID)' ;\
	else \
		apt install -y zip dosfstools syslinux-utils genisoimage ;\
		cat $(ROOT_DIR)/Build.sh \
			| sed 's/__COREVER__/$(COREVER)/g' \
			| sed 's/__EXTRA_PKGS__/$(EXTRA_PKGS)/g' \
		> $(ROOT_DIR)/netbootcd/Build_bootchain.sh &&\
		chmod a+x $(ROOT_DIR)/netbootcd/Build_bootchain.sh && \
		cd $(ROOT_DIR)/netbootcd &&\
		./Build_bootchain.sh &&\
		cd $(ROOT_DIR) &&\
		cp -rfv $(ROOT_DIR)/netbootcd/done/vmlinuz $(ROOT_DIR)/ &&\
		cp -rfv $(ROOT_DIR)/netbootcd/done/nbinit4.gz $(ROOT_DIR)/ &&\
		if [ "$$(mount | grep tcisomnt)" != "" ] ; then\
		 	umount $(ROOT_DIR)/netbootcd/work/tcisomnt ; \
		fi ;\
		chmod a+xwr -R $(ROOT_DIR)/netbootcd/work ; \
		chown -R $(UID):$(GID) $(ROOT_DIR)/netbootcd/work ;\
		chown -R $(UID):$(GID) $(ROOT_DIR)/netbootcd/done ;\
		chown -R $(UID):$(GID) $(ROOT_DIR)/netbootcd/Core* ;\
		chown -R $(UID):$(GID) $(ROOT_DIR)/netbootcd/Build_bootchain* ;\
		chown -R $(UID):$(GID) $(ROOT_DIR)/nbinit4.gz ;\
		chown -R $(UID):$(GID) $(ROOT_DIR)/vmlinuz ;\
	fi

clean:
	rm -rf \
		nbinit4.gz vmlinuz \
		./netbootcd/work \
		./netbootcd/done \
		./netbootcd/Core* \
		./netbootcd/Build_bootchain.sh

#include $(GRUB_ROOT_DIR)Makefile