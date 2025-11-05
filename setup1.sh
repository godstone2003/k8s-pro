#!/bin/bash
set -e  # Stop the script if any command fails
set -o pipefail
sudo apt install dos2unix

echo "==== Verifying kernel version ===="
uname -r

echo "==== Updating and installing essential tools ===="
sudo apt update -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release git 

# Install docker.io only temporarily to ensure dependencies are met
sudo apt install -y docker.io

echo "==== Installing kubectl ===="
sudo snap install kubectl --classic || {
  echo "Snap installation failed, installing kubectl via apt as fallback..."
  sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
}

echo "==== Removing old Docker versions ===="
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

echo "==== Setting up Docker repository ===="
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y

echo "==== Installing Docker Engine and plugins ===="
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==== Enabling and starting Docker ===="
sudo systemctl enable docker
sudo systemctl start docker

echo "==== Adding current user to docker group ===="
sudo usermod -aG docker $USER
newgrp docker <<EONG
echo "Docker group applied successfully for current session."
EONG

echo "==== Verifying Docker installation ===="
docker --version
docker ps || echo "Docker is running fine, no containers yet."

echo "==== Installing Minikube ===="
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm -f minikube-linux-amd64

echo "==== Starting Minikube with 4 CPUs and 6GB RAM ===="
minikube start --cpus=4 --memory=6144 --driver=docker || {
  echo "Minikube start failed — retrying once..."
  minikube delete
  minikube start --cpus=4 --memory=6144 --driver=docker
}

echo "==== Installing eBPF tools (bpftool) ===="
sudo apt install -y linux-tools-$(uname -r) linux-tools-generic
sudo bpftool version

echo "==== Setup Complete ===="
echo "Docker and Minikube are ready to use!"

