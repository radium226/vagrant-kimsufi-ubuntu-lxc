#!/bin/bash

# Start a Systemd unit and enable it
systemctl_start_enable()
{
  local unit="${1}"
  local action=
  for action in "start" "enable"; do
    systemctl "${action}" "${unit}"
  done
}



ethernet_driver()
{
    lspci -v | awk 'BEGIN { p = 0 } $0 ~ /Ethernet/ { p = 1 } p == 1 { print $0 } p == 1 && $0 == "" { p = 0 }' | grep "Kernel driver in use" | cut -d":" -f2 | tr -d " "
}

PROVSION_MODULES=("apt" "sshd" "fail2ban" "ufw" "ipv6" "default_user" "link")
provision()
{
  local provision_module=
  for provision_module in "${PROVSION_MODULES[@]}"; do
    init_${provision_module}
  done
}

# Link
init_link()
{
  sed -i -r -e 's,^GRUB_CMDLINE_LINUX="(.*)"$,GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 \1",g' "/etc/default/grub"
  update-grub
  sed -i -r -e 's,en[a-z0-9]{4},eth0,g' '/etc/network/interfaces'

  local driver="$( ethernet_driver )"
  systemctl stop networking
  modprobe -r "${ethernet_driver}"
  udevadm control --reload-rule
  udevadm trigger
  modprobe "${ethernet_driver}"
  systemctl start networking
}

# IPv6
init_ipv6()
{
  cat <<EOCAT >"/etc/sysctl.d/99-disable-ipv6.conf"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOCAT
  sysctl -p
}

# APT
APT_PACKAGES_TO_REMOVE="bind9" # Because of Kimsufi
APT_PACKAGES_TO_INSTALL=("python-minimal" "fail2ban" "ufw" "virt-what") # In order to use Ansible
init_apt()
{
  apt-get -y update
  apt-get -y upgrade
  apt-get -y remove "${APT_PACKAGES_TO_REMOVE[@]}"
  apt-get -y install "${APT_PACKAGES_TO_INSTALL[@]}"
}

# SSH
SSHD_CONFG_SED_EXPRESSIONS=(
  "s,^#?PermitRootLogin .+$,PermitRootLogin no,g"
)
init_sshd()
{
  local sshd_config="/etc/ssh/sshd_config"
  for sed_expression in "${SSHD_CONFG_SED_EXPRESSIONS[@]}"; do
    sed -i -r -e  "${sed_expression}" "${sshd_config}"
  done
  systemctl reload "sshd"
}

# Fail2ban
init_fail2ban()
{
  systemctl_start_enable "fail2ban"
  cat <<EOCAT >"/etc/fail2ban/jail.d/sshd.conf"
[sshd]
enabled  = true
EOCAT
  systemctl reload "fail2ban"
}

# UFW
UFW_DEFAULT_RULES=("allow outgoing" "deny incoming")
UFW_RULES=("allow ssh")
init_ufw()
{
  systemctl_start_enable "ufw"

  local ufw_default_rule=
  for ufw_default_rule in "${UFW_DEFAULT_RULES[@]}"; do
    ufw default ${ufw_default_rule}
  done

  local ufw_rule=
  for ufw_rule in "${UFW_RULES[@]}"; do
    ufw ${ufw_rule}
  done

  systemctl restart "ufw"
}

DEFAULT_USER_AUTHORIZED_KEYS=(
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDHjNfvzqrG5ycYv17hsi15K0dLlzknDUh5H0o3PCNv7jif5DcXJ18eMg3iOaUOWHTIAc0BxjZyzUYIAFEwCL/6v5h3pSy5Lw0oDjSyEhtN0hc6eiR8jx/x6d44aZ77uq+rMQeu9bbgCHHJei/9Fy2wkju/yHiL2QI+MqFrOuVAMmcUIUPrUtLMY7P+YFn6ORufSokxGZ383EvGLwKGTebqljeZLs2bWVQbSsE6vpbKIZFOpAtYvRAno9af4wfCUOFUt6Mfmwpd0pzwZJ5WvbLmlzFVhcEXZ9StLO6bmD6J0czCWmLXcOXBCTBhZzFz18hBdL568GNWxs4RDfnO/zRz adrien@iridum"
)
init_default_user()
{
  local default_user=
  if virt-what | grep -qi "VirtualBox"; then
    default_user="vagrant"
  else
    default_user="kimsufi"
  fi

  # Creation
  getent passwd "${default_user}" >"/dev/null" 2>&1 || useradd "${default_user}" --create-home --shell "/bin/bash"

  # SSH
  su "${default_user}" -c 'mkdir -p -m 700 "\${HOME}/.ssh"'
  su "${default_user}" -c 'test -f "\${HOME}/.ssh/id_rsa"' || su "${default_user}" -c 'ssh-keygen -t rsa -N "" -f "\${HOME}/.ssh/id_rsa"'
  su "${default_user}" -c 'touch "\${HOME}/.ssh/authorized_keys"'
  su "${default_user}" -c 'chmod 600 "\${HOME}/.ssh/authorized_keys"'
  for authorized_key in "${DEFAULT_USER_AUTHORIZED_KEYS[@]}"; do
    su "${default_user}" -c "{
      touch \"\${HOME}/.ssh/authorized_keys\"
      cat \"\${HOME}/.ssh/authorized_keys\" | grep -v '${authorized_key}'
      echo '${authorized_key}'
    } >> \"\${HOME}/.ssh/authorized_keys\""
  done

  # Sudoer
  cat <<EOCAT >"/etc/sudoers.d/${default_user}"
  Defaults:${default_user} !requiretty
  Defaults:${default_user} secure_path = /sbin:/bin:/usr/sbin:/usr/local/bin:/usr/bin
  Defaults:${default_user} env_keep += "PATH"
  ${default_user} ALL=(ALL) NOPASSWD:ALL
EOCAT
}

provision "${@}"
