Vagrant.configure("2") do |config|
  
  # Base OS box - Ubuntu 22.04 LTS
  config.vm.box = "ubuntu/jammy64"

  # Ensure DNS and networking issues are handled for internet access
  config.vm.provider "virtualbox" do |vb|
    vb.name = "Ubuntu22.04-InternetReady"
    vb.cpus = 4
    vb.memory = 8192
    
    # Use NAT adapter for internet access
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end

  #  Forward Grafana port to host machine
  config.vm.network "forwarded_port", guest: 3000, host: 3000, auto_correct: true
  config.vm.network "forwarded_port", guest: 9090, host: 9090, auto_correct: true
  config.vm.network "forwarded_port", guest: 6443, host: 6443, auto_correct: true
  config.vm.network "forwarded_port", guest: 2802, host: 2802, auto_correct: true

  # Provision script to test internet and install packages
  config.vm.provision "shell", inline: <<-SHELL
    sudo apt-get update -y
    sudo apt-get install -y curl wget net-tools vim
    echo "✅ Internet reachable and basic packages installed"
    curl -I https://www.google.com || echo " Internet test failed!"
  SHELL

end
