Vagrant.configure("2") do |config|
  # Ubuntu Xenial
  config.vm.box = "bento/ubuntu-16.04"
  config.vm.define "sun.vagrant" do |name|
  end
  config.vm.network "forwarded_port", guest: 22, host: 2222, id: "ssh"
  config.vm.provision "shell", path: "./post-install.sh"
end
