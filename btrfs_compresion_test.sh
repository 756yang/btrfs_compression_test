#!/bin/bash

# btrfs测试压缩性能
# 尝试用测试tar文件在磁盘设备/dev/sdaN进行btrfs性能测试
# ./btrfs_compression_test.sh [device] [tar_file] [disk_size]
# 若不指定device，则尝试在文件系统上创建512M磁盘镜像用作测试
# 若不指定tar_file，则下载glibc源码用作测试文件
# 压缩性能：先将测试文件解压到内存，并设置好btrfs压缩参数，复制到btrfs磁盘中
# 解压性能：从已压缩的btrfs磁盘中复制文件到内存中
# 使用的内存文件系统是/dev/shm目录

function _info {
    echo -e "[\e[33mINFO\e[0m]" "$@"
}
function _ok {
    echo -e "[\e[32m OK \e[0m]" "$@"
}
function _erro {
    echo -e "[\e[31mERRO\e[0m]" "$@" 1>&2
}

[ "$*" = "-h" ] && {
	echo './btrfs_compression_test.sh [devices] [tar_file] [disk_size] -<number>
    -h              display this help
    [device]        test disk device or disk img file
    [tar_file]      test tar file(.tar .tar.gz .tgz) or directory,
    [disk_size]     the disk img file size in MB
    -<number>       test file copy multiple times'
	exit
}

[ $# -gt 3 ] && {
	_erro "the arguments is too many!"
	exit 2
}

[ $(id -u) -ne 0 ] && _erro "Please run as root!" && exit 1

checkcmd_install="$(wget -qO- https://github.com/756yang/shell_common/raw/main/checkcmd_install.sh)"

# 检查需要的命令
bash -c "$checkcmd_install" @ tar wget gzip btrfs compsize
[ $? -ne 0 ] && exit 1

function test_cleanup {
	umount $disk_dev
	[[ "$disk_dev" =~ "loop" ]] && losetup -d $disk_dev
	! [ -b "$disk_file" ] && rm "$disk_file"
	rm -rf "$TEMP_DIR" "$TEMP_MOUNT"
	exit "${*:-130}"
}
trap test_cleanup SIGINT

# 参数处理
TEMP_DIR=/dev/shm/TEST_BTRFS
TEMP_MOUNT=/dev/shm/MOUNT_BTRFS
mkdir "$TEMP_DIR" "$TEMP_MOUNT"
disk_file="disk_btrfs.img"
disk_size=512
multi_copy=1
while [ $# -gt 0 ]; do
	if [ "$1" -ge 0 ] &>/dev/null; then
		disk_size="$1"
	elif [ "$1" -lt 0 ] &>/dev/null; then
		multi_copy=$((-$1))
	elif [ -d "$1" ]; then
		cp -af "$1/." "$TEMP_DIR"
	elif [ "$1" = "-" -o ${1##*.} = tar ]; then
		tar -xf "$1" -C "$TEMP_DIR"
	elif [ ${1##*.} = tgz -o "${1: -7}" = ".tar.gz" ]; then
		tar -xzf "$1" -C "$TEMP_DIR"
	else
		! [ -b "$1" ] && ! [ -d "$(dirname "$1")" ] && {
			_erro "$1 is not a file path!"
			exit 2
		}
		disk_file="$1"
	fi
	shift
done
[ -z "$(ls -A "$TEMP_DIR")" ] && {
	wget -qO- "http://ftp.gnu.org/gnu/glibc/glibc-2.36.tar.gz" | tar -xzf - -C "$TEMP_DIR"
}
[ $multi_copy -gt 1 ] && {
	mv "$TEMP_DIR"/{.,}* "$TEMP_MOUNT" &>/dev/null
	for ((i=1;i<$multi_copy;i++)); do
		cp -af "$TEMP_MOUNT" "$TEMP_DIR/test$i"
	done
	mv "$TEMP_MOUNT" "$TEMP_DIR/test$multi_copy" && mkdir "$TEMP_MOUNT"
}

[ -b "$disk_file" ] && disk_dev="$disk_file" || { # 建立文件映像并关联loop设备
	dd if=/dev/zero "of=$disk_file" bs=1M count=$disk_size status=progress || exit 2
	disk_dev=$(losetup -f)
	losetup $disk_dev "$disk_file"
}

lsmod | grep btrfs &>/dev/null || modprobe btrfs
mkfs.btrfs $disk_dev || exit 1

function test_compression {
	# 测量压缩耗时
	[ "$(ls -A "$TEMP_MOUNT")" ] && rm -rf "$TEMP_MOUNT"/{.,}* &>/dev/null
	sync && echo 1 > /proc/sys/vm/drop_caches
	(time (cp -af "$TEMP_DIR/." "$TEMP_MOUNT";sync)) 2>&1 | grep real | awk '{
	print "compressed time " $2*60+substr($2,index($2,"m")+1)}'
	# 测量压缩率
	compsize -x "$TEMP_MOUNT" | grep TOTAL | awk '{print "compression ratio " $2}'
	#测量解压耗时
	rm -rf "$TEMP_DIR"/{.,}* &>/dev/null
	sync && echo 1 > /proc/sys/vm/drop_caches
	(time cp -af "$TEMP_MOUNT/." "$TEMP_DIR") 2>&1 | grep real | awk '{
	print "decompressed time " $2*60+substr($2,index($2,"m")+1)}'
	[ "$(ls -A "$TEMP_MOUNT")" ] && rm -rf "$TEMP_MOUNT"/{.,}* &>/dev/null
}

mount -t btrfs $disk_dev "$TEMP_MOUNT"
test_result=$(test_compression)
origin_write=$(echo "$test_result" | grep -w compressed | awk '{print $3}')
origin_ratio=$(echo "$test_result" | grep -w compression | awk '{print $3+0}')
origin_read=$(echo "$test_result" | grep -w decompressed | awk '{print $3}')

trap break SIGINT
echo && _info "Testing compression for 'zlib'"
echo " Level | Time (compress) | Compression ratio | Time (decompress)"
echo "-------+-----------------+-------------------+-------------------"
printf "  none | %14.3fs | %16.3f%% | %16.3fs\n" $origin_write $origin_ratio $origin_read
for ((i=0;i<=9;i++)); do
	umount $disk_dev
	mount -t btrfs -o compress=zlib:$i $disk_dev "$TEMP_MOUNT"
	test_result=$(test_compression)
	test_write=$(echo "$test_result" | grep -w compressed | awk '{print $3}')
	test_ratio=$(echo "$test_result" | grep -w compression | awk '{print $3+0}')
	test_read=$(echo "$test_result" | grep -w decompressed | awk '{print $3}')
	printf " %5d | %14.3fs | %16.3f%% | %16.3fs\n" $i $test_write $test_ratio $test_read
done

echo && _info "Testing compression for 'zstd'"
echo " Level | Time (compress) | Compression ratio | Time (decompress)"
echo "-------+-----------------+-------------------+-------------------"
printf "  none | %14.3fs | %16.3f%% | %16.3fs\n" $origin_write $origin_ratio $origin_read
for ((i=0;i<=15;i++)); do
	umount $disk_dev
	mount -t btrfs -o compress=zstd:$i $disk_dev "$TEMP_MOUNT"
	test_result=$(test_compression)
	test_write=$(echo "$test_result" | grep -w compressed | awk '{print $3}')
	test_ratio=$(echo "$test_result" | grep -w compression | awk '{print $3+0}')
	test_read=$(echo "$test_result" | grep -w decompressed | awk '{print $3}')
	printf " %5d | %14.3fs | %16.3f%% | %16.3fs\n" $i $test_write $test_ratio $test_read
done

echo && _info "Testing compression for 'lzo'"
echo " Level | Time (compress) | Compression ratio | Time (decompress)"
echo "-------+-----------------+-------------------+-------------------"
printf "  none | %14.3fs | %16.3f%% | %16.3fs\n" $origin_write $origin_ratio $origin_read
for ((i=0;i<=0;i++)); do
	umount $disk_dev
	mount -t btrfs -o compress=lzo:$i $disk_dev "$TEMP_MOUNT"
	test_result=$(test_compression)
	test_write=$(echo "$test_result" | grep -w compressed | awk '{print $3}')
	test_ratio=$(echo "$test_result" | grep -w compression | awk '{print $3+0}')
	test_read=$(echo "$test_result" | grep -w decompressed | awk '{print $3}')
	printf " %5d | %14.3fs | %16.3f%% | %16.3fs\n" $i $test_write $test_ratio $test_read
done

echo && _ok "Test complete!" && test_cleanup 0
