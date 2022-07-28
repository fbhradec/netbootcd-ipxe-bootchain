#!/bin/sh
#Build.sh 11.1 for netbootcd

## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
##
## The full text of the GNU GPL, versions 2 or 3, can be found at
## <http://www.gnu.org/copyleft/gpl.html> or on the CD itself.

set -e
PATH=$PATH:/sbin
WORK=$(pwd)/work
DONE=$(pwd)/done
NBINIT=${WORK}/nbinit #for CD/USB

#Set to false to not build floppy images
FLOPPY=true
NBCDVER=13.1
COREVER=13.1

EXTRA_PKGS="
	avahi.tcz
	dbus.tcz
	expat2.tcz
	gcc_libs.tcz
	glib2.tcz
	libavahi.tcz
	libdaemon.tcz
	libffi.tcz
	liblvm2.tcz
	libpci.tcz
	ncursesw.tcz
	nss-mdns.tcz
	openssh.tcz
	openssl-1.1.1.tcz
	parted.tcz
	pci-utils.tcz
	readline.tcz
	sc101-nbd.tcz
	udev-lib.tcz
"

COREVER_GENERIC=$(echo $COREVER | awk -F'.' '{print $1".x"}')
if [ ! -f CorePlus-$COREVER.iso ];then
	wget http://www.tinycorelinux.net/$COREVER_GENERIC/x86/release/CorePlus-$COREVER.iso --no-check-certificate
fi

NO=0
for i in CorePlus-$COREVER.iso \
nbscript.sh tc-config.diff kexec.tgz \
grub.exe \
dialog.tcz ncurses.tcz;do
	if [ ! -e $i ];then
		echo "Couldn't find $i!"
		NO=1
	fi
done
if $FLOPPY && [ ! -e blank-bootable-1440-floppy.gz ];then
	echo "Couldn't find blank-bootable-1440-floppy.gz!"
	NO=1
fi
for i in mkdosfs unsquashfs isohybrid zip;do
	if ! which $i > /dev/null;then
		echo "Please install $i!"
		NO=1
	fi
done
if ! which genisoimage > /dev/null;then
	if ! which mkisofs > /dev/null;then
		echo "Please install genisoimage or mkisofs!"
		NO=1
	fi
fi
if [ $NO = 1 ];then
	exit 1
fi

#make sure we are root
if [ $(whoami) != "root" ];then
	echo "Please run as root."
	exit 1
fi

if [ -d ${WORK} ];then
	rm -r ${WORK}
fi
if [ -d ${DONE} ];then
	rm -r ${DONE}
fi

mkdir -p ${WORK} ${DONE} ${NBINIT}

#Extract TinyCore ISO to new dir
TCISO=${WORK}/tciso
mkdir ${TCISO} ${WORK}/tcisomnt
mount -o loop CorePlus-$COREVER.iso ${WORK}/tcisomnt
cp -r ${WORK}/tcisomnt/* ${TCISO}
umount ${WORK}/tcisomnt
rmdir ${WORK}/tcisomnt

#Copy kernel - Core 5.0+ already built with kexec
cp ${TCISO}/boot/vmlinuz ${DONE}/vmlinuz
chmod +w ${DONE}/vmlinuz

#Make nbinit4.gz. NetbootCD itself won't use any separate TCZ files. It will all be in the initrd.
if [ -d ${NBINIT} ];then
	rm -r ${NBINIT}
fi
mkdir ${NBINIT}

FDIR=$(pwd)
cd ${NBINIT}
echo "Extracting..."
gzip -cd ${TCISO}/boot/core.gz | cpio -id
cd -
#write wrapper script
cat > ${NBINIT}/usr/bin/netboot << "EOF"
#!/bin/sh
if [ $(whoami) != "root" ];then
	exec sudo $0 $*
fi

exec /sbin/sshd
sh
#echo "Waiting for internet connection (will keep trying indefinitely)"
#echo -n "Testing example.com"
#[ -f /tmp/internet-is-up ]
#while [ $? != 0 ];do
#	sleep 1
#	echo -n "."
#	wget --spider http://www.example.com &> /dev/null
#done
echo > /tmp/internet-is-up

if [ -x /tmp/nbscript.sh ];then
	/tmp/nbscript.sh
else
	/usr/bin/nbscript.sh
fi
echo "Type \"netboot\" to return to the menu."
EOF
chmod +x ${NBINIT}/usr/bin/netboot
#patch /etc/init.d/tc-config
cd ${NBINIT}/etc/init.d
patch -p0 < ${FDIR}/tc-config.diff
cd -
#copy nbscript
cp -v nbscript.sh ${NBINIT}/usr/bin

#copy dialog & ncurses
if [ -e squashfs-root ];then
	rm -r squashfs-root
fi

for i in dialog.tcz ncurses.tcz;do
	unsquashfs $i
	cp -a squashfs-root/* ${NBINIT}
	rm -r squashfs-root
done

tar -C ${NBINIT} -xvf kexec.tgz

echo "if ! which startx;then netboot;else sleep 5;echo \*\* Type \"netboot\" and press enter to launch the NetbootCD main menu. \*\*;fi" >> ${NBINIT}/etc/skel/.profile

#Add pxe-kexec to nbinit, if it exists in this folder
if [ -f pxe-kexec/pxe-kexec.tgz ] && [ -f pxe-kexec/readline.tcz ] && \
   [ -f pxe-kexec/curl.tcz ] && [ -f pxe-kexec/openssl.tcz ] && \
   [ -f pxe-kexec/libgcrypt.tcz ] && [ -f pxe-kexec/libgpg-error.tcz ] && \
   [ -f pxe-kexec/libidn.tcz ] && [ -f pxe-kexec/libssh2.tcz ];then
	mkdir ${WORK}/pxe-kexec
	tar -C ${WORK}/pxe-kexec -xf pxe-kexec/pxe-kexec.tgz # an extra utility
	for i in readline.tcz curl.tcz openssl.tcz libgcrypt.tcz libgpg-error.tcz libidn.tcz libssh2.tcz;do #dependencies of pxe-kexec
		unsquashfs pxe-kexec/$i
		cp -a squashfs-root/* ${WORK}/pxe-kexec
		rm -r squashfs-root
	done
	#workaround for libraries
	mkdir ${WORK}/pxe-kexec/usr/lib
	for i in ${WORK}/pxe-kexec/usr/local/lib/*;do
		BASENAME=$(basename $i)
		if [ ! -e ${WORK}/pxe-kexec/usr/lib/$BASENAME ];then
			ln -s ../local/lib/$BASENAME ${WORK}/pxe-kexec/usr/lib/$BASENAME
		fi
	done
	cp -a ${WORK}/pxe-kexec/* ${NBINIT}
#	rm -r ${WORK}/pxe-kexec
else
	echo "pxe-kexec not included"
	sleep 2
fi

# download extra packages
mkdir -p ${NBINIT}/extra/
cd ${NBINIT}/extra/
for n in $EXTRA_PKGS ; do
	echo "Downloading package $n..."
	curl -L -O "http://www.tinycorelinux.net/$COREVER_GENERIC/x86/tcz/$n"
	if [ $? -ne 0 ] ; then
		echo "ERROR: Can't download package $n"
		exit -1
	fi
 done


cd ${NBINIT}
find . | cpio -o -H 'newc' | gzip -c > ${DONE}/nbinit4.gz
cd -
if which advdef 2> /dev/null;then
	advdef -z ${DONE}/nbinit4.gz
fi
#rm -r ${NBINIT}
echo "Made initrd:" $(wc -c ${DONE}/nbinit4.gz)

if [ -d ${WORK}/iso ];then
	rm -r ${WORK}/iso
fi
mkdir -p ${WORK}/iso/boot/isolinux

cp ${TCISO}/boot/isolinux/isolinux.bin ${WORK}/iso/boot/isolinux #get ISOLINUX from the TinyCore disc
cp ${TCISO}/boot/isolinux/menu.c32 ${WORK}/iso/boot/isolinux #get menu.c32 from the TinyCore disc

for i in vmlinuz nbinit4.gz;do
	cp ${DONE}/$i ${WORK}/iso/boot
done
wget -O ${WORK}/iso/boot/grub.exe https://www.lakora.us/netbootcd/downloads/grub4dos-0.4.6a-2020-02-29/grub.exe --no-check-certificate

echo "DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
ONTIMEOUT nbcd

LABEL hd
MENU LABEL Boot from hard disk
localboot 0x80

LABEL nbcd
menu label Start ^NetbootCD $NBCDVER
menu default
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
append quiet

LABEL grub4dos
menu label ^GRUB4DOS 0.4.6a-2020-02-29
kernel /boot/grub.exe
" >> ${WORK}/iso/boot/isolinux/isolinux.cfg

if which mkisofs>/dev/null;then
	CDRTOOLS=1
	MAKER=mkisofs
fi
if which genisoimage>/dev/null;then
	CDRKIT=1
	MAKER=genisoimage
fi
if [ -n $CDRKIT ] && [ -n $CDRTOOLS ];then
	echo "Using genisoimage over mkisofs. It shouldn't make any difference."
fi
$MAKER --no-emul-boot --boot-info-table --boot-load-size 4 \
-b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat -J -r \
-o ${DONE}/NetbootCD-$NBCDVER.iso ${WORK}/iso

chown -R 1000.1000 $DONE
isohybrid ${DONE}/NetbootCD-$NBCDVER.iso

ln -s ${DONE}/NetbootCD-$NBCDVER.iso ${DONE}/NetbootCD.iso

cp -r ${TCISO}/cde ${WORK}/iso
cp ${TCISO}/boot/core.gz ${WORK}/iso/boot

echo "DEFAULT menu.c32
PROMPT 0

TIMEOUT 100
ONTIMEOUT nbcd

LABEL hd
MENU LABEL Boot from hard disk
localboot 0x80

LABEL nbcd-coreplus
menu label Start Core Plus $COREVER on top of NetbootCD $NBCDVER
menu default
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
append loglevel=3 cde showapps desktop=flwm_topside
text help
Uses the core of NetbootCD with the TCZ extensions of Core Plus. The
result is that Core Plus is loaded first, and NetbootCD is run when you
choose \"Exit To Prompt\".
endtext

LABEL nbcd
menu label Start ^NetbootCD $NBCDVER only
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
text help
Runs NetbootCD on its own, without loading GUI or extensions.
Boot media is removable.
endtext

LABEL plus
menu label Boot Core Plus $COREVER with default FLWM topside.
TEXT HELP
Boot Core plus support extensions of networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
kernel /boot/vmlinuz
initrd /boot/core.gz
append loglevel=3 cde showapps desktop=flwm_topside

MENU BEGIN Other Core Plus options

LABEL plus
MENU DEFAULT
MENU LABEL Boot Core Plus with default FLWM topside.
TEXT HELP
Boot Core plus support extensions of networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=flwm_topside

LABEL jwm
MENU LABEL Boot Core Plus with Joe's Window Manager.
TEXT HELP
Boot Core with JWM plus networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=jwm

LABEL icewm
MENU LABEL Boot Core Plus with ICE Window Manager.
TEXT HELP
Boot Core with ICE window manager plus networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=icewm

LABEL fluxbox
MENU LABEL Boot Core Plus with Fluxbox Window Manager.
TEXT HELP
Boot Core with Fluxbox plus networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=fluxbox

LABEL hackedbox
MENU LABEL Boot Core Plus with Hackedbox Window Manager.
TEXT HELP
Boot Core with hackedbox plus networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=hackedbox

LABEL openbox
MENU LABEL Boot Core Plus with Openbox Window Manager.
TEXT HELP
Boot Core with openbox plus networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=openbox

LABEL flwm
MENU LABEL Boot Core Plus with FLWM Classic Window Manager.
TEXT HELP
Boot Core with flwm plus networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps desktop=flwm

LABEL tiny
MENU LABEL Boot Core with only X/GUI (TinyCore).
TEXT HELP
Boot Core with flwm_topside. Both user and support extensions are not loaded.
All X/GUI extensions are loaded mount mode. Boot media is not removable.
Use TAB to edit desktop= to boot to alternate window manager.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps lst=xbase.lst base desktop=flwm_topside

LABEL cxi
MENU LABEL Boot Core with X/GUI (TinyCore) + Installation Extension.
TEXT HELP
Boot Core with flwm_topside, X/GUI, and the installation extension.
Extensions are loaded mount mode. Boot media is not removable.
Use TAB to edit desktop= to boot to alternate window manager.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps lst=xibase.lst base desktop=flwm_topside

LABEL cxw
MENU LABEL Boot Core with X/GUI (TinyCore) + Wifi Extension.
TEXT HELP
Boot Core with flwm_topside with X/GUI and the Wifi Extension.
Extensions are loaded mount mode. Boot media is not removable.
Use TAB to edit desktop= to boot to alternate window manager.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps lst=xwbase.lst base desktop=flwm_topside

LABEL cxf
MENU LABEL Boot Core with X/GUI (TinyCore) + Wifi + Firmware.
TEXT HELP
Boot Core with flwm_topside with X/GUI, Wifi, and firmware extensions.
Extensions are loaded mount mode. Boot media is not removable.
Use TAB to edit desktop= to boot to alternate window manager.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 cde showapps lst=xfbase.lst base desktop=flwm_topside

LABEL core
MENU LABEL Boot Core to command line only. No X/GUI or extensions.
TEXT HELP
Boot Core character text mode to ram. No user or support extensions are loaded.
Boot media is removable.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 base

LABEL nocde
MENU LABEL Boot Core without embedded extensions with waitusb=5.
TEXT HELP
Boot Core to base system. No embedded support extensions are loaded. User extensions
scanned or specified will be loaded and will need to provide X/GUI if required.
ENDTEXT
KERNEL /boot/vmlinuz
APPEND initrd=/boot/core.gz loglevel=3 waitusb=5

MENU END

LABEL grub4dos
menu label ^GRUB4DOS 0.4.6a-2020-02-29
kernel /boot/grub.exe
" > ${WORK}/iso/boot/isolinux/isolinux.cfg
$MAKER --no-emul-boot --boot-info-table --boot-load-size 4 \
-b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat -J -r -l \
-o ${DONE}/NetbootCD-$NBCDVER+CorePlus-$COREVER.iso ${WORK}/iso

chown -R 1000.1000 $DONE
isohybrid ${DONE}/NetbootCD-$NBCDVER+CorePlus-$COREVER.iso

ln -s ${DONE}/NetbootCD-$NBCDVER+CorePlus-$COREVER.iso ${DONE}/NetbootCD+CorePlus.iso

rm -r ${WORK}/iso
