# OpenSSH RPM Docker 一键编译

基于 [nugent1a/openssh-rpms](https://github.com/nugent1a/openssh-rpms)，用 Docker 在任意宿主机（含 Windows/WSL2、macOS、Linux）上编译出目标系统的 OpenSSH RPM 包。

## GitHub Actions 自动构建

工作流每天北京时间 10:00 自动检查 OpenSSH 最新稳定版和 OpenSSL 最新 LTS
补丁版。对应版本组合的 Release 不存在时自动构建，已有 Release 时跳过。
OpenSSH 发布签名者必须命中工作流中的可信指纹白名单；上游轮换密钥时任务会安全失败，
需人工核验并更新白名单。

也可以修改 `.github/workflows/build-openssh.yml` 顶部的固定版本号并推送，或手动运行：

```yaml
env:
  SSH_VERSION: "10.6p1"
  SSL_VERSION: "3.5.9"
```

推送和手动运行使用上述固定版本；定时运行使用自动检测版本。工作流会并行构建60个目标，
全部成功后发布到 `openssh-<OpenSSH版本>-openssl-<OpenSSL版本>` Release，
同时保留每个目标的 Actions Artifact。

| 系统 | x86_64 | aarch64 |
| --- | --- | --- |
| CentOS 7 | 是 | 是（使用 CentOS AltArch 归档源） |
| CentOS Stream 8 | 是 | 是 |
| CentOS Stream 9 | 是 | 是 |
| Rocky Linux 8/9/10 | 是 | 是 |
| openEuler 24.03 LTS SP2/SP3/SP4 | 是 | 是 |
| 银河麒麟 V10 SP1/SP2/SP3 | 是 | 是 |
| UOS 20 兼容包 | 是 | 是 |
| Ubuntu 22.04/24.04/26.04 LTS（deb） | 是 | 是 |
| Anolis OS 8/23 | 是 | 是 |
| RHEL 8/9/10（UBI 镜像构建） | 是 | 是 |
| AlmaLinux 8/9/10 | 是 | 是 |
| Fedora 43/44 | 是 | 是 |
| Debian 12/13（deb） | 是 | 是 |
| openSUSE Leap 15.6 | 是 | 是 |
| deepin 25（deb） | 是 | 是 |

> deepin 25 未在 Docker Hub 发布官方镜像，构建基底使用与其二进制兼容的 `debian:13`，产物仍标记为 `deepin25`。

Ubuntu/Debian/deepin 目标输出 `.deb` 包（安装包内含的 install.sh 会自动改用 dpkg 安装），
其余目标输出 RPM 包。

麒麟目标使用社区镜像 `hxsoong/kylin`，并锁定多架构 digest；该镜像不是麒麟官方发布。
UOS 20 目标参考 [boypt/openssh-rpms](https://github.com/boypt/openssh-rpms)，在 EL8
环境构建并应用 UOS 20 内核 `dup2()` 兼容补丁，并非使用 UOS 官方容器镜像。

## 目录结构

```
openssh-rpms-docker/
├── build.sh              # 一键编译脚本（入口）
├── install.sh            # RPM 安装、配置校验和服务重启
├── Dockerfile            # 编译环境镜像（基础镜像可参数化）
├── repo/                 # 克隆的上游仓库（含 build_openssh.sh）
└── output/               # 编译产物输出目录（自动创建）
```

## 使用步骤

1. **准备源码包**，放到本目录（`openssh-rpms-docker/`）下：
   - `openssh-10.0p2.tar.gz`（版本任选）
   - `openssl-3.3.1.tar.gz`
   - 可选：`x11-ssh-askpass-*.tar.gz`

   下载地址：https://www.openssh.com/releasenotes.html / https://www.openssl.org/source/

2. **一键编译**（默认 CentOS 7）：

   ```bash
   cd openssh-rpms-docker
   bash build.sh
   ```

3. **指定目标系统**：

   ```bash
   # Rocky Linux 9
   bash build.sh -i rockylinux/rockylinux:9 -t el9

   # openEuler 22.03
   bash build.sh -i openeuler/openeuler:22.03-lts -t oe22

   # 麒麟 V10 SP3（用你拿到的麒麟基础镜像）
   bash build.sh -i <kylin-v10-sp3镜像名> -t ky10
   ```

4. **取产物**：编译完成后 RPM 打包在 `output/openssh-<版本>-rpms-<标签>-<架构>.tar.gz`。

## ARM (aarch64) 编译

`build_openssh.sh` 用 `uname -m` 自动探测架构，产物自动打上 `x86_64` 或 `aarch64` 标记，无需改脚本。

**方式一：在 ARM 服务器上编译（推荐，鲲鹏/飞腾等）**

直接用多架构基础镜像，其余步骤完全相同：

```bash
bash build.sh -i rockylinux/rockylinux:9 -t el9  # 多架构镜像自动拉 arm64 层
bash build.sh -i <麒麟V10-ARM镜像> -t ky10
```

`centos:7` 包含 ARM64 层，但软件源已归档到 CentOS AltArch vault；Dockerfile 已自动处理。

**方式二：在 x86 电脑上交叉编译（QEMU 模拟，慢 3-10 倍）**

```bash
# 首次先安装 ARM 模拟支持
docker run --privileged --rm tonistiigi/binfmt --install arm64

# 编译（-p 指定目标平台）
bash build.sh -p linux/arm64 -i rockylinux/rockylinux:9 -t el9
```

脚本会把镜像和容器都跑在 `linux/arm64` 下，产物为 aarch64 RPM。编译 OpenSSL + OpenSSH 在 QEMU 下可能需要 1-3 小时，建议优先用方式一。

## 安装到目标机器（以 el7 为例）

```bash
tar zxvf openssh-*.tar.gz
cd openssh-*-rpms-*
sudo ./install.sh
```

安装脚本默认保留现有SELinux和SSH登录策略；它会备份 `sshd_config`、安装RPM、
执行 `sshd -t`，验证成功后才重启服务。确实需要关闭SELinux并允许root密码登录时：

```bash
sudo env ALLOW_ROOT_PASSWORD=1 DISABLE_SELINUX=1 ./install.sh
```

⚠️ **不要关闭旧的 SSH 窗口**，新开一个连接验证成功后再退出，防止失联。建议提前开启 Telnet 等备用通道。

## 工作原理

- `Dockerfile` 以目标系统为基础镜像，预装全部编译依赖（rpm-build/gcc/perl 模块/pam/krb5/gtk2 等）。
- `build.sh` 把当前目录挂载到容器 `/build`（脚本在其中探测源码包），把 `./output` 挂载到 `/opt` 直接接住产物。
- 容器内执行 `echo 1 | bash build_openssh.sh` 自动应答依赖安装交互。

## 常见问题

- **CentOS 7 镜像源 404**：Dockerfile 已自动切到 vault.centos.org，无需处理。
- **麒麟 V10 镜像哪里找**：需要内部信创源或华为云/阿里云上的麒麟官方镜像；`ky10` 标签只是产物命名，脚本本身兼容任何 yum 系系统。
- **更换源码版本**：直接替换目录里的 tar.gz 即可，脚本自动探测文件名中的版本号。
- **强制重建镜像**：`bash build.sh -f`。
