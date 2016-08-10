#!/bin/bash

set -e

wait_for_ssh()
{
	declare hostname="${1}"
	while ! nmap -p 22 "${hostname}" 2>"/dev/null" | grep "^22" | grep "open" >"/dev/null"; do
  		echo >"/dev/null"
			sleep 1
	done
}

create_lxc()
{
	declare hostname="${1}"
	declare lxc_dp="/var/lib/lxc"
	declare rootfs_dp="${lxc_dp}/${hostname}/rootfs"
	declare user="${2}"
	declare password="${2}"

  # -t download -- -d centos -r 7 -a amd64
	lxc-create --name "${hostname}" --template "ubuntu" -- --release "xenial" --user "${user}" --password "${password}"

 	sed -i -r -e 's/^#?GSSAPIAuthentication .+/GSSAPIAuthentication no/' "${rootfs_dp}/etc/ssh/sshd_config"
	sed -i -r -e 's/^#?UseDNS .+/UseDNS no/' "${rootfs_dp}/etc/ssh/sshd_config"

	cat <<EOF >"${rootfs_dp}/etc/sudoers.d/${user}"
Defaults:${user} !requiretty
Defaults:${user} secure_path = /sbin:/bin:/usr/sbin:/usr/local/bin:/usr/bin
Defaults:${user} env_keep += "PATH"
${user} ALL=(ALL) NOPASSWD:ALL
EOF
}

main()
{
  declare fqdn="${1}"
  declare hostname="$( echo "${fqdn}" | cut -d'.' -f1 )"
	declare user="${2}"

	declare return_code=1

	if ! lxc-ls -1 | grep -q "${hostname}"; then
		create_lxc "${hostname}" "${user}"
		return_code=0
	fi

	if ! lxc-ls -1 --running | grep -q "${hostname}"; then
		lxc-start -n "${hostname}"
		wait_for_ssh "${fqdn}"
		return_code=0
	fi

	# FIXME: Add a new step
	declare ssh_pub_key="$( su - "${SUDO_USER}" -c "cat \"\${HOME}/.ssh/id_rsa.pub\"" )"
	lxc-attach --name "${hostname}" -- su "${user}" -c "mkdir -p \"\${HOME}/.ssh\" ; chmod 700 \"\${HOME}/.ssh\""
	lxc-attach --name "${hostname}" -- su "${user}" -c "echo '${ssh_pub_key}' >\"\${HOME}/.ssh/authorized_keys\""

	return ${return_code}
}

main "${@}"
