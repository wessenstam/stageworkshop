# Push Button Calm: Bugs, Priorities, Notes #

- bug report from mike.bujara@nutanix.com:
  - I created the cluster file and run it with stage_Workshop and it gives me the menu
but none of the inputs are accepted:
    - ./stage_Workshop.sh
    - example_poc.txt
    - 2 (no response, back to menu)
    - Test 10/10|Substate=running, exec properly, sleep 7 seconds..
    Error 12: AutoDC VM running, giving up after 11 tries.
    AutoDC pending
    AutoDC complete
    - PC_Configure|OPTIONAL: send bin to PC, sshpass: no such file or dir _TEST 3/3 Error 11 giving up after 3 tries...
- document public cloud account/credentials
  - Add to: https://drt-it-github-prod-1.eng.nutanix.com/akim-sissaoui/calm_aws_setup_blueprint/blob/master/Action%20Create%20Project/3-Create%20AWS%20Calm%20Entry

# PC 5.7.1 #

- update default or create new project
- fix role mappings, logins on PE, PC
  - PE, PC: use RBAC user for APIs, etc.: cluster Admin
  - improve/run poc_samba_users.sh
- Move AutoDC to DHCP? and adjust DNS for SRE HPOC subnets?
- nuclei (run local from container?)
  - version.get # gives API 3.1 and AOS 5.7.0.1 (bug!)
    - vs: cat /etc/nutanix/release_version
  - project.create name=mark.lavi.test \
    description='test_from NuClei!'
  - project.get mark.lavi.test
  - project.update mark.lavi.test
      spec.resources.account_reference_list.kind= or .uuid
      spec.resources.default_subnet_reference.kind=
      spec.resources.environment_reference_list.kind=
      spec.resources.external_user_group_reference_list.kind=
      spec.resources.subnet_reference_list.kind=
      spec.resources.user_reference_list.kind=

      resources:
        account_reference_list: []
        environment_reference_list: []
        external_user_group_reference_list: []
        is_default: false
        resource_domain:
          resources: []
        subnet_reference_list: []
        user_reference_list: []
  - nuclei authconfig (run local from container?) See notes#nuceli section, below.
  - (localize?) and upload blueprint via nuclei (see unit tests)?
  - Default project environment set, enable marketplace item, launch!
  - Karan: by PC version, add to cache and pre-stage?
  - Enable multiple cloud account settings, then environments, then marketplace launch
  - PE, PC: clear our warnings: resolve/ack issues for cleanliness?
  - nutanix@PC Linux account password change?
  - OPTIMIZATION: Upload AutoDC image in parallel with PC.tar

# Overall TODO #

- PC 5.6:
  - Revalidate it works, add AOS 5.5 dependency note
- SRE Clusters of HPOC (10.63.x.x)
  - Cluster IP: https://10.63.30.150:9440/console/#login
    Prism UI Credentials: admin/nx2Tech975!
    CVM Credentials: nutanix/nx2Tech975!
    AHV Host Credentials: root / nx2Tech975!

    AOS Version: 5.6
    Hypervisor Version: AHV 20170830.115 (AOS5.6+)

    NETWORK INFORMATION
    Subnet Mask: 255.255.252.0
    Gateway: 10.63.28.1
    Nameserver IP: 10.63.25.10

    SECONDARY NETWORK INFORMATION
    Secondary VLAN: 0
    Secondary Subnet: 255.255.252.0
    Secondary Gateway: 10.63.28.1
    Secondary IP Range: 10.63.31.146-149

- Calm 5.8 bootcamp labs and 5.5-6 bugs
  - https://github.com/nutanixworkshops/introcalm
  vs. https://github.com/mlavi/calm_workshop
- file Calm bugs from guide
- Refactor 10.21 out further: mostly done! move to bats?
- create cache, use cache, propagate cache to PC, fall back to global
- review, refactor & migrate to bugs.txt: TODO, TOFIX comments
- refactor out all passwords, hardcoded values to variables
  - SSP Admins
- Create adminuser2, assign privs, use it instead of base admin user (drop privs/delete at end?)
- Insure exit codes unique/consistent, error messages consistent
- Bash test framework for unit tests and on blueprints?
  - https://kitchen.ci/ which can do spec, BATS, etc. = https://github.com/test-kitchen/test-kitchen
    - https://kitchen.ci/docs/getting-started/writing-test
    - https://serverspec.org/ DSL Spec TDD
    - http://rspec.info/ Ruby TDD
    - inspec
      - more compliance from supermarket
      - https://dev-sec.io/features.html#os-hardening
      - https://www.cisecurity.org/cis-benchmarks/
    - https://en.wikipedia.org/wiki/ERuby
    - https://www.engineyard.com/blog/bats-test-command-line-tools
    - https://medium.com/@pimterry/testing-your-shell-scripts-with-bats-abfca9bdc5b9
      - http://ohmyz.sh/
      - https://github.com/jakubroztocil/httpie#scripting
      - https://github.com/pimterry/git-confirm
  - BATS https://github.com/bats-core/bats-core
  - https://invent.life/project/bash-infinity-framework
  - Runit/rundeck? http://bashdb.sourceforge.net/
  - Tests:
    - external URLs working (PC x, sshpass, jq, autodc, etc.)
    - userX login to PE, PC
    - userX new project, upload, run blueprint
- Base images/boxes: https://github.com/chef/bento
  - https://qemu.weilnetz.de/doc/qemu-doc.html#disk_005fimages_005fssh
    qemu-system-x86_64 -drive file=ssh://[user@]server[:port]/path[?host_key_check=host_key_check]

  + clear; MY_PE_PASSWORD='nx2Tech!'; sshpass -p "${MY_PE_PASSWORD}" \
  ssh -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null \
  nutanix@10.21.${MY_HPOC_NUMBER}.37 'pkill tail; ps -efww|grep calm'
+ AutoDC:
  + NTNXLAB, ntnxlab.local, root:nutanix/4u
  + samba --version Version 4.2.14-Debian
  - https://wiki.archlinux.org/index.php/samba
  - https://gitlab.com/mlavi/alpine-dc (fork)
  - yum install samba-ldap
    - https://help.ubuntu.com/lts/serverguide/samba-ldap.html.en
+ PE:
  + user01@ntnxlab.local auth test fine

# Notes #

## Citations for other Calm automation ##

- https://drt-it-github-prod-1.eng.nutanix.com/sylvain-huguet/auto-hpoc
- One more: @anthony.c?

## Push Button Calm #

- https://github.com/mlavi/stageworkshop/blob/master/guidebook.md
- MP4 Video = 292MB: https://drive.google.com/open?id=1AfIWDff-mlvwth_lKv9DG4x-vi0ZsWij
 ~11 minute screencast overview of the 70 minute journey from Foundation
  to Calm running a blueprint: most of it is waiting for foundation and PC download/upload/deploy.
- Social coding: https://github.com/nutanixworkshops/stageworkshop/pull/1
- Biggest pain:
  - finding a HPOC
  - second biggest pain: keeping it for more than a few hours except on the weekend.
  - third biggest pain: coding in Bash :slightly_smiling_face: it makes you miss even script kiddie programming languages!

## NuCLeI ##

https://jira.nutanix.com/browse/ENG-78322 <nuclei>
````app_blueprint
availability_zone
available_extension
available_extension_images
catalog_item
category
certificate
changed_regions
client_auth
cloud_credentials
cluster
container
core                          CLI control.
diag                          Diagnostic tools.
directory_service
disk
docker_image
docker_registry
exit                          Exits the CLI.
extension
get                           Gets the current value of the given configuration options.
help                          Provides help text for the named object.
host
image
network_function_chain
network_security_rule
oauth_client
oauth_token
permission
project
protection_rule
quit                          Exits the CLI.
recovery_plan
recovery_plan_job
remote_connection
report_config
report_instance
role
set                           Sets the value of the given configuration options.
ssh_user
subnet
user
version                       NuCLEI Version Information.
virtual_network
vm
vm_backup
vm_snapshot
volume_group
volume_group_backup
volume_group_snapshot
webhook````

### nuclei authconfig (run local from container?) ####

````list | ls
edit | update
remove | rm
list-directory | ls-directory
create-directory | add-directory
edit-directory | update-directory
remove-directory | rm-directory
list-role-mappings | ls-role-mappings
delete-role-mapping
add-role-mapping
add-to-role-mapping-values
remove-from-role-mapping-values
get-directory-values-by-type
test-ldap-connection````

## File servers for container updates ##

- https://sewiki.nutanix.com/index.php/Hosted_Proof_of_Concept_(HPOC)#What_you_get_with_each_reservation
- https://sewiki.nutanix.com/index.php/Hosted_Proof_of_Concept_(HPOC)#Lab_Resources
- https://sewiki.nutanix.com/index.php/HPOC_Access_Instructions#FTP
  - \\lab-ftp\ftp
  - smb://hpoc-ftp/ = \\hpoc-ftp\ftp
  - ftp://nutanix:nutanix/4u@hostedpoc.nutanix.com/
  - smb://pocfs/    = \\pocfs\iso\ and \images\
    - WIN> nslookup pocfs.nutanixdc.local
    - smbclient -I 10.21.249.12 \\\\pocfs\\images \
      --user mark.lavi@nutanixdc.local --command "prompt ; cd /Calm-EA/pc-5.7.1/ ; mget *tar"
  - smb://hpoc-afs/ = \\hpoc-afs\se\
    - smbclient \\\\hpoc-afs\\se\\ --user mark.lavi@nutanixdc.local --debuglevel=10
    - WIN> nslookup hpoc-afs.nutanixdc.local
    10.21.249.41-3
    - smbclient -I 10.21.249.41 \\\\hpoc-afs\\se\\ --user mark.lavi@nutanixdc.local
  - smb://NTNX-HPOC-AFS-3.NUTANIXDC.LOCAL
  default password = welcome123
  - https://ubuntuswitch.wordpress.com/2010/02/05/nautilus-slow-network-or-network-does-not-work/
- smb-client vs cifs?
  - https://www.tldp.org/HOWTO/SMB-HOWTO-8.html
  - https://www.samba.org/samba/docs/current/man-html/smbclient.1.html
  - https://linux-cifs.samba.org/
    - https://pserver.samba.org/samba/ftp/cifs-cvs/linux-cifs-client-guide.pdf
    - https://serverfault.com/questions/609365/cifs-mount-in-fstab-succeeds-on-ip-fails-on-hostname-written-in-etc-hosts
      - sudo apt-get install cifs-utils
      - yum install cifs-utils
        man mount.cifs
        USER=mark.lavi@nutanix.com PASSWD=secret mount -t cifs //hpoc-afs/se /mnt/se/
  - mac: sudo mount -v -r -t nfs -o resvport,nobrowse,nosuid,locallocks,nfc,actimeo=1 10.21.34.37:/SelfServiceContainer/ nfstest
- mount AFS and then put a web/S/FTP server on top
- python -m SimpleHTTPServer 8080 || python -m http.server 8080
