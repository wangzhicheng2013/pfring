#!/bin/bash
LOG_DIR=/home/webdefender/log
LOG_FILE=/home/webdefender/log/update.log  #监测审计升级日志文件
NIC_DIVERS=("e1000e" "igb" "ixgbevf" "ixgbe" "fm10k" "i40e")	#pfring7.8.0支持的网卡驱动类型
ADMIN_NAME=eth0	#管理口名称
UP_TMP=/home/wdd/release/tmp
PFRING_KERNEL_DIR=$UP_TMP/pf_ring/kernel
PFRING_LIBPCAP_DIR=$UP_TMP/pf_ring/libpcap
PFRING_DRIVERS_DIR=$UP_TMP/pf_ring/drivers
PF_RING_INSTALLED_OK=0
#step1:创建相关目录
mkdir -p $LOG_DIR
mkdir -p $UP_TMP
#step2:解压pfring
echo "[`date +%Y-%m-%d' '%H:%M:%S`] <<<<<<<<<<<<<<<<<<<< start to install pfring >>>>>>>>>>>>>>>>>>>>" >> $LOG_FILE
unzip -o pf_ring.zip
cd ./pf_ring
#step3:检查pfring是否已安装
cat /proc/net/pf_ring/info | grep 'PF_RING'
if [ $? -eq 0 ] ;then
	echo "pfring kernel has been installed...!" >> $LOG_FILE
	exit 1 
fi
#step4:检查网卡驱动
echo "start to check NIC driver for pfring..." >> $LOG_FILE
diver_name=`ethtool -i $ADMIN_NAME | grep driver |  awk -F ": " '{print $2}'`
echo 'NIC diver name:'$diver_name >> $LOG_FILE
if [ ! $diver_name ];then
	echo "driver name is null...!" >> $LOG_FILE
	exit 1
fi
lsmod | grep $diver_name
if [ $? -ne 0 ] ;then
    echo $diver_name" does not exist...!" >> $LOG_FILE
    exit 1 
fi
found=0
for (( i = 0; i < ${#NIC_DIVERS[@]}; i++ ))
do
	if [ ${NIC_DIVERS[$i]} == $diver_name ];then
		found=1
		break
	fi
done
if [ $found -eq 0 ];then
	echo $diver_name" can not be supported by pfring...!" >> $LOG_FILE
	exit 1
fi
echo 'check NIC diver ok.' >> $LOG_FILE
#step5:卸载网卡驱动
echo "start to remove current NIC driver for pfring..." >> $LOG_FILE
rmmod $diver_name
if [ $? -ne 0 ] ;then
	echo "remove NIC driver failed...!" >> $LOG_FILE
	exit 1 
fi
echo "remove NIC driver ok." >> $LOG_FILE
#step6:安装内核
cd $PFRING_KERNEL_DIR
make install
if [ $? -ne 0 ] ;then
	echo "make install pfring kernel failed...!" >> $LOG_FILE
	exit 1 
fi
insmod pf_ring.ko transparent_mode=1 >> $LOG_FILE 2>&1
cat /proc/net/pf_ring/info | grep 'PF_RING'
if [ $? -ne 0 ] ;then
	echo "pfring kernel install failed...!" >> $LOG_FILE
	exit 1 
fi
#step7:安装libpcap
cd $PFRING_LIBPCAP_DIR
rpm -qa libpcap #卸载libpcap包，执行该命令后，系统的/usr/lib64/libpcap.so*会被删除
rpm -e libpcap --nodeps > /dev/null  2>&1 #--nodeps不验证依赖包 -e直接卸载
\cp -rf ./include/* /usr/local/include/
\cp -rf ./lib/* /usr/local/lib/
if [ $? -ne 0 ] ;then
	echo "copy for pfring lib failed...!" >> $LOG_FILE
	cd $UP_TMP
	exit 1 
fi
#step8:安装网卡驱动
cd $PFRING_DRIVERS_DIR
modprobe ptp
insmod $diver_name.ko  >> $LOG_FILE 2>&1
modprobe $diver_name   >> $LOG_FILE 2>&1
sleep 5 #尝试2次
insmod $diver_name.ko  >> $LOG_FILE 2>&1
modprobe $diver_name   >> $LOG_FILE 2>&1
if [ $? -ne 0 ] ;then
	echo "pfring driver install failed...!" >> $LOG_FILE
	cd $UP_TMP
	exit 1 
fi
cd $UP_TMP
echo "[`date +%Y-%m-%d' '%H:%M:%S`] <<<<<<<<<<<<<<<<<<<< pfring install ok. >>>>>>>>>>>>>>>>>>>>" >> $LOG_FILE
PF_RING_INSTALLED_OK=1