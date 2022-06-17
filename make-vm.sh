#!/bin/bash

set -eu

memory_mb=4096
while getopts :m: opt; do
  case "$opt" in
    m )
      re='$^[0-9]+$'
      if [[ $OPTARG =~ $re ]] ; then
        memory_mb="$OPTARG"
      else
        echo "Error - memory must be specified as a number" >&2
        exit 112
      fi
      ;;
    \? )
      echo "invalid option, exiting" >&2
      exit 113
      ;;
    : )
      printf "\55%s needs an argument, exiting\n" "$OPTARG" >&2
      exit 114
      ;;
  esac
done

shift $((OPTIND - 1))
if [ -z "$1" ] ; then
  echo "Error - you must provide a name for your vm" >&2
  echo "example: $0 my-vm" >&2
  exit 111
fi
vm_name="$1"


loc=/var/lib/libvirt/images
destdisk="$loc/$vm_name.qcow2"


sudo cp -a --sparse=always "$loc/Rocky-8-GenericCloud-8.6-20220515.x86_64.qcow2" "$destdisk"
sudo virt-sysprep --operations=defaults -a "$destdisk"

meta=$(mktemp)
printf "instance-id: %s\n" $(uuidgen) > "$meta"

sudo virt-install  \
	--name ${1?} \
        --os-variant rhel8.4  \
        --memory $memory_mb \
        --vcpus 2  \
        --network default \
        --import \
        --disk "$destdisk" \
        --noautoconsole   \
        --cloud-init disable=on,user-data=cloud-init-rocky.yml,meta-data="$meta"



