Vagrant.configure("2") do |config|
  # Ubuntu Xenial
  config.vm.box = "bento/ubuntu-16.04"
  config.vm.define "sun.vagrant" do |name|
  end

  # Larger VM for LxC
  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 2
  end

  # Basic Provisioning
  config.vm.network "forwarded_port", guest: 22, host: 2222, id: "ssh"
  config.vm.provision "shell", path: "./files/post-install.sh"
end
