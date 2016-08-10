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

PROVSION_MODULES=("sshd" "apt" "fail2ban" "ufw" "ipv6" "default_user" "link")
provision()
{
  local provision_module=
  for provision_module in "${PROVSION_MODULES[@]}"; do
    provision_${provision_module}
  done
}

# Link
provision_link()
{
  local old_ifname="$( ip link | sed -n -r -e 's,^[0-9]+: (e[a-z0-9]+?): .+,\1,gp' )"
  local new_ifname="eth0"

  # We rename the interface if needed
  if [[ "${old_ifname}" != "${new_ifname}" ]]; then
    sed -i -r -e 's,^GRUB_CMDLINE_LINUX="(.*)"$,GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 \1",g' "/etc/default/grub"
    update-grub
    systemctl stop networking && \
    ip link set "${old_ifname}" down && \
    ip link set "${old_ifname}" name "${new_ifname}" && \
    sed -i -r -e "s,${old_ifname},${new_ifname},g" '/etc/network/interfaces' && \
    ip link set "${new_ifname}" up && \
    systemctl start networking
  fi
}

# IPv6
provision_ipv6()
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
provision_apt()
{
  apt-get -y update
  #apt-get -y upgrade
  apt-get -y remove "${APT_PACKAGES_TO_REMOVE[@]}"
  apt-get -y install "${APT_PACKAGES_TO_INSTALL[@]}"
}

# SSH
SSHD_CONFG_SED_EXPRESSIONS=(
  "s,^#?PermitRootLogin .+$,PermitRootLogin no,g"
)
provision_sshd()
{
  local sshd_config="/etc/ssh/sshd_config"
  for sed_expression in "${SSHD_CONFG_SED_EXPRESSIONS[@]}"; do
    sed -i -r -e  "${sed_expression}" "${sshd_config}"
  done
  systemctl reload "sshd"
}

# Fail2ban
provision_fail2ban()
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
provision_ufw()
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
provision_default_user()
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
  su "${default_user}" -c 'mkdir -p -m 700 "${HOME}/.ssh"'
  su "${default_user}" -c 'test -f "${HOME}/.ssh/id_rsa"' || su "${default_user}" -c 'ssh-keygen -t rsa -N "" -f "${HOME}/.ssh/id_rsa"'
  su "${default_user}" -c 'touch "${HOME}/.ssh/authorized_keys"'
  su "${default_user}" -c 'chmod 600 "${HOME}/.ssh/authorized_keys"'
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
