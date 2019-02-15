# Darksite #

## Rationale ##

Many Nutanix customers run their on-prem clusters with a requirement for network isolation, usually in a DMZ, private LAN, or otherwise air gapped environment. For security purposes, these environments are further restricted without Internet access. This causes the need to transport software binaries, updates, etc. via physical access to the cluster, *a.k.a.* sneaker net.

This document outlines the procedure to bootstrap a new or established Nutanix AHV cluster with software from your laptop.

## Overview ##

Ideal to do this on a CVM, but you can prepare by downloading all of the bits in advance. The goal is to get everything onto the CVM if there’s room. If not, get it onto a fileserver that the CVM can access, even via SCP/SSH or HTTP.

- Download the push button Calm archive, unarchive, create a ````cache```` directory inside:

````wget https://github.com/mlavi/stageworkshop/archive/master.zip && \
unzip master.zip && pushd stageworkshop-master && mkdir cache && cd ${_}
````
-  Put everything else below in this cache directory and contact me.

    - AutoDC: http://10.59.103.143:8000/autodc-2.0.qcow2
    - CentOS 7.4 image: http://download.nutanix.com/calm/CentOS-7-x86_64-GenericCloud-1801-01.qcow2
      - OPTIONAL rolling: http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2
    - PC-5.9.1 metadata and bits:
      - http://download.nutanix.com/pc/one-click-pc-deployment/5.9.1/v1/euphrates-5.9.1-stable-prism_central_metadata.json
      - http://download.nutanix.com/pc/one-click-pc-deployment/5.9.1/euphrates-5.9.1-stable-prism_central.tar
    - jq-1.5: https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
    - sshpass: http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm
