#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt
# Function: DIY script (After updating feeds — modify the default IP, hostname, theme, add/remove packages, etc.)
# Source code repository: https://github.com/coolsnowwolf/lede / Branch: master
#========================================================================================================================

# ------------------------------- Main source started -------------------------------
#
# Set default IP address
default_ip="192.168.1.1"
ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
# Modify default IP if an argument is provided and it matches the IP format
[[ -n "${1}" && "${1}" != "${default_ip}" && "${1}" =~ ${ip_regex} ]] && {
    echo "Modify default IP address to: ${1}"
    sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${1}\"}/" package/base-files/*/bin/config_generate
}

# Use the same login defaults as OpenWRT-CI: hostname FWRT and no root password.
sed -i "s/hostname='[^']*'/hostname='FWRT'/g" package/base-files/*/bin/config_generate
sed -i 's|^root:[^:]*:|root::|' package/base-files/files/etc/shadow

# Add autocore support for armsr-armv8
sed -i 's/TARGET_rockchip/TARGET_rockchip\|\|TARGET_armsr/g' package/lean/autocore/Makefile

# Set etc/openwrt_release
sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/lean/default-settings/files/zzz-default-settings
echo "DISTRIB_SOURCEREPO='github.com/coolsnowwolf/lede'" >>package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCECODE='lede'" >>package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCEBRANCH='master'" >>package/base-files/files/etc/openwrt_release

# Set ccache
# Remove existing ccache settings
sed -i '/CONFIG_DEVEL/d' .config
sed -i '/CONFIG_CCACHE/d' .config
# Apply new ccache configuration
if [[ "${2}" == "true" ]]; then
    echo "CONFIG_DEVEL=y" >>.config
    echo "CONFIG_CCACHE=y" >>.config
    echo 'CONFIG_CCACHE_DIR="$(TOPDIR)/.ccache"' >>.config
else
    echo '# CONFIG_DEVEL is not set' >>.config
    echo "# CONFIG_CCACHE is not set" >>.config
    echo 'CONFIG_CCACHE_DIR=""' >>.config
fi
#
# ------------------------------- Main source ends -------------------------------

# Install or update packages from external repositories.
UPDATE_PACKAGE() {
	local package_names="$1"
	local repo="$2"
	local branch="$3"
	local mode="${4:-}"
	local repo_name repo_url clone_dir name path matched
	local -a names

	read -r -a names <<< "$package_names"
	for name in "${names[@]}"; do
		find feeds/luci feeds/packages package -maxdepth 4 -type d \
			\( -name "$name" -o -name "luci-*-$name" \) \
			-prune -exec rm -rf {} + 2>/dev/null || true
	done

	if [[ "$repo" == http* ]]; then
		repo_url="$repo"
	else
		repo_url="https://github.com/$repo.git"
	fi

	repo_name="$(basename "${repo_url%.git}")"
	clone_dir="package/.diy-${repo_name}"
	rm -rf "$clone_dir"
	if ! git clone --depth=1 --single-branch --branch "$branch" "$repo_url" "$clone_dir"; then
		echo "Error: failed to clone $repo_url (branch: $branch)."
		exit 1
	fi

	case "$mode" in
		pkg)
			for name in "${names[@]}"; do
				matched=false
				while IFS= read -r -d '' path; do
					rm -rf "package/$(basename "$path")"
					cp -a "$path" package/
					matched=true
				done < <(find "$clone_dir" -mindepth 1 -maxdepth 4 -type d -name "$name" -prune -print0)

				if [[ "$matched" != "true" ]]; then
					echo "Error: package '$name' was not found in $repo_url."
					rm -rf "$clone_dir"
					exit 1
				fi
			done
			rm -rf "$clone_dir"
			;;
		name)
			rm -rf "package/$package_names"
			mv "$clone_dir" "package/$package_names"
			;;
		"")
			rm -rf "package/$repo_name"
			mv "$clone_dir" "package/$repo_name"
			;;
		*)
			echo "Error: unsupported package mode '$mode'."
			rm -rf "$clone_dir"
			exit 1
			;;
	esac
}

UPDATE_PACKAGE "luci-app-amlogic" "ophub/luci-app-amlogic" "main"
UPDATE_PACKAGE "luci-app-poweroff" "esirplayground/luci-app-poweroff" "main"
UPDATE_PACKAGE "luci-theme-shadcn" "ysuolmai/luci-theme-shadcn" "main"
UPDATE_PACKAGE "ddns-go luci-app-ddns-go" "sirpdboy/luci-app-ddns-go" "main" "pkg"
UPDATE_PACKAGE "openlist2 luci-app-openlist2" "sbwml/luci-app-openlist2" "main" "pkg"
UPDATE_PACKAGE "xray-core dns2socks geoview \
        chinadns-ng ipt2socks tcping frp luci-app-passwall \
        luci-app-vlmcsd vlmcsd" \
        "kenzok8/jell" "main" "pkg"

# tcping's upstream Makefile otherwise uses the x86_64 host strip on AArch64 output.
sed -i 's/CC="$(TARGET_CC)" CFLAGS=/CC="$(TARGET_CC)" STRIP="$(TARGET_CROSS)strip" CFLAGS=/' package/tcping/Makefile

# The lightweight FRP package skips the Node.js web build; restore its OpenWrt service files.
if ! grep -q 'files/$(2).init' package/frp/Makefile; then
    sed -i '/$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)\/$(2) $(1)\/usr\/bin\//a \
\	$(INSTALL_DIR) $(1)/etc/init.d/\
\	$(INSTALL_BIN) ./files/$(2).init $(1)/etc/init.d/$(2)\
\	$(INSTALL_DIR) $(1)/etc/config/\
\	$(INSTALL_CONF) ./files/$(2).config $(1)/etc/config/$(2)' package/frp/Makefile
fi
for init_file in package/frp/files/frpc.init package/frp/files/frps.init; do
    if [[ -f "$init_file" ]] && ! grep -q 'mkdir -p /var/etc' "$init_file"; then
        sed -i '/local conf_file="\/var\/etc\/$NAME.ini"/a \	mkdir -p /var/etc' "$init_file"
    fi
done
for config_file in package/frp/files/frpc.config package/frp/files/frps.config; do
    [[ -f "$config_file" ]] || continue
    sed -i 's/option user frpc/option user root/g; s/option group frpc/option group root/g; s/option user frps/option user root/g; s/option group frps/option group root/g' "$config_file"
done
UPDATE_PACKAGE "luci-app-netspeedtest speedtest-cli" "sbwml/openwrt_pkgs" "main" "pkg"
UPDATE_PACKAGE "luci-app-adguardhome" "ysuolmai/luci-app-adguardhome" "master"
UPDATE_PACKAGE "luci-app-quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "luci-app-diskman" "lisaac/luci-app-diskman" "master" "pkg"

keywords_to_delete=(
    "uugamebooster" "luci-app-wol" "luci-i18n-wol-zh-cn"
    "CONFIG_TARGET_INITRAMFS" "ddns" "luci-app-advancedplus"
    "luci-app-ssr-plus" "luci-i18n-ssr-plus"
    "luci-app-passwall2" "luci-i18n-passwall2"
    "luci-app-openclash" "mihomo" "nikki" "smartdns"
    "kucat" "bootstrap" "material" "argon"
)

for keyword in "${keywords_to_delete[@]}"; do
    sed -i "/$keyword/d" ./.config
done

sed -i \
    -e '/^CONFIG_USE_APK=/d' \
    -e '/^# CONFIG_USE_APK is not set$/d' \
    -e '/^CONFIG_PACKAGE_apk-/d' \
    -e '/^# CONFIG_PACKAGE_apk-/d' \
    -e '/^CONFIG_PACKAGE_opkg=/d' \
    -e '/^# CONFIG_PACKAGE_opkg is not set$/d' \
    .config

# Configuration lines to append to .config
provided_config_lines=(
    "CONFIG_PACKAGE_luci-app-zerotier=y"
    "CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-adguardhome=y"
    "CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-poweroff=y"
    "CONFIG_PACKAGE_luci-i18n-poweroff-zh-cn=y"
    "CONFIG_PACKAGE_cpufreq=y"
    "CONFIG_PACKAGE_luci-app-cpufreq=y"
    "CONFIG_PACKAGE_luci-i18n-cpufreq-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-ttyd=y"
    "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y"
    "CONFIG_PACKAGE_ttyd=y"
    "CONFIG_PACKAGE_luci-app-ddns-go=y"
    "CONFIG_PACKAGE_luci-i18n-ddns-go-zh-cn=y"
    "CONFIG_PACKAGE_luci-theme-shadcn=y"
    "CONFIG_PACKAGE_nano=y"
    "CONFIG_BUSYBOX_CONFIG_LSUSB=n"
    "CONFIG_PACKAGE_luci-app-netspeedtest=y"
    "CONFIG_PACKAGE_luci-app-vlmcsd=y"
    "CONFIG_COREMARK_OPTIMIZE_O3=y"
    "CONFIG_COREMARK_ENABLE_MULTITHREADING=y"
    "CONFIG_COREMARK_NUMBER_OF_THREADS=6"
    "CONFIG_PACKAGE_luci-app-filetransfer=y"
    "CONFIG_PACKAGE_openssh-sftp-server=y"
    "CONFIG_PACKAGE_luci-app-frpc=y"
    "CONFIG_OPKG_USE_CURL=y"
    "CONFIG_PACKAGE_opkg=y"
    "# CONFIG_USE_APK is not set"
    "CONFIG_PACKAGE_luci-app-diskman=y"
    "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-docker=m"
    "CONFIG_PACKAGE_luci-i18n-docker-zh-cn=m"
    "CONFIG_PACKAGE_luci-app-dockerman=m"
    "CONFIG_PACKAGE_luci-i18n-dockerman-zh-cn=m"
    "CONFIG_PACKAGE_luci-app-openlist2=y"
    "CONFIG_PACKAGE_luci-i18n-openlist2-zh-cn=y"
    "CONFIG_PACKAGE_fdisk=y"
    "CONFIG_PACKAGE_parted=y"
    "CONFIG_PACKAGE_iptables-mod-extra=y"
    "CONFIG_PACKAGE_ip6tables-nft=y"
    "CONFIG_PACKAGE_ip6tables-mod-fullconenat=y"
    "CONFIG_PACKAGE_iptables-mod-fullconenat=y"
    "CONFIG_PACKAGE_libip4tc=y"
    "CONFIG_PACKAGE_libip6tc=y"
    "CONFIG_PACKAGE_luci-app-passwall=y"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview=y"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Haproxy=y"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y"
    "CONFIG_PACKAGE_htop=y"
    "CONFIG_PACKAGE_fuse-utils=y"
    "CONFIG_PACKAGE_tcpdump=y"
    "CONFIG_PACKAGE_sgdisk=y"
    "CONFIG_PACKAGE_openssl-util=y"
    "CONFIG_PACKAGE_resize2fs=y"
    "CONFIG_PACKAGE_qrencode=y"
    "CONFIG_PACKAGE_smartmontools-drivedb=y"
    "CONFIG_PACKAGE_usbutils=y"
    "CONFIG_PACKAGE_default-settings=y"
    "CONFIG_PACKAGE_default-settings-chn=y"
    "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y"
    "CONFIG_PACKAGE_kmod-br-netfilter=y"
    "CONFIG_PACKAGE_kmod-ip6tables=y"
    "CONFIG_PACKAGE_kmod-ipt-conntrack=y"
    "CONFIG_PACKAGE_kmod-ipt-extra=y"
    "CONFIG_PACKAGE_kmod-ipt-nat=y"
    "CONFIG_PACKAGE_kmod-ipt-nat6=y"
    "CONFIG_PACKAGE_kmod-ipt-physdev=y"
    "CONFIG_PACKAGE_kmod-nf-ipt6=y"
    "CONFIG_PACKAGE_kmod-nf-ipvs=y"
    "CONFIG_PACKAGE_kmod-nf-nat6=y"
    "CONFIG_PACKAGE_kmod-dummy=y"
    "CONFIG_PACKAGE_kmod-veth=y"
    "CONFIG_PACKAGE_automount=y"
    "CONFIG_PACKAGE_luci-app-frps=y"
    "CONFIG_PACKAGE_luci-app-samba4=y"
    "CONFIG_PACKAGE_luci-app-quickfile=y"
)

# Append configuration lines to .config
for line in "${provided_config_lines[@]}"; do
    echo "$line" >> .config
done

find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-[^[:space:]]*/luci-theme-shadcn/g" {} +
find ./feeds/luci/ -type f -name "Makefile" -exec sed -i "s/luci-theme-[^[:space:]]*/luci-theme-shadcn/g" {} \;

# Apply persistent UI and login defaults.
install -Dm755 "${GITHUB_WORKSPACE}/diypatch/99_ttyd-nopass.sh" "package/base-files/files/etc/uci-defaults/99_ttyd-nopass"
install -Dm755 "${GITHUB_WORKSPACE}/diypatch/99_set_shadcn_theme.sh" "package/base-files/files/etc/uci-defaults/99_set_shadcn_theme"
install -Dm755 "${GITHUB_WORKSPACE}/diypatch/99_dropbear_setup.sh" "package/base-files/files/etc/uci-defaults/99_dropbear_setup"
