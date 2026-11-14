#!/bin/sh

set -eu

die() {
    echo "ERROR: $*" >&2
    exit 1
}

backup_file() {
    file=$1
    [ -f "$file" ] || return 0
    backup="${file}.bak.${BACKUP_TIME}"
    cp -p "$file" "$backup"
    echo "已备份: $backup"
}

set_sshd_option() {
    key=$1
    value=$2
    tmp="${SSHD_CONFIG}.tmp.$$"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0; in_match = 0; wanted = tolower(key) }
        {
            active = $0
            sub(/^[[:space:]]*/, "", active)
            split(active, active_fields, /[[:space:]]+/)
            active_key = tolower(active_fields[1])

            normalized = active
            sub(/^#[[:space:]]*/, "", normalized)
            split(normalized, fields, /[[:space:]]+/)
            current_key = tolower(fields[1])
        }
        !in_match && (active_key == "include" || active_key == "match") {
            if (!done) print key " " value
            done = 1
            if (active_key == "match") in_match = 1
        }
        !in_match && current_key == wanted {
            if (!done) print key " " value
            done = 1
            next
        }
        { print }
        END { if (!done) print key " " value }
    ' "$SSHD_CONFIG" > "$tmp"
    cat "$tmp" > "$SSHD_CONFIG"
    rm -f "$tmp"
}

disable_selinux_config() {
    file=$1
    [ -f "$file" ] || return 0
    backup_file "$file"
    if grep -q '^[[:space:]]*SELINUX=' "$file"; then
        sed -i 's/^[[:space:]]*SELINUX=.*/SELINUX=disabled/' "$file"
    else
        echo 'SELINUX=disabled' >> "$file"
    fi
}

if [ "${1:-}" = "--self-test" ]; then
    test_dir=$(mktemp -d)
    trap 'rm -rf "$test_dir"' 0
    SSHD_CONFIG="$test_dir/sshd_config"
    BACKUP_TIME=test
    printf '%s\n' 'include /etc/ssh/sshd_config.d/*.conf' 'permitrootlogin no' \
        'passwordauthentication no' 'match User backup' \
        '    passwordauthentication no' > "$SSHD_CONFIG"
    set_sshd_option PermitRootLogin yes
    set_sshd_option PasswordAuthentication yes
    [ "$(grep -c '^PermitRootLogin yes$' "$SSHD_CONFIG")" -eq 1 ]
    [ "$(grep -c '^PasswordAuthentication yes$' "$SSHD_CONFIG")" -eq 1 ]
    [ "$(sed -n '1p' "$SSHD_CONFIG")" = 'PermitRootLogin yes' ]
    [ "$(sed -n '2p' "$SSHD_CONFIG")" = 'PasswordAuthentication yes' ]
    grep -q '^    passwordauthentication no$' "$SSHD_CONFIG"
    printf '%s\n' 'SELINUX=enforcing' > "$test_dir/selinux"
    disable_selinux_config "$test_dir/selinux"
    grep -q '^SELINUX=disabled$' "$test_dir/selinux"
    echo "install.sh self-test passed"
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "请使用 root 运行此脚本"

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
SSHD_CONFIG=${SSHD_CONFIG:-/etc/ssh/sshd_config}
BACKUP_TIME=$(date +%Y%m%d%H%M%S)

echo "即将升级 OpenSSH；请保持当前 SSH 会话，并准备备用登录通道。"
backup_file "$SSHD_CONFIG"

if [ -n "$(ls "$SCRIPT_DIR"/*.deb 2>/dev/null)" ]; then
    # DEB 目标（Debian/Ubuntu/deepin 等）
    command -v dpkg >/dev/null 2>&1 || die "未找到 dpkg 命令"
    # --force-confold: 保留系统现有 sshd_config 等配置（等价于 RPM 的 %config(noreplace)）
    DEBIAN_FRONTEND=noninteractive dpkg -i --force-confdef --force-confold "$SCRIPT_DIR"/*.deb
    # dpkg -i 不做依赖解析；若有其他包依赖 openssh-client/server 会留下依赖破损状态
    broken_pkgs=$(dpkg -C 2>/dev/null || true)
    if [ -n "$broken_pkgs" ]; then
        echo "WARNING: 以下软件包存在依赖破损（通常因替换 openssh-client/server）："
        echo "$broken_pkgs"
        echo "可执行 'apt-get -f install' 收尾；不影响本次 OpenSSH 安装。"
    fi
elif [ -n "$(ls "$SCRIPT_DIR"/*.rpm 2>/dev/null)" ]; then
    # RPM 目标
    command -v rpm >/dev/null 2>&1 || die "未找到 rpm 命令（Debian/Ubuntu/deepin 等系统请先执行: apt-get install -y rpm）"
    # --nodeps: Debian/Ubuntu 等系统的 rpm 数据库为空，包依赖（如 systemd）无法解析
    rpm -Uvh --replacefiles --nodeps "$SCRIPT_DIR"/*.rpm
else
    die "当前安装包中未找到 RPM/DEB 文件"
fi

[ -f "$SSHD_CONFIG" ] || die "未找到 $SSHD_CONFIG"

if [ "${ALLOW_ROOT_PASSWORD:-0}" = "1" ]; then
    set_sshd_option PermitRootLogin yes
    set_sshd_option PasswordAuthentication yes
    echo "已启用 root 密码登录"
fi

if [ "${DISABLE_SELINUX:-0}" = "1" ]; then
    disable_selinux_config /etc/selinux/config
    disable_selinux_config /etc/sysconfig/selinux
    setenforce 0 2>/dev/null || true
    echo "已禁用 SELinux；永久生效需要重启系统"
fi

for key in /etc/ssh/ssh_host_*_key; do
    [ -f "$key" ] && chmod 600 "$key"
done

# 全新/极简系统可能没有任何 host key（sshd -t 与服务启动都会失败）
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -A
fi

SSHD_BIN=$(command -v sshd 2>/dev/null || true)
[ -n "$SSHD_BIN" ] || SSHD_BIN=/usr/sbin/sshd
[ -x "$SSHD_BIN" ] || die "未找到 sshd"

if ! "$SSHD_BIN" -t; then
    [ -f "${SSHD_CONFIG}.bak.${BACKUP_TIME}" ] && cp -p "${SSHD_CONFIG}.bak.${BACKUP_TIME}" "$SSHD_CONFIG"
    die "sshd 配置校验失败，已恢复安装前配置，服务未重启"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    if ! systemctl restart sshd.service 2>/dev/null; then
        # Debian/Ubuntu 等系统服务名为 ssh.service
        systemctl restart ssh.service
    fi
elif command -v service >/dev/null 2>&1; then
    service sshd restart || service ssh restart
elif [ -x /etc/init.d/sshd ]; then
    /etc/init.d/sshd restart
else
    die "未找到 sshd 服务管理命令"
fi

ssh -V 2>&1
echo "OpenSSH 安装完成"

