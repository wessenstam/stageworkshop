# HPoC Automation: Push Button Calm

## Caveat ##

This is a work in progress and your milage may vary!

## Acknowledgements ##

The entire Global Technical Sales Enablement team has delivered an amazing amount of content and automation for Nutanix Tech Summits and Workshops alongside the Corporate SE team automation gurus. It has been a pleasure to work with all of them and this work stands on the shoulders of those giants. Thank you!

## For the Impatient ##

You can get push button Calm in two ways:

1. To set up an individual Nutanix AHV cluster, the easiest manner is to SSH to Prism Element on the Cluster IP and run the bootstrap script:

        curl --remote-name --location https://raw.githubusercontent.com/nutanixworkshops/stageworkshop/master/bootstrap.sh && sh ${_##*/}

2. To set up multiple clusters or do development, satisfy these requirements:

    - Tested on Ubuntu and Mac, but could work easily on other Linux distributions.
      - Mac requires https://brew.sh installed.
    - Terminal with command line git.

          echo "Start Foundation on your HPoC now, we'll wait 40 minutes..."

          export PE=10.21.X.37 && export PE_PASSWORD='nx2Tech###!' && EMAIL=first.last@nutanix.com \
          && cd $(git clone https://github.com/mlavi/stageworkshop.git 2>&1 | grep Cloning | awk -F\' '{print $2}') \
          && echo "${PE}|${PE_PASSWORD}|${EMAIL}" > clusters.txt \
          && ./stage_workshop.sh -f clusters.txt -w 1 #latest calm

          sleep 60*30 && lynx https://admin:${PE_PASSWORD}@${PE}:9440/

    - While Foundation typically takes *~30 minutes,* we'll:

      1. Set the Prism Element (PE) IP address, password, and your email address
      2. Change directory into the cloned git repository
      3. Put settings into a configuration file
      4. Stage the cluster with the configuration file and the Workshop #1.

Approximately 30 minutes later, you can login to PE to get to PC (or directly to PC) and follow step #7 below to finish push button Calm automation.

## How to Do a Calm Bootcamp ##

- __Planning:__
    - Work with your stakeholders at the partner or customer to plan the bootcamp/workshop agenda, facilities, and proposed schedule dates. Facility considerations for all attendees:
        - Leader podium/projector
        - WiFi access
        - Seating with tables and power access
        - Breakfast/Lunch/refreshments
        - Local SEs to help moderate, assist, and troubleshoot each attendee's needs while the leader continues to drive the bootcamp.
        - *Do not do a 15+ person workshop alone* unless you are comfortable dealing with adverse situations, have back up plans, and can easily adapt to make the most of attendee's valuable time (i.e. videos, presentation decks, and/or print outs).
    - If appropriate, work with your local field marketing team to make a Bootcamp event landing and registration page, they can also help reserve a marketing cluster.
      - You should drive attendees to register.
      - More information and supporting materials are on GDrive in the [Technology Bootcamp](https://drive.google.com/drive/folders/0B_IfSpggJeFVfjdrVUxkZ25tQVRINHFVMkl4TFpWMG1GUUNhOVhaWnJOZ1gtSkJfa2QzSGc) folder.
    - Estimate the count of your audience, reserve a HPOC cluster for every 25 attendees.
      - Budget for extra people to attend at the last moment and expect last minute attrition as well.
      - Confirm your dates.
      - Think about bringing Nutanix schwag: stickers, t-shirts, etc. for giveaways.
    - Ask questions not covered here in Slack to the Global Sales Technical Enablement team, first see the pinned items in each channel:
      - __#technology-bootcamps:__ for customer and prospect bootcamps
      - __#hands-on-workshops:__ for Nutanix Partner and SE workshops
   - Make a HPOC reservation(s) on https://rx.corp.nutanix.com/ with:

      - __AOS + Hypevisor:__ proper versions for your workshop, specified in the Workshop title.
        - *Recommended:* AOS 5.8
        - Older or newer versions of AOS may not function as expected.
        - Use for the Calm development workshop to test with the latest Prism Central and Calm versions.
        - Prism Central and Calm UIs are continually evolving, you may encounter variations that require different feature navigation from the step by step directions.
      - __OS Images:__ *you do not* need to specify images (CentOS, Windows2012, etc.) for your reservation.
      - __Start and End Times:__ It is nice to have the cluster extend to the end of the day in case anyone would like to save their blueprints or work after the bootcamp ends.
      - The default HPOC reservation comes with 25 VDI user sessions, therefore it is recommended that you reserve a cluster for every 25 attendees.
          - For attendees that can install and use Juniper Pulse VPN to access the HPOC, you can consolidate those users to access a single cluster in addition to the VDI users.

3. __Once your HPOC reservation starts:__
    - Leverage Push button Calm automation to stage your cluster with the Calm workshop of your choice.
    - *Optional:*
        - For every attendee over 25 or a previously known/arranged audience, it is ideal to populate them by userXX or by email in the directory and then configure sign on into Prism Central.
        - Populate the authentication directory with additional users and email addresses, add into groups if desired.
        - Configure SSP role mappings if desired.
        - Populate PC projects with groups and/or users with roles.

5. __Before the Bootcamp:__
    - Survey the site and conference/classroom, correct any logistical problems, confirm driving, parking, sign-in procedures, room location/directions, and WiFi access.
    - The day(s) before the Bootcamp or as soon as push button Calm completes with any optional configuration, send a reminder notice in email with logistical details, and *ask people to test their VDI and/or VPN access.*
      - This reduces logistical problems encountered on the bootcamp day starting to access the cluster(s).
    - Send WiFi details for on-site network access.
    - Run through the first lab to check everything works!

6. __The Day of the Bootcamp__

    - Arrive early, re-survey the site, send any updates to the e-mail attendee list, and include this link:
      - [Nutanix Partner Workshop](https://nutanix.handsonworkshops.com/workshops/6070f10d-3aa0-4c7e-b727-dc554cbc2ddf/start/)
      - Alternatively, have them access http://nutanix.handsonworkshops.com and register/log in.

## Bugs, Priorities, Notes ##

See [the planning and working document](bugs.md).

## Development: Feature Branches ##

    cd $(git clone https://github.com/mlavi/stageworkshop.git 2>&1 \
      | grep Cloning | awk -F\' '{print $2}') \
      && git checkout <BRANCH>
    # Create your cluster file, e.g.: echo "${PE}|${PE_PASSWORD}|${EMAIL}" > example_pocs.txt
    ./stage_workshop.sh -f example_pocs.txt

### Timing ###

We'll round up to the nearest half minute.

1. 30 min = RX Foundation times to PE up (approximate)

| Cluster | 5/24 (minutes) | 6/2 (min) | 6/10 (min) |
| :------------- | ------------- | --- | ---------- |
| NX-1060 | 30 | N/A | N/A |
| NX-3060-G5 | 25 | 35 | 33 |

2. 0.5 min per cluster = ./stage_workshop.sh

3. 28/26/20 min = calm.sh PE
Typical download and install of Prism Central is 17 minutes of waiting!

| Function | Run1@5/24 (minutes) | 6/2 (min) | 6/10 (min) |
| :------------- | :------------- | --- | ---------- |
| __start__ | 11:26:53 | 09:07:55 | 03:15:35 |
| __end__ | 11:54:28 | 09:34:09 | 03:35:25 |

4. 1.5 min = calm.sh PC

| Function | Run1@5/24 (minutes) | 6/2 (min) | 6/10 (min) |
| :------------- | :------------- | --- | ---------- |
| __start (localtime)__ | 04:54:27 | 02:34:08 | 20:35:24 |
| __end (localtime)__ | 04:55:57 | 02:35:37 | 20:36:45 |

5. 2 min: Login to PC, manual configuration of Calm default project (see step 7, below).

## Procedure ##

0. Crank some tunes and record the start time!
1. __Browse (tab1)__ to this page = https://github.com/mlavi/stageworkshop/blob/master/guidebook.md

    - I have submitted [a pull request](https://github.com/nutanixworkshops/stageworkshop/pull/1) to merge my work.
2. __Browse (tab2)__ to review HPoC reservation details in https://rx.corp.nutanix.com:8443/

    1. Find the __Cluster External IP__ and the __PE admin password__:
    we will use both of these in a moment.
    2. Memorize the HPOC number (third octet of the External IPv4)
    and prepare to copy by highlighting the __PE admin password__
    or merely memorize the three digits of __PE admin password__.
    3. *Browse (tab3)* to the PE URL to show unavailable before or during foundation process.
    4. *Launch a new terminal*:

        1. Change terminal font size for demo.
        2. Cut and paste the first line the follows to create, and change to the repository directory
            - or cut and paste the entire code block if you're comfortable editing the command line,
            - otherwise copy one line at a time and substitute __Cluster External IP__
            on the ````MY_HPOC```` assignment line or change that ````X```` you cleverly memorized
            and paste the __PE admin password__ onto the ````PE_PASSWORD```` line
            or change the ````###```` you cleverly memorized.

        git clone https://github.com/mlavi/stageworkshop.git && cd $_
        export MY_HPOC=10.21.X.37 \
        && export PE_PASSWORD='nx2Tech###!' \
        && echo "${MY_HPOC}|${PE_PASSWORD}" >> example_pocs.txt

        - *OPTIONAL:* Make a mistake with the HPoC octet to show a failure mode.
        - That's it, you're done! Just sit back and wait, periodically
        reload browser tab3, or follow the log output on PE and PC...

1. Side by side: (screens because split desktop doesn't work well enough)

   1. __Browser (tab 2):__ Open RX automation cluster foundation status detail page, it will be tab4.
   2. __Terminal:__ After the automation is uploaded to the cluster CVM, copy and paste the command to monitor the ````calm.sh```` progress.

   3. __Browser (tab3):__ Reload the PE URL, accept security override, login as admin and password to PE EULA.
   4. __Terminal:__ Once PE UI configured, reload browser tab3 to show EULA bypassed or click on the decline EULA button to return to login prompt.

      - *BUG:* Once Authentication Server is up, you should be able to login as a SSP admin = adminuser05@ntnxlab.local
  5. __Browser:__

      - Show PE Authentication: test above user with the default password.
      - View All Tasks, wait until software is uploading
  6. __Terminal:__ Show that we're waiting...approximately 17 minutes (fast forward). Highlight automation scripts sent to PC.
  7. __Browser:__ from PE, show VM table, go to home and show PE registered to PC, launch PC and login as admin.

    * *BUG:* Can't login as a SSP admin = adminuser05@ntnxlab.local
    * Show Authentication, show role mapping, show images.

1. Push button Calm!

    1. __PC> Apps:__ click lower left ? to show Calm 5.7

        * *BUG* why a ? in the UI?
    2. __Projects:__ Default: add the following:

      - Description: "Freedom to Cloud",
      - Roles: assign and save,
      - Local and Cloud,
      - choose PoC AHV cluster,
      - Network: enable VLANs,
      - and Save.
    3. __Blueprints:__ Upload blueprint: ````beachhead-centos7-calm5.7.0.1.json```` in default project.

      - Resize icon
      - Pull left tab open, note public key in AHVCluster application profile, zoom to show end of the value.
      - __Credentials:__ upload private key, note user centos, save, back.
      - __Service = Webtier:__

          - Show VM name, zoom in to show macros.
          - Choose local image uploaded to cluster to save time versus the dynamic imported image.
          - Show user centos in cloud-init and @@{your_public_key}@@ macro.
          - Show package install task: uncomment install work
          - Show service tab: Deployment Config

            - *bug* service > service is redundant!
        - Save, Launch!
    4. __Application Launch:__

      - Name application deployment: marklavi-beachhead-took-X-minutes
      - Terminal: find start time, find end time.

        - *BUG:* time zones of server, cloud-init?

      - Show logical deployment, open terminal, audit logs
