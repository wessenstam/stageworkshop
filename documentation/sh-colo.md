# SH-COLO Automation

## Overview

Rebuild AHV-2 cluster in 1 hour. need more automation.


## Foundation

- ssh to foundation VM ``10.132.128.10``
    - double check the environemnt you will foundation
        - confirm no one will use AHV-2
        - confirm ``~/foundation/config/ahv-2.conf`` are correct. (please refer last chapter)
    - run script to foundation your gears
        ```
        cd ~/foundation
        service foundation_service stop
        ./bin/foundation --nos=./nos/5.8.2.tar --cluster_name=AHV-2 config/ahv-2.config
        ```

    - after foundation 
        ```
        ncli user reset-password user-name=admin password='nx2Tech432!'
        ncli user add last-name=nutanix first-name=nutanix user-name=nutanix user-password='nutanix/4u' email-id=nutanix@nutanix.sh
        ncli user grant-cluster-admin-role user-name=nutanix
        ncli user grant-user-admin-role user-name=nutanix
        ncli cluster edit-info new-name=AHV-2
        ncli cluster set-timezone timezone=Asia/Shanghai
        ncli cluster edit-info external-ip-address=10.132.129.37
        ncli cluster add-to-name-servers servers=10.132.71.40
        echo -e 'nx2Tech432!\nnx2Tech432!' | sudo passwd nutanix
        ```

## Configuration

- download automation script for your Configuration
    ```
    wget -O stageworkshop-customize-for-sh-colo.zip https://github.com/panlm/stageworkshop/archive/customize-for-sh-colo.zip 
    unzip stageworkshop-customize-for-sh-colo.zip 
    ```

- put default info to ``~/clusters.txt``
    ```
    #cluster_ip|pe_password|mail_address
    10.132.129.37|nx2Tech432!|leiming.pan@nutanix.com 
    ```

- start to configure, using the 5th workshop
    ```
    cd stageworkshop-customize-for-sh-colo 
    ./stage_workshop.sh -f ../clusters.txt -w 5
    ```

- see log
    ```
    tail -f ~/sh-colo.log
    ```
    
- finial configure
    ```
    ncli user reset-password user-name=admin password='nx2Tech432!'
    ncli user add last-name=nutanix first-name=nutanix user-name=nutanix user-password='nutanix/4u' email-id=nutanix@nutanix.sh
    ncli user grant-cluster-admin-role user-name=nutanix
    ncli user grant-user-admin-role user-name=nutanix
    echo -e 'nx2Tech432!\nnx2Tech432!' | sudo passwd nutanix
    MY_DOMAIN_NAME=NTNXLAB
    MY_DOMAIN_FQDN=ntnxlab.local
    MY_DOMAIN_URL=ldap://10.132.129.40:389
    MY_DOMAIN_USER=administrator@ntnxlab.local
    MY_DOMAIN_PASS=nutanix/4u
    ncli authconfig add-directory \
        directory-type=ACTIVE_DIRECTORY \
        connection-type=LDAP directory-url="${MY_DOMAIN_URL}" \
        domain="${MY_DOMAIN_FQDN}" \
        name="${MY_DOMAIN_NAME}" \
        service-account-username="${MY_DOMAIN_USER}" \
        service-account-password="${MY_DOMAIN_PASS}"
    nuclei image.create name=test image_type=DISK_IMAGE \
        source_uri=http://10.132.128.50:81/share/saved-images/panlm-img-52.qcow2 wait=false
    ```

## Login

- Login PE ``https://10.132.129.37:9440``
- Login PC ``https://10.132.129.39:9440``


# Reference

## ahv-2.config

- default ahv-2 configure
    ```
    ipmi_user=ADMIN
    ipmi_password=ADMIN

    hypervisor_netmask=255.255.128.0
    hypervisor_gateway=10.132.128.4
    hypervisor_nameserver=10.132.71.40
    hypervisor_password=nutanix/4u
    svm_subnet_mask=255.255.128.0
    svm_default_gw=10.132.128.4

    hyp_type=kvm
    hyp_version=20170830.166

    10.132.129.33
        hypervisor_ip=10.132.129.25
        svm_ip=10.132.129.29
        node_position=A

    10.132.129.34
        hypervisor_ip=10.132.129.26
        svm_ip=10.132.129.30
        node_position=A

    10.132.129.35
        hypervisor_ip=10.132.129.27
        svm_ip=10.132.129.31
        node_position=B
    ```


