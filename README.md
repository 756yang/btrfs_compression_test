
# btrfs_compression_test

简单测试btrfs透明压缩的性能

上传`btrfs_compresion_test.sh`脚本到你的服务器并以root权限运行测试。

请勿传入错误参数以免造成数据损失！

如果测试文本压缩，直接运行命令：

	sudo bash -c "$(wget -qO- https://github.com/756yang/btrfs_compression_test/raw/main/btrfs_compresion_test.sh)"

如果测试系统文件压缩，运行命令：

	wget -qO- https://github.com/756yang/btrfs_compression_test/raw/main/debian9test.tar.xz | xz -dc - | sudo bash -c "$(wget -qO- https://github.com/756yang/btrfs_compression_test/raw/main/btrfs_compresion_test.sh)" @ -

测试时，你随时可以按Ctrl+C终止循环或测试，脚本退出时会自动清理。
