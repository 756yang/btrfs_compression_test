
# btrfs_compression_test

简单测试btrfs透明压缩的性能

上传`btrfs_compresion_test.sh`脚本到你的服务器并以root权限运行测试。

请勿传入错误参数以免造成数据损失！

如果测试文本压缩，直接运行命令：

	sudo bash -c "$(wget -qO- https://github.com/756yang/btrfs_compression_test/raw/main/btrfs_compresion_test.sh)"

如果测试系统文件压缩，运行命令：

	wget -qO- https://github.com/756yang/btrfs_compression_test/raw/main/debian9test.tar.xz | xz -dc - | sudo bash -c "$(wget -qO- https://github.com/756yang/btrfs_compression_test/raw/main/btrfs_compresion_test.sh)" @ -

测试时，你随时可以按Ctrl+C终止循环或测试，脚本退出时会自动清理。

经过我测试，通常来说，透明压缩对体积不大的文件读写有优势，会降低固态硬盘上的\
大文件连续读写，因此不建议对大体积且难以压缩的文件开启透明压缩，通常情况下透明\
压缩使用`zstd:1`的算法都有较理想的效果，可以直接用此参数挂载btrfs文件系统。
