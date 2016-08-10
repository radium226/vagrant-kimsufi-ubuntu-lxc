#!/bin/bash

export SUCCESS=0
export DONE=0
export ALREADY_DONE=1
export FAILURE=2

declare remote_host="${1}"
declare remote_user="${2:-adrien}"
declare ansible_user="${3:-ansible}"
declare ssh_config="${4:-.ssh/config}"

if [[ -z "${remote_host}" ]]; then
    echo "The host should be defined. " >&2
    exit ${FAILURE}
fi

has_bootstrap_already_been_done()
{
  declare remote_host="${1}"
  declare remote_user="${2}"
  declare ssh_config="${3}"
  declare ansible_user="${4}"

  ssh -F "${ssh_config}" -q -o "StrictHostKeyChecking=no" -o "BatchMode=yes" "${ansible_user}@${remote_host}" exit 0
  test ${?} -eq 0 && return ${SUCCESS} || return ${FAILURE}
}

ssh_exec()
{
  declare ssh_host="${1}"
  declare ssh_user="${2}"
  declare ssh_config="${3}"

  ssh <<EOSSH -o "StrictHostKeyChecking no" -F "${ssh_config}" "${ssh_user}@${ssh_host}"
$( cat )
EOSSH
}

bootstrap()
{
  declare ssh_host="${1}"
  declare ssh_user="${2}"
  declare ssh_config="${3}"
  declare ansible_user="${4}"

  declare pub_key="$( cat "$( find "${HOME}/.ssh" -type "f" -name "*.pub" | head -n1 )" )"
  ssh_exec <<EOF "${ssh_host}" "${ssh_user}" "${ssh_config}"
cat <<EOC >"/tmp/bootstrap_ansible.sh"
#!/bin/bash
#FIXME
rm /var/lib/dpkg/lock
rm /var/lib/apt/lists/lock
rm /var/cache/apt/archives/lock
apt-get -y install "python-minimal"
getent passwd "${ansible_user}" >"/dev/null" 2>&1 || useradd "${ansible_user}" --create-home --shell "/bin/bash"
su "${ansible_user}" -c 'mkdir -p -m 700 "\\\${HOME}/.ssh"'
su "${ansible_user}" -c 'test -f "\\\${HOME}/.ssh/id_rsa"' || su "${ansible_user}" -c 'ssh-keygen -t rsa -N "" -f "\\\${HOME}/.ssh/id_rsa"'
su "${ansible_user}" -c 'touch "\\\${HOME}/.ssh/authorized_keys"'
su "${ansible_user}" -c 'chmod 600 "\\\${HOME}/.ssh/authorized_keys"'
su "${ansible_user}" -c '{
  cat "\\\${HOME}/.ssh/authorized_keys" | grep -v "${pub_key}"
  echo "${pub_key}"
} > "\\\${HOME}/.ssh/authorized_keys"'
cat <<EOS >'/etc/sudoers.d/ansible'
Defaults:${ansible_user} !requiretty
Defaults:${ansible_user} secure_path = /sbin:/bin:/usr/sbin:/usr/local/bin:/usr/bin
Defaults:${ansible_user} env_keep += "PATH"
${ansible_user} ALL=(ALL) NOPASSWD:ALL
EOS
EOC
chmod +x "/tmp/bootstrap_ansible.sh"
sudo "/tmp/bootstrap_ansible.sh"
EOF
}

main()
{
  declare ssh_host="${1}"
  declare ssh_user="${2:-adrien}"
  declare ssh_config="${3:-.ssh/config}"
  declare ansible_user="${4:-ansible}"

  if ! has_bootstrap_already_been_done "${ssh_host}" "${ssh_user}" "${ssh_config}" "${ansible_user}"; then
    echo "Bootstrap need to be done"
    #bootstrap_user "${ssh_host}" "${ssh_user}" "${ssh_config}" "${ansible_user}"
    bootstrap "${ssh_host}" "${ssh_user}" "${ssh_config}" "${ansible_user}"
    return ${DONE}
  else
    echo "Bootstrap has already been done" >&2
    return ${ALREADY_DONE}
  fi
}

main "${@}"
