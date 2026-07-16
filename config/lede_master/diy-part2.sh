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

# vlmcsd-svn1113's GNUmakefile conflicts with OpenWrt's ccache compiler wrapper:
# it can pass multiple sources to one "-c -o" command. Use the real compiler
# and serialize this package, matching the fix maintained in openwrt-ci2.
VLMCSD_MK="$(find package/ -path "*/vlmcsd/Makefile" | head -n 1)"
if [[ -f "$VLMCSD_MK" ]]; then
    echo ">>> Patching vlmcsd build: $VLMCSD_MK"
    python3 - "$VLMCSD_MK" <<'PYEOF'
import re
import sys

mk_path = sys.argv[1]
with open(mk_path, encoding="utf-8") as makefile:
    content = makefile.read()

content = re.sub(r'\ndefine Build/Compile\n.*?endef\n', '\n', content, flags=re.DOTALL)
new_compile = r'''
define Build/Compile
	$(MAKE) -j1 -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC_NOCACHE)" \
		CXX="$(TARGET_CXX_NOCACHE)" \
		AR="$(TARGET_AR)" \
		RANLIB="$(TARGET_RANLIB)" \
		STRIP="$(STRIP)" \
		AS="$(TARGET_CROSS)as" \
		LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		CROSS="$(TARGET_CROSS)" \
		ARCH="$(ARCH)" \
		-e
endef
'''
content, replacements = re.subn(
    r'(\$\(eval\s+\$\(call\s+BuildPackage)',
    new_compile + r'\1',
    content,
    count=1,
)
if replacements != 1:
    raise SystemExit("Could not locate vlmcsd BuildPackage declaration")

with open(mk_path, "w", encoding="utf-8") as makefile:
    makefile.write(content)
print(f">>> Patched OK: {mk_path}")
PYEOF
else
    echo "Error: vlmcsd Makefile not found after package update."
    exit 1
fi
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
# Keep diskman's frontend and parted backend aligned with the maintained source.
find feeds/luci feeds/packages package -maxdepth 4 -type d -name parted -prune -exec rm -rf {} + 2>/dev/null || true
mkdir -p package/parted
curl -fsSL https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/Parted.Makefile \
    -o package/parted/Makefile || {
    echo "Error: failed to download diskman's Parted.Makefile."
    exit 1
}
sed -i 's/fs-ntfs /fs-ntfs3 /g; /ntfs-3g-utils /d' package/luci-app-diskman/Makefile

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
    "CONFIG_PACKAGE_docker=y"
    "CONFIG_PACKAGE_dockerd=y"
    "CONFIG_PACKAGE_docker-compose=y"
    "CONFIG_PACKAGE_luci-app-docker=y"
    "CONFIG_PACKAGE_luci-i18n-docker-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-dockerman=y"
    "CONFIG_PACKAGE_luci-i18n-dockerman-zh-cn=y"
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
# Keep the helper behavior and default shell profile compatible with minimal
# images that do not ship zsh.
find . -name getifaddr.c -exec sed -i 's/return 1;/return 0;/g' {} +
sed -i '/\/usr\/bin\/zsh/d' package/base-files/files/etc/profile

# Normalize package versions for APK-style dependency parsing when these
# optional packages are present in the selected third-party package set.
if [[ -f package/v2ray-geodata/Makefile ]]; then
    sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' package/v2ray-geodata/Makefile
fi
if [[ -f package/luci-lib-taskd/Makefile ]]; then
    sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' package/luci-lib-taskd/Makefile
fi
if [[ -f package/luci-app-openclash/Makefile ]] && ! grep -q '^PKG_RELEASE:=' package/luci-app-openclash/Makefile; then
    sed -i '/^PKG_VERSION:=/a PKG_RELEASE:=1' package/luci-app-openclash/Makefile
fi
for makefile in package/luci-app-quickstart/Makefile package/luci-app-store/Makefile; do
    [[ -f "$makefile" ]] || continue
    sed -i -E 's/PKG_VERSION:=([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)/PKG_VERSION:=\1\nPKG_RELEASE:=\2/' "$makefile"
done

# Replace ddns-go's incomplete service defaults with the known-good OpenWRT-CI
# files so the daemon and LuCI use the same UCI section and config path.
if [[ -d package/ddns-go/file ]]; then
    install -Dm755 "${GITHUB_WORKSPACE}/diypatch/ddns-go.init" \
        package/ddns-go/file/ddns-go.init
    install -Dm755 "${GITHUB_WORKSPACE}/diypatch/ddns-go.uci-default" \
        package/ddns-go/file/luci-ddns-go.uci-default
    install -Dm644 "${GITHUB_WORKSPACE}/diypatch/ddns-go.config" \
        package/base-files/files/etc/config/ddns-go
fi

# Old CMake projects need an explicit compatibility floor with current CMake.
if ! grep -q 'CMAKE_POLICY_VERSION_MINIMUM' include/cmake.mk; then
    echo 'CMAKE_OPTIONS += -DCMAKE_POLICY_VERSION_MINIMUM=3.5' >> include/cmake.mk
fi

# Restore OpenWrt's host patch phase and avoid Rust's incompatible CI mode.
RUST_FILE="$(find feeds/packages -maxdepth 3 -type f -wholename '*/rust/Makefile' | head -n 1)"
if [[ -f "$RUST_FILE" ]]; then
    sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"
    if ! patch --batch --forward "$RUST_FILE" "${GITHUB_WORKSPACE}/diypatch/rust-makefile.patch"; then
        if grep -q '^define Host/Patch' "$RUST_FILE" && ! grep -q -- '--ci false' "$RUST_FILE"; then
            echo "Rust host-build fixes are already present upstream."
            rm -f "${RUST_FILE}.orig" "${RUST_FILE}.rej"
        else
            echo "Error: failed to apply the Rust host-build patch."
            exit 1
        fi
    fi
fi

# Use dockerman and luci-lib-docker from their maintained repositories and
# remove the obsolete cgroupfs-mount dependency.
rm -rf package/feeds/luci/luci-app-dockerman package/feeds/luci/luci-lib-docker \
    package/luci-app-dockerman package/luci-lib-docker
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman.git package/.diy-dockerman || exit 1
mv package/.diy-dockerman/applications/luci-app-dockerman package/luci-app-dockerman || exit 1
rm -rf package/.diy-dockerman
git clone --depth=1 https://github.com/lisaac/luci-lib-docker.git package/.diy-libdocker || exit 1
if [[ -d package/.diy-libdocker/collections/luci-lib-docker ]]; then
    mv package/.diy-libdocker/collections/luci-lib-docker package/luci-lib-docker || exit 1
else
    mv package/.diy-libdocker package/luci-lib-docker || exit 1
fi
rm -rf package/.diy-libdocker
sed -i 's/+cgroupfs-mount //g; s/+cgroupfs-mount//g' package/luci-app-dockerman/Makefile
./scripts/feeds install luci-lib-docker || exit 1

# The feed recipes can lag Docker's retagged release sources. Resolve the
# current matching engine/CLI commits and bypass their stale vendoring hashes.
MOBY_TAG="$(curl -fsSL https://api.github.com/repos/moby/moby/releases/latest | jq -r '.tag_name // empty')"
DOCKER_VER="$(echo "$MOBY_TAG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ -n "$DOCKER_VER" ]]; then
    DOCKERD_COMMIT="$(curl -fsSL "https://api.github.com/repos/moby/moby/commits?sha=${MOBY_TAG}&per_page=1" | jq -r '.[0].sha[0:7] // empty')"
    DOCKER_CLI_COMMIT="$(curl -fsSL "https://api.github.com/repos/docker/cli/commits?sha=v${DOCKER_VER}&per_page=1" | jq -r '.[0].sha[0:7] // empty')"
fi
if [[ -z "$DOCKER_VER" || -z "$DOCKERD_COMMIT" || -z "$DOCKER_CLI_COMMIT" ]]; then
    DOCKER_VER="29.5.2"
    DOCKERD_COMMIT="568f755"
    DOCKER_CLI_COMMIT="79eb04c"
fi

dockerd_makefile="$(find package feeds -name Makefile -exec grep -lE '^PKG_NAME:=dockerd$' {} + | head -n 1)"
docker_makefile="$(find package feeds -name Makefile -exec grep -lE '^PKG_NAME:=docker$' {} + | head -n 1)"
if [[ -f "$dockerd_makefile" ]]; then
    sed -i \
        -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$DOCKER_VER/" \
        -e "s/PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:=$DOCKERD_COMMIT/g" \
        -e 's/^PKG_HASH:=.*/PKG_HASH:=skip/' \
        -e '/define Build\/Prepare/,/endef/c\define Build/Prepare\n\t$(Build/Prepare/Default)\nendef' \
        -e 's/^\t$(call EnsureVendored/#\t$(call EnsureVendored/g' \
        "$dockerd_makefile"
fi
if [[ -f "$docker_makefile" ]]; then
    sed -i \
        -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$DOCKER_VER/" \
        -e "s/PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:=$DOCKER_CLI_COMMIT/g" \
        -e 's/^PKG_HASH:=.*/PKG_HASH:=skip/' \
        -e '/define Build\/Prepare/,/endef/c\define Build/Prepare\n\t$(Build/Prepare/Default)\nendef' \
        "$docker_makefile"
fi
