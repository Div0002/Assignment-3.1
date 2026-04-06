#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=${1:-/tmp/aeld}
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
FINDER_APP_DIR=$(realpath "$(dirname "$0")")

echo "Using output directory: ${OUTDIR}"
mkdir -p "${OUTDIR}"

##############################
# Clone and build Linux kernel
##############################

cd "${OUTDIR}"

if [ ! -d linux-stable ]
then
    echo "Cloning Linux kernel"
    git clone "${KERNEL_REPO}" --depth 1 --branch "${KERNEL_VERSION}"
fi

cd linux-stable
git checkout "${KERNEL_VERSION}"

make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" mrproper
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" all

cp "arch/${ARCH}/boot/Image" "${OUTDIR}/Image"

##############################
# Create root filesystem
##############################

echo "Creating rootfs"
mkdir -p "${OUTDIR}/rootfs"

cd "${OUTDIR}/rootfs"

mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin var/log

##############################
# BusyBox
##############################

cd "${OUTDIR}"

if [ ! -d busybox ]
then
    echo "Cloning BusyBox"
    git clone https://git.busybox.net/busybox --depth 1 --branch "${BUSYBOX_VERSION}" busybox
fi

cd busybox
git checkout "${BUSYBOX_VERSION}"

make distclean
yes "" | make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
yes "" | make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" oldconfig
make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}"
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" install

##############################
# Library dependencies
##############################

echo "Adding library dependencies"

LIBC_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libc.so.6)
LIBM_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libm.so.6)
LIBRESOLV_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libresolv.so.2)
LDLINUX_PATH=$(${CROSS_COMPILE}gcc -print-file-name=ld-linux-aarch64.so.1)
LIBGCCS_PATH=$(${CROSS_COMPILE}gcc -print-file-name=libgcc_s.so.1)

cp -L "${LIBC_PATH}" "${OUTDIR}/rootfs/lib/"
cp -L "${LIBM_PATH}" "${OUTDIR}/rootfs/lib/"
cp -L "${LIBRESOLV_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true
cp -L "${LDLINUX_PATH}" "${OUTDIR}/rootfs/lib/"
cp -L "${LIBGCCS_PATH}" "${OUTDIR}/rootfs/lib/" 2>/dev/null || true

##############################
# Device nodes
##############################

cd "${OUTDIR}/rootfs/dev"

sudo mknod -m 666 null c 1 3
sudo mknod -m 600 console c 5 1

##############################
# Init script
##############################

cd "${OUTDIR}/rootfs"

cat > init << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

echo "Starting shell"
/bin/sh
EOF

chmod +x init

##############################
# Build writer
##############################

make -C "${FINDER_APP_DIR}" clean
make -C "${FINDER_APP_DIR}" CROSS_COMPILE="${CROSS_COMPILE}"

##############################
# Finder app
##############################

echo "Adding finder app"

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

##############################
# Ownership
##############################

sudo chown -R root:root "${OUTDIR}/rootfs"

##############################
# Create initramfs
##############################

cd "${OUTDIR}/rootfs"

find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"

echo "Build complete"
echo "Kernel: ${OUTDIR}/Image"
echo "Initramfs: ${OUTDIR}/initramfs.cpio.gz"