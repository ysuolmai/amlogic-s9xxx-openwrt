

#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt
# Function: Diy script (After Update feeds, Modify the default IP, hostname, theme, add/remove software packages, etc.)
# Source code repository: https://github.com/immortalwrt/immortalwrt / Branch: master
#========================================================================================================================

# ------------------------------- Main source started -------------------------------
#
# Add the default password for the 'root' user（Change the empty password to 'password'）
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# Set etc/openwrt_release
sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCECODE='immortalwrt'" >>package/base-files/files/etc/openwrt_release

# Modify default IP（FROM 192.168.1.1 CHANGE TO 192.168.31.4）
# sed -i 's/192.168.1.1/192.168.31.4/g' package/base-files/files/bin/config_generate
#
# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# Add luci-app-amlogic
rm -rf package/luci-app-amlogic
git clone https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic


git clone --depth=1 https://github.com/fw876/helloworld.git package/helloworld
git clone https://github.com/sirpdboy/luci-app-ddns-go.git package/ddns-go
git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome package/luci-app-adguardhome
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff
git clone --depth=1 https://github.com/VIKINGYFY/homeproxy package/homeproxy
#DDNS-go
git clone https://github.com/sirpdboy/luci-app-ddns-go.git package/ddns-go

#luci-app-zerotier
git clone https://github.com/rufengsuixing/luci-app-zerotier.git package/luci-app-zerotier

provided_config_lines=(
#"CONFIG_PACKAGE_luci-app-ssr-plus=y"
#"CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn=y"
"CONFIG_PACKAGE_luci-app-zerotier=y"
"CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y"
"CONFIG_PACKAGE_luci-app-adguardhome=y"
"CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn=y"
"CONFIG_PACKAGE_luci-app-ddns-go=y"
"CONFIG_PACKAGE_luci-i18n-ddns-go-zh-cn=y"
"CONFIG_PACKAGE_luci-app-poweroff=y"
"CONFIG_PACKAGE_luci-i18n-poweroff-zh-cn=y"
"CONFIG_PACKAGE_cpufreq=y"
"CONFIG_PACKAGE_luci-app-cpufreq=y"
"CONFIG_PACKAGE_luci-i18n-cpufreq-zh-cn=y"
"CONFIG_PACKAGE_luci-app-ttyd=y"
"CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y"
"CONFIG_PACKAGE_ttyd=y"
"CONFIG_TARGET_INITRAMFS=n"
#"CONFIG_PACKAGE_luci-app-passwall=y"
#"CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y"
"CONFIG_PACKAGE_luci-app-homeproxy=y"
"CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y"
)

#if [[ $FIRMWARE_TAG != *"NOWIFI"* ]]; then
#  	provided_config_lines+=("CONFIG_PACKAGE_luci-app-diskman=y")
#  	provided_config_lines+=("CONFIG_PACKAGE_luci-i18n-luci-app-diskman=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-app-docker=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-i18n-docker-zh-cn=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-app-dockerman=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-i18n-dockerman-zh-cn=y")
#fi

# Path to the .config file
config_file_path=".config" 

# Append lines to the .config file
for line in "${provided_config_lines[@]}"; do
    echo "$line" >> "$config_file_path"
done
provided_config_lines=(
#"CONFIG_PACKAGE_luci-app-ssr-plus=y"
#"CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn=y"
"CONFIG_PACKAGE_luci-app-zerotier=y"
"CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y"
"CONFIG_PACKAGE_luci-app-adguardhome=y"
"CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn=y"
"CONFIG_PACKAGE_luci-app-ddns-go=y"
"CONFIG_PACKAGE_luci-i18n-ddns-go-zh-cn=y"
"CONFIG_PACKAGE_luci-app-poweroff=y"
"CONFIG_PACKAGE_luci-i18n-poweroff-zh-cn=y"
"CONFIG_PACKAGE_cpufreq=y"
"CONFIG_PACKAGE_luci-app-cpufreq=y"
"CONFIG_PACKAGE_luci-i18n-cpufreq-zh-cn=y"
"CONFIG_PACKAGE_luci-app-ttyd=y"
"CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y"
"CONFIG_PACKAGE_ttyd=y"
"CONFIG_TARGET_INITRAMFS=n"
#"CONFIG_PACKAGE_luci-app-passwall=y"
#"CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y"
"CONFIG_PACKAGE_luci-app-homeproxy=y"
"CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y"
)

#if [[ $FIRMWARE_TAG != *"NOWIFI"* ]]; then
#  	provided_config_lines+=("CONFIG_PACKAGE_luci-app-diskman=y")
#  	provided_config_lines+=("CONFIG_PACKAGE_luci-i18n-luci-app-diskman=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-app-docker=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-i18n-docker-zh-cn=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-app-dockerman=y")
#    provided_config_lines+=("CONFIG_PACKAGE_luci-i18n-dockerman-zh-cn=y")
#fi

# Path to the .config file
config_file_path=".config" 

# Append lines to the .config file
for line in "${provided_config_lines[@]}"; do
    echo "$line" >> "$config_file_path"
done


PKG_PATCH="$GITHUB_WORKSPACE/wrt/package/"

#预置HomeProxy数据
if [ -d *"homeproxy"* ]; then
	HP_RULES="surge"
	HP_PATCH="homeproxy/root/etc/homeproxy"

	chmod +x ./$HP_PATCH/scripts/*
	rm -rf ./$HP_PATCH/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULES/
	cd ./$HP_RULES/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATCH/resources/

	cd .. && rm -rf ./$HP_RULES/

	cd $PKG_PATCH && echo "homeproxy date has been updated!"
fi
./scripts/feeds update -a
./scripts/feeds install -a

#
# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------

