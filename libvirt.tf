provider "libvirt" {
  uri = "qemu+ssh://rafa@desktop/system"
}

# Kube network
resource "libvirt_network" "network_kube" {
  name = "network_kube"
  mode = "nat"
  domain = "k8s.local"
  addresses = ["10.240.0.0/24"]
  dns {
    enabled = true
    local_only = false
  }
}

# Pool for ubuntu images
resource "libvirt_pool" "ubuntu" {
  name = "ubuntu"
  type = "dir"
  path = "/var/lib/libvirt/pool-ubuntu"
}

# Fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "ubuntu_qcow2" {
  name   = "ubuntu_qcow2"
  pool   = libvirt_pool.ubuntu.name
  source = "https://cloud-images.ubuntu.com/releases/xenial/release/ubuntu-16.04-server-cloudimg-amd64-disk1.img"
  format = "qcow2"
}

resource "libvirt_volume" "master1_qcow2" {
  name = "master1_qcow2"
  base_volume_id = libvirt_volume.ubuntu_qcow2.id
  base_volume_pool = libvirt_pool.ubuntu.name
  size = "21474836480"
}

# Set default password
data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
}

# Set network settings
data "template_file" "network_config" {
  template = file("${path.module}/network_config.cfg")
}

# for more info about parameter check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.ubuntu.name
}

# Create the machine
resource "libvirt_domain" "domain_master1" {
  name   = "domain_master1"
  memory = "512"
  vcpu   = 1

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    network_id = libvirt_network.network_kube.id
    addresses = ["10.240.0.11"]
    wait_for_lease = true 
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.master1_qcow2.id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

terraform {
  required_version = ">= 0.12"
}
