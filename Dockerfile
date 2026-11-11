# OpenSSH RPM 编译镜像
# 用法: docker build --build-arg BASE_IMAGE=centos:7 -t openssh-builder:el7 .
# 切换目标系统只需改 BASE_IMAGE，例如:
#   centos:7                -> el7
#   centos:8 / rockylinux:8 -> el8
#   rockylinux:9            -> el9
#   openeuler/openeuler:22.03-lts -> oe22
#   麒麟 V10 (需有内部/社区镜像，如 swr.cn-north-4.myhuaweicloud.com/.../kylin-v10-sp3)
#
# ARM (aarch64):
#   - ARM 宿主机(鲲鹏/飞腾)上直接用多架构镜像: rockylinux:9, openeuler/openeuler 等
#   - x86 宿主机交叉编译: 加 --platform linux/arm64，首次需安装 QEMU:
#     docker run --privileged --rm tonistiigi/binfmt --install arm64
#   - 注意: 官方 centos:7 没有 arm64 版本，ARM 用 rockylinux:8 / openeuler 或麒麟 ARM 镜像
ARG BASE_IMAGE=centos:7
FROM ${BASE_IMAGE}

# 仅修复已停止维护的 CentOS 7 / Stream 8 软件源。
RUN if grep -q 'CentOS Linux release 7' /etc/centos-release 2>/dev/null; then \
      sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
        -e 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=https://vault.centos.org/7.9.2009|' \
        -e 's|^#baseurl=http://mirror.centos.org/altarch/\$releasever|baseurl=https://vault.centos.org/altarch/7.9.2009|' \
        /etc/yum.repos.d/CentOS-*.repo; \
    elif grep -q 'CentOS Stream release 8' /etc/centos-release 2>/dev/null; then \
      sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^metalink=|#metalink=|' \
        -e 's|^#baseurl=http://mirror.centos.org/\$contentdir|baseurl=https://vault.centos.org|' \
        -e 's|^#baseurl=http://mirror.stream.centos.org/\$contentdir|baseurl=https://vault.centos.org|' \
        /etc/yum.repos.d/CentOS-*.repo; \
    fi \
 && if command -v apt-get >/dev/null 2>&1; then \
      apt-get clean; \
    elif command -v zypper >/dev/null 2>&1; then \
      zypper -n clean; \
    elif command -v yum >/dev/null 2>&1; then \
      yum clean all; \
    fi

# 预装编译依赖，容器内即可跳过脚本里的交互式依赖安装
RUN if command -v apt-get >/dev/null 2>&1; then \
      export DEBIAN_FRONTEND=noninteractive; \
      apt-get update; \
      apt-get install -y --no-install-recommends \
        rpm gcc g++ make perl zlib1g-dev libpam0g-dev \
        tar gzip patch xz-utils procps ca-certificates; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v zypper >/dev/null 2>&1; then \
      zypper --non-interactive --gpg-auto-import-keys refresh --force 2>/dev/null || zypper -n refresh; \
      zypper -n install rpm-build gcc gcc-c++ make perl perl-base zlib-devel pam-devel tar gzip patch which; \
      zypper -n clean --all; \
    elif command -v dnf >/dev/null 2>&1; then \
      dnf install -y rpm-build gcc gcc-c++ make \
        perl perl-core perl-IPC-Cmd perl-Data-Dumper perl-Pod-Html perl-devel perl-Time-Piece \
        zlib-devel pam-devel tar gzip which patch ncurses \
      || dnf install -y --allowerasing rpm-build gcc gcc-c++ make \
        perl perl-core perl-IPC-Cmd perl-Data-Dumper perl-Pod-Html perl-devel perl-Time-Piece \
        zlib-devel pam-devel tar gzip which patch ncurses; \
      dnf install -y perl-lib 2>/dev/null || true; \
      dnf clean all; \
    else \
      yum install -y rpm-build gcc gcc-c++ make \
        perl perl-core perl-IPC-Cmd perl-Data-Dumper perl-Pod-Html perl-devel perl-Time-Piece \
        zlib-devel pam-devel tar gzip which patch ncurses; \
      yum install -y perl-lib 2>/dev/null || true; \
      yum clean all; \
    fi

WORKDIR /build
CMD ["/bin/bash"]
