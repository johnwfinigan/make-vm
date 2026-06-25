#!/bin/bash

set -eu

export PATH=/usr/bin

memory_mb=4096
distro=el
disk_gb=50
virt_sysprep=false
transient=false
network=default

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] vm-name

Options:
  -d  Linux distribution (default: el)
      el = Rocky or CentOS
      ol = Oracle Linux
      debian = Debian
      fedora = Fedora
      ubuntu = Ubuntu
  -g  Disk size in GB (default: 50)
  -h  Help
  -m  Memory in MB (default: 4096)
  -s  Enable virt-sysprep (disabled by default)
  -t  Transient VM, deleted when shut down
  -v  Distribution version 

Example:
  $(basename "$0") -m 4096 -g 40 -d debian -v 12 debian-12-test
EOF
  exit 0
}

while getopts :hstd:g:i:m:n:v: opt; do
  case "$opt" in
  d)
    distro="$OPTARG"
    ;;
  g)
    disk_gb="$OPTARG"
    ;;
  h)
    usage
    ;;
  i)
    custom_image="$OPTARG"
    distro=custom
    ;;
  m)
    re='^[0-9]+$'
    if [[ $OPTARG =~ $re ]]; then
      memory_mb="$OPTARG"
    else
      echo "Error - memory must be specified as a number" >&2
      exit 112
    fi
    ;;
  n)
    network="$OPTARG"
    ;;
  s)
    virt_sysprep=true
    ;;
  t)
    transient=true
    ;;
  v)
    version="$OPTARG"
    ;;
  \?)
    echo "invalid option, exiting" >&2
    exit 113
    ;;
  :)
    printf -- "%s needs an argument, exiting\n" "$OPTARG" >&2
    exit 114
    ;;
  esac
done

shift $((OPTIND - 1))
if [ -z "$1" ]; then
  echo "Error - you must provide a name for your vm" >&2
  echo "example: $0 my-vm" >&2
  exit 111
fi
vm_name="$1"

loc=/var/lib/libvirt/images
destdisk="$loc/$vm_name.qcow2"

case "$distro" in
el)
  vers="${version:-9}"
  os_variant="rhel${vers}.0"
  if [ "$vers" = 8 ] || [ "$vers" = 9 ] || [ "$vers" = 10 ]; then
    url_prefix="https://download.rockylinux.org/pub/rocky/${vers}/images/x86_64/"
    url_file="Rocky-${vers}-GenericCloud-Base.latest.x86_64.qcow2"
  elif [ "$vers" = 7 ]; then
    url_prefix="https://cloud.centos.org/centos/7/images/"
    url_file="CentOS-7-x86_64-GenericCloud.qcow2"
  else
    echo "Error - unknown os version" >&2
    exit 112
  fi
  ;;
ol)
  vers="${version:-10}"
  os_variant="rhel${vers}.0"
  url_prefix="https://yum.oracle.com/templates/OracleLinux/"
  case "$vers" in
  7)
    url_prefix+="OL7/u9/x86_64/"
    url_file="OL7U9_x86_64-kvm-b257.qcow2"
    ;;
  8)
    url_prefix+="OL8/u10/x86_64/"
    url_file="OL8U10_x86_64-kvm-b271.qcow2"
    ;;
  9)
    url_prefix+="OL9/u7/x86_64/"
    url_file="OL9U7_x86_64-kvm-b269.qcow2"
    ;;
  10)
    url_prefix+="OL10/u1/x86_64/"
    url_file="OL10U1_x86_64-kvm-b270.qcow2"
    ;;
  *)
    echo "Error - unknown os version" >&2
    exit 112
    ;;
  esac
  ;;
debian)
  vers="${version:-12}"
  os_variant=debian11
  if [ "$vers" = 12 ]; then
    url_prefix="https://cloud.debian.org/images/cloud/bookworm/latest/"
    url_file="debian-12-generic-amd64.qcow2"
  elif [ "$vers" = 13 ]; then
    url_prefix="https://cloud.debian.org/images/cloud/trixie/latest/"
    url_file="debian-13-generic-amd64.qcow2"
  elif [ "$vers" = 14 ]; then
    url_prefix="https://cloud.debian.org/images/cloud/forky/daily/latest/"
    url_file="debian-14-generic-amd64-daily.qcow2"
  else
    echo "Error - unknown os version" >&2
    exit 112
  fi
  ;;
fedora)
  os_variant="rhel9.0"
  url_prefix="https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/"
  url_file="Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2"
  ;;
ubuntu)
  vers="${version:-noble}"
  os_variant=debian11
  url_prefix="https://cloud-images.ubuntu.com/${vers}/current/"
  url_file="${vers}-server-cloudimg-amd64.img"
  ;;
custom)
  os_variant="rhel8.0"
  url_file="$custom_image"
  ;;
*)
  echo "Error - unknown os version" >&2
  exit 112
  ;;
esac

srcdisk="$loc/$url_file"

if ! sudo stat "$srcdisk"; then
  img=$(mktemp)
  curl -L "${url_prefix}${url_file}" >"$img"
  sudo cp --sparse=always "$img" "$srcdisk"
  rm "$img"
  if [ -f /usr/sbin/restorecon ]; then
    /usr/sbin/restorecon "$srcdisk"
  fi
else
  echo template image already exists at "$srcdisk"
fi

sudo cp -a --sparse=always --reflink=auto "$srcdisk" "$destdisk"
sudo qemu-img resize "$destdisk" "${disk_gb}G"

if "$virt_sysprep"; then
  sudo virt-sysprep --operations=defaults -a "$destdisk"
fi

meta=$(mktemp)
printf "instance-id: %s\n" "$(uuidgen)" >"$meta"

cloudinit=$(mktemp)
sed -e "s/XXX_HOSTNAME/$vm_name/" <cloud-init-el.yml >"$cloudinit"

virt_install_cmd=(
  virt-install
  --name "$1"
  --os-variant "$os_variant"
  --memory "$memory_mb"
  --vcpus 2
  --network "$network"
  --import
  --disk "$destdisk"
  --noautoconsole
  --cloud-init disable=on,user-data="$cloudinit",meta-data="$meta"
  --events on_reboot=restart
)

if "$transient"; then
  virt_install_cmd+=(--transient)
fi

sudo "${virt_install_cmd[@]}"

# Unlink virtual disk while still running for auto cleanup
if "$transient"; then
  sudo rm -v "$destdisk"
fi

rm "$meta" "$cloudinit"
