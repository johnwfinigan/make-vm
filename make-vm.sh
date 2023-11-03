#!/bin/bash

set -eu

export PATH=/usr/bin

memory_mb=4096
vers=9
distro=el
disk_gb=32

while getopts :m:v:d: opt; do
  case "$opt" in
  m)
    re='^[0-9]+$'
    if [[ $OPTARG =~ $re ]]; then
      memory_mb="$OPTARG"
    else
      echo "Error - memory must be specified as a number" >&2
      exit 112
    fi
    ;;
  v)
    vers="$OPTARG"
    ;;
  d)
    distro="$OPTARG"
    ;;
  g)
    disk_gb="$OPTARG"
    ;;
  \?)
    echo "invalid option, exiting" >&2
    exit 113
    ;;
  :)
    printf "\55%s needs an argument, exiting\n" "$OPTARG" >&2
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

if [ "$distro" = el ]; then
  os_variant="rhel${vers}.0"
  if [ "$vers" = 8 ] || [ "$vers" = 9 ] ; then
    url_prefix="https://download.rockylinux.org/pub/rocky/${vers}/images/x86_64/"
    url_file="Rocky-${vers}-GenericCloud.latest.x86_64.qcow2"
  elif [ "$vers" = 7 ]; then
    url_prefix="https://cloud.centos.org/centos/7/images/"
    url_file="CentOS-7-x86_64-GenericCloud.qcow2"
  else
    echo "Error - unknown os version" >&2
    exit 112
  fi
elif [ "$distro" = debian ] ; then
  os_variant=debian11
  if [ "$vers" = 12 ]; then
    url_prefix="https://cloud.debian.org/images/cloud/bookworm/latest/"
    url_file="debian-12-generic-amd64.qcow2"
  else
    echo "Error - unknown os version" >&2
    exit 112
  fi
fi

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
sudo virt-sysprep --operations=defaults -a "$destdisk"

meta=$(mktemp)
printf "instance-id: %s\n" "$(uuidgen)" >"$meta"

cloudinit=$(mktemp)
sed -e "s/XXX_HOSTNAME/$vm_name/" < cloud-init-el.yml > "$cloudinit"

sudo virt-install \
  --name "$1" \
  --os-variant "$os_variant" \
  --memory "$memory_mb" \
  --vcpus 2 \
  --network default \
  --import \
  --disk "$destdisk" \
  --noautoconsole \
  --cloud-init disable=on,user-data="$cloudinit",meta-data="$meta"

rm "$meta" "$cloudinit"
