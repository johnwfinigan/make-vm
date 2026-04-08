# Overview

make-vm.sh automates creating libvirt VMs from distro cloud images

You need a working libvirtd with a network called "default" for this to work.

# Examples

The distro abbreviation "el" means Enterprise Linux and selects a RHEL rebuild, currently Rocky.

```
./make-vm.sh my-vm-rocky9 # the default distro is Rocky 9

./make-vm.sh -d el -v 10 my-vm-rocky10

./make-vm.sh -d debian -v 13 my-vm-debian-trixie

./make-vm.sh -d ubuntu -v jammy my-vm-ubuntu-2204
```

# Get VM IP

```sudo virsh net-dhcp-leases default```

```sudo virsh domifaddr```
