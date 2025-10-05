# create VM skeleton
resource "proxmox_vm_qemu" "vm_from_img" {
  vmid         = 200
  name         = "ubuntu-ci-200"
  target_node  = "pve-node01"
  cores        = 2
  memory       = 2048
  scsihw       = "virtio-scsi-pci"

  # attach an imported disk (format/identifier depends on storage)
  # when using `qm importdisk` externally, refer to storage:vm-<id>-disk-0
  disk {
    slot    = 0
    size    = 20
    type    = "scsi"
    storage = "local-lvm"
    format  = "qcow2"
  }

  # add a cloud-init drive (provider may expose proxmox_cloud_init_disk resource)
  # Option A: provider-populated cloud-init iso
  #cloudinit_cdrom_storage = "local"

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
}
