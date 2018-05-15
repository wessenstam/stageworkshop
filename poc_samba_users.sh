#!/bin/bash

#remotely populate domain controller:
# export DC_IP='10.21.example.40' && scp poc*sh root@${DC_IP}: && ssh root@${DC_IP} "chmod a+x poc*sh; ./poc_samba_users.sh"

     count=70
group_name='CalmAdmin'
  password='nutanix/4u'

samba-tool group add ${group_name}

for((n=1; n<=${count}; n++))
{
  if [ "$n" -lt 10 ]
  then
    zeropadded="0$n";
  else
    zeropadded="$n";
  fi

  samba-tool user add user${zeropadded} "${password}" --use-username-as-cn --userou='CN=Users'
  samba-tool group addmembers ${group_name} user${zeropadded}
  echo
}
