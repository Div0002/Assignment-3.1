#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
KERNEL_TARBALL=https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-5.15.163.tar.xz
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath "$(dirname "$0")")
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

OUTDIR=$(realpath "${OUTDIR}")
mkdir -p "${OUTDIR}"

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "DOWNLOADING AND EXTRACTING LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    wget -O linux.tar.xz "${KERNEL_TARBALL}"
    tar -xf linux.tar.xz
    mv "linux-5.15.163" linux-stable
fi

if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    cd linux-stable
    echo "Preparing kernel version ${KERNEL_VERSION}"

    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" mrproper
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
    make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" all
fi

echo "Adding the Image in outdir"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/Image"

echo "Creating the staging directory for the root filesystem"
cd "${OUTDIR}"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf "${OUTDIR}/rootfs"
fi

mkdir -p "${OUTDIR}/rootfs"
mkdir -p "${OUTDIR}/rootfs/bin"
mkdir -p "${OUTDIR}/rootfs/dev"
mkdir -p "${OUTDIR}/rootfs/etc"
mkdir -p "${OUTDIR}/rootfs/home"
mkdir -p "${OUTDIR}/rootfs/lib"
mkdir -p "${OUTDIR}/rootfs/lib64"
mkdir -p "${OUTDIR}/rootfs/proc"
mkdir -p "${OUTDIR}/rootfs/sbin"
mkdir -p "${OUTDIR}/rootfs/sys"
mkdir -p "${OUTDIR}/rootfs/tmp"
mkdir -p "${OUTDIR}/rootfs/usr"
mkdir -p "${OUTDIR}/rootfs/usr/bin"
mkdir -p "${OUTDIR}/rootfs/usr/lib"
mkdir -p "${OUTDIR}/rootfs/usr/sbin"
mkdir -p "${OUTDIR}/rootfs/var"
mkdir -p "${OUTDIR}/rootfs/var/log"

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]
then
    git clone https://git.busybox.net/busybox --depth 1 --branch "${BUSYBOX_VERSION}" busybox
fi

cd busybox
git checkout "${BUSYBOX_VERSION}"

yes "" | make distclean
yes "" | make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
yes "" | make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" oldconfig

make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}"
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" CONFIG_PREFIX="${OUTDIR}/rootfs" install

echo "Library dependencies"
if [ -x "${OUTDIR}/rootfs/bin/busybox" ]; then
    ${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "program interpreter" || true
    ${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "Shared library" || true
fi

LIBC_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libc.so.6)
LIBM_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libm.so.6)
LIBRESOLV_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libresolv.so.2)
LDLINUX_PATH=$(${CROSS_COMPILE}gcc -print-file-name=ld-linux-aarch64.so.1)
LIBGCCS_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libgcc_s.so.1)

cp -L "${LIBC_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true
cp -L "${LIBM_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true
cp -L "${LIBRESOLV_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true
cp -L "${LDLINUX_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true
cp -L "${LIBGCCS_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true

sudo mknod -m 666 "${OUTDIR}/rootfs/dev/null" c 1 3
sudo mknod -m 600 "${OUTDIR}/rootfs/dev/console" c 5 1

cat > "${OUTDIR}/rootfs/init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
echo "Starting shell"
/bin/sh
EOF

chmod +x "${OUTDIR}/rootfs/init"

make -C "${FINDER_APP_DIR}" clean
${CROSS_COMPILE}gcc -static -Wall -Werror -o "${FINDER_APP_DIR}/writer" "${FINDER_APP_DIR}/writer.c"

cp "${FINDER_APP_DIR}/writer" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder-test.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/autorun-qemu.sh" "${OUTDIR}/rootfs/home/"

mkdir -p "${OUTDIR}/rootfs/home/conf"
cp "${FINDER_APP_DIR}/../conf/username.txt" "${OUTDIR}/rootfs/home/conf/"
cp "${FINDER_APP_DIR}/../conf/assignment.txt" "${OUTDIR}/rootfs/home/conf/"

sed -i 's#../conf/assignment.txt#conf/assignment.txt#g' "${OUTDIR}/rootfs/home/finder-test.sh"

chmod +x "${OUTDIR}/rootfs/home/finder.sh"
chmod +x "${OUTDIR}/rootfs/home/finder-test.sh"
chmod +x "${OUTDIR}/rootfs/home/autorun-qemu.sh"

sudo chown -R root:root "${OUTDIR}/rootfs"

cd "${OUTDIR}/rootfs"
find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"